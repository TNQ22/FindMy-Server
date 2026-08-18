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

async def send_test_email_alert(recipient_email: str):
    """
    Sends a test email alert to verify SMTP configuration and connectivity.
    """
    if not settings.SMTP_HOST or not settings.SMTP_USER:
        raise ValueError("Hệ thống chưa cấu hình máy chủ gửi thư (SMTP_HOST / SMTP_USER) trong file .env hoặc cấu hình server.")

    msg = EmailMessage()
    msg['From'] = settings.SMTP_FROM or settings.SMTP_USER
    msg['To'] = recipient_email
    msg['Subject'] = "🔔 FindMy Server: Kiểm tra kết nối thông báo Email"

    html_content = f"""
    <html>
      <body style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #00897B, #004D40); padding: 20px; border-radius: 12px; text-align: center; color: white; margin-bottom: 20px;">
          <h2 style="margin: 0; font-size: 22px;">🔔 FindMy Server</h2>
          <p style="margin: 5px 0 0 0; opacity: 0.9; font-size: 14px;">Kiểm tra cấu hình kênh thông báo Email</p>
        </div>
        <div style="background-color: #E0F2F1; border-left: 4px solid #00897B; padding: 14px 18px; margin: 15px 0; border-radius: 6px;">
          <p style="margin: 0; font-size: 15px; color: #004D40; font-weight: bold;">
            ✅ Kênh thông báo Email đã được kết nối và hoạt động chính xác!
          </p>
        </div>
        <p>Chào bạn,</p>
        <p>Đây là email kiểm tra tự động được gửi từ hệ thống <b>FindMy Server</b> tới hộp thư <strong>{recipient_email}</strong>.</p>
        <p>Kênh thông báo qua Email của bạn hiện đã được thiết lập thành công và sẵn sàng nhận các thông báo từ hệ thống.</p>
        <hr style="border: none; border-top: 1px solid #eee; margin: 25px 0;">
        <p style="font-size: 12px; color: #888; text-align: center;">Đây là tin nhắn tự động từ FindMy Server. Vui lòng không phản hồi email này.</p>
      </body>
    </html>
    """
    msg.set_content(
        f"FindMy Server: Kênh thông báo Email đã được thiết lập thành công tới {recipient_email}! Kênh thông báo qua Email của bạn hiện đã sẵn sàng nhận các thông báo từ hệ thống."
    )
    msg.add_alternative(html_content, subtype='html')

    await aiosmtplib.send(
        msg,
        hostname=settings.SMTP_HOST,
        port=settings.SMTP_PORT,
        username=settings.SMTP_USER,
        password=settings.SMTP_PASS,
        use_tls=(settings.SMTP_PORT == 465),
        start_tls=(settings.SMTP_PORT == 587),
    )
    logger.info(f"Successfully sent test notification email to {recipient_email}")

async def send_icloud_status_alert(recipient_email: str, apple_id: str, reason: str):
    """
    Sends an email alert when an iCloud account is disconnected, expired, or requires re-authentication.
    """
    if not settings.SMTP_HOST or not settings.SMTP_USER:
        logger.warning(f"SMTP not configured. Skipping iCloud status alert for {apple_id}.")
        return

    msg = EmailMessage()
    msg['From'] = settings.SMTP_FROM
    msg['To'] = recipient_email
    
    msg['Subject'] = f"🚨 Cảnh báo: Tài khoản Apple ID {apple_id} không khả dụng"
    
    html_content = f"""
    <html>
      <body style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: #d9534f; margin-bottom: 5px;">⚠️ Cảnh Báo Tài Khoản iCloud Mất Kết Nối</h2>
        <p>Chào bạn,</p>
        <p>Hệ thống <b>FindMy Server</b> phát hiện tài khoản Apple ID <strong>{apple_id}</strong> của bạn hiện <b>không thể truy vấn vị trí</b>.</p>
        <div style="background-color: #fff3cd; border-left: 4px solid #ffeeba; padding: 12px 15px; margin: 15px 0; border-radius: 4px;">
            <p style="margin: 0; font-size: 14px; color: #856404;">
                <strong>Lý do:</strong> {reason}
            </p>
        </div>
        <p><strong>Hành động cần làm:</strong></p>
        <ul>
            <li>Vui lòng truy cập trang quản trị <b>FindMy Server</b>.</li>
            <li>Mở mục <b>Cài đặt (Settings) &gt; iCloud Pool</b> để đăng nhập lại hoặc hoàn tất mã xác thực 2FA.</li>
        </ul>
        <p>Việc này giúp hệ thống tiếp tục tự động cập nhật vị trí các thẻ định vị một cách liên tục và chính xác nhất.</p>
        <hr style="border: 1px solid #eee; margin: 20px 0;">
        <p style="font-size: 12px; color: #999;">Đây là tin nhắn tự động từ hệ thống FindMy Server. Vui lòng không trả lời email này.</p>
      </body>
    </html>
    """
    
    msg.set_content(f"Cảnh báo: Tài khoản Apple ID {apple_id} hiện không thể truy vấn vị trí. Lý do: {reason}. Vui lòng đăng nhập lại trên trang quản trị FindMy Server.")
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
        logger.info(f"Successfully sent iCloud status alert for {apple_id} to {recipient_email}")
    except Exception as e:
        logger.error(f"Failed to send iCloud status alert email for {apple_id}: {e}")


async def send_geofence_alert(
    recipient_email: str,
    device_name: str,
    zone_name: str,
    alert_type: str,
    lat: float,
    lon: float,
    distance: float,
    radius: float,
):
    """
    Sends an email alert when a device enters or exits a geofence zone.
    """
    if not settings.SMTP_HOST or not settings.SMTP_USER:
        logger.warning(f"SMTP not configured. Skipping geofence email alert for {device_name} in {zone_name}.")
        return

    msg = EmailMessage()
    msg['From'] = settings.SMTP_FROM
    msg['To'] = recipient_email

    is_exit = alert_type.upper() == "EXIT"
    action_text = "RỜI KHỎI" if is_exit else "ĐI VÀO"
    badge_color = "#d9534f" if is_exit else "#28a745"
    title_text = f"Cảnh Báo Vùng An Toàn: {device_name} đã {action_text} {zone_name}"
    
    maps_url = f"https://www.google.com/maps/search/?api=1&query={lat},{lon}"

    msg['Subject'] = f"{'🚨' if is_exit else '📍'} {title_text}"

    html_content = f"""
    <html>
      <body style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background-color: {badge_color}; color: #fff; padding: 12px 18px; border-radius: 6px; text-align: center;">
          <h2 style="margin: 0; font-size: 20px;">{title_text}</h2>
        </div>
        <p style="margin-top: 20px;">Chào bạn,</p>
        <p>Hệ thống <b>FindMy Server</b> phát hiện thẻ định vị <strong>{device_name}</strong> vừa có sự kiện vị trí:</p>
        
        <div style="background-color: #f8f9fa; border: 1px solid #e9ecef; border-left: 5px solid {badge_color}; padding: 15px; border-radius: 4px; margin: 15px 0;">
          <p style="margin: 5px 0;">🏷️ <b>Thiết bị:</b> {device_name}</p>
          <p style="margin: 5px 0;">🛡️ <b>Khu vực:</b> {zone_name} (Bán kính: {int(radius)}m)</p>
          <p style="margin: 5px 0;">⚡ <b>Sự kiện:</b> <span style="color: {badge_color}; font-weight: bold;">{action_text} KHU VỰC</span></p>
          <p style="margin: 5px 0;">📏 <b>Khoảng cách tới tâm:</b> {distance:.1f} m</p>
          <p style="margin: 5px 0;">🌐 <b>Tọa độ:</b> {lat:.6f}, {lon:.6f}</p>
        </div>

        <div style="text-align: center; margin: 25px 0;">
          <a href="{maps_url}" style="background-color: #007bff; color: #ffffff; padding: 10px 20px; text-decoration: none; border-radius: 4px; font-weight: bold; display: inline-block;">
            📍 Xem Vị Trí Trên Google Maps
          </a>
        </div>

        <hr style="border: 1px solid #eee; margin: 20px 0;">
        <p style="font-size: 12px; color: #999;">Đây là thông báo tự động từ hệ thống Geofencing của FindMy Server. Vui lòng không trả lời email này.</p>
      </body>
    </html>
    """

    msg.set_content(
        f"{title_text}\n\n"
        f"Thiết bị: {device_name}\n"
        f"Khu vực: {zone_name}\n"
        f"Sự kiện: {action_text} khu vực\n"
        f"Khoảng cách tới tâm: {distance:.1f} m (Bán kính: {int(radius)}m)\n"
        f"Tọa độ: {lat:.6f}, {lon:.6f}\n"
        f"Xem bản đồ: {maps_url}\n"
    )
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
        logger.info(f"Successfully sent geofence alert ({alert_type}) for {device_name} to {recipient_email}")
    except Exception as e:
        logger.error(f"Failed to send geofence alert email for {device_name}: {e}")


