# FindMy Server

Hệ thống máy chủ tự triển khai (**Self-hosted**) cho mạng lưới **Apple Find My**, được đóng gói trọn gói bằng Docker. Hỗ trợ theo dõi vị trí các thiết bị OpenHaystack / AirTag tự chế (ESP32, NRF5x...) 24/7 một cách an toàn và bảo mật. Hỗ trợ đăng nhập nhiều người dùng bằng Google OAuth.

![Giao diện FindMy Server](images/dashboard_web.png)

---

## Screenshots

<details><summary>Website</summary>

### Web
![Dashboard](images/dashboard_web_swipe_acction.png)
![Dashboard](images/history_web_light.png)
![Dashboard](images/accessories_web.png)
![Dashboard](images/settings_web.png)

</details>

---
## 🌟 Tính Năng Nổi Bật

- 👥 **Hồ Chứa iCloud Dùng Chung (Shared iCloud Pool)**:
  - Thêm nhiều tài khoản Apple ID để tự động xoay vòng truy vấn vị trí, tránh bị giới hạn tần suất từ Apple.
  - Hỗ trợ xác thực 2FA trực tiếp (Thiết bị tin cậy hoặc SMS).
- 📧 **Cảnh Báo Qua Email (SMTP)**:
  - **Cảnh báo tài khoản iCloud**: Tự động gửi email khi tài khoản Apple ID bị hết hạn phiên đăng nhập, yêu cầu xác thực lại (2FA), hoặc gặp sự cố kết nối với Apple.
  - **Cảnh báo pin yếu**: Tự động gửi email thông báo cho người dùng khi thẻ định vị bị yếu pin hoặc sắp cạn pin.

    Hệ thống tự động giải mã trạng thái pin từ các bản tin của mạng Apple Find My và phân loại thành **4 mức**:

    | Mức mã hóa (Bit) | Trạng thái | Tỷ lệ pin ước tính | Cảnh báo Email |
    | :---: | :--- | :---: | :--- |
    | `00` | 🟢 **Đầy / Tốt (`ok`)** | ~75% – 100% | Không |
    | `01` | 🟡 **Trung bình (`medium`)** | ~25% – 75% | Không |
    | `10` | 🟠 **Yếu (`low`)** | ~10% – 25% | 📧 **Gửi email cảnh báo** |
    | `11` | 🔴 **Rất yếu / Sắp cạn (`criticalLow`)** | < 10% | 📧 **Gửi email cảnh báo khẩn cấp** |

  > 💡 **Cơ chế gửi mail thông minh:** Email chỉ được gửi 1 lần khi trạng thái chuyển sang lỗi hoặc pin yếu (tránh spam). Khi sự cố được khắc phục (đăng nhập lại hoặc thay pin mới), hệ thống sẽ tự động đặt lại cờ cảnh báo.

- 🔒 **Đăng Nhập Google OAuth & Phân Quyền**: Đăng nhập an toàn bằng tài khoản Google, phân quyền Admin và User riêng biệt.
- ⚡ **Tự Động Đồng Bộ Vị Trí 24/7**: Máy chủ tự động tải và giải mã vị trí ngầm định kỳ vào cơ sở dữ liệu mà không cần giữ trình duyệt mở.
- 🗺️ **Lịch Sử Di Chuyển Thông Minh**:
  - Tự động gom các vị trí lân cận thành điểm dừng và hiển thị thời gian lưu trú.
  - Kích thước icon điểm dừng co giãn theo thời gian lưu lại.
- 📦 **Tất Cả Trong Một (All-in-One Docker)**: Giao diện Web (Flutter) và Backend (FastAPI) được đóng gói chung vào một container duy nhất (Port `6176`).

---

## Hardware setup

1. Head over to the [releases](https://github.com/dchristl/macless-haystack/releases/latest) section and download `generate_keys.py` and your needed firmware (ESP32 or NRF5x) zip file.

2. Execute the `generate_keys.py` script to generate your keypair. (Note: dependency `cryptography` is needed. Install it with `pip install cryptography`)

3. Unzip the firmware and flash it to your device (see [Install ESP32-firmware with your key](firmware/ESP32/README.md) or [Install NRF5x-firmware with your key](firmware/nrf5x/README.md))

###### Note: In general, any OpenHaystack-compatible device or its firmware is also compatible with Macless-Haystack (i.e. [the ST17H66](https://github.com/biemster/FindMy/tree/main/Lenze_ST17H66)). Typically, only the Base64-encoded advertisement key is required, which can be found in the .keys file after key generation

---

## 🚀 Khởi Chạy FindMy Server Nhanh Với Docker Compose

### 1. Tạo file `.env`

Tạo file `.env` trong thư mục dự án với nội dung mẫu:

```env
# Google OAuth (Bắt buộc để đăng nhập)
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com

# Chu kỳ tự động lấy vị trí (phút), không nên để thấp hơn 15 phút để tránh bị block
SYNC_INTERVAL_MINUTES=60

# Danh sách email Admin (cách nhau bởi dấu phẩy)
ADMIN_EMAILS=admin@example.com

# (Tùy chọn) Cấu hình gửi mail cảnh báo Pin yếu
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM=FindMy Server <your-email@gmail.com>
```

---

### 2. Khởi chạy bằng Docker Compose

Tạo file `docker-compose.yml`:

```yaml
services:
  anisette:
    image: dadoum/anisette-v3-server:latest
    container_name: findmy-anisette
    restart: unless-stopped
    #ports:
    #  - "6969:6969"
    volumes:
      - anisette_data:/home/Alcoholic/.config/anisette-v3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  findmy-server:
    image: tnq22/findmy-server:latest
    container_name: findmy-server
    restart: unless-stopped
    ports:
      - "6176:6176"
    environment:
      - ANISETTE_SERVER_URL=http://anisette:6969
      - GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
      - JWT_SECRET=${JWT_SECRET:-super-secret-findmy-key-change-in-production}
      - SYNC_INTERVAL_MINUTES=${SYNC_INTERVAL_MINUTES:-60}
      - DEBUG_LOGS=${DEBUG_LOGS:-false}
      - SMTP_HOST=${SMTP_HOST}
      - SMTP_PORT=${SMTP_PORT:-587}
      - SMTP_USER=${SMTP_USER}
      - SMTP_PASS=${SMTP_PASS}
      - SMTP_FROM=${SMTP_FROM}
      - ADMIN_EMAILS=${ADMIN_EMAILS}
    volumes:
      - ./database:/app/data
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    depends_on:
      - anisette
volumes:
  anisette_data:

```

Chạy lệnh để khởi động:

```bash
docker compose up -d
```

---

### 3. Truy Cập Ứng Dụng

- 🌐 **Giao diện Web**: [http://localhost:6176](http://localhost:6176)
- 📖 **API Docs (Swagger)**: [http://localhost:6176/docs](http://localhost:6176/docs)

---

## 🛠️ Cài Đặt Thẻ Định Vị (Hardware Tag)

1. Sử dụng script `generate_keys.py` để tạo cặp khóa định vị Apple Find My.
2. Nạp (flash) firmware trong thư mục `firmware/` (hỗ trợ **ESP32**, **NRF51**, **NRF52**...) vào thiết bị.
3. Đăng nhập vào giao diện Web FindMy Server và thêm thẻ bằng khóa Base64 đã tạo.

---

## 📜 Ghi Nhận (Credits)

Dự án phát triển và tối ưu hóa dựa trên các mã nguồn mở:
- [OpenHaystack](https://github.com/seemoo-lab/openhaystack)
- [FindMy.py](https://github.com/malmeloo/FindMy.py)
- [Anisette-v3-Server](https://github.com/Dadoum/anisette-v3-server)
- [Macless-Haystack](https://github.com/dchristl/macless-haystack)
