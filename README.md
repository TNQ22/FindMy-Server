# 🛰️ FindMy Server

Hệ thống máy chủ mạng lưới **Apple FindMy** tự triển khai (Self-hosted) hiện đại, đóng gói Docker hoàn chỉnh với tính năng **Hồ chứa iCloud dùng chung (Shared iCloud Pool)**, **Đăng nhập Google OAuth** và **Tự động đồng bộ vị trí ngầm 24/7**.

![Architecture](images/dashboard_web.png)

---

## 🌟 Tính Năng Nổi Bật

- 👥 **Shared iCloud Dùng Chung (Shared iCloud Pool)**:
  - Thêm nhiều tài khoản Apple ID vào một hồ chứa dùng chung.
  - Tự động xoay vòng tài khoản (Round-Robin) và tự động bỏ qua các tài khoản bị lỗi/kẹt 2FA.
  - Hỗ trợ xác thực 2FA tương tác trực tiếp (Thiết bị tin cậy & Tin nhắn SMS) với tính năng điền sẵn email thông minh.

- 🔒 **Đăng Nhập Google OAuth & Đồng Bộ Server**:
  - Đăng nhập bảo mật tuyệt đối qua Google OAuth.
  - Đồng bộ 24/7 danh sách thiết bị, Thẻ định vị (Tag) và cài đặt cá nhân trên mọi trình duyệt và thiết bị di động.

- ⚡ **Tự Động Nạp Vị Trí Ngầm 24/7**:
  - Tự động gom bản tin vị trí mới từ Apple FindMy Network mỗi 15 phút một lần (có thể tùy chỉnh qua biến `SYNC_INTERVAL_MINUTES`).
  - Không cần giữ trình duyệt mở—vị trí của các Tag luôn được máy chủ tự động cập nhật liên tục vào CSDL.

- 🗺️ **Bản Đồ Hiện Đại & Giao Diện Mượt Mà**:
  - Giao diện OpenStreetMap sắc nét, tự động hỗ trợ Chế độ Tối (Dark Mode).
  - Định vị thiết bị GPS và căn chỉnh góc nhìn mượt mà, giữ nguyên mức Zoom không bị nhảy Zoom Out đột ngột.
  - Bật thông báo Toast phản hồi trạng thái tức thì khi F5 hoặc nạp thủ công.

- 🐳 **Triển Khai 1-Click Với Docker Compose**:
  - Đóng gói container trọn gói bao gồm **Flutter Web Frontend**, **FastAPI Backend** và **Anisette v3 Server**.

---

## 🏗️ Sơ Đồ Kiến Trúc Hệ Thống

```
                        ┌───────────────────────────────┐
                        │   Flutter Web App (Port 8080) │
                        └──────────────┬────────────────┘
                                       │ REST API / JWT
                                       ▼
                        ┌───────────────────────────────┐
                        │  FastAPI Backend (Port 6176)  │
                        └───────┬───────────────┬───────┘
                                │               │
          Anisette Headers      │               │  Bản tin vị trí
                                ▼               ▼
            ┌───────────────────────┐       ┌───────────────────────┐
            │ Anisette v3 (Port 6969)│       │  Apple FindMy Network │
            └───────────────────────┘       └───────────────────────┘
```

---

## 🚀 Hướng Dẫn Khởi Chạy Nhanh (Docker Compose)

### 1. Yêu Cầu Tiên Quyết
- Đã cài đặt [Docker](https://www.docker.com/) và [Docker Compose](https://docs.docker.com/compose/).

### 2. Cấu Hình Biến Môi Trường

Tạo một tệp `.env` tại thư mục gốc của dự án:

```env
# Cấu hình Google OAuth Client ID
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com

# Mã Secret đính kèm JWT của Backend
JWT_SECRET=super-secret-findmy-key-change-in-production

# Chu kỳ tự động nạp vị trí ngầm (Tính theo phút)
SYNC_INTERVAL_MINUTES=15
```

### 3. Khởi Chạy Hệ Thống

Chạy lệnh sau để build và khởi chạy toàn bộ các dịch vụ:

```bash
docker-compose up --build -d
```

### 4. Cổng Truy Cập
- 📱 **Giao diện Web (Frontend)**: [http://localhost:8080](http://localhost:8080)
- ⚙️ **Tài liệu REST API (Backend Swagger)**: [http://localhost:6176/docs](http://localhost:6176/docs)
- 🔑 **Dịch vụ Anisette v3 Server**: `http://localhost:6969`

---

## ⚙️ Bảng Biến Môi Trường Cấu Hình

| Biến Môi Trường | Mô Tả | Giá Trị Mặc Định |
| :--- | :--- | :--- |
| `GOOGLE_CLIENT_ID` | Client ID dùng để xác thực Đăng nhập Google OAuth | *Bắt buộc để Đăng nhập Web* |
| `JWT_SECRET` | Khóa bảo mật tạo Token phiên làm việc cho Backend | `super-secret-findmy-key...` |
| `SYNC_INTERVAL_MINUTES` | Chu kỳ thời gian (phút) tự động nạp vị trí ngầm | `15` |
| `ANISETTE_SERVER_URL` | Địa chỉ URL kết nối đến Anisette Server container | `http://anisette:6969` |
| `DEBUG_LOGS` | Bật/tắt ghi nhật ký chi tiết trong Backend | `true` |

---

## 🛠️ Cài Đặt Thẻ Định Vị Phần Cứng (Hardware Tag)

1. Tạo cặp khóa định vị Apple FindMy bằng công cụ tạo khóa trong thư mục `firmware/`.
2. Nạp (flash) khóa công khai đã tạo vào thiết bị phần cứng tương thích (ESP32, NRF51, NRF52, ST17H66 hoặc các thiết bị tương thích OpenHaystack).
3. Thêm khóa quảng cáo dạng Base64 vào bảng điều khiển **FindMy Server** trên Web.

---

## 📜 Giấy Phép & Ghi Nhận

Dự án này tích hợp và phát triển dựa trên nhiều nền tảng mã nguồn mở FindMy uy tín bao gồm OpenHaystack, FindMy.py và Anisette v3 Server.
