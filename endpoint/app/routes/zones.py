import json
from typing import List, Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, func, delete, or_
from sqlalchemy.orm import joinedload
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User, Device, Zone, ZoneDevice, ZoneAlert, ZoneSchedule
from app.schemas import (
    ZoneCreateRequest,
    ZoneUpdateRequest,
    ZoneResponse,
    ZoneDeviceItemResponse,
    ZoneAlertItemResponse,
    ZoneAlertListResponse,
    ZoneScheduleCreate,
    ZoneScheduleUpdate,
    ZoneScheduleResponse,
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

    schedules_data: list[ZoneScheduleResponse] = []
    for s in getattr(zone, "schedules", []) or []:
        if not s.is_active:
            continue
        days = []
        try:
            days = json.loads(s.days_of_week) if isinstance(s.days_of_week, str) else (s.days_of_week or [1, 2, 3, 4, 5, 6, 7])
        except Exception:
            days = [1, 2, 3, 4, 5, 6, 7]

        dev_name = "Tất cả thiết bị"
        if s.device_id:
            for zd in getattr(zone, "zone_devices", []) or []:
                if zd.device and zd.device.id == s.device_id:
                    dev_name = zd.device.name
                    break

        schedules_data.append(
            ZoneScheduleResponse(
                id=s.id,
                zone_id=s.zone_id,
                device_id=s.device_id,
                device_name=dev_name,
                user_id=s.user_id,
                rule_type=s.rule_type,
                target_time=s.target_time,
                days_of_week=days,
                is_active=s.is_active,
                last_triggered_date=s.last_triggered_date,
                created_at=s.created_at,
            )
        )

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
        is_safe_zone=getattr(zone, "is_safe_zone", True),
        created_at=zone.created_at,
        updated_at=zone.updated_at,
        devices=devices_data,
        schedules=schedules_data,
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
            joinedload(Zone.zone_devices).joinedload(ZoneDevice.device),
            joinedload(Zone.schedules),
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
        is_safe_zone=body.is_safe_zone,
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
        .options(
            joinedload(Zone.zone_devices).joinedload(ZoneDevice.device),
            joinedload(Zone.schedules),
        )
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
        .options(
            joinedload(Zone.zone_devices).joinedload(ZoneDevice.device),
            joinedload(Zone.schedules),
        )
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
    if body.is_safe_zone is not None:
        zone.is_safe_zone = body.is_safe_zone

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


@router.get("/{zone_id}/schedules", response_model=List[ZoneScheduleResponse])
async def list_zone_schedules(
    zone_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    List all time schedule reminder rules for a specific zone.
    """
    z_stmt = select(Zone).where(Zone.id == zone_id, Zone.user_id == current_user.id)
    zone = (await db.execute(z_stmt)).scalar_one_or_none()
    if not zone:
        raise HTTPException(status_code=404, detail="Khu vực không tồn tại")

    stmt = (
        select(ZoneSchedule)
        .options(joinedload(ZoneSchedule.device))
        .where(ZoneSchedule.zone_id == zone_id, ZoneSchedule.user_id == current_user.id)
        .order_by(ZoneSchedule.target_time.asc())
    )
    schedules = (await db.execute(stmt)).scalars().all()

    resp = []
    for s in schedules:
        days = []
        try:
            days = json.loads(s.days_of_week)
        except Exception:
            days = [1, 2, 3, 4, 5, 6, 7]
        resp.append(
            ZoneScheduleResponse(
                id=s.id,
                zone_id=s.zone_id,
                device_id=s.device_id,
                device_name=s.device.name if s.device else "Tất cả thiết bị",
                user_id=s.user_id,
                rule_type=s.rule_type,
                target_time=s.target_time,
                days_of_week=days,
                is_active=s.is_active,
                last_triggered_date=s.last_triggered_date,
                created_at=s.created_at,
            )
        )
    return resp


@router.post("/{zone_id}/schedules", response_model=ZoneScheduleResponse, status_code=status.HTTP_201_CREATED)
async def create_zone_schedule(
    zone_id: int,
    body: ZoneScheduleCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Create a new time-based reminder rule for this zone.
    """
    z_stmt = select(Zone).where(Zone.id == zone_id, Zone.user_id == current_user.id)
    zone = (await db.execute(z_stmt)).scalar_one_or_none()
    if not zone:
        raise HTTPException(status_code=404, detail="Khu vực không tồn tại")

    device_name = "Tất cả thiết bị"
    if body.device_id:
        d_stmt = select(Device).where(Device.id == body.device_id, Device.user_id == current_user.id)
        device = (await db.execute(d_stmt)).scalar_one_or_none()
        if not device:
            raise HTTPException(status_code=400, detail="Thiết bị không tồn tại")
        device_name = device.name

    days_json = json.dumps(body.days_of_week or [1, 2, 3, 4, 5, 6, 7])
    new_sched = ZoneSchedule(
        zone_id=zone_id,
        device_id=body.device_id,
        user_id=current_user.id,
        rule_type=body.rule_type,
        target_time=body.target_time,
        days_of_week=days_json,
        is_active=body.is_active,
    )
    db.add(new_sched)
    await db.commit()
    await db.refresh(new_sched)

    return ZoneScheduleResponse(
        id=new_sched.id,
        zone_id=new_sched.zone_id,
        device_id=new_sched.device_id,
        device_name=device_name,
        user_id=new_sched.user_id,
        rule_type=new_sched.rule_type,
        target_time=new_sched.target_time,
        days_of_week=body.days_of_week or [1, 2, 3, 4, 5, 6, 7],
        is_active=new_sched.is_active,
        last_triggered_date=new_sched.last_triggered_date,
        created_at=new_sched.created_at,
    )


@router.put("/schedules/{schedule_id}", response_model=ZoneScheduleResponse)
async def update_zone_schedule(
    schedule_id: int,
    body: ZoneScheduleUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Update an existing zone time schedule rule.
    """
    stmt = select(ZoneSchedule).where(ZoneSchedule.id == schedule_id, ZoneSchedule.user_id == current_user.id)
    sched = (await db.execute(stmt)).scalar_one_or_none()
    if not sched:
        raise HTTPException(status_code=404, detail="Quy tắc lịch trình không tồn tại")

    device_name = "Tất cả thiết bị"
    if body.device_id is not None:
        if body.device_id > 0:
            d_stmt = select(Device).where(Device.id == body.device_id, Device.user_id == current_user.id)
            device = (await db.execute(d_stmt)).scalar_one_or_none()
            if not device:
                raise HTTPException(status_code=400, detail="Thiết bị không tồn tại")
            sched.device_id = body.device_id
            device_name = device.name
        else:
            sched.device_id = None
    elif sched.device_id:
        d_stmt = select(Device).where(Device.id == sched.device_id, Device.user_id == current_user.id)
        device = (await db.execute(d_stmt)).scalar_one_or_none()
        if device:
            device_name = device.name

    if body.rule_type is not None:
        sched.rule_type = body.rule_type
    if body.target_time is not None:
        sched.target_time = body.target_time
    if body.days_of_week is not None:
        sched.days_of_week = json.dumps(body.days_of_week)
    if body.is_active is not None:
        sched.is_active = body.is_active

    await db.commit()
    await db.refresh(sched)

    days = []
    try:
        days = json.loads(sched.days_of_week)
    except Exception:
        days = [1, 2, 3, 4, 5, 6, 7]

    return ZoneScheduleResponse(
        id=sched.id,
        zone_id=sched.zone_id,
        device_id=sched.device_id,
        device_name=device_name,
        user_id=sched.user_id,
        rule_type=sched.rule_type,
        target_time=sched.target_time,
        days_of_week=days,
        is_active=sched.is_active,
        last_triggered_date=sched.last_triggered_date,
        created_at=sched.created_at,
    )


@router.delete("/schedules/{schedule_id}", status_code=status.HTTP_200_OK)
async def delete_zone_schedule(
    schedule_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Delete a zone time schedule rule.
    """
    stmt = select(ZoneSchedule).where(ZoneSchedule.id == schedule_id, ZoneSchedule.user_id == current_user.id)
    sched = (await db.execute(stmt)).scalar_one_or_none()
    if not sched:
        raise HTTPException(status_code=404, detail="Quy tắc lịch trình không tồn tại")

    await db.delete(sched)
    await db.commit()
    return {"status": "ok", "message": "Đã xóa quy tắc lịch trình"}

