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
    try:
        await send_low_battery_alert(current_user.email, "Thiết bị Test", "criticalLow")
        return {"status": "ok", "message": "Email sent successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/test-channel")
async def test_notification_channel(
    payload: dict,
    current_user: User = Depends(get_current_user)
):
    from app.services.notification_service import (
        send_telegram_alert,
        send_discord_alert,
        send_custom_webhook_alert,
        get_user_notification_settings,
    )
    from datetime import datetime, timezone
    
    channel = payload.get("channel", "").lower()
    custom_cfg = payload.get("config", {}) or {}
    user_cfg = get_user_notification_settings(current_user)

    now_str = datetime.now(timezone.utc).strftime("%d/%m/%Y %H:%M:%S UTC")

    if channel == "telegram":
        token = custom_cfg.get("telegram_bot_token") or user_cfg.get("telegram_bot_token")
        chat_id = custom_cfg.get("telegram_chat_id") or user_cfg.get("telegram_chat_id")
        if not token or not chat_id:
            raise HTTPException(status_code=400, detail="Vui lòng nhập Bot Token và Chat ID của Telegram.")
        
        test_msg = (
            f"🔔 <b>FindMy Server: Kiểm tra kết nối Telegram</b>\n\n"
            f"✅ Kênh thông báo Telegram đã được thiết lập thành công!\n"
            f"👤 <b>Tài khoản:</b> {current_user.email}\n"
            f"🕒 <b>Thời gian:</b> {now_str}\n\n"
            f"<i>Kênh thông báo Telegram của bạn đã sẵn sàng nhận các thông báo từ hệ thống.</i>"
        )
        ok = await send_telegram_alert(token, str(chat_id), test_msg)
        if not ok:
            raise HTTPException(status_code=400, detail="Không thể gửi tin nhắn Telegram. Vui lòng kiểm tra lại Bot Token và Chat ID (đảm bảo bạn đã bấm /start với bot).")
        return {"status": "ok", "message": "Đã gửi tin nhắn kiểm tra qua Telegram thành công!"}

    elif channel == "discord":
        webhook_url = custom_cfg.get("discord_webhook_url") or user_cfg.get("discord_webhook_url")
        if not webhook_url:
            raise HTTPException(status_code=400, detail="Vui lòng nhập Discord Webhook URL.")
        
        fields = [
            {"name": "Trạng thái", "value": "Kết nối thành công", "inline": True},
            {"name": "Người dùng", "value": current_user.email, "inline": True}
        ]
        ok = await send_discord_alert(
            webhook_url=webhook_url,
            title="🔔 FindMy Server: Kiểm tra kết nối Discord",
            description="Kênh thông báo Discord Webhook đã được cấu hình thành công trên FindMy Server.",
            color=0x2ecc71,
            fields=fields
        )
        if not ok:
            raise HTTPException(status_code=400, detail="Không thể gửi tin nhắn đến Discord Webhook. Vui lòng kiểm tra lại Webhook URL.")
        return {"status": "ok", "message": "Đã gửi tin nhắn kiểm tra qua Discord thành công!"}

    elif channel in ("webhook", "zalo"):
        webhook_url = custom_cfg.get("webhook_url") or user_cfg.get("webhook_url")
        if not webhook_url:
            raise HTTPException(status_code=400, detail="Vui lòng nhập Webhook URL.")
        
        test_payload = {
            "event": "test_notification",
            "title": "FindMy Server: Kiểm tra kết nối Webhook",
            "message": "Webhook test message from FindMy Server.",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "user_email": current_user.email
        }
        ok = await send_custom_webhook_alert(webhook_url, test_payload)
        if not ok:
            raise HTTPException(status_code=400, detail="Không thể gửi POST request đến Webhook URL. Vui lòng kiểm tra lại URL endpoint.")
        return {"status": "ok", "message": "Đã gửi payload kiểm tra đến Webhook thành công!"}

    elif channel == "email":
        from app.services.email_service import send_test_email_alert
        recipient = custom_cfg.get("recipient_email") or current_user.email
        if not recipient:
            raise HTTPException(status_code=400, detail="Không tìm thấy địa chỉ email người nhận.")
        try:
            await send_test_email_alert(recipient)
            return {"status": "ok", "message": f"Đã gửi email kiểm tra thành công tới {recipient}! Vui lòng kiểm tra hộp thư (bao gồm cả mục Spam/Junk)."}
        except ValueError as ve:
            raise HTTPException(status_code=400, detail=str(ve))
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Lỗi gửi email SMTP: {str(e)}")

    else:
        raise HTTPException(status_code=400, detail=f"Kênh thông báo không hợp lệ: {channel}")


