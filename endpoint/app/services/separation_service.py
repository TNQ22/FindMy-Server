import asyncio
import logging
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.models import Device, Zone, ZoneDevice
from app.services.geofence_service import haversine_distance, point_in_polygon
from app.services.notification_service import dispatch_separation_notification
import json

logger = logging.getLogger("separation_service")


async def is_point_in_user_safe_zones(db: AsyncSession, user_id: int, lat: float, lon: float) -> bool:
    """
    Checks if a given coordinate is within any active safe zone belonging to the user.
    """
    try:
        stmt = select(Zone).where(
            Zone.user_id == user_id,
            Zone.is_active == True,
            Zone.is_safe_zone == True,
        )
        result = await db.execute(stmt)
        zones = result.scalars().all()

        for zone in zones:
            dist = haversine_distance(lat, lon, zone.latitude, zone.longitude)
            if getattr(zone, "shape_type", "circle") == "polygon" and zone.polygon_points:
                try:
                    points = json.loads(zone.polygon_points)
                    if point_in_polygon(lat, lon, points):
                        return True
                except Exception:
                    if dist <= zone.radius:
                        return True
            else:
                if dist <= zone.radius:
                    return True
        return False
    except Exception as e:
        logger.error(f"Error checking safe zones for user {user_id}: {e}")
        return False


async def evaluate_device_separation(
    db: AsyncSession,
    device: Device,
    current_lat: float,
    current_lon: float,
    timestamp: datetime | None = None,
):
    """
    Evaluates separation between:
    1. If `device` is a companion tag with a master: evaluates distance to its master device.
    2. If `device` is a master device: evaluates distance to all its companion tags.
    """
    if current_lat is None or current_lon is None:
        return

    now = datetime.now(timezone.utc)
    event_time = timestamp if timestamp else now
    if event_time.tzinfo is None:
        event_time = event_time.replace(tzinfo=timezone.utc)
    event_naive = event_time.replace(tzinfo=None)

    try:
        # Case 1: device is a companion tag pointing to a master
        if device.master_device_id and device.separation_alert_enabled:
            master_stmt = (
                select(Device)
                .options(joinedload(Device.user))
                .where(Device.id == device.master_device_id)
            )
            master_res = await db.execute(master_stmt)
            master_dev = master_res.scalar_one_or_none()

            if master_dev and master_dev.last_lat is not None and master_dev.last_lon is not None:
                await _check_pair_separation(
                    db=db,
                    companion=device,
                    companion_lat=current_lat,
                    companion_lon=current_lon,
                    master=master_dev,
                    master_lat=master_dev.last_lat,
                    master_lon=master_dev.last_lon,
                    event_time=event_time,
                    event_naive=event_naive,
                )

        # Case 2: device is a master device, check all its companion devices
        if device.is_master:
            comp_stmt = (
                select(Device)
                .options(joinedload(Device.user))
                .where(
                    Device.master_device_id == device.id,
                    Device.separation_alert_enabled == True,
                )
            )
            comp_res = await db.execute(comp_stmt)
            companions = comp_res.scalars().all()

            for comp in companions:
                if comp.last_lat is not None and comp.last_lon is not None:
                    await _check_pair_separation(
                        db=db,
                        companion=comp,
                        companion_lat=comp.last_lat,
                        companion_lon=comp.last_lon,
                        master=device,
                        master_lat=current_lat,
                        master_lon=current_lon,
                        event_time=event_time,
                        event_naive=event_naive,
                    )

    except Exception as e:
        logger.error(f"Error evaluating separation for device {device.name} (id={device.id}): {e}", exc_info=True)


async def _check_pair_separation(
    db: AsyncSession,
    companion: Device,
    companion_lat: float,
    companion_lon: float,
    master: Device,
    master_lat: float,
    master_lon: float,
    event_time: datetime,
    event_naive: datetime,
):
    distance = haversine_distance(companion_lat, companion_lon, master_lat, master_lon)
    companion.last_separation_distance = distance
    threshold = companion.separation_threshold_meters or 150.0

    logger.debug(
        f"Separation check: Companion '{companion.name}' <-> Master '{master.name}': "
        f"{distance:.1f}m (Threshold: {threshold}m)"
    )

    if distance > threshold:
        # Check safe zone exclusion
        if companion.ignore_separation_in_safe_zones:
            in_safe_zone = await is_point_in_user_safe_zones(
                db, companion.user_id, companion_lat, companion_lon
            )
            if in_safe_zone:
                logger.info(
                    f"Separation alert for '{companion.name}' suppressed: inside user safe zone."
                )
                return

        # Check cooldown (15 minutes between separation alerts for same companion)
        can_alert = True
        if companion.last_separation_alert_time:
            last_naive = (
                companion.last_separation_alert_time.replace(tzinfo=None)
                if companion.last_separation_alert_time.tzinfo
                else companion.last_separation_alert_time
            )
            elapsed_seconds = (event_naive - last_naive).total_seconds()
            if elapsed_seconds < 0 or (elapsed_seconds / 60.0) < 15.0:
                can_alert = False

        if can_alert:
            logger.warning(
                f"SEPARATION ALERT TRIGGERED: Companion '{companion.name}' separated from "
                f"Master '{master.name}' (Distance: {distance:.1f}m > {threshold}m)"
            )
            companion.last_separation_alert_time = event_naive

            target_user = companion.user or master.user
            if target_user:
                try:
                    await dispatch_separation_notification(
                        user=target_user,
                        companion_name=companion.name,
                        master_name=master.name,
                        distance=distance,
                        threshold=threshold,
                        lat=companion_lat,
                        lon=companion_lon,
                        event_time=event_time,
                    )
                    await asyncio.sleep(0.5)
                except Exception as notif_err:
                    logger.error(f"Error dispatching separation notification: {notif_err}")
