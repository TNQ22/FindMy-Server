import json
import traceback
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models import User, ICloudAccount
from app.schemas import ICloudLoginRequest, ICloud2FARequest, ICloud2FARequestCode, ICloudStatusResponse, ICloudAccountItem
from app.services.auth_service import get_current_user
from app.services.icloud_service import (
    login_apple_account,
    request_2fa_code,
    submit_2fa_code,
    restore_apple_account,
    serialize_apple_account,
)
from findmy import LoginState

router = APIRouter(prefix="/api/icloud", tags=["iCloud"])

def mask_email(email: str) -> str:
    if not email or "@" not in email:
        return email
    name, domain = email.split("@", 1)
    if len(name) <= 3:
        masked_name = name[0] + "***"
    else:
        masked_name = name[:2] + "***" + name[-2:]
    return f"{masked_name}@{domain}"

def get_login_state_fast(state_json: str) -> str:
    if not state_json or state_json.strip() in ("", "{}"):
        return "LOGGED_OUT"
    try:
        data = json.loads(state_json)
        if isinstance(data, dict):
            # Check FindMy.py serialized format: data["login"]["state"]
            login_sec = data.get("login")
            if isinstance(login_sec, dict) and "state" in login_sec:
                st = login_sec["state"]
                if st == 3 or st == "3" or str(st).upper() == "LOGGED_IN":
                    return "LOGGED_IN"
                elif st == 1 or st == "1" or str(st).upper() == "REQUIRE_2FA":
                    return "REQUIRE_2FA"
                elif st == 2 or st == "2" or str(st).upper() == "AUTHENTICATED":
                    return "AUTHENTICATED"
                elif st == 0 or st == "0" or str(st).upper() == "LOGGED_OUT":
                    return "LOGGED_OUT"

            # Check direct top-level state fields
            st_val = data.get("login_state") or data.get("_state") or data.get("state")
            if st_val is not None:
                st_str = str(st_val).upper()
                if "LOGGED_IN" in st_str or st_val == 3:
                    return "LOGGED_IN"
                if "REQUIRE_2FA" in st_str or st_val == 1:
                    return "REQUIRE_2FA"
                if "AUTHENTICATED" in st_str or st_val == 2:
                    return "AUTHENTICATED"
                if "LOGGED_OUT" in st_str or st_val == 0:
                    return "LOGGED_OUT"

            # Check for presence of MobileMe authentication data
            login_data = login_sec.get("data", {}) if isinstance(login_sec, dict) else {}
            if isinstance(login_data, dict):
                if "mobileme_data" in login_data or "searchPartyToken" in str(login_data):
                    return "LOGGED_IN"

            if "mobileme_auth" in data or "trust_token" in data or "mobileme" in data:
                return "LOGGED_IN"
    except Exception:
        pass

    if "REQUIRE_2FA" in state_json or "require_2fa" in state_json.lower():
        return "REQUIRE_2FA"

    return "LOGGED_OUT"

@router.get("/status", response_model=ICloudStatusResponse)
async def get_icloud_status(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(select(ICloudAccount).order_by(ICloudAccount.updated_at.desc()))
        all_accounts = result.scalars().all()
    except Exception as e:
        print(f"Failed to query iCloud accounts: {e}")
        all_accounts = []

    account_items: list[ICloudAccountItem] = []

    for acc in all_accounts:
        is_owner = (acc.user_id == current_user.id)
        display_email = acc.apple_id if is_owner else mask_email(acc.apple_id)
        try:
            apple_acc = await restore_apple_account(acc.state_json)
            st_obj = apple_acc.login_state
            login_state = st_obj.name if hasattr(st_obj, 'name') else str(st_obj)
        except Exception:
            login_state = get_login_state_fast(acc.state_json)

        account_items.append(
            ICloudAccountItem(
                id=acc.id,
                apple_id=display_email,
                masked_apple_id=mask_email(acc.apple_id),
                is_owner=is_owner,
                is_active=acc.is_active,
                login_state=login_state,
                fetch_count=getattr(acc, 'fetch_count', 0) or 0,
                last_used_at=getattr(acc, 'last_used_at', None)
            )
        )

    # Determine primary status accurately across the pool
    # 1. Prefer user's active & LOGGED_IN account
    # 2. Otherwise any active & LOGGED_IN account in pool
    # 3. Otherwise any active account owned by user
    # 4. Fallback to first available account
    primary_apple_id = None
    primary_state = "LOGGED_OUT"
    primary_active = False

    user_logged_in = next((a for a in account_items if a.is_owner and a.is_active and a.login_state == "LOGGED_IN"), None)
    pool_logged_in = next((a for a in account_items if a.is_active and a.login_state == "LOGGED_IN"), None)
    user_any = next((a for a in account_items if a.is_owner and a.is_active), None)
    req_2fa_acc = next((a for a in account_items if a.is_active and "REQUIRE_2FA" in a.login_state), None)

    best_match = user_logged_in or pool_logged_in or user_any or req_2fa_acc or (account_items[0] if account_items else None)

    if best_match:
        primary_apple_id = best_match.apple_id
        primary_state = best_match.login_state
        primary_active = best_match.is_active

    return ICloudStatusResponse(
        apple_id=primary_apple_id,
        is_active=primary_active,
        login_state=primary_state,
        accounts=account_items
    )

@router.post("/login", response_model=ICloudStatusResponse)
async def login_icloud(
    body: ICloudLoginRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    try:
        result = await db.execute(select(ICloudAccount).where(ICloudAccount.apple_id == body.apple_id))
        acc_rec = result.scalar_one_or_none()

        current_state_json = acc_rec.state_json if acc_rec else None

        account, state, two_factor_methods = await login_apple_account(
            body.apple_id, body.password, current_state_json
        )
        state_json = serialize_apple_account(account)

        if acc_rec:
            acc_rec.user_id = current_user.id
            acc_rec.state_json = state_json
            acc_rec.is_active = True
            acc_rec.is_alerted = False
            acc_rec.last_error = None
        else:
            acc_rec = ICloudAccount(
                user_id=current_user.id,
                apple_id=body.apple_id,
                state_json=state_json,
                is_active=True,
                is_alerted=False,
                last_error=None
            )
            db.add(acc_rec)

        await db.commit()
        await db.refresh(acc_rec)

        status_res = await get_icloud_status(current_user=current_user, db=db)
        status_res.two_factor_methods = two_factor_methods
        status_res.login_state = str(state.name if hasattr(state, 'name') else state)
        return status_res
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        print("Apple Login Error Traceback:")
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Apple login failed: {str(e)}"
        )

@router.post("/2fa/request", response_model=ICloudStatusResponse)
async def request_icloud_2fa_code(
    body: ICloud2FARequestCode,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if body.apple_id:
        result = await db.execute(select(ICloudAccount).where(ICloudAccount.apple_id == body.apple_id))
        acc_rec = result.scalar_one_or_none()
    else:
        result = await db.execute(select(ICloudAccount).where(ICloudAccount.user_id == current_user.id).order_by(ICloudAccount.updated_at.desc()))
        acc_rec = result.scalars().first()

    if not acc_rec:
        raise HTTPException(status_code=404, detail="No active iCloud account found for 2FA.")

    try:
        account, state = await request_2fa_code(acc_rec.state_json, body.method_index)
        acc_rec.state_json = serialize_apple_account(account)
        await db.commit()

        return await get_icloud_status(current_user=current_user, db=db)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Requesting 2FA code failed: {str(e)}"
        )

@router.post("/2fa", response_model=ICloudStatusResponse)
async def submit_icloud_2fa(
    body: ICloud2FARequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    if body.apple_id:
        result = await db.execute(select(ICloudAccount).where(ICloudAccount.apple_id == body.apple_id))
        acc_rec = result.scalar_one_or_none()
    else:
        result = await db.execute(select(ICloudAccount).where(ICloudAccount.user_id == current_user.id).order_by(ICloudAccount.updated_at.desc()))
        acc_rec = result.scalars().first()

    if not acc_rec:
        raise HTTPException(status_code=404, detail="No active iCloud account found for 2FA.")

    try:
        account, state = await submit_2fa_code(acc_rec.state_json, body.method_index, body.code)
        acc_rec.state_json = serialize_apple_account(account)
        if state == LoginState.LOGGED_IN:
            acc_rec.is_alerted = False
            acc_rec.last_error = None
        await db.commit()

        return await get_icloud_status(current_user=current_user, db=db)
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"2FA verification failed: {str(e)}"
        )

@router.delete("/accounts/{account_id}", response_model=ICloudStatusResponse)
async def delete_icloud_account(
    account_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(ICloudAccount).where(ICloudAccount.id == account_id))
    acc_rec = result.scalar_one_or_none()
    if not acc_rec:
        raise HTTPException(status_code=404, detail="Tài khoản iCloud không tồn tại.")
    
    if acc_rec.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Bạn không có quyền đăng xuất hoặc xóa tài khoản iCloud của người khác trong Pool!"
        )

    await db.delete(acc_rec)
    await db.commit()

    return await get_icloud_status(current_user=current_user, db=db)

@router.post("/logout", response_model=ICloudStatusResponse)
async def logout_icloud(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(ICloudAccount).where(ICloudAccount.user_id == current_user.id))
    acc_recs = result.scalars().all()
    for acc in acc_recs:
        await db.delete(acc)
    await db.commit()

    return await get_icloud_status(current_user=current_user, db=db)
