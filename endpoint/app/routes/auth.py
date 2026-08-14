from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.schemas import GoogleAuthRequest, TokenResponse, UserResponse
from app.schemas import GoogleAuthRequest, TokenResponse, UserResponse, UserSettingsUpdate
from app.services.auth_service import (
    verify_google_token,
    get_or_create_user_from_google,
    create_access_token,
    get_current_user,
)
from app.models import User

router = APIRouter(prefix="/api/auth", tags=["Auth"])

@router.post("/google", response_model=TokenResponse)
async def login_google(body: GoogleAuthRequest, db: AsyncSession = Depends(get_db)):
    id_info = await verify_google_token(body.id_token)
    user = await get_or_create_user_from_google(id_info, db)
    token = create_access_token({"sub": str(user.id), "email": user.email})
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user=UserResponse.model_validate(user)
    )

@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    return UserResponse.model_validate(current_user)

@router.post("/settings", response_model=UserResponse)
async def update_user_settings(
    body: UserSettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    current_user.settings_json = body.settings_json
    await db.commit()
    await db.refresh(current_user)
    return UserResponse.model_validate(current_user)

@router.post("/test-email")
async def send_test_email(current_user: User = Depends(get_current_user)):
    from app.services.email_service import send_low_battery_alert
    import asyncio
    
    # Fire and forget or await
    try:
        await send_low_battery_alert(current_user.email, "Thiết bị Test", "criticalLow")
        return {"status": "ok", "message": "Email sent successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

