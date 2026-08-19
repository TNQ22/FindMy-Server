from datetime import datetime, timezone
from sqlalchemy import String, Integer, Float, Text, Boolean, DateTime, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.database import Base

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    google_sub: Mapped[str | None] = mapped_column(String(255), unique=True, index=True, nullable=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(255), default="")
    picture: Mapped[str | None] = mapped_column(Text, nullable=True)
    settings_json: Mapped[str] = mapped_column(Text, default="{}")
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    icloud_accounts: Mapped[list["ICloudAccount"]] = relationship("ICloudAccount", back_populates="user", cascade="all, delete-orphan")
    devices: Mapped[list["Device"]] = relationship("Device", back_populates="user", cascade="all, delete-orphan")
    reports: Mapped[list["LocationReport"]] = relationship("LocationReport", back_populates="user", cascade="all, delete-orphan")
    zones: Mapped[list["Zone"]] = relationship("Zone", back_populates="user", cascade="all, delete-orphan")
    zone_alerts: Mapped[list["ZoneAlert"]] = relationship("ZoneAlert", back_populates="user", cascade="all, delete-orphan")

class ICloudAccount(Base):
    __tablename__ = "icloud_accounts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    apple_id: Mapped[str] = mapped_column(String(255), nullable=False)
    state_json: Mapped[str] = mapped_column(Text, nullable=False, default="{}")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_alerted: Mapped[bool] = mapped_column(Boolean, default=False)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    fetch_count: Mapped[int] = mapped_column(Integer, default=0)
    last_used_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    user: Mapped["User"] = relationship("User", back_populates="icloud_accounts")

class Device(Base):
    __tablename__ = "devices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), nullable=False)
    owner_user_id: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    hashed_adv_key: Mapped[str] = mapped_column(String(255), index=True, nullable=False)
    private_key_b64: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    # Server-side decrypted last known location (updated by sync_service)
    last_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    last_lon: Mapped[float | None] = mapped_column(Float, nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_battery: Mapped[str | None] = mapped_column(String(50), nullable=True)
    last_alerted_battery: Mapped[str | None] = mapped_column(String(50), nullable=True)

    user: Mapped["User"] = relationship("User", back_populates="devices")
    zone_links: Mapped[list["ZoneDevice"]] = relationship("ZoneDevice", back_populates="device", cascade="all, delete-orphan")
    zone_alerts: Mapped[list["ZoneAlert"]] = relationship("ZoneAlert", back_populates="device", cascade="all, delete-orphan")

class LocationReport(Base):
    __tablename__ = "location_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    hashed_adv_key: Mapped[str] = mapped_column(String(255), index=True, nullable=False)
    payload_b64: Mapped[str] = mapped_column(Text, nullable=False)
    timestamp_published: Mapped[int] = mapped_column(Integer, index=True, nullable=False)
    status_code: Mapped[int] = mapped_column(Integer, default=200)
    fetched_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    # Decrypted location fields (populated by decrypt_service)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    accuracy: Mapped[int | None] = mapped_column(Integer, nullable=True)
    battery_status: Mapped[str | None] = mapped_column(String(50), nullable=True)
    decrypted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    user: Mapped["User"] = relationship("User", back_populates="reports")

__table_args__ = (
    Index("idx_key_timestamp", LocationReport.hashed_adv_key, LocationReport.timestamp_published),
)


class Zone(Base):
    __tablename__ = "zones"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    radius: Mapped[float] = mapped_column(Float, default=100.0)  # Radius in meters for circle
    shape_type: Mapped[str] = mapped_column(String(20), default="circle", nullable=False)  # "circle" or "polygon"
    polygon_points: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON list of coordinates
    alert_on_exit: Mapped[bool] = mapped_column(Boolean, default=True)
    alert_on_enter: Mapped[bool] = mapped_column(Boolean, default=False)
    cooldown_minutes: Mapped[int] = mapped_column(Integer, default=15)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    user: Mapped["User"] = relationship("User", back_populates="zones")
    zone_devices: Mapped[list["ZoneDevice"]] = relationship("ZoneDevice", back_populates="zone", cascade="all, delete-orphan")
    alerts: Mapped[list["ZoneAlert"]] = relationship("ZoneAlert", back_populates="zone", cascade="all, delete-orphan")


class ZoneDevice(Base):
    __tablename__ = "zone_devices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    zone_id: Mapped[int] = mapped_column(Integer, ForeignKey("zones.id", ondelete="CASCADE"), index=True, nullable=False)
    device_id: Mapped[int] = mapped_column(Integer, ForeignKey("devices.id", ondelete="CASCADE"), index=True, nullable=False)
    last_status: Mapped[str] = mapped_column(String(20), default="UNKNOWN")  # INSIDE, OUTSIDE, UNKNOWN
    last_alert_time: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_alert_type: Mapped[str | None] = mapped_column(String(20), nullable=True)  # EXIT, ENTER
    last_distance: Mapped[float | None] = mapped_column(Float, nullable=True)  # in meters
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    zone: Mapped["Zone"] = relationship("Zone", back_populates="zone_devices")
    device: Mapped["Device"] = relationship("Device", back_populates="zone_links")


class ZoneAlert(Base):
    __tablename__ = "zone_alerts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    zone_id: Mapped[int] = mapped_column(Integer, ForeignKey("zones.id", ondelete="CASCADE"), index=True, nullable=False)
    device_id: Mapped[int] = mapped_column(Integer, ForeignKey("devices.id", ondelete="CASCADE"), index=True, nullable=False)
    alert_type: Mapped[str] = mapped_column(String(20), nullable=False)  # EXIT, ENTER
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    distance: Mapped[float] = mapped_column(Float, nullable=False)  # distance in meters
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)

    user: Mapped["User"] = relationship("User", back_populates="zone_alerts")
    zone: Mapped["Zone"] = relationship("Zone", back_populates="alerts")
    device: Mapped["Device"] = relationship("Device", back_populates="zone_alerts")

