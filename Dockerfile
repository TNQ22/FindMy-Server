# === STAGE 1: Build Flutter Web App ===
FROM instrumentisto/flutter:latest AS web-builder
#Bạn chỉ cần để máy chủ x86_64 (amd64) build ra thư mục web 1 lần duy nhất, sau đó copy kết quả đó vào stage Python cho cả 2 kiến trúc.
#FROM --platform=$BUILDPLATFORM instrumentisto/flutter:latest AS web-builder

WORKDIR /app_web

# Copy Flutter source code
COPY macless_haystack /app_web

RUN flutter config --enable-web
RUN flutter pub get
RUN flutter build web --release --no-tree-shake-icons

# === STAGE 2: Python FastAPI Server + Static Web App ===
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy backend requirements & install Python packages
COPY endpoint/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy FastAPI backend source code
COPY endpoint /app

# Copy Flutter Web build output from STAGE 1 into static_web directory
COPY --from=web-builder /app_web/build/web /app/static_web

EXPOSE 6176

VOLUME ["/app/data"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "6176"]
