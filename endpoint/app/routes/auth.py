import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.config import settings
from app.schemas import GoogleAuthRequest, TokenResponse, UserResponse, UserSettingsUpdate
from app.services.auth_service import (
    verify_google_token,
    get_or_create_user_from_google,
    create_access_token,
    get_current_user,
)
from app.models import User

router = APIRouter(prefix="/api/auth", tags=["Auth"])

# In-memory temporary mobile auth sessions: session_id -> {token, user, created_at}
_auth_sessions: dict[str, dict] = {}

@router.post("/session/create")
async def create_auth_session():
    now = datetime.now(timezone.utc)
    expired = [k for k, v in _auth_sessions.items() if (now - v["created_at"]).total_seconds() > 600]
    for k in expired:
        _auth_sessions.pop(k, None)
    sid = str(uuid.uuid4())
    _auth_sessions[sid] = {"token": None, "user": None, "created_at": now}
    return {"session_id": sid}

@router.post("/session/{sid}/complete")
async def complete_auth_session(sid: str, body: GoogleAuthRequest, db: AsyncSession = Depends(get_db)):
    if sid not in _auth_sessions:
        raise HTTPException(status_code=404, detail="Phiên đăng nhập không tồn tại hoặc đã hết hạn")
    id_info = await verify_google_token(body.id_token)
    user = await get_or_create_user_from_google(id_info, db)
    token = create_access_token({"sub": str(user.id), "email": user.email, "v": user.token_version or 1})
    _auth_sessions[sid]["token"] = token
    _auth_sessions[sid]["user"] = UserResponse.model_validate(user).model_dump()
    return {"status": "ok"}

@router.get("/session/{sid}/poll")
async def poll_auth_session(sid: str):
    if sid not in _auth_sessions:
        raise HTTPException(status_code=404, detail="Phiên đăng nhập không tồn tại hoặc đã hết hạn")
    data = _auth_sessions[sid]
    if data["token"]:
        token = data["token"]
        user = data["user"]
        _auth_sessions.pop(sid, None)
        return {"authenticated": True, "access_token": token, "user": user}
    return {"authenticated": False}

@router.get("/mobile-login", response_class=HTMLResponse)
async def mobile_login_page(session: str):
    client_id = settings.GOOGLE_CLIENT_ID or ""
    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>FindMy Server - Đăng nhập Google</title>
    <script src="https://accounts.google.com/gsi/client" async defer></script>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #0f172a;
            color: #f8fafc;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            padding: 20px;
            box-sizing: border-box;
        }}
        .card {{
            background: #1e293b;
            padding: 36px 24px;
            border-radius: 20px;
            text-align: center;
            max-width: 400px;
            width: 100%;
            border: 1px solid rgba(20, 184, 166, 0.3);
            box-shadow: 0 10px 35px rgba(0,0,0,0.6);
        }}
        .icon {{
            width: 60px;
            height: 60px;
            background: rgba(20, 184, 166, 0.15);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0 auto 16px;
        }}
        h2 {{ margin: 0 0 8px; color: #fff; font-size: 22px; }}
        p {{ color: #94a3b8; font-size: 14px; line-height: 1.5; margin: 0 0 24px; }}
        .btn-box {{ display: flex; justify-content: center; margin-top: 10px; }}
        #success-msg {{ display: none; margin-top: 20px; }}
        .success-box {{
            background: rgba(34, 197, 94, 0.15);
            border: 1px solid #22c55e;
            border-radius: 12px;
            padding: 20px;
        }}
        .success-box h3 {{ color: #4ade80; margin: 8px 0 4px; font-size: 18px; }}
        .success-box p {{ color: #cbd5e1; margin: 0; font-size: 13px; }}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">
            <svg style="width:32px;height:32px;fill:#14b8a6;" viewBox="0 0 24 24">
                <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5a2.5 2.5 0 0 1 0-5 2.5 2.5 0 0 1 0 5z"/>
            </svg>
        </div>
        <h2>FindMy Server</h2>
        <p>Chọn tài khoản Google để xác thực và kết nối vào ứng dụng trên điện thoại.</p>
        
        <div id="btn-box" class="btn-box">
            <div id="g_id_onload"
                 data-client_id="{client_id}"
                 data-context="signin"
                 data-ux_mode="popup"
                 data-callback="handleCredentialResponse"
                 data-auto_prompt="false">
            </div>
            <div class="g_id_signin"
                 data-type="standard"
                 data-shape="rectangular"
                 data-theme="filled_blue"
                 data-text="signin_with"
                 data-size="large"
                 data-logo_alignment="left">
            </div>
        </div>

        <div id="success-msg">
            <div class="success-box">
                <svg style="width:40px;height:40px;fill:#22c55e;display:block;margin:auto;" viewBox="0 0 24 24">
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                </svg>
                <h3>Xác thực thành công!</h3>
                <p>Ứng dụng trên điện thoại đang tự động kết nối.<br>Bạn có thể chuyển về app FindMy bây giờ.</p>
            </div>
        </div>
    </div>

    <script>
        function handleCredentialResponse(response) {{
            if (!response.credential) return;
            document.getElementById('btn-box').style.display = 'none';
            fetch('/api/auth/session/{session}/complete', {{
                method: 'POST',
                headers: {{ 'Content-Type': 'application/json' }},
                body: JSON.stringify({{ id_token: response.credential }})
            }}).then(res => {{
                if (res.ok) {{
                    document.getElementById('success-msg').style.display = 'block';
                }} else {{
                    alert('Xác thực thất bại, vui lòng thử lại.');
                    document.getElementById('btn-box').style.display = 'flex';
                }}
            }}).catch(err => {{
                alert('Lỗi kết nối máy chủ: ' + err);
                document.getElementById('btn-box').style.display = 'flex';
            }});
        }}
    </script>
</body>
</html>
"""
    return HTMLResponse(content=html_content)

@router.post("/google", response_model=TokenResponse)
async def login_google(body: GoogleAuthRequest, db: AsyncSession = Depends(get_db)):
    id_info = await verify_google_token(body.id_token)
    user = await get_or_create_user_from_google(id_info, db)
    token = create_access_token({"sub": str(user.id), "email": user.email, "v": user.token_version or 1})
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user=UserResponse.model_validate(user)
    )

@router.post("/logout")
async def logout(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Revoke all existing tokens for this user by incrementing token_version.
    """
    current_user.token_version = (current_user.token_version or 1) + 1
    await db.commit()
    return {"status": "ok", "message": "Đã đăng xuất thành công và vô hiệu hóa các phiên token cũ."}

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


