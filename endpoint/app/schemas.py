from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field

class GoogleAuthRequest(BaseModel):
    id_token: str

class UserResponse(BaseModel):
    id: int
    email: str
    name: str
    picture: str | None = None
    settings_json: str | None = "{}"
    is_admin: bool = False

    class Config:
        from_attributes = True

class UserSettingsUpdate(BaseModel):
    settings_json: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse

class AdminUserListResponse(BaseModel):
    id: int
    email: str
    name: str
    picture: str | None = None
    is_admin: bool = False
    device_count: int
    created_at: datetime
    
    class Config:
        from_attributes = True

class AdminAddDeviceRequest(BaseModel):
    name: str
    private_key_b64: str

class AdminRoleUpdateRequest(BaseModel):
    is_admin: bool

class ICloudLoginRequest(BaseModel):
    apple_id: str
    password: str

class ICloud2FARequestCode(BaseModel):
    method_index: int = 0
    apple_id: str | None = None

class ICloud2FARequest(BaseModel):
    code: str
    method_index: int = 0
    apple_id: str | None = None

class ICloudAccountItem(BaseModel):
    id: int
    apple_id: str
    masked_apple_id: str
    is_owner: bool
    is_active: bool
    login_state: str = "LOGGED_OUT"
    fetch_count: int = 0
    last_used_at: datetime | None = None

class ICloudStatusResponse(BaseModel):
    apple_id: str | None = None
    is_active: bool = False
    login_state: str = "LOGGED_OUT"
    two_factor_methods: list[str] = []
    accounts: list[ICloudAccountItem] = []

class DeviceCreateRequest(BaseModel):
    name: str
    hashed_adv_key: str
    private_key_b64: str | None = None

from pydantic import BaseModel, Field, field_validator
from datetime import timezone

class DeviceResponse(BaseModel):
    id: int
    name: str
    hashed_adv_key: str
    private_key_b64: str | None = None
    created_at: datetime
    # Server-side decrypted last known location
    last_lat: float | None = None
    last_lon: float | None = None
    last_seen_at: datetime | None = None
    last_battery: str | None = None

    @field_validator('created_at', 'last_seen_at', mode='after')
    @classmethod
    def set_utc(cls, v):
        if isinstance(v, datetime) and v.tzinfo is None:
            return v.replace(tzinfo=timezone.utc)
        return v

    class Config:
        from_attributes = True

class MaclessFetchRequest(BaseModel):
    ids: list[str]
    days: int = 7

class MaclessReportItem(BaseModel):
    payload: str
    datePublished: int
    statusCode: int = 200
    id: str

class MaclessFetchResponse(BaseModel):
    results: list[MaclessReportItem]

# ── Location history ──────────────────────────────────────────────────────────

class LocationHistoryItem(BaseModel):
    latitude: float
    longitude: float
    accuracy: int | None = None
    battery_status: str | None = None
    timestamp_ms: int           # unix milliseconds (UTC)
    timestamp_published_ms: int # original Apple publish timestamp

class LocationHistoryResponse(BaseModel):
    hashed_adv_key: str
    items: list[LocationHistoryItem]
    total: int

# ── Sharing ───────────────────────────────────────────────────────────────────

class ShareDeviceRequest(BaseModel):
    device_id: Optional[int] = None
    hashed_adv_key: Optional[str] = None
    target_user_id: Optional[int] = None
    target_email: Optional[str] = None

class SharedUserInfo(BaseModel):
    device_id: int
    user_id: int
    email: str
    name: str
    picture: Optional[str] = None

# ── Sync ──────────────────────────────────────────────────────────────────────

class SyncNowResponse(BaseModel):
    new_reports: int = 0
    decrypted: int = 0
    updated_devices: list[str] = []

# ── Zones & Geofencing ────────────────────────────────────────────────────────

class ZoneDeviceItemResponse(BaseModel):
    device_id: int
    device_name: str
    hashed_adv_key: str
    last_status: str = "UNKNOWN"
    last_distance: Optional[float] = None
    last_alert_time: Optional[datetime] = None
    last_alert_type: Optional[str] = None

    class Config:
        from_attributes = True

class PolygonPoint(BaseModel):
    lat: float
    lon: float

class ZoneCreateRequest(BaseModel):
    name: str
    latitude: float
    longitude: float
    radius: float = 100.0
    shape_type: str = "circle"
    polygon_points: Optional[list[PolygonPoint]] = None
    alert_on_exit: bool = True
    alert_on_enter: bool = False
    cooldown_minutes: int = 15
    is_active: bool = True
    device_ids: list[int] = []
    hashed_adv_keys: list[str] = []

class ZoneUpdateRequest(BaseModel):
    name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    radius: Optional[float] = None
    shape_type: Optional[str] = None
    polygon_points: Optional[list[PolygonPoint]] = None
    alert_on_exit: Optional[bool] = None
    alert_on_enter: Optional[bool] = None
    cooldown_minutes: Optional[int] = None
    is_active: Optional[bool] = None
    device_ids: Optional[list[int]] = None
    hashed_adv_keys: Optional[list[str]] = None

class ZoneResponse(BaseModel):
    id: int
    user_id: int
    name: str
    latitude: float
    longitude: float
    radius: float
    shape_type: str = "circle"
    polygon_points: Optional[list[PolygonPoint]] = None
    alert_on_exit: bool
    alert_on_enter: bool
    cooldown_minutes: int
    is_active: bool
    created_at: datetime
    updated_at: datetime
    devices: list[ZoneDeviceItemResponse] = []

    class Config:
        from_attributes = True

class ZoneAlertItemResponse(BaseModel):
    id: int
    zone_id: int
    zone_name: str
    device_id: int
    device_name: str
    alert_type: str
    latitude: float
    longitude: float
    distance: float
    created_at: datetime

    class Config:
        from_attributes = True

class ZoneAlertListResponse(BaseModel):
    items: list[ZoneAlertItemResponse]
    total: int


