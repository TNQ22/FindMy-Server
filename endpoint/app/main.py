import asyncio
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from app.database import init_db, AsyncSessionLocal
from app.routes.auth import router as auth_router
from app.routes.icloud import router as icloud_router
from app.routes.devices import router as devices_router
from app.routes.reports import router as reports_router
from app.routes.sync import router as sync_router
from app.routes.admin import router as admin_router
from app.routes.zones import router as zones_router
from app.services.sync_service import start_sync_scheduler, stop_sync_scheduler
from app.services.decrypt_service import decrypt_pending_reports_background

from app.config import settings

if settings.DEBUG_LOGS:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )
    logging.getLogger("uvicorn.access").setLevel(logging.INFO)
else:
    logging.basicConfig(
        level=logging.WARNING,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.WARNING)

logging.getLogger("asyncio").setLevel(logging.CRITICAL)
logger = logging.getLogger("main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing database...")
    await init_db()
    logger.info("Starting background sync scheduler...")
    start_sync_scheduler()

    # Decrypt any historical reports that were stored before server-side
    # decryption was introduced (runs as a non-blocking background task).
    asyncio.create_task(decrypt_pending_reports_background(AsyncSessionLocal))
    logger.info("Background decryption of pending reports scheduled.")

    yield

    logger.info("Stopping background sync scheduler...")
    stop_sync_scheduler()


app = FastAPI(
    title="FindMy Server",
    description="FastAPI Backend for FindMy Server with FindMy.py, Google Login, and Auto-Sync",
    version="2.1.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(icloud_router)
app.include_router(devices_router)
app.include_router(reports_router)
app.include_router(sync_router)
app.include_router(admin_router)
app.include_router(zones_router)

from app.config import settings


@app.get("/health")
async def health():
    return {"status": "ok", "service": "FindMy-Server"}


@app.get("/api/config")
async def get_config():
    return {
        "google_client_id": settings.GOOGLE_CLIENT_ID,
        "sync_interval_minutes": settings.SYNC_INTERVAL_MINUTES
    }


@app.get("/api/version")
async def get_version():
    candidates = [
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "version"),
        os.path.join(os.getcwd(), "version"),
        os.path.join(os.getcwd(), "..", "version"),
        "/app/version",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    ver = f.read().strip()
                    if ver:
                        return {"version": ver}
            except Exception:
                pass
    return {"version": "1.1.1"}



from app.routes.reports import fetch_location_reports
from app.schemas import MaclessFetchRequest, MaclessFetchResponse
from app.models import User
from app.services.auth_service import get_current_user
from app.database import get_db
from sqlalchemy.ext.asyncio import AsyncSession


@app.post("/fetch", response_model=MaclessFetchResponse, tags=["Reports"])
@app.post("/reports/fetch", response_model=MaclessFetchResponse, tags=["Reports"])
async def legacy_fetch(
    body: MaclessFetchRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Legacy endpoint kept for backward compatibility."""
    return await fetch_location_reports(body, current_user, db)


import os
from fastapi.staticfiles import StaticFiles

static_web_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "static_web")
if not os.path.exists(static_web_dir):
    static_web_dir = os.path.join(os.getcwd(), "static_web")

if os.path.exists(static_web_dir):
    logger.info(f"Mounting static web UI from {static_web_dir}")
    app.mount("/", StaticFiles(directory=static_web_dir, html=True), name="static_web")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=6176, reload=True)
