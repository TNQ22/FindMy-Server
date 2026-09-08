import asyncio
import json
import logging
from datetime import datetime, timezone, timedelta
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.config import get_local_timezone
from app.models import ZoneSchedule, Zone, ZoneDevice, Device, User
from app.services.notification_service import dispatch_zone_schedule_notification

logger = logging.getLogger("schedule_service")


async def check_zone_schedules(db: AsyncSession):
    """
    Checks all active zone schedules against the current local time.
    Triggers reminder if device has not left (MUST_LEAVE_BY) or has not entered (MUST_ENTER_BY).
    Runs periodically via APScheduler.
    """
    try:
        local_tz = get_local_timezone()
        local_now = datetime.now(local_tz)
        cur_day = local_now.isoweekday()  # 1 = Monday, ..., 7 = Sunday
        cur_time_str = local_now.strftime("%H:%M")
        cur_date_str = local_now.strftime("%Y-%m-%d")

        stmt = (
            select(ZoneSchedule)
            .options(
                joinedload(ZoneSchedule.zone).joinedload(Zone.zone_devices).joinedload(ZoneDevice.device),
                joinedload(ZoneSchedule.device),
                joinedload(ZoneSchedule.user),
            )
            .where(ZoneSchedule.is_active == True)
        )
        result = await db.execute(stmt)
        schedules = result.scalars().unique().all()

        for sched in schedules:
            # Check if already triggered today
            if sched.last_triggered_date == cur_date_str:
                continue

            # Check day of week
            days = []
            try:
                days = json.loads(sched.days_of_week)
            except Exception:
                days = [1, 2, 3, 4, 5, 6, 7]

            if cur_day not in days:
                continue

            # Check time: trigger within a 15-minute window of target_time
            target_parts = sched.target_time.split(":")
            if len(target_parts) != 2:
                continue
            target_hour = int(target_parts[0])
            target_minute = int(target_parts[1])
            sched_today = local_now.replace(hour=target_hour, minute=target_minute, second=0, microsecond=0)

            diff_seconds = (local_now - sched_today).total_seconds()
            # If current time is within [0, 900] seconds after the target time
            if not (0 <= diff_seconds <= 900):
                continue

            zone = sched.zone
            if not zone or not zone.is_active:
                continue

            # Determine list of devices to check
            devices_to_check: list[tuple[Device, str]] = []  # (device, last_status)
            if sched.device_id:
                # Specific device
                zd = next((d for d in zone.zone_devices if d.device_id == sched.device_id), None)
                if zd and zd.device:
                    devices_to_check.append((zd.device, zd.last_status or "UNKNOWN"))
            else:
                # All devices in zone
                for zd in zone.zone_devices:
                    if zd.device:
                        devices_to_check.append((zd.device, zd.last_status or "UNKNOWN"))

            if not devices_to_check:
                continue

            triggered_any = False
            for dev, status in devices_to_check:
                should_alert = False
                if sched.rule_type == "MUST_LEAVE_BY":
                    # If device is still INSIDE the zone, alert!
                    if status == "INSIDE":
                        should_alert = True
                elif sched.rule_type == "MUST_ENTER_BY":
                    # If device is NOT INSIDE the zone, alert!
                    if status != "INSIDE":
                        should_alert = True

                if should_alert:
                    triggered_any = True
                    logger.warning(
                        f"ZONE SCHEDULE TRIGGERED: Device '{dev.name}' in Zone '{zone.name}' "
                        f"rule={sched.rule_type} target={sched.target_time} status={status}"
                    )
                    if sched.user:
                        asyncio.create_task(
                            dispatch_zone_schedule_notification(
                                user=sched.user,
                                device_name=dev.name,
                                zone_name=zone.name,
                                rule_type=sched.rule_type,
                                target_time=sched.target_time,
                                lat=dev.last_lat,
                                lon=dev.last_lon,
                                event_time=local_now,
                            )
                        )

            if triggered_any:
                sched.last_triggered_date = cur_date_str

        await db.commit()

    except Exception as e:
        logger.error(f"Error checking zone schedules: {e}", exc_info=True)
