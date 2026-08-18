from typing import List, Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models import User, Device, LocationReport
from app.schemas import (
    DeviceCreateRequest,
    DeviceResponse,
    LocationHistoryItem,
    LocationHistoryResponse,
    ShareDeviceRequest,
    SharedUserInfo,
)
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/api/devices", tags=["Devices"])


@router.get("/available-users")
async def list_available_users(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Returns other registered users that the current user can share devices with."""
    result = await db.execute(select(User).where(User.id != current_user.id))
    users = result.scalars().all()
    return [{"id": u.id, "email": u.email, "name": u.name, "picture": u.picture} for u in users]


@router.get("/shared-with", response_model=List[SharedUserInfo])
async def get_shared_users(
    device_id: Optional[int] = Query(None),
    hashed_adv_key: Optional[str] = Query(None),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get list of other users with whom this device is currently shared."""
    stmt = select(Device).where(Device.user_id == current_user.id)
    if device_id:
        stmt = stmt.where(Device.id == device_id)
    elif hashed_adv_key:
        stmt = stmt.where(Device.hashed_adv_key == hashed_adv_key)
    else:
        raise HTTPException(status_code=400, detail="device_id hoặc hashed_adv_key là bắt buộc")

    source_dev = (await db.execute(stmt)).scalar_one_or_none()
    if not source_dev:
        # If device not found for this user, check if this user is a shared recipient
        # by searching by hashed_adv_key
        if hashed_adv_key:
            source_dev = (await db.execute(
                select(Device).where(
                    Device.hashed_adv_key == hashed_adv_key,
                    Device.user_id == current_user.id
                )
            )).scalar_one_or_none()
        if not source_dev:
            raise HTTPException(status_code=404, detail="Không tìm thấy thiết bị")

    # Find all other instances of this key belonging to other users
    shared_stmt = (
        select(Device, User)
        .join(User, Device.user_id == User.id)
        .where(
            Device.hashed_adv_key == source_dev.hashed_adv_key,
            Device.user_id != current_user.id,
        )
    )
    results = (await db.execute(shared_stmt)).all()

    shared_users = []
    for dev, user in results:
        shared_users.append(
            SharedUserInfo(
                device_id=dev.id,
                user_id=user.id,
                email=user.email,
                name=user.name,
                picture=user.picture,
            )
        )
    return shared_users


@router.post("/share")
async def share_device_to_user(
    body: ShareDeviceRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Share a device with another registered user by email or user_id."""
    stmt = select(Device).where(Device.user_id == current_user.id)
    if body.device_id:
        stmt = stmt.where(Device.id == body.device_id)
    elif body.hashed_adv_key:
        stmt = stmt.where(Device.hashed_adv_key == body.hashed_adv_key)
    else:
        raise HTTPException(status_code=400, detail="device_id hoặc hashed_adv_key là bắt buộc")

    source_dev = (await db.execute(stmt)).scalar_one_or_none()
    if not source_dev:
        raise HTTPException(status_code=404, detail="Không tìm thấy thiết bị trong tài khoản của bạn")

    # Find target user
    target_user = None
    if body.target_user_id:
        target_user = (await db.execute(select(User).where(User.id == body.target_user_id))).scalar_one_or_none()
    elif body.target_email:
        clean_email = body.target_email.strip().lower()
        target_user = (await db.execute(select(User).where(func.lower(User.email) == clean_email))).scalar_one_or_none()

    if not target_user:
        raise HTTPException(
            status_code=404,
            detail="Không tìm thấy người dùng này. Người thân cần đăng nhập vào hệ thống trước!",
        )

    if target_user.id == current_user.id:
        raise HTTPException(status_code=400, detail="Bạn không thể tự chia sẻ thiết bị cho chính mình")

    # Check if target user already has device
    existing = (
        await db.execute(
            select(Device).where(
                Device.user_id == target_user.id,
                Device.hashed_adv_key == source_dev.hashed_adv_key,
            )
        )
    ).scalar_one_or_none()

    if existing:
        return {"status": "ok", "message": f"Tài khoản {target_user.email} đã có Tag này rồi"}

    new_dev = Device(
        user_id=target_user.id,
        name=source_dev.name,
        hashed_adv_key=source_dev.hashed_adv_key,
        private_key_b64=source_dev.private_key_b64,
        last_lat=source_dev.last_lat,
        last_lon=source_dev.last_lon,
        last_seen_at=source_dev.last_seen_at,
        last_battery=source_dev.last_battery,
    )
    db.add(new_dev)
    await db.commit()
    return {"status": "ok", "message": f"Đã chia sẻ thiết bị '{source_dev.name}' cho {target_user.email}"}


@router.delete("/shared-with/{target_device_id}")
async def unshare_device_from_user(
    target_device_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Unshare a device by deleting the target user's shared device instance."""
    target_dev = (await db.execute(select(Device).where(Device.id == target_device_id))).scalar_one_or_none()
    if not target_dev:
        raise HTTPException(status_code=404, detail="Không tìm thấy thiết bị chia sẻ")

    # Check if current user has the matching key
    owner_dev = (
        await db.execute(
            select(Device).where(
                Device.user_id == current_user.id,
                Device.hashed_adv_key == target_dev.hashed_adv_key,
            )
        )
    ).scalar_one_or_none()

    if not owner_dev:
        raise HTTPException(status_code=403, detail="Bạn không có quyền hủy chia sẻ thiết bị này")

    await db.delete(target_dev)
    await db.commit()
    return {"status": "ok", "message": "Đã hủy chia sẻ thiết bị thành công"}


@router.get("", response_model=List[DeviceResponse])
async def list_devices(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Device).where(Device.user_id == current_user.id))
    devices = result.scalars().all()
    has_updates = False
    for d in devices:
        if d.hashed_adv_key:
            latest = await db.execute(
                select(LocationReport)
                .where(LocationReport.hashed_adv_key == d.hashed_adv_key)
                .where(LocationReport.latitude.isnot(None))
                .order_by(LocationReport.timestamp_published.desc(), LocationReport.id.desc())
                .limit(1)
            )
            latest_rep = latest.scalar_one_or_none()
            if latest_rep:
                rep_dt_utc = datetime.fromtimestamp(latest_rep.timestamp_published / 1000, tz=timezone.utc)
                if d.last_lat != latest_rep.latitude or d.last_lon != latest_rep.longitude or d.last_lat is None:
                    d.last_lat = latest_rep.latitude
                    d.last_lon = latest_rep.longitude
                    d.last_seen_at = rep_dt_utc.replace(tzinfo=None)
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

    async def restore_history(d: Device):
        latest = await db.execute(
            select(LocationReport)
            .where(LocationReport.hashed_adv_key == d.hashed_adv_key)
            .where(LocationReport.latitude.isnot(None))
            .order_by(LocationReport.timestamp_published.desc(), LocationReport.id.desc())
            .limit(1)
        )
        latest_rep = latest.scalar_one_or_none()
        if latest_rep:
            d.last_lat = latest_rep.latitude
            d.last_lon = latest_rep.longitude
            d.last_seen_at = datetime.fromtimestamp(latest_rep.timestamp_published / 1000, tz=timezone.utc).replace(tzinfo=None)
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
            timestamp_ms           = rep.timestamp_published,
            timestamp_published_ms = rep.timestamp_published,
        )
        for rep in reports
    ]

    return LocationHistoryResponse(
        hashed_adv_key = device.hashed_adv_key,
        items          = items,
        total          = len(items),
    )
