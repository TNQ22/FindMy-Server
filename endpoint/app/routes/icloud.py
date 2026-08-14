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
    if not state_json or state_json.strip() == "{}" or state_json.strip() == "":
        return "LOGGED_OUT"
    if "REQUIRE_2FA" in state_json or "require_2fa" in state_json.lower():
        return "REQUIRE_2FA"
    try:
        data = json.loads(state_json)
        if isinstance(data, dict):
            st_val = data.get("login_state") if "login_state" in data else (data.get("_state") if "_state" in data else data.get("state"))
            st_str = str(st_val) if st_val is not None else ""

            if st_val == 1 or st_str == "1" or "REQUIRE_2FA" in st_str or "require_2fa" in st_str.lower():
                return "REQUIRE_2FA"
            if st_val == 0 or st_str == "0" or "LOGGED_OUT" in st_str or "logged_out" in st_str.lower():
                return "LOGGED_OUT"

            # MobileMe authentication tokens are ONLY generated after 2FA is verified
            if "mobileme_auth" in data or "trust_token" in data or "mobileme" in data:
                return "LOGGED_IN"

            if st_val == 2 or st_str == "2" or "LOGGED_IN" in st_str or "logged_in" in st_str.lower():
                return "LOGGED_IN"

            # If account is present without MobileMe tokens, it is pending 2FA
            if "account_id" in data or "apple_id" in data:
                return "REQUIRE_2FA"
    except Exception:
        pass
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
    primary_apple_id = None
    primary_state = "LOGGED_OUT"
    primary_active = False

    for acc in all_accounts:
        is_owner = (acc.user_id == current_user.id)
        display_email = acc.apple_id if is_owner else mask_email(acc.apple_id)
        try:
            apple_acc = await restore_apple_account(acc.state_json)
            st_obj = apple_acc.login_state
            login_state = st_obj.name if hasattr(st_obj, 'name') else str(st_obj)
        except Exception:
            login_state = get_login_state_fast(acc.state_json)

        if is_owner and not primary_apple_id:
            primary_apple_id = acc.apple_id
            primary_state = login_state
            primary_active = acc.is_active

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

    if not primary_apple_id and account_items:
        primary_apple_id = account_items[0].masked_apple_id
        primary_state = account_items[0].login_state
        primary_active = account_items[0].is_active

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
