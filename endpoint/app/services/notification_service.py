import json
import logging
from datetime import datetime, timezone
import aiohttp
from app.config import settings
from app.models import User
from app.services.email_service import (
    send_low_battery_alert,
    send_icloud_status_alert,
    send_geofence_alert,
    send_separation_alert,
    send_zone_schedule_alert,
)

logger = logging.getLogger("notification_service")

async def send_telegram_alert(bot_token: str, chat_id: str, text: str) -> bool:
    """
    Sends a message to a Telegram chat via Telegram Bot API using HTML format.
    """
    if not bot_token or not chat_id:
        logger.warning("Telegram Bot Token or Chat ID is missing.")
        return False

    url = f"https://api.telegram.org/bot{bot_token.strip()}/sendMessage"
    payload = {
        "chat_id": chat_id.strip(),
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }

    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(url, json=payload, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status == 200:
                    logger.info(f"Telegram alert successfully sent to chat {chat_id}")
                    return True
                else:
                    body = await resp.text()
                    logger.error(f"Failed to send Telegram alert (status {resp.status}): {body}")
                    return False
    except Exception as e:
        logger.error(f"Error sending Telegram alert: {e}")
        return False


async def send_discord_alert(webhook_url: str, title: str, description: str, color: int = 0x3498db, fields: list[dict] = None) -> bool:
    """
    Sends a rich embed message to a Discord channel via Webhook.
    """
    if not webhook_url:
        logger.warning("Discord Webhook URL is missing.")
        return False

    embed = {
        "title": title,
        "description": description,
        "color": color,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "footer": {
            "text": "FindMy Server Notification"
        }
    }
    if fields:
        embed["fields"] = fields

    payload = {
        "embeds": [embed]
    }

    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(webhook_url.strip(), json=payload, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status in (200, 204):
                    logger.info("Discord webhook alert successfully sent.")
                    return True
                else:
                    body = await resp.text()
                    logger.error(f"Failed to send Discord alert (status {resp.status}): {body}")
                    return False
    except Exception as e:
        logger.error(f"Error sending Discord alert: {e}")
        return False


async def send_custom_webhook_alert(webhook_url: str, payload: dict) -> bool:
    """
    Sends a generic JSON POST webhook (usable with Zalo bridge, n8n, Node-RED, Home Assistant, etc.).
    """
    if not webhook_url:
        logger.warning("Custom Webhook URL is missing.")
        return False

    try:
        headers = {
            "Content-Type": "application/json",
            "User-Agent": "FindMyServer-Notifier/1.0"
        }
        async with aiohttp.ClientSession() as session:
            async with session.post(webhook_url.strip(), json=payload, headers=headers, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status in (200, 201, 202, 204):
                    logger.info(f"Custom webhook alert successfully sent to {webhook_url}")
                    return True
                else:
                    body = await resp.text()
                    logger.error(f"Failed to send custom webhook (status {resp.status}): {body}")
                    return False
    except Exception as e:
        logger.error(f"Error sending custom webhook: {e}")
        return False


def get_user_notification_settings(user: User) -> dict:
    """
    Parses user settings_json and returns notification settings with defaults.
    """
    try:
        if user.settings_json:
            return json.loads(user.settings_json)
    except Exception:
        pass
    return {}


async def dispatch_low_battery_notification(user: User, device_name: str, battery_status: str):
    """
    Dispatches low battery alert across all user-configured channels (Email, Telegram, Discord, Webhook).
    """
    cfg = get_user_notification_settings(user)
    status_text = "Rất thấp (Sắp cạn)" if battery_status == "criticalLow" else "Thấp"
    now_str = datetime.now(timezone.utc).strftime("%d/%m/%Y %H:%M:%S UTC")

    # 1. Email Alert
    if cfg.get("email_alerts_enabled", True) and user.email:
        try:
            await send_low_battery_alert(user.email, device_name, battery_status)
        except Exception as e:
            logger.error(f"Email alert error: {e}")

    # 2. Telegram Alert
    if cfg.get("telegram_alerts_enabled", False):
        token = cfg.get("telegram_bot_token", "")
        chat_id = cfg.get("telegram_chat_id", "")
        if token and chat_id:
            text = (
                f"⚠️ <b>FindMy Server: Cảnh Báo Pin Yếu</b>\n\n"
                f"🏷️ <b>Thiết bị:</b> {device_name}\n"
                f"🔋 <b>Mức pin:</b> {status_text}\n"
                f"🕒 <b>Thời gian:</b> {now_str}\n\n"
                f"<i>Vui lòng kiểm tra hoặc thay pin mới cho thẻ để đảm bảo tín hiệu hoạt động liên tục.</i>"
            )
            await send_telegram_alert(token, chat_id, text)

    # 3. Discord Alert
    if cfg.get("discord_alerts_enabled", False):
        webhook_url = cfg.get("discord_webhook_url", "")
        if webhook_url:
            color = 0xe74c3c if battery_status == "criticalLow" else 0xf39c12
            fields = [
                {"name": "🏷️ Thiết bị", "value": device_name, "inline": True},
                {"name": "🔋 Mức pin", "value": status_text, "inline": True},
                {"name": "👤 Chủ sở hữu", "value": user.email, "inline": True}
            ]
            await send_discord_alert(
                webhook_url=webhook_url,
                title=f"⚠️ Cảnh Báo Pin Yếu: {device_name}",
                description=f"Thẻ định vị **{device_name}** đang có trạng thái pin ở mức **{status_text}**.",
                color=color,
                fields=fields
            )

    # 4. Custom Webhook (Zalo / Automation)
    if cfg.get("webhook_alerts_enabled", False):
        wh_url = cfg.get("webhook_url", "")
        if wh_url:
            payload = {
                "event": "low_battery",
                "title": f"Cảnh báo pin {status_text}: {device_name}",
                "device_name": device_name,
                "battery_status": battery_status,
                "battery_status_text": status_text,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "user_email": user.email
            }
            await send_custom_webhook_alert(wh_url, payload)


async def dispatch_icloud_status_notification(user: User, apple_id: str, reason: str):
    """
    Dispatches iCloud failure alert across all user-configured channels.
    """
    cfg = get_user_notification_settings(user)
    now_str = datetime.now(timezone.utc).strftime("%d/%m/%Y %H:%M:%S UTC")

    # 1. Email Alert
    if cfg.get("email_alerts_enabled", True) and user.email:
        try:
            await send_icloud_status_alert(user.email, apple_id, reason)
        except Exception as e:
            logger.error(f"Email alert error: {e}")

    # 2. Telegram Alert
    if cfg.get("telegram_alerts_enabled", False):
        token = cfg.get("telegram_bot_token", "")
        chat_id = cfg.get("telegram_chat_id", "")
        if token and chat_id:
            text = (
                f"🚨 <b>FindMy Server: Cảnh Báo iCloud Mất Kết Nối</b>\n\n"
                f"👤 <b>Apple ID:</b> {apple_id}\n"
                f"⚠️ <b>Lý do:</b> {reason}\n"
                f"🕒 <b>Thời gian:</b> {now_str}\n\n"
                f"<i>Vui lòng đăng nhập lại tài khoản trên giao diện quản trị FindMy Server để khôi phục đồng bộ vị trí.</i>"
            )
            await send_telegram_alert(token, chat_id, text)

    # 3. Discord Alert
    if cfg.get("discord_alerts_enabled", False):
        webhook_url = cfg.get("discord_webhook_url", "")
        if webhook_url:
            fields = [
                {"name": "🍎 Apple ID", "value": apple_id, "inline": True},
                {"name": "⚠️ Lý do", "value": reason, "inline": False}
            ]
            await send_discord_alert(
                webhook_url=webhook_url,
                title="🚨 Cảnh Báo Tài Khoản iCloud Mất Kết Nối",
                description=f"Tài khoản **{apple_id}** hiện không thể truy vấn vị trí.",
                color=0xe74c3c,
                fields=fields
            )

    # 4. Custom Webhook
    if cfg.get("webhook_alerts_enabled", False):
        wh_url = cfg.get("webhook_url", "")
        if wh_url:
            payload = {
                "event": "icloud_status",
                "title": f"Tài khoản Apple ID {apple_id} mất kết nối",
                "apple_id": apple_id,
                "reason": reason,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "user_email": user.email
            }
            await send_custom_webhook_alert(wh_url, payload)


async def dispatch_geofence_notification(
    user: User,
    device_name: str,
    zone_name: str,
    alert_type: str,
    lat: float,
    lon: float,
    distance: float,
    radius: float,
    event_time: datetime | None = None,
):
    """
    Dispatches geofence entry/exit alert across all user-configured channels (Email, Telegram, Discord, Webhook).
    """
    cfg = get_user_notification_settings(user)
    is_exit = alert_type.upper() == "EXIT"
    action_text = "RỜI KHỎI" if is_exit else "ĐI VÀO"
    title_text = f"Cảnh Báo Vùng An Toàn: {device_name} đã {action_text} {zone_name}"
    
    event_dt = event_time if event_time else datetime.now(timezone.utc)
    if event_dt.tzinfo is None:
        event_dt = event_dt.replace(tzinfo=timezone.utc)
    time_str = event_dt.astimezone(timezone.utc).strftime("%d/%m/%Y %H:%M:%S UTC")
    maps_url = f"https://www.google.com/maps/search/?api=1&query={lat},{lon}"

    # 1. Email Alert
    if cfg.get("email_alerts_enabled", True) and user.email:
        try:
            await send_geofence_alert(
                recipient_email=user.email,
                device_name=device_name,
                zone_name=zone_name,
                alert_type=alert_type,
                lat=lat,
                lon=lon,
                distance=distance,
                radius=radius,
                event_time=event_dt,
            )
        except Exception as e:
            logger.error(f"Geofence email alert error: {e}")

    # 2. Telegram Alert
    if cfg.get("telegram_alerts_enabled", False):
        token = cfg.get("telegram_bot_token", "")
        chat_id = cfg.get("telegram_chat_id", "")
        if token and chat_id:
            emoji_icon = "🚨" if is_exit else "📍"
            text = (
                f"{emoji_icon} <b>FindMy Server: Cảnh Báo Vùng An Toàn</b>\n\n"
                f"🏷️ <b>Thiết bị:</b> {device_name}\n"
                f"🛡️ <b>Khu vực:</b> {zone_name} (Bán kính: {int(radius)}m)\n"
                f"⚡ <b>Sự kiện:</b> <b>{action_text} KHU VỰC</b>\n"
                f"📏 <b>Khoảng cách:</b> {distance:.1f} m\n"
                f"🌐 <b>Tọa độ:</b> {lat:.6f}, {lon:.6f}\n"
                f"🕒 <b>Thời gian:</b> {time_str}\n\n"
                f"🔗 <a href=\"{maps_url}\">Xem vị trí trên Google Maps</a>"
            )
            await send_telegram_alert(token, chat_id, text)

    # 3. Discord Alert
    if cfg.get("discord_alerts_enabled", False):
        webhook_url = cfg.get("discord_webhook_url", "")
        if webhook_url:
            color = 0xe74c3c if is_exit else 0x2ecc71
            fields = [
                {"name": "🏷️ Thiết bị", "value": device_name, "inline": True},
                {"name": "🛡️ Khu vực", "value": f"{zone_name} (R={int(radius)}m)", "inline": True},
                {"name": "⚡ Sự kiện", "value": f"**{action_text}**", "inline": True},
                {"name": "📏 Khoảng cách", "value": f"{distance:.1f} m", "inline": True},
                {"name": "🌐 Tọa độ", "value": f"[{lat:.6f}, {lon:.6f}]({maps_url})", "inline": True},
                {"name": "🕒 Thời gian", "value": time_str, "inline": True},
                {"name": "👤 Chủ sở hữu", "value": user.email, "inline": True},
            ]
            await send_discord_alert(
                webhook_url=webhook_url,
                title=f"{'🚨' if is_exit else '📍'} {title_text}",
                description=f"Thẻ định vị **{device_name}** vừa được phát hiện **{action_text}** khu vực an toàn **{zone_name}**.",
                color=color,
                fields=fields,
            )

    # 4. Custom Webhook
    if cfg.get("webhook_alerts_enabled", False):
        wh_url = cfg.get("webhook_url", "")
        if wh_url:
            payload = {
                "event": "geofence_alert",
                "alert_type": alert_type.upper(),
                "action": action_text,
                "title": title_text,
                "device_name": device_name,
                "zone_name": zone_name,
                "radius": radius,
                "distance": distance,
                "latitude": lat,
                "longitude": lon,
                "maps_url": maps_url,
                "timestamp": event_dt.isoformat(),
                "user_email": user.email,
            }
            await send_custom_webhook_alert(wh_url, payload)


async def dispatch_separation_notification(
    user: User,
    companion_name: str,
    master_name: str,
    distance: float,
    threshold: float,
    lat: float,
    lon: float,
    event_time: datetime | None = None,
):
    """
    Dispatches separation (left behind) alert across user channels.
    """
    cfg = get_user_notification_settings(user)
    title_text = f"Cảnh Báo Tách Rời: {companion_name} đã tách xa {master_name}"
    event_dt = event_time if event_time else datetime.now(timezone.utc)
    if event_dt.tzinfo is None:
        event_dt = event_dt.replace(tzinfo=timezone.utc)
    time_str = event_dt.astimezone(timezone.utc).strftime("%d/%m/%Y %H:%M:%S UTC")
    maps_url = f"https://www.google.com/maps/search/?api=1&query={lat},{lon}"

    # 1. Email Alert
    if cfg.get("email_alerts_enabled", True) and user.email:
        try:
            await send_separation_alert(
                recipient_email=user.email,
                companion_name=companion_name,
                master_name=master_name,
                distance=distance,
                threshold=threshold,
                lat=lat,
                lon=lon,
                event_time=event_dt,
            )
        except Exception as e:
            logger.error(f"Separation email alert error: {e}")

    # 2. Telegram Alert
    if cfg.get("telegram_alerts_enabled", False):
        token = cfg.get("telegram_bot_token", "")
        chat_id = cfg.get("telegram_chat_id", "")
        if token and chat_id:
            text = (
                f"⚠️ <b>FindMy Server: Cảnh Báo Bỏ Quên / Tách Rời</b>\n\n"
                f"🏷️ <b>Thẻ đồng hành:</b> {companion_name}\n"
                f"📱 <b>Thiết bị chủ:</b> {master_name}\n"
                f"📏 <b>Khoảng cách:</b> <b>{distance:.1f} m</b> (Ngưỡng: {int(threshold)}m)\n"
                f"🌐 <b>Tọa độ thẻ:</b> {lat:.6f}, {lon:.6f}\n"
                f"🕒 <b>Thời gian:</b> {time_str}\n\n"
                f"🔗 <a href=\"{maps_url}\">Xem vị trí trên Google Maps</a>"
            )
            await send_telegram_alert(token, chat_id, text)

    # 3. Discord Alert
    if cfg.get("discord_alerts_enabled", False):
        webhook_url = cfg.get("discord_webhook_url", "")
        if webhook_url:
            fields = [
                {"name": "🏷️ Thẻ đồng hành", "value": companion_name, "inline": True},
                {"name": "📱 Thiết bị chủ", "value": master_name, "inline": True},
                {"name": "📏 Khoảng cách", "value": f"**{distance:.1f} m** (Ngưỡng {int(threshold)}m)", "inline": True},
                {"name": "🌐 Tọa độ", "value": f"[{lat:.6f}, {lon:.6f}]({maps_url})", "inline": True},
                {"name": "🕒 Thời gian", "value": time_str, "inline": True},
                {"name": "👤 Chủ sở hữu", "value": user.email, "inline": True},
            ]
            await send_discord_alert(
                webhook_url=webhook_url,
                title=f"⚠️ {title_text}",
                description=f"Thẻ **{companion_name}** vừa được phát hiện đã tách xa khỏi thiết bị chủ **{master_name}**.",
                color=0xe67e22,
                fields=fields,
            )

    # 4. Custom Webhook
    if cfg.get("webhook_alerts_enabled", False):
        wh_url = cfg.get("webhook_url", "")
        if wh_url:
            payload = {
                "event": "separation_alert",
                "title": title_text,
                "companion_name": companion_name,
                "master_name": master_name,
                "distance": distance,
                "threshold": threshold,
                "latitude": lat,
                "longitude": lon,
                "maps_url": maps_url,
                "timestamp": event_dt.isoformat(),
                "user_email": user.email,
            }
            await send_custom_webhook_alert(wh_url, payload)


async def dispatch_zone_schedule_notification(
    user: User,
    device_name: str,
    zone_name: str,
    rule_type: str,
    target_time: str,
    lat: float | None = None,
    lon: float | None = None,
    event_time: datetime | None = None,
):
    """
    Dispatches zone schedule reminder alert across user channels.
    """
    cfg = get_user_notification_settings(user)
    is_leave = rule_type == "MUST_LEAVE_BY"
    action_desc = f"chưa rời khỏi {zone_name} trước {target_time}" if is_leave else f"chưa về tới {zone_name} trước {target_time}"
    title_text = f"Nhắc Nhở Quên Đồ: {device_name} {action_desc}" if is_leave else f"Cảnh Báo Thất Lạc: {device_name} {action_desc}"
    
    event_dt = event_time if event_time else datetime.now(timezone.utc)
    if event_dt.tzinfo is None:
        event_dt = event_dt.replace(tzinfo=timezone.utc)
    time_str = event_dt.astimezone(timezone.utc).strftime("%d/%m/%Y %H:%M:%S UTC")
    maps_url = f"https://www.google.com/maps/search/?api=1&query={lat},{lon}" if lat and lon else ""

    # 1. Email Alert
    if cfg.get("email_alerts_enabled", True) and user.email:
        try:
            await send_zone_schedule_alert(
                recipient_email=user.email,
                device_name=device_name,
                zone_name=zone_name,
                rule_type=rule_type,
                target_time=target_time,
                lat=lat,
                lon=lon,
                event_time=event_dt,
            )
        except Exception as e:
            logger.error(f"Zone schedule email alert error: {e}")

    # 2. Telegram Alert
    if cfg.get("telegram_alerts_enabled", False):
        token = cfg.get("telegram_bot_token", "")
        chat_id = cfg.get("telegram_chat_id", "")
        if token and chat_id:
            emoji = "⏰" if is_leave else "🚨"
            maps_line = f"🔗 <a href=\"{maps_url}\">Xem vị trí hiện tại</a>\n" if maps_url else ""
            coord_line = f"🌐 <b>Tọa độ:</b> {lat:.6f}, {lon:.6f}\n" if lat and lon else ""
            rule_text = f"Phải rời khỏi trước {target_time}" if is_leave else f"Phải có mặt trước {target_time}"
            text = (
                f"{emoji} <b>FindMy Server: Lịch Trình Vùng An Toàn</b>\n\n"
                f"🏷️ <b>Thiết bị:</b> {device_name}\n"
                f"🛡️ <b>Khu vực:</b> {zone_name}\n"
                f"⚡ <b>Yêu cầu:</b> <b>{rule_text}</b>\n"
                f"⚠️ <b>Hiện trạng:</b> <b>{action_desc}</b>\n"
                f"{coord_line}"
                f"🕒 <b>Thời gian kiểm tra:</b> {time_str}\n\n"
                f"{maps_line}"
            )
            await send_telegram_alert(token, chat_id, text)

    # 3. Discord Alert
    if cfg.get("discord_alerts_enabled", False):
        webhook_url = cfg.get("discord_webhook_url", "")
        if webhook_url:
            color = 0xe74c3c if is_leave else 0x8e44ad
            fields = [
                {"name": "🏷️ Thiết bị", "value": device_name, "inline": True},
                {"name": "🛡️ Khu vực", "value": zone_name, "inline": True},
                {"name": "⚡ Yêu cầu", "value": f"Trước {target_time}", "inline": True},
                {"name": "⚠️ Hiện trạng", "value": action_desc, "inline": False},
                {"name": "🕒 Thời gian", "value": time_str, "inline": True},
            ]
            if lat and lon and maps_url:
                fields.append({"name": "🌐 Tọa độ", "value": f"[{lat:.6f}, {lon:.6f}]({maps_url})", "inline": True})
            await send_discord_alert(
                webhook_url=webhook_url,
                title=f"{'⏰' if is_leave else '🚨'} {title_text}",
                description=f"Hệ thống phát hiện **{device_name}** {action_desc}.",
                color=color,
                fields=fields,
            )

    # 4. Custom Webhook
    if cfg.get("webhook_alerts_enabled", False):
        wh_url = cfg.get("webhook_url", "")
        if wh_url:
            payload = {
                "event": "zone_schedule_alert",
                "rule_type": rule_type,
                "title": title_text,
                "device_name": device_name,
                "zone_name": zone_name,
                "target_time": target_time,
                "status": action_desc,
                "latitude": lat,
                "longitude": lon,
                "maps_url": maps_url,
                "timestamp": event_dt.isoformat(),
                "user_email": user.email,
            }
            await send_custom_webhook_alert(wh_url, payload)

