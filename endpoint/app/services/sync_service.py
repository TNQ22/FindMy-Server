import logging
from datetime import datetime, timezone
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select
from sqlalchemy.orm import joinedload
from findmy import LoginState
from app.config import settings
from app.database import AsyncSessionLocal
from app.models import User, ICloudAccount, Device, LocationReport
from app.services.icloud_service import restore_apple_account, fetch_reports_from_icloud, serialize_apple_account
from app.services.decrypt_service import decrypt_report, extract_private_key_from_device_json
from app.services.email_service import send_low_battery_alert

logger = logging.getLogger("sync_service")

scheduler = AsyncIOScheduler()


async def run_sync_task() -> dict:
    """
    Fetch new reports from Apple iCloud for all devices,
    decrypt them immediately, and update device last-known location.

    Returns a summary dict: { new_reports, decrypted, updated_devices }.
    """
    logger.info("Starting background iCloud sync job...")
    total_new = 0
    total_decrypted = 0
    updated_device_names = []

    async with AsyncSessionLocal() as db:
        # ── 1. Fetch active iCloud accounts ───────────────────────────────────
        result = await db.execute(
            select(ICloudAccount).where(ICloudAccount.is_active == True)
        )
        accounts = result.scalars().all()

        if not accounts:
            logger.warning("No active iCloud accounts found for background sync.")
            return {"new_reports": 0, "decrypted": 0, "updated_devices": []}

        logger.info(f"Found {len(accounts)} active iCloud account(s) for background sync.")

        # ── 2. Build private-key map: hashed_adv_key → raw private key b64 ────
        dev_result = await db.execute(select(Device).options(joinedload(Device.user)))
        devices = dev_result.scalars().all()

        if not devices:
            logger.info("No registered devices found in DB to sync.")
            return {"new_reports": 0, "decrypted": 0, "updated_devices": []}

        key_map: dict[str, str | None] = {}
        device_map: dict[str, Device] = {}
        for dev in devices:
            key_map[dev.hashed_adv_key] = extract_private_key_from_device_json(dev.private_key_b64)
            device_map[dev.hashed_adv_key] = dev

        # ── 3. Fetch reports from Apple for each device ───────────────────────
        active_accounts = []
        for account_rec in accounts:
            apple_acc = await restore_apple_account(account_rec.state_json)
            if apple_acc.login_state == LoginState.LOGGED_IN:
                active_accounts.append((account_rec, apple_acc))
            else:
                logger.warning(
                    f"Skipping sync for Apple ID {account_rec.apple_id}: "
                    f"Login state is {apple_acc.login_state}"
                )

        if not active_accounts:
            logger.info("No active Apple accounts for background sync. Skipping sync.")
            return {"new_reports": 0, "decrypted": 0, "updated_devices": []}

        # Pick the least recently used account for this sync cycle
        active_accounts.sort(key=lambda x: x[0].last_used_at.timestamp() if x[0].last_used_at else 0)
        account_rec, apple_acc = active_accounts[0]

        try:
            assigned_devices = devices
            if not assigned_devices:
                return {"new_reports": 0, "decrypted": 0, "updated_devices": []}

            logger.info(
                f"Syncing {len(assigned_devices)} device(s) using Apple ID "
                f"{account_rec.apple_id} (User ID {account_rec.user_id})..."
            )

            keys = [dev.hashed_adv_key for dev in assigned_devices]
            logger.info(f"  -> Fetching reports from Apple for {len(keys)} device(s) in a single request...")

            reports = await fetch_reports_from_icloud(apple_acc, keys)
            logger.info(f"     Apple returned {len(reports)} raw report(s) total.")

            for rep in reports:
                r_key  = rep["id"]
                ts_pub = rep["datePublished"]
                p_b64  = rep["payload"]

                private_key_b64 = key_map.get(r_key)

                # Skip if already in DB
                existing = await db.execute(
                    select(LocationReport).where(
                        LocationReport.hashed_adv_key == r_key,
                        LocationReport.payload_b64 == p_b64,
                    )
                )
                if existing.scalar_one_or_none():
                    continue

                # ── Decrypt immediately ───────────────────────────────
                dec_result = None
                if private_key_b64:
                    dec_result = decrypt_report(p_b64, private_key_b64)

                dev_obj = device_map.get(r_key)
                user_id_val = dev_obj.user_id if dev_obj else account_rec.user_id

                new_rep = LocationReport(
                    user_id           = user_id_val,
                    hashed_adv_key    = r_key,
                    payload_b64       = p_b64,
                    timestamp_published = ts_pub,
                    status_code       = rep.get("statusCode", 200),
                    fetched_at        = datetime.now(timezone.utc),
                )

                if dec_result:
                    new_rep.latitude       = dec_result["latitude"]
                    new_rep.longitude      = dec_result["longitude"]
                    new_rep.accuracy       = dec_result["accuracy"]
                    new_rep.battery_status = dec_result["battery_status"]
                    new_rep.decrypted_at   = datetime.now(timezone.utc)
                    total_decrypted += 1

                    # Update device last-known location if newer
                    rep_ts = dec_result["timestamp"]
                    if dev_obj:
                        if (
                            dev_obj.last_seen_at is None
                            or rep_ts.replace(tzinfo=timezone.utc)
                            > dev_obj.last_seen_at.replace(tzinfo=timezone.utc)
                        ):
                            dev_obj.last_lat     = dec_result["latitude"]
                            dev_obj.last_lon     = dec_result["longitude"]
                            dev_obj.last_seen_at = rep_ts.replace(tzinfo=None)
                            
                            new_battery = dec_result["battery_status"]
                            dev_obj.last_battery = new_battery
                            
                            # Handle low battery alerts
                            if new_battery in ["low", "criticalLow"]:
                                if dev_obj.last_alerted_battery != new_battery:
                                    dev_obj.last_alerted_battery = new_battery
                                    if dev_obj.user and dev_obj.user.email:
                                        import json
                                        user_settings = {}
                                        try:
                                            user_settings = json.loads(dev_obj.user.settings_json or "{}")
                                        except Exception:
                                            pass
                                        
                                        email_enabled = user_settings.get("email_alerts_enabled", True)
                                        if email_enabled:
                                            import asyncio
                                            asyncio.create_task(
                                                send_low_battery_alert(dev_obj.user.email, dev_obj.name, new_battery)
                                            )
                                        else:
                                            logger.info(f"Skipping email alert for {dev_obj.name} (user disabled it).")
                            elif new_battery in ["ok", "medium"]:
                                # Reset alert state if battery is replaced or recovered
                                dev_obj.last_alerted_battery = None
                                
                            if dev_obj.name not in updated_device_names:
                                updated_device_names.append(dev_obj.name)

                db.add(new_rep)
                total_new += 1

            # Save updated account state
            account_rec.last_used_at = datetime.now(timezone.utc)
            account_rec.fetch_count  = (getattr(account_rec, "fetch_count", 0) or 0) + 1
            account_rec.state_json   = serialize_apple_account(apple_acc)

            await db.commit()
            logger.info(
                f"Sync completed for Apple ID {account_rec.apple_id}: "
                f"{total_new} new report(s), {total_decrypted} decrypted."
            )

        except Exception as e:
            logger.error(f"Sync failed for Apple ID {account_rec.apple_id}: {e}", exc_info=True)

    return {
        "new_reports":     total_new,
        "decrypted":       total_decrypted,
        "updated_devices": updated_device_names,
    }


def start_sync_scheduler():
    if not scheduler.running:
        scheduler.add_job(
            run_sync_task,
            "interval",
            minutes=settings.SYNC_INTERVAL_MINUTES,
            id="icloud_sync_job",
            replace_existing=True,
        )
        scheduler.start()
        logger.info(f"Background Sync Scheduler started (Interval: {settings.SYNC_INTERVAL_MINUTES} minutes).")


def stop_sync_scheduler():
    if scheduler.running:
        scheduler.shutdown()
        logger.info("Background Sync Scheduler stopped.")
