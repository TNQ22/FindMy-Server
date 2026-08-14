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

# ── Sync ──────────────────────────────────────────────────────────────────────

class SyncNowResponse(BaseModel):
    new_reports: int = 0
    decrypted: int = 0
    updated_devices: list[str] = []
