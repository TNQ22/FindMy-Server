from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models import User, ICloudAccount, LocationReport, Device
from app.schemas import MaclessFetchRequest, MaclessFetchResponse, MaclessReportItem
from app.services.auth_service import get_current_user
from app.services.icloud_service import restore_apple_account, fetch_reports_from_icloud, serialize_apple_account

router = APIRouter(prefix="/api/reports", tags=["Reports"])

@router.post("/", response_model=MaclessFetchResponse)
@router.post("/fetch", response_model=MaclessFetchResponse)
async def fetch_location_reports(
    body: MaclessFetchRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if not body.ids:
        return MaclessFetchResponse(results=[])

    days = body.days
    if days > 0:
        start_time_ms = int((datetime.now(timezone.utc) - timedelta(days=days)).timestamp() * 1000)
        cached_stmt = select(LocationReport).where(
            LocationReport.user_id == current_user.id,
            LocationReport.hashed_adv_key.in_(body.ids),
            LocationReport.timestamp_published >= start_time_ms
        ).order_by(LocationReport.timestamp_published.desc())
    else:
        cached_stmt = select(LocationReport).where(
            LocationReport.user_id == current_user.id,
            LocationReport.hashed_adv_key.in_(body.ids)
        ).order_by(LocationReport.timestamp_published.desc())

    result = await db.execute(cached_stmt)
    cached_reports = result.scalars().all()

    report_items: list[MaclessReportItem] = []
    seen_keys = set()

    for rep in cached_reports:
        rep_key = f"{rep.hashed_adv_key}_{rep.payload_b64}"
        if rep_key not in seen_keys:
            seen_keys.add(rep_key)
            report_items.append(
                MaclessReportItem(
                    payload=rep.payload_b64,
                    datePublished=rep.timestamp_published,
                    statusCode=rep.status_code,
                    id=rep.hashed_adv_key
                )
            )

    # 2. Select next active & LOGGED_IN iCloud account from Shared Pool via Round-Robin
    all_active_accs = []
    try:
        icloud_stmt = select(ICloudAccount).where(ICloudAccount.is_active == True)
        acc_result = await db.execute(icloud_stmt)
        all_active_accs = list(acc_result.scalars().all())

        from app.routes.icloud import get_login_state_fast

        # Prioritize accounts whose state_json indicates LOGGED_IN
        logged_in_accs = [
            a for a in all_active_accs
            if get_login_state_fast(a.state_json) == "LOGGED_IN"
        ]
        if logged_in_accs:
            all_active_accs = logged_in_accs
        else:
            all_active_accs = [a for a in all_active_accs if get_login_state_fast(a.state_json) != "REQUIRE_2FA"]

        all_active_accs.sort(
            key=lambda a: getattr(a, 'last_used_at', None) or datetime.fromtimestamp(0, tz=timezone.utc)
        )
    except Exception as e:
        print(f"Failed to query iCloud accounts pool: {e}")

    from findmy import LoginState

    for candidate in all_active_accs:
        try:
            apple_acc = await restore_apple_account(candidate.state_json)
            if getattr(apple_acc, 'login_state', None) != LoginState.LOGGED_IN:
                continue

            candidate.last_used_at = datetime.now(timezone.utc)
            candidate.fetch_count = (getattr(candidate, 'fetch_count', 0) or 0) + 1
            try:
                await db.commit()
            except Exception:
                await db.rollback()

            print(f"[FETCH_REPORTS] Account {candidate.apple_id} state: {apple_acc.login_state}")
            live_reports = await fetch_reports_from_icloud(apple_acc, body.ids)
            print(f"[FETCH_REPORTS] Account {candidate.apple_id} returned {len(live_reports)} live reports from Apple")

            try:
                candidate.state_json = serialize_apple_account(apple_acc)
                await db.commit()
            except Exception as se:
                print(f"[FETCH_REPORTS] Failed to save updated session state: {se}")

            new_count = 0
            for rep in live_reports:
                key_b64 = rep["id"]
                pub_ts = rep["datePublished"]
                p_b64 = rep["payload"]
                s_code = rep["statusCode"]

                ex_stmt = select(LocationReport).where(
                    LocationReport.hashed_adv_key == key_b64,
                    LocationReport.payload_b64 == p_b64
                )
                ex_res = await db.execute(ex_stmt)
                if not ex_res.scalar_one_or_none():
                    db.add(
                        LocationReport(
                            user_id=current_user.id,
                            hashed_adv_key=key_b64,
                            timestamp_published=pub_ts,
                            payload_b64=p_b64,
                            status_code=s_code
                        )
                    )
                    new_count += 1

            if new_count > 0:
                await db.commit()
                print(f"[FETCH_REPORTS] Added {new_count} new reports to DB for keys {body.ids}")

            # Successfully fetched reports from active account, stop searching
            break
        except Exception as fe:
            print(f"[FETCH_REPORTS] Failed to fetch using candidate {candidate.apple_id}: {fe}")

    # Sort reports descending by timestamp
    report_items.sort(key=lambda x: x.datePublished, reverse=True)

    return MaclessFetchResponse(results=report_items)
