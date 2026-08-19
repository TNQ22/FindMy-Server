import base64
import json
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Dict, Any, List, Tuple
from findmy import (
    AsyncAppleAccount,
    RemoteAnisetteProvider,
    LoginState,
    HasHashedPublicKey,
    SmsSecondFactorMethod,
    TrustedDeviceSecondFactorMethod,
)
from app.config import settings

logger = logging.getLogger(__name__)

# Ensure FindMy.py modules are accessible if needed
FINDMY_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../FindMy.py/FindMy.py-main"))
if os.path.exists(FINDMY_DIR) and FINDMY_DIR not in sys.path:
    sys.path.insert(0, FINDMY_DIR)

class SimpleHashedKey(HasHashedPublicKey):
    """Simple wrapper for base64 hashed advertisement key."""
    def __init__(self, hashed_adv_key_b64: str):
        self._key_b64 = hashed_adv_key_b64
        self._bytes = base64.b64decode(hashed_adv_key_b64)

    @property
    def hashed_adv_key_bytes(self) -> bytes:
        return self._bytes

    @property
    def hashed_adv_key_b64(self) -> str:
        return self._key_b64

def get_anisette_provider() -> RemoteAnisetteProvider:
    return RemoteAnisetteProvider(settings.ANISETTE_SERVER_URL)

def serialize_apple_account(account: AsyncAppleAccount) -> str:
    try:
        dict_state = account.to_json()
        return json.dumps(dict_state)
    except Exception as e:
        logger.error(f"Failed to serialize Apple account: {e}")
        return "{}"

async def restore_apple_account(state_json: str | None) -> AsyncAppleAccount:
    anisette = get_anisette_provider()
    if state_json and state_json.strip() and state_json != "{}":
        try:
            state_dict = json.loads(state_json)
            account = AsyncAppleAccount.from_json(state_dict)
            account._anisette = anisette
            return account
        except Exception as e:
            logger.warning(f"Failed to restore Apple account state: {e}")
    return AsyncAppleAccount(anisette=anisette)

async def login_apple_account(apple_id: str, password: str, current_state_json: str | None = None) -> Tuple[AsyncAppleAccount, LoginState, List[str]]:
    # Create fresh Apple account instance for explicit login attempts to guarantee valid MobileMe tokens & 2FA
    account = AsyncAppleAccount(anisette=get_anisette_provider())

    state = await account.login(apple_id, password)
    two_factor_methods = []

    if state == LoginState.REQUIRE_2FA:
        methods = await account.get_2fa_methods()
        for i, method in enumerate(methods):
            if isinstance(method, TrustedDeviceSecondFactorMethod):
                two_factor_methods.append(f"{i}: Trusted Device")
            elif isinstance(method, SmsSecondFactorMethod):
                phone = getattr(method, "phone_number", "SMS")
                two_factor_methods.append(f"{i}: SMS ({phone})")

    return account, state, two_factor_methods

async def request_2fa_code(state_json: str, method_index: int) -> Tuple[AsyncAppleAccount, LoginState]:
    account = await restore_apple_account(state_json)
    if account.login_state != LoginState.REQUIRE_2FA:
        raise ValueError(f"Account is not in REQUIRE_2FA state (current: {account.login_state})")

    methods = await account.get_2fa_methods()
    if method_index < 0 or method_index >= len(methods):
        raise ValueError(f"Invalid 2FA method index: {method_index}")

    method = methods[method_index]
    await method.request()
    return account, account.login_state

async def submit_2fa_code(state_json: str, method_index: int, code: str) -> Tuple[AsyncAppleAccount, LoginState]:
    account = await restore_apple_account(state_json)
    if account.login_state != LoginState.REQUIRE_2FA:
        raise ValueError(f"Account is not in REQUIRE_2FA state (current: {account.login_state})")

    methods = await account.get_2fa_methods()
    if method_index < 0 or method_index >= len(methods):
        raise ValueError(f"Invalid 2FA method index: {method_index}")

    method = methods[method_index]
    await method.submit(code)
    return account, account.login_state

async def fetch_reports_from_icloud(account: AsyncAppleAccount, hashed_b64_keys: List[str]) -> List[Dict[str, Any]]:
    if account.login_state != LoginState.LOGGED_IN:
        logger.warning(f"Apple account state is {account.login_state}, skipping report fetch.")
        return []

    keys = [SimpleHashedKey(k) for k in hashed_b64_keys]
    
    # Query Apple FindMy servers via FindMy.py
    try:
        results_map = await account.fetch_location_history(keys)
    except Exception as e:
        logger.error(f"Error calling fetch_location_history: {e}")
        try:
            if hasattr(account, "login_mobileme"):
                await account.login_mobileme()
            elif hasattr(account, "_login_mobileme"):
                await account._login_mobileme()
            results_map = await account.fetch_location_history(keys)
        except Exception as retry_err:
            logger.error(f"Retry fetch_location_history failed: {retry_err}")
            return []

    parsed_reports = []
    logger.info(f"[DEBUG] results_map type: {type(results_map)}")
    
    if isinstance(results_map, list):
        logger.info(f"[DEBUG] results_map is a list of length {len(results_map)}")
        # Single key passed or list of reports
        fallback_key = hashed_b64_keys[0] if hashed_b64_keys else ""
        for rep in results_map:
            parsed_reports.append(_parse_location_report(rep, fallback_key=fallback_key))
    elif isinstance(results_map, dict):
        logger.info(f"[DEBUG] results_map is a dict with keys: {list(results_map.keys())}")
        for key_obj, reports in results_map.items():
            if isinstance(key_obj, SimpleHashedKey):
                key_b64 = key_obj.hashed_adv_key_b64
            elif hasattr(key_obj, "hashed_adv_key_b64"):
                key_b64 = key_obj.hashed_adv_key_b64
            elif isinstance(key_obj, bytes):
                key_b64 = base64.b64encode(key_obj).decode("ascii")
            else:
                key_b64 = str(key_obj)

            if key_b64 not in hashed_b64_keys and hashed_b64_keys:
                key_b64 = hashed_b64_keys[0]

            for rep in reports:
                parsed_reports.append(_parse_location_report(rep, fallback_key=key_b64))

    return parsed_reports

def _parse_location_report(report: Any, fallback_key: str | None = None) -> Dict[str, Any]:
    payload_bytes = getattr(report, "payload", b"")
    if isinstance(payload_bytes, str):
        payload_b64 = payload_bytes
        payload_bytes = base64.b64decode(payload_bytes)
    else:
        payload_b64 = base64.b64encode(payload_bytes).decode("ascii")

    # Extract published timestamp
    published_ts = None
    if hasattr(report, "timestamp") and report.timestamp:
        if isinstance(report.timestamp, datetime):
            published_ts = int(report.timestamp.timestamp() * 1000)
        elif isinstance(report.timestamp, (int, float)):
            published_ts = int(report.timestamp)

    if not published_ts and len(payload_bytes) >= 4:
        seen_timestamp = int.from_bytes(payload_bytes[0:4], "big", signed=True)
        published_ts = (seen_timestamp + 978307200) * 1000

    if not published_ts:
        published_ts = int(datetime.now(timezone.utc).timestamp() * 1000)

    key_id = getattr(report, "hashed_adv_key_b64", None) or getattr(report, "id", None) or fallback_key or ""

    return {
        "payload": payload_b64,
        "datePublished": published_ts,
        "statusCode": 200,
        "id": key_id,
    }
