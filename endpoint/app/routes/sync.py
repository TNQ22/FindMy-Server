"""
POST /api/sync/now  — Trigger an immediate Apple iCloud sync + decrypt on demand.
Called by the frontend Refresh button.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models import User
from app.schemas import SyncNowResponse
from app.services.auth_service import get_current_user
from app.services.sync_service import run_sync_task

router = APIRouter(prefix="/api/sync", tags=["Sync"])


@router.post("/now", response_model=SyncNowResponse)
async def sync_now(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Immediately fetch the latest reports from Apple FindMy for all devices,
    decrypt them server-side, and return a summary.
    """
    try:
        result = await run_sync_task()
        return SyncNowResponse(
            new_reports=result.get("new_reports", 0),
            decrypted=result.get("decrypted", 0),
            updated_devices=result.get("updated_devices", []),
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Sync failed: {e}")
