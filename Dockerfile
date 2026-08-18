# === STAGE 1: Build Flutter Web App ===
FROM --platform=$BUILDPLATFORM instrumentisto/flutter:latest AS web-builder

WORKDIR /app_web

# Copy Flutter source code
COPY macless_haystack /app_web

RUN flutter config --enable-web \
    && flutter pub get \
    && flutter build web --release --no-tree-shake-icons

# === STAGE 2: Python Builder (Compile & Install Dependencies) ===
FROM python:3.11-slim-bookworm AS python-builder

WORKDIR /build

COPY endpoint/requirements.txt /build/requirements.txt
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# === STAGE 3: Final Minimal Runtime Image ===
FROM python:3.11-slim-bookworm

WORKDIR /app

# Copy installed Python packages from python-builder
COPY --from=python-builder /install /usr/local

# Copy Flutter Web build output from STAGE 1 into static_web directory
COPY --from=web-builder /app_web/build/web /app/static_web

# Copy FastAPI backend source code
COPY endpoint /app
COPY version /app/version

EXPOSE 6176

VOLUME ["/app/data"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "6176"]
