from typing import List, Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models import User, Device, LocationReport
from app.schemas import DeviceCreateRequest, DeviceResponse, LocationHistoryItem, LocationHistoryResponse
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/api/devices", tags=["Devices"])


@router.get("", response_model=List[DeviceResponse])
async def list_devices(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Device).where(Device.user_id == current_user.id))
    devices = result.scalars().all()
    from datetime import timezone
    has_updates = False
    for d in devices:
        if d.hashed_adv_key:
            latest = await db.execute(
                select(LocationReport)
                .where(LocationReport.hashed_adv_key == d.hashed_adv_key)
                .where(LocationReport.latitude.isnot(None))
                .order_by(LocationReport.timestamp_published.desc())
                .limit(1)
            )
            latest_rep = latest.scalar_one_or_none()
            if latest_rep:
                rep_dt = datetime.fromtimestamp(latest_rep.timestamp_published / 1000, tz=timezone.utc)
                curr_seen = d.last_seen_at.replace(tzinfo=timezone.utc) if (d.last_seen_at and d.last_seen_at.tzinfo is None) else d.last_seen_at
                if curr_seen is None or rep_dt > curr_seen or d.last_lat is None:
                    d.last_lat = latest_rep.latitude
                    d.last_lon = latest_rep.longitude
                    d.last_seen_at = datetime.fromtimestamp(latest_rep.timestamp_published / 1000)
                    d.last_battery = latest_rep.battery_status
                    has_updates = True
        if d.last_seen_at and d.last_seen_at.tzinfo is None:
            d.last_seen_at = d.last_seen_at.replace(tzinfo=timezone.utc)
            
    if has_updates:
        await db.commit()

    return [DeviceResponse.model_validate(d) for d in devices]


@router.post("", response_model=DeviceResponse)
async def create_device(
    body: DeviceCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Check if device with same name OR hashed_adv_key already registered for this user
    import base64
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
    import hashlib

    derived_hashed_key = body.hashed_adv_key
    if body.private_key_b64:
        try:
            import json
            try:
                priv = json.loads(body.private_key_b64).get("privateKey", body.private_key_b64)
            except:
                priv = body.private_key_b64
            
            priv_bytes = base64.b64decode(priv)
            if len(priv_bytes) == 28:
                priv_int = int.from_bytes(priv_bytes, "big")
                priv_key = ec.derive_private_key(priv_int, ec.SECP224R1())
                pub_key = priv_key.public_key()
                pub_bytes = pub_key.public_numbers().x.to_bytes(28, "big")
                sha256 = hashlib.sha256()
                sha256.update(pub_bytes)
                derived_hashed_key = base64.b64encode(sha256.digest()).decode("ascii")
        except Exception:
            pass

    from app.models import LocationReport
    from datetime import datetime

    async def restore_history(d: Device):
        latest = await db.execute(
            select(LocationReport)
            .where(LocationReport.hashed_adv_key == d.hashed_adv_key)
            .where(LocationReport.latitude.isnot(None))
            .order_by(LocationReport.timestamp_published.desc())
            .limit(1)
        )
        latest_rep = latest.scalar_one_or_none()
        if latest_rep:
            d.last_lat = latest_rep.latitude
            d.last_lon = latest_rep.longitude
            d.last_seen_at = datetime.fromtimestamp(latest_rep.timestamp_published / 1000)
            d.last_battery = latest_rep.battery_status

    existing = await db.execute(
        select(Device).where(
            Device.user_id == current_user.id,
            (Device.hashed_adv_key == derived_hashed_key) | (Device.name == body.name),
        )
    )
    dev = existing.scalar_one_or_none()
    if dev:
        dev.name           = body.name
        dev.hashed_adv_key = derived_hashed_key
        dev.private_key_b64 = body.private_key_b64
        await restore_history(dev)
        await db.commit()
        await db.refresh(dev)
        return DeviceResponse.model_validate(dev)

    device = Device(
        user_id        = current_user.id,
        name           = body.name,
        hashed_adv_key = derived_hashed_key,
        private_key_b64 = body.private_key_b64,
    )
    db.add(device)
    await restore_history(device)
    await db.commit()
    await db.refresh(device)
    return DeviceResponse.model_validate(device)


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_device(
    device_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Device).where(Device.id == device_id, Device.user_id == current_user.id)
    )
    device = result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    await db.delete(device)
    await db.commit()
    return None


@router.get("/{device_id}/locations", response_model=LocationHistoryResponse)
async def get_device_location_history(
    device_id: int,
    from_ts: Optional[int] = Query(None, description="Start time in unix milliseconds (0 = all time)"),
    to_ts: Optional[int] = Query(None, description="End time in unix milliseconds"),
    days: Optional[int] = Query(None, description="Shorthand: number of days back from now"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Get the decrypted location history for a device.

    Supports two query modes:
    - `days=N` — fetch the last N days
    - `from_ts` / `to_ts` — explicit unix millisecond range (0 = no lower bound)
    """
    from datetime import datetime, timedelta, timezone

    # Verify device belongs to user
    dev_result = await db.execute(
        select(Device).where(Device.id == device_id, Device.user_id == current_user.id)
    )
    device = dev_result.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    # Build time range
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

    if days is not None and days > 0:
        from_ms = int((datetime.now(timezone.utc) - timedelta(days=days)).timestamp() * 1000)
        to_ms   = now_ms
    elif from_ts is not None:
        from_ms = from_ts  # 0 means no lower bound
        to_ms   = to_ts if to_ts is not None else now_ms
    else:
        # Default: last 1 day
        from_ms = int((datetime.now(timezone.utc) - timedelta(days=1)).timestamp() * 1000)
        to_ms   = now_ms

    # Query decrypted reports
    stmt = (
        select(LocationReport)
        .where(
            LocationReport.hashed_adv_key == device.hashed_adv_key,
            LocationReport.latitude.is_not(None),
            LocationReport.longitude.is_not(None),
        )
    )
    if from_ms > 0:
        stmt = stmt.where(LocationReport.timestamp_published >= from_ms)
    if to_ms:
        stmt = stmt.where(LocationReport.timestamp_published <= to_ms)

    stmt = stmt.order_by(LocationReport.timestamp_published.asc())

    result = await db.execute(stmt)
    reports = result.scalars().all()

    items = [
        LocationHistoryItem(
            latitude               = rep.latitude,
            longitude              = rep.longitude,
            accuracy               = rep.accuracy,
            battery_status         = rep.battery_status,
            timestamp_ms           = int(rep.decrypted_at.timestamp() * 1000)
                                     if rep.decrypted_at else rep.timestamp_published,
            timestamp_published_ms = rep.timestamp_published,
        )
        for rep in reports
    ]

    return LocationHistoryResponse(
        hashed_adv_key = device.hashed_adv_key,
        items          = items,
        total          = len(items),
    )
