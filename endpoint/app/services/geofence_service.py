import math
import json
import logging
import asyncio
from datetime import datetime, timezone
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.models import Device, Zone, ZoneDevice, ZoneAlert
from app.services.notification_service import dispatch_geofence_notification

logger = logging.getLogger("geofence_service")

EARTH_RADIUS_METERS = 6371000.0  # Earth's radius in meters


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculates the great-circle distance between two points on the Earth (in meters)
    using the Haversine formula.
    """
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))

    return EARTH_RADIUS_METERS * c


def point_in_polygon(lat: float, lon: float, polygon: list[dict]) -> bool:
    """
    Ray-casting algorithm to determine if a point (lat, lon) is inside a polygon.
    Polygon is a list of points: [{'lat': float, 'lon': float}, ...]
    """
    if not polygon or len(polygon) < 3:
        return False

    inside = False
    n = len(polygon)
    p1 = polygon[0]
    p1_lat = float(p1.get("lat", p1.get("latitude", 0.0)))
    p1_lon = float(p1.get("lon", p1.get("longitude", 0.0)))

    for i in range(1, n + 1):
        p2 = polygon[i % n]
        p2_lat = float(p2.get("lat", p2.get("latitude", 0.0)))
        p2_lon = float(p2.get("lon", p2.get("longitude", 0.0)))

        if min(p1_lat, p2_lat) < lat <= max(p1_lat, p2_lat):
            if lon <= max(p1_lon, p2_lon):
                xinters = lon
                if p1_lat != p2_lat:
                    xinters = (lat - p1_lat) * (p2_lon - p1_lon) / (p2_lat - p1_lat) + p1_lon
                if p1_lon == p2_lon or lon <= xinters:
                    inside = not inside
        p1 = p2
        p1_lat = p2_lat
        p1_lon = p2_lon

    return inside


async def evaluate_device_geofence(
    db: AsyncSession,
    device: Device,
    current_lat: float,
    current_lon: float,
    timestamp: datetime | None = None,
):
    """
    Evaluates geofence status for a device against all associated active zones.
    Detects ENTER / EXIT state transitions, applies cooldown debounce, logs alerts,
    and dispatches multi-channel notifications. Supports both Circle and Polygon geofences.
    """
    if current_lat is None or current_lon is None:
        return

    try:
        # Fetch all zone bindings for this device including zone and zone owner
        stmt = (
            select(ZoneDevice)
            .options(
                joinedload(ZoneDevice.zone).joinedload(Zone.user)
            )
            .where(ZoneDevice.device_id == device.id)
        )
        result = await db.execute(stmt)
        zone_links = result.scalars().all()

        if not zone_links:
            return

        now = datetime.now(timezone.utc)

        for zd in zone_links:
            zone = zd.zone
            if not zone or not zone.is_active:
                continue

            # Calculate distance from current tag location to zone center
            distance = haversine_distance(
                current_lat, current_lon, zone.latitude, zone.longitude
            )

            # Determine inside/outside status according to shape_type
            if getattr(zone, "shape_type", "circle") == "polygon" and zone.polygon_points:
                try:
                    points = json.loads(zone.polygon_points)
                    is_in = point_in_polygon(current_lat, current_lon, points)
                    new_status = "INSIDE" if is_in else "OUTSIDE"
                except Exception as e:
                    logger.error(f"Error parsing polygon points for zone {zone.id}: {e}")
                    new_status = "INSIDE" if distance <= zone.radius else "OUTSIDE"
            else:
                new_status = "INSIDE" if distance <= zone.radius else "OUTSIDE"

            last_status = zd.last_status or "UNKNOWN"

            # Determine trigger event
            alert_type: str | None = None
            if last_status == "INSIDE" and new_status == "OUTSIDE":
                if zone.alert_on_exit:
                    alert_type = "EXIT"
            elif last_status == "OUTSIDE" and new_status == "INSIDE":
                if zone.alert_on_enter:
                    alert_type = "ENTER"

            # If this is the initial location report (UNKNOWN), record status without alert
            if last_status == "UNKNOWN":
                zd.last_status = new_status
                zd.last_distance = distance
                zd.updated_at = now
                continue

            if alert_type:
                # Check cooldown window
                can_alert = True
                if zd.last_alert_time:
                    last_alert_naive = (
                        zd.last_alert_time.replace(tzinfo=None)
                        if zd.last_alert_time.tzinfo
                        else zd.last_alert_time
                    )
                    now_naive = now.replace(tzinfo=None)
                    elapsed_seconds = (now_naive - last_alert_naive).total_seconds()
                    elapsed_minutes = elapsed_seconds / 60.0

                    if zd.last_alert_type == alert_type:
                        # Same event type: enforce full cooldown_minutes
                        if elapsed_minutes < zone.cooldown_minutes:
                            can_alert = False
                            logger.info(
                                f"Geofence {alert_type} for device '{device.name}' in zone '{zone.name}' "
                                f"suppressed by cooldown ({elapsed_minutes:.1f}/{zone.cooldown_minutes} min)."
                            )
                    else:
                        # State changed (e.g. EXIT -> ENTER): allow if minimal debounce (5s) met
                        if elapsed_seconds < 5.0:
                            can_alert = False

                if can_alert:
                    logger.warning(
                        f"GEOFENCE TRIGGER: Device '{device.name}' triggered {alert_type} "
                        f"on Zone '{zone.name}' (Dist: {distance:.1f}m, Radius: {zone.radius}m)"
                    )

                    # Log to database
                    alert_record = ZoneAlert(
                        user_id=zone.user_id,
                        zone_id=zone.id,
                        device_id=device.id,
                        alert_type=alert_type,
                        latitude=current_lat,
                        longitude=current_lon,
                        distance=distance,
                        created_at=now,
                    )
                    db.add(alert_record)
                    zd.last_alert_time = now
                    zd.last_alert_type = alert_type

                    # Dispatch notifications asynchronously
                    if zone.user:
                        asyncio.create_task(
                            dispatch_geofence_notification(
                                user=zone.user,
                                device_name=device.name,
                                zone_name=zone.name,
                                alert_type=alert_type,
                                lat=current_lat,
                                lon=current_lon,
                                distance=distance,
                                radius=zone.radius,
                            )
                        )

            # Update zone_device state
            zd.last_status = new_status
            zd.last_distance = distance
            zd.updated_at = now

    except Exception as e:
        logger.error(f"Error evaluating geofence for device {device.name} (id={device.id}): {e}", exc_info=True)
