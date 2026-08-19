import base64
from datetime import datetime, timedelta, timezone
import jwt
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from fastapi import Depends, HTTPException, status, Header
from fastapi.security import HTTPBearer, HTTPBasic, HTTPBasicCredentials, HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.config import settings
from app.database import get_db
from app.models import User

security_bearer = HTTPBearer(auto_error=False)
security_basic = HTTPBasic(auto_error=False)

def create_access_token(data: dict, expires_delta: timedelta | None = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(days=settings.JWT_EXPIRE_DAYS))
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> dict | None:
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
        return payload
    except jwt.PyJWTError:
        return None

async def verify_google_token(token: str) -> dict:
    try:
        # If GOOGLE_CLIENT_ID is set, verify against it
        target_client_id = settings.GOOGLE_CLIENT_ID if settings.GOOGLE_CLIENT_ID else None
        # Allow 60s clock skew tolerance for server/container clock drift
        id_info = id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audience=target_client_id,
            clock_skew_in_seconds=60,
        )
        return id_info
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid Google Token: {str(e)}"
        )

async def get_or_create_user_from_google(id_info: dict, db: AsyncSession) -> User:
    sub = id_info.get("sub")
    email = id_info.get("email")
    name = id_info.get("name", "")
    picture = id_info.get("picture")

    if not email:
        raise HTTPException(status_code=400, detail="Google token missing email")

    admin_emails = [e.strip().lower() for e in settings.ADMIN_EMAILS.split(",") if e.strip()]
    is_env_admin = email.lower() in admin_emails
    
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if not user:
        from sqlalchemy import func
        user_count_res = await db.execute(select(func.count(User.id)))
        user_count = user_count_res.scalar() or 0
        
        is_first_user = (user_count == 0)
        
        user = User(
            google_sub=sub, 
            email=email, 
            name=name, 
            picture=picture, 
            settings_json="{}", 
            is_admin=(is_first_user or is_env_admin)
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    else:
        changed = False
        # update google_sub or picture if changed
        if not user.google_sub and sub:
            user.google_sub = sub
            changed = True
        if picture and user.picture != picture:
            user.picture = picture
            changed = True
            
        # Promote if in ADMIN_EMAILS (force promote)
        if is_env_admin and not user.is_admin:
            user.is_admin = True
            changed = True
            
        if changed:
            await db.commit()

    return user

async def get_current_user(
    auth_bearer: HTTPAuthorizationCredentials | None = Depends(security_bearer),
    auth_basic: HTTPBasicCredentials | None = Depends(security_basic),
    db: AsyncSession = Depends(get_db)
) -> User:
    # 1. Try JWT Bearer
    if auth_bearer and auth_bearer.credentials:
        payload = decode_access_token(auth_bearer.credentials)
        if payload and "sub" in payload:
            user_id = int(payload["sub"])
            result = await db.execute(select(User).where(User.id == user_id))
            user = result.scalar_one_or_none()
            if user:
                return user

    # 2. Try Basic Auth (for backward compatibility with mh_endpoint)
    if auth_basic:
        if (settings.ENDPOINT_USER and auth_basic.username == settings.ENDPOINT_USER and
            settings.ENDPOINT_PASS and auth_basic.password == settings.ENDPOINT_PASS) or \
           (not settings.ENDPOINT_USER and not settings.ENDPOINT_PASS):
            # Return or create default admin user
            result = await db.execute(select(User).where(User.email == "default@macless.local"))
            user = result.scalar_one_or_none()
            if not user:
                user = User(email="default@macless.local", name="Default Admin")
                db.add(user)
                await db.commit()
                await db.refresh(user)
            return user

    # 3. If GOOGLE_CLIENT_ID is configured (Multi-User Public Server Mode), require Google Login to write to Server DB & sync 24/7
    if settings.GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Vui lòng đăng nhập Google để lưu thiết bị lên Server và đồng bộ 24/7!",
            headers={"WWW-Authenticate": "Bearer"}
        )

    # 4. Single-User Private Server Mode (no GOOGLE_CLIENT_ID) -> Fallback to default admin
    result = await db.execute(select(User).where(User.email == "default@macless.local"))
    user = result.scalar_one_or_none()
    if not user:
        user = User(email="default@macless.local", name="Default Admin")
        db.add(user)
        await db.commit()
        await db.refresh(user)
    return user
