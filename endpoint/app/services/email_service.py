import logging
from email.message import EmailMessage
import aiosmtplib
from app.config import settings

logger = logging.getLogger(__name__)

async def send_low_battery_alert(recipient_email: str, device_name: str, battery_status: str):
    """
    Sends an email alert to the user when a device battery is low.
    """
    if not settings.SMTP_HOST or not settings.SMTP_USER:
        logger.warning(f"SMTP not configured. Skipping low battery email alert for {device_name}.")
        return

    msg = EmailMessage()
    msg['From'] = settings.SMTP_FROM
    msg['To'] = recipient_email
    
    # Format battery text for display
    status_text = "Rất thấp (Sắp cạn)" if battery_status == "criticalLow" else "Thấp"
    
    msg['Subject'] = f"⚠️ Cảnh báo: Pin của thẻ {device_name} đang ở mức {status_text}"
    
    html_content = f"""
    <html>
      <body style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: #d9534f;">Cảnh báo Pin Yếu</h2>
        <p>Chào bạn,</p>
        <p>Hệ thống <b>FindMy Server</b> vừa phát hiện thẻ định vị <strong>{device_name}</strong> của bạn đang có trạng thái pin ở mức <b>{status_text}</b>.</p>
        <p>Để đảm bảo thẻ tiếp tục hoạt động và phát sóng vị trí, vui lòng kiểm tra hoặc thay pin mới cho thẻ trong thời gian sớm nhất.</p>
        <hr style="border: 1px solid #eee; margin: 20px 0;">
        <p style="font-size: 12px; color: #999;">Đây là tin nhắn tự động từ hệ thống FindMy Server. Vui lòng không trả lời email này.</p>
      </body>
    </html>
    """
    
    msg.set_content(f"Cảnh báo: Pin của thẻ {device_name} đang ở mức {status_text}. Vui lòng thay pin mới để đảm bảo thiết bị hoạt động liên tục.")
    msg.add_alternative(html_content, subtype='html')

    try:
        await aiosmtplib.send(
            msg,
            hostname=settings.SMTP_HOST,
            port=settings.SMTP_PORT,
            username=settings.SMTP_USER,
            password=settings.SMTP_PASS,
            use_tls=(settings.SMTP_PORT == 465),
            start_tls=(settings.SMTP_PORT == 587),
        )
        logger.info(f"Successfully sent low battery alert for {device_name} to {recipient_email}")
    except Exception as e:
        logger.error(f"Failed to send low battery alert email: {e}")
