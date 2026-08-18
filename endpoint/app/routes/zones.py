import json
from typing import List, Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, func, delete, or_
from sqlalchemy.orm import joinedload
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, Device, Zone, ZoneDevice, ZoneAlert
from app.schemas import (
    ZoneCreateRequest,
    ZoneUpdateRequest,
    ZoneResponse,
    ZoneDeviceItemResponse,
    ZoneAlertItemResponse,
    ZoneAlertListResponse,
    PolygonPoint,
)
from app.services.auth_service import get_current_user
from app.services.geofence_service import haversine_distance, point_in_polygon

router = APIRouter(prefix="/api/zones", tags=["Zones & Geofencing"])


def _format_zone_response(zone: Zone) -> ZoneResponse:
    devices_data: list[ZoneDeviceItemResponse] = []
    for zd in zone.zone_devices or []:
        dev = zd.device
        if dev:
            devices_data.append(
                ZoneDeviceItemResponse(
                    device_id=dev.id,
                    device_name=dev.name,
                    hashed_adv_key=dev.hashed_adv_key,
                    last_status=zd.last_status or "UNKNOWN",
                    last_distance=zd.last_distance,
                    last_alert_time=zd.last_alert_time,
                    last_alert_type=zd.last_alert_type,
                )
            )

    poly_points: list[PolygonPoint] | None = None
    if getattr(zone, "polygon_points", None):
        try:
            raw_pts = json.loads(zone.polygon_points)
            poly_points = [
                PolygonPoint(
                    lat=p.get("lat", p.get("latitude", 0.0)),
                    lon=p.get("lon", p.get("longitude", 0.0))
                )
                for p in raw_pts
            ]
        except Exception:
            poly_points = None

    return ZoneResponse(
        id=zone.id,
        user_id=zone.user_id,
        name=zone.name,
        latitude=zone.latitude,
        longitude=zone.longitude,
        radius=zone.radius,
        shape_type=getattr(zone, "shape_type", "circle"),
        polygon_points=poly_points,
        alert_on_exit=zone.alert_on_exit,
        alert_on_enter=zone.alert_on_enter,
        cooldown_minutes=zone.cooldown_minutes,
        is_active=zone.is_active,
        created_at=zone.created_at,
        updated_at=zone.updated_at,
        devices=devices_data,
    )


@router.get("/", response_model=List[ZoneResponse])
async def list_zones(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    List all geofence zones belonging to the current user, including assigned devices.
    """
    stmt = (
        select(Zone)
        .options(
            joinedload(Zone.zone_devices).joinedload(ZoneDevice.device)
        )
        .where(Zone.user_id == current_user.id)
        .order_by(Zone.id.asc())
    )
    result = await db.execute(stmt)
    zones = result.unique().scalars().all()
    return [_format_zone_response(z) for z in zones]


@router.post("/", response_model=ZoneResponse, status_code=status.HTTP_201_CREATED)
async def create_zone(
    body: ZoneCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Create a new geofence safe zone (circle or polygon) and optionally associate devices to it.
    """
    poly_str: str | None = None
    if body.polygon_points and len(body.polygon_points) >= 3:
        poly_str = json.dumps([{"lat": p.lat, "lon": p.lon} for p in body.polygon_points])

    new_zone = Zone(
        user_id=current_user.id,
        name=body.name.strip(),
        latitude=body.latitude,
        longitude=body.longitude,
        radius=max(10.0, float(body.radius)),
        shape_type="polygon" if body.shape_type == "polygon" and poly_str else "circle",
        polygon_points=poly_str,
        alert_on_exit=body.alert_on_exit,
        alert_on_enter=body.alert_on_enter,
        cooldown_minutes=max(1, body.cooldown_minutes),
        is_active=body.is_active,
    )
    db.add(new_zone)
    await db.flush()  # populate new_zone.id

    # Associate devices (match by ID or hashed_adv_key)
    if body.device_ids or body.hashed_adv_keys:
        conditions = []
        if body.device_ids:
            conditions.append(Device.id.in_(body.device_ids))
        if body.hashed_adv_keys:
            conditions.append(Device.hashed_adv_key.in_(body.hashed_adv_keys))

        dev_stmt = select(Device).where(
            or_(*conditions),
            Device.user_id == current_user.id
        )
        dev_res = await db.execute(dev_stmt)
        valid_devices = dev_res.scalars().all()

        now = datetime.now(timezone.utc)
        for dev in valid_devices:
            initial_status = "UNKNOWN"
            initial_dist = None
            if dev.last_lat is not None and dev.last_lon is not None:
                initial_dist = haversine_distance(
                    dev.last_lat, dev.last_lon, new_zone.latitude, new_zone.longitude
                )
                if new_zone.shape_type == "polygon" and body.polygon_points:
                    pts = [{"lat": p.lat, "lon": p.lon} for p in body.polygon_points]
                    initial_status = "INSIDE" if point_in_polygon(dev.last_lat, dev.last_lon, pts) else "OUTSIDE"
                else:
                    initial_status = "INSIDE" if initial_dist <= new_zone.radius else "OUTSIDE"

            zd = ZoneDevice(
                zone_id=new_zone.id,
                device_id=dev.id,
                last_status=initial_status,
                last_distance=initial_dist,
                updated_at=now,
            )
            db.add(zd)

    created_zone_id = new_zone.id
    await db.commit()
    db.expunge_all()

    # Re-fetch full object with relations
    stmt = (
        select(Zone)
        .options(joinedload(Zone.zone_devices).joinedload(ZoneDevice.device))
        .where(Zone.id == created_zone_id)
    )
    res = await db.execute(stmt)
    full_zone = res.unique().scalar_one()
    return _format_zone_response(full_zone)


@router.get("/{zone_id}", response_model=ZoneResponse)
async def get_zone_by_id(
    zone_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Get details of a specific safe zone.
    """
    stmt = (
        select(Zone)
        .options(joinedload(Zone.zone_devices).joinedload(ZoneDevice.device))
        .where(Zone.id == zone_id, Zone.user_id == current_user.id)
    )
    result = await db.execute(stmt)
    zone = result.unique().scalar_one_or_none()
    if not zone:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Khu vực không tồn tại.")
    return _format_zone_response(zone)


@router.put("/{zone_id}", response_model=ZoneResponse)
async def update_zone(
    zone_id: int,
    body: ZoneUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Update a safe zone settings and assigned devices.
    """
    stmt = (
        select(Zone)
        .options(joinedload(Zone.zone_devices).joinedload(ZoneDevice.device))
        .where(Zone.id == zone_id, Zone.user_id == current_user.id)
    )
    result = await db.execute(stmt)
    zone = result.unique().scalar_one_or_none()
    if not zone:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Khu vực không tồn tại.")

    if body.name is not None:
        zone.name = body.name.strip()
    if body.latitude is not None:
        zone.latitude = body.latitude
    if body.longitude is not None:
        zone.longitude = body.longitude
    if body.radius is not None:
        zone.radius = max(10.0, float(body.radius))
    if body.shape_type is not None:
        zone.shape_type = body.shape_type
    if body.polygon_points is not None:
        if len(body.polygon_points) >= 3:
            zone.polygon_points = json.dumps([{"lat": p.lat, "lon": p.lon} for p in body.polygon_points])
        else:
            zone.polygon_points = None
    if body.alert_on_exit is not None:
        zone.alert_on_exit = body.alert_on_exit
    if body.alert_on_enter is not None:
        zone.alert_on_enter = body.alert_on_enter
    if body.cooldown_minutes is not None:
        zone.cooldown_minutes = max(1, body.cooldown_minutes)
    if body.is_active is not None:
        zone.is_active = body.is_active

    zone.updated_at = datetime.now(timezone.utc)

    # Handle device list updates if provided
    if body.device_ids is not None or body.hashed_adv_keys is not None:
        conditions = []
        if body.device_ids is not None and len(body.device_ids) > 0:
            conditions.append(Device.id.in_(body.device_ids))
        if body.hashed_adv_keys is not None and len(body.hashed_adv_keys) > 0:
            conditions.append(Device.hashed_adv_key.in_(body.hashed_adv_keys))

        if conditions:
            dev_stmt = select(Device).where(
                or_(*conditions),
                Device.user_id == current_user.id
            )
            dev_res = await db.execute(dev_stmt)
            valid_devices = {d.id: d for d in dev_res.scalars().all()}
        else:
            valid_devices = {}

        existing_links = {zd.device_id: zd for zd in zone.zone_devices or []}

        # Remove unselected devices
        for dev_id, zd in list(existing_links.items()):
            if dev_id not in valid_devices:
                await db.delete(zd)

        # Add or update selected devices
        now = datetime.now(timezone.utc)
        for dev_id, dev in valid_devices.items():
            initial_dist = None
            if dev.last_lat is not None and dev.last_lon is not None:
                initial_dist = haversine_distance(
                    dev.last_lat, dev.last_lon, zone.latitude, zone.longitude
                )

            if dev_id in existing_links:
                zd = existing_links[dev_id]
                if initial_dist is not None:
                    zd.last_distance = initial_dist
                    zd.last_status = "INSIDE" if initial_dist <= zone.radius else "OUTSIDE"
            else:
                initial_status = "UNKNOWN"
                if initial_dist is not None:
                    initial_status = "INSIDE" if initial_dist <= zone.radius else "OUTSIDE"
                new_zd = ZoneDevice(
                    zone_id=zone.id,
                    device_id=dev.id,
                    last_status=initial_status,
                    last_distance=initial_dist,
                    updated_at=now,
                )
                db.add(new_zd)

    target_zone_id = zone.id
    await db.commit()
    db.expunge_all()

    # Re-fetch full object
    res = await db.execute(
        select(Zone)
        .options(joinedload(Zone.zone_devices).joinedload(ZoneDevice.device))
        .where(Zone.id == target_zone_id, Zone.user_id == current_user.id)
    )
    full_zone = res.unique().scalar_one()
    return _format_zone_response(full_zone)


@router.delete("/{zone_id}", status_code=status.HTTP_200_OK)
async def delete_zone(
    zone_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Delete a safe zone. Cascades to associated device bindings and alert records.
    """
    stmt = select(Zone).where(Zone.id == zone_id, Zone.user_id == current_user.id)
    result = await db.execute(stmt)
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Khu vực không tồn tại.")

    await db.delete(zone)
    await db.commit()
    return {"status": "ok", "message": f"Đã xóa khu vực '{zone.name}'."}


# ── Alerts History ────────────────────────────────────────────────────────────

@router.get("/alerts/history", response_model=ZoneAlertListResponse)
async def get_alerts_history(
    zone_id: Optional[int] = Query(None),
    device_id: Optional[int] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Retrieve geofence alert logs for the current user with pagination and filters.
    """
    base_stmt = (
        select(ZoneAlert)
        .options(
            joinedload(ZoneAlert.zone),
            joinedload(ZoneAlert.device)
        )
        .where(ZoneAlert.user_id == current_user.id)
    )

    if zone_id:
        base_stmt = base_stmt.where(ZoneAlert.zone_id == zone_id)
    if device_id:
        base_stmt = base_stmt.where(ZoneAlert.device_id == device_id)

    # Total count
    count_stmt = select(func.count(ZoneAlert.id)).where(ZoneAlert.user_id == current_user.id)
    if zone_id:
        count_stmt = count_stmt.where(ZoneAlert.zone_id == zone_id)
    if device_id:
        count_stmt = count_stmt.where(ZoneAlert.device_id == device_id)

    total_res = await db.execute(count_stmt)
    total = total_res.scalar_one() or 0

    # Paginated query
    paged_stmt = base_stmt.order_by(ZoneAlert.id.desc()).offset(offset).limit(limit)
    res = await db.execute(paged_stmt)
    alerts = res.scalars().all()

    items = []
    for a in alerts:
        items.append(
            ZoneAlertItemResponse(
                id=a.id,
                zone_id=a.zone_id,
                zone_name=a.zone.name if a.zone else "Đã xóa",
                device_id=a.device_id,
                device_name=a.device.name if a.device else "Đã xóa",
                alert_type=a.alert_type,
                latitude=a.latitude,
                longitude=a.longitude,
                distance=a.distance,
                created_at=a.created_at,
            )
        )

    return ZoneAlertListResponse(items=items, total=total)


@router.delete("/alerts/{alert_id}", status_code=status.HTTP_200_OK)
async def delete_alert(
    alert_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Delete a single alert log record.
    """
    stmt = select(ZoneAlert).where(ZoneAlert.id == alert_id, ZoneAlert.user_id == current_user.id)
    result = await db.execute(stmt)
    alert = result.scalar_one_or_none()
    if not alert:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bản ghi cảnh báo không tồn tại.")

    await db.delete(alert)
    await db.commit()
    return {"status": "ok", "message": "Đã xóa bản ghi cảnh báo."}


@router.delete("/alerts", status_code=status.HTTP_200_OK)
async def clear_all_alerts(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Clear all alert logs for the current user.
    """
    stmt = delete(ZoneAlert).where(ZoneAlert.user_id == current_user.id)
    await db.execute(stmt)
    await db.commit()
    return {"status": "ok", "message": "Đã xóa toàn bộ lịch sử cảnh báo."}
