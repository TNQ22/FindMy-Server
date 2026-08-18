from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import joinedload
from app.database import get_db
from app.models import User, Device
from app.schemas import AdminUserListResponse, AdminAddDeviceRequest, AdminRoleUpdateRequest
from app.services.auth_service import get_current_user
import hashlib
import base64
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/admin", tags=["Admin"])

async def get_admin_user(current_user: User = Depends(get_current_user)):
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin privileges required")
    return current_user

@router.get("/users", response_model=list[AdminUserListResponse])
async def list_users(
    admin_user: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db)
):
    # Fetch all users and count their devices
    # SQLite friendly query
    result = await db.execute(select(User).options(joinedload(User.devices)))
    users = result.unique().scalars().all()
    
    response = []
    for u in users:
        response.append(AdminUserListResponse(
            id=u.id,
            email=u.email,
            name=u.name,
            picture=u.picture,
            is_admin=u.is_admin,
            device_count=len(u.devices),
            created_at=u.created_at
        ))
    return response

@router.delete("/users/{user_id}")
async def delete_user(
    user_id: int,
    admin_user: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db)
):
    if user_id == admin_user.id:
        raise HTTPException(status_code=400, detail="Cannot delete yourself")
        
    result = await db.execute(select(User).where(User.id == user_id))
    target_user = result.scalar_one_or_none()
    
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")
        
    await db.delete(target_user)
    await db.commit()
    return {"status": "ok", "message": f"User {target_user.email} deleted"}

@router.put("/users/{user_id}/role")
async def update_user_role(
    user_id: int,
    body: AdminRoleUpdateRequest,
    admin_user: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db)
):
    if user_id == admin_user.id:
        raise HTTPException(status_code=400, detail="Cannot change your own role")
        
    result = await db.execute(select(User).where(User.id == user_id))
    target_user = result.scalar_one_or_none()
    
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")
        
    target_user.is_admin = body.is_admin
    await db.commit()
    return {"status": "ok", "message": f"Role updated for {target_user.email}"}

@router.post("/users/{user_id}/devices")
async def add_device_for_user(
    user_id: int,
    body: AdminAddDeviceRequest,
    admin_user: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db)
):
    # Verify user exists
    result = await db.execute(select(User).where(User.id == user_id))
    target_user = result.scalar_one_or_none()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    try:
        import json
        try:
            priv = json.loads(body.private_key_b64).get("privateKey", body.private_key_b64)
        except:
            priv = body.private_key_b64
        
        raw_key = base64.b64decode(priv)
        if len(raw_key) != 28:
            raise ValueError("Invalid private key length (expected 28 bytes).")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid private key format: {e}")

    # Derive hashed advertisement key: sha256(28-byte X coordinate of SECP224R1 public key)
    # Matches OpenHaystack / Apple FindMy specification
    import cryptography.hazmat.primitives.asymmetric.ec as ec
    from cryptography.hazmat.backends import default_backend

    try:
        priv_int = int.from_bytes(raw_key, "big")
        private_key = ec.derive_private_key(priv_int, ec.SECP224R1(), default_backend())
        pub_key = private_key.public_key()
        pub_bytes = pub_key.public_numbers().x.to_bytes(28, "big")
        
        hasher = hashlib.sha256()
        hasher.update(pub_bytes)
        b64_hashed_key = base64.b64encode(hasher.digest()).decode("ascii")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to derive public key: {e}")

    # Check if exists for THIS user
    existing = await db.execute(
        select(Device).where(
            Device.user_id == user_id,
            Device.hashed_adv_key == b64_hashed_key
        )
    )
    dev = existing.scalar_one_or_none()
    if dev:
        dev.name = body.name
        dev.private_key_b64 = body.private_key_b64
    else:
        dev = Device(
            user_id=user_id,
            name=body.name,
            hashed_adv_key=b64_hashed_key,
            private_key_b64=body.private_key_b64
        )
        db.add(dev)

    # Restore history so the device appears on the map immediately if location exists
    from app.models import LocationReport
    from datetime import datetime
    latest = await db.execute(
        select(LocationReport)
        .where(LocationReport.hashed_adv_key == dev.hashed_adv_key)
        .where(LocationReport.latitude.isnot(None))
        .order_by(LocationReport.timestamp_published.desc())
        .limit(1)
    )
    latest_rep = latest.scalar_one_or_none()
    if latest_rep:
        dev.last_lat = latest_rep.latitude
        dev.last_lon = latest_rep.longitude
        from datetime import timezone
        dev.last_seen_at = datetime.fromtimestamp(latest_rep.timestamp_published / 1000, tz=timezone.utc).replace(tzinfo=None)
        dev.last_battery = latest_rep.battery_status

    await db.commit()
    await db.refresh(dev)
    return {"status": "ok", "message": "Device saved successfully", "device_id": dev.id}


@router.get("/users/{user_id}/devices")
async def list_user_devices(
    user_id: int,
    admin_user: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Device).where(Device.user_id == user_id))
    devices = result.scalars().all()
    
    # Find all users sharing the same devices (by hashed_adv_key)
    all_hashed_keys = [d.hashed_adv_key for d in devices]
    shared_map: dict[str, list[dict]] = {}
    if all_hashed_keys:
        shared_res = await db.execute(
            select(Device)
            .options(joinedload(Device.user))
            .where(Device.hashed_adv_key.in_(all_hashed_keys))
        )
        all_shared_devs = shared_res.scalars().all()
        for sd in all_shared_devs:
            if sd.user_id != user_id and sd.user:
                if sd.hashed_adv_key not in shared_map:
                    shared_map[sd.hashed_adv_key] = []
                shared_map[sd.hashed_adv_key].append({
                    "device_id": sd.id,
                    "user_id": sd.user.id,
                    "email": sd.user.email,
                    "name": sd.user.name,
                })

    from datetime import timezone
    out = []
    for d in devices:
        last_seen = d.last_seen_at
        if last_seen and last_seen.tzinfo is None:
            last_seen = last_seen.replace(tzinfo=timezone.utc)
        out.append({
            "id": d.id,
            "name": d.name,
            "hashed_adv_key": d.hashed_adv_key,
            "private_key_b64": d.private_key_b64,
            "last_lat": d.last_lat,
            "last_lon": d.last_lon,
            "last_seen_at": last_seen.isoformat() if last_seen else None,
            "last_battery": d.last_battery,
            "shared_with": shared_map.get(d.hashed_adv_key, []),
        })
    return out


@router.post("/share-device")
async def share_device(
    payload: dict,
    admin_user: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db)
):
    device_id = payload.get("device_id")
    target_user_id = payload.get("target_user_id")

    if not device_id or not target_user_id:
        raise HTTPException(status_code=400, detail="device_id and target_user_id are required")

    # Verify target user exists
    target_user = (await db.execute(select(User).where(User.id == target_user_id))).scalar_one_or_none()
    if not target_user:
        raise HTTPException(status_code=404, detail="Target user not found")

    # Fetch source device
    source_dev = (await db.execute(select(Device).where(Device.id == device_id))).scalar_one_or_none()
    if not source_dev:
        raise HTTPException(status_code=404, detail="Source device not found")

    # Check if target user already has this device
    existing = (await db.execute(
        select(Device).where(
            Device.user_id == target_user_id,
            Device.hashed_adv_key == source_dev.hashed_adv_key
        )
    )).scalar_one_or_none()

    if existing:
        return {"status": "ok", "message": f"User {target_user.email} đã có Tag này rồi"}

    # Copy device to target user
    new_dev = Device(
        user_id=target_user_id,
        name=source_dev.name,
        hashed_adv_key=source_dev.hashed_adv_key,
        private_key_b64=source_dev.private_key_b64,
        last_lat=source_dev.last_lat,
        last_lon=source_dev.last_lon,
        last_seen_at=source_dev.last_seen_at,
        last_battery=source_dev.last_battery
    )
    db.add(new_dev)
    await db.commit()
    return {"status": "ok", "message": f"Đã chia sẻ Tag '{source_dev.name}' cho {target_user.email}"}


@router.delete("/devices/{device_id}")
async def delete_admin_device(
    device_id: int,
    admin_user: User = Depends(get_admin_user),
    db: AsyncSession = Depends(get_db)
):
    dev = (await db.execute(select(Device).where(Device.id == device_id))).scalar_one_or_none()
    if not dev:
        raise HTTPException(status_code=404, detail="Device not found")
    await db.delete(dev)
    await db.commit()
    return {"status": "ok", "message": f"Device {device_id} deleted"}

