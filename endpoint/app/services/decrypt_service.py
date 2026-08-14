"""
Apple FindMy Location Report Decryption Service.

Implements the same algorithm as the Flutter/Dart `DecryptReports` class:
  1. Parse Apple payload (timestamp, ephemeral public key, encrypted data, auth tag)
  2. ECDH on P-224 (SECP224R1) → 28-byte shared secret
  3. ANSI X9.63 KDF: SHA-256(shared_secret || counter(1) || ephemeral_pub_key)
  4. AES-GCM decrypt with key=kdf[0:16], nonce=kdf[16:32]
  5. Decode lat/lon/accuracy/battery from 10-byte plaintext
"""

import base64
import hashlib
import json
import logging
import struct
from datetime import datetime, timedelta, timezone
from typing import Optional

logger = logging.getLogger(__name__)

# Apple's CoreLocation epoch starts Jan 1, 2001
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)

# Overflow correction constant (same as in Dart code)
POINT_CORRECTION = 0xFFFFFFFF / 10_000_000.0


def extract_private_key_from_device_json(private_key_b64_json: str | None) -> str | None:
    """
    Extract the raw base64 private key from the device's private_key_b64 field.

    Supports two formats stored in DB:
    - JSON blob: {"privateKey": "base64...", "name": "...", ...}
    - Raw base64 string: "base64..."
    """
    if not private_key_b64_json:
        return None
    # Try JSON first (newer format from Flutter JSON export)
    try:
        acc_json = json.loads(private_key_b64_json)
        if isinstance(acc_json, dict):
            return acc_json.get("privateKey")
    except Exception:
        pass
    # Fall back: treat value directly as raw base64 private key
    return private_key_b64_json.strip()


def decrypt_report(payload_b64: str, private_key_b64: str) -> Optional[dict]:
    """
    Decrypt one Apple FindMy encrypted location report.

    Args:
        payload_b64:     Base64-encoded raw Apple payload (from location_reports.payload_b64)
        private_key_b64: Base64-encoded raw 28-byte EC private key scalar (SECP224R1)

    Returns:
        dict with keys: latitude, longitude, accuracy, battery_status, timestamp, confidence
        or None if decryption fails for any reason.
    """
    try:
        from cryptography.hazmat.primitives.asymmetric.ec import (
            SECP224R1,
            ECDH,
            EllipticCurvePublicNumbers,
            derive_private_key,
        )
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.backends import default_backend
        from cryptography.exceptions import InvalidTag

        payload = base64.b64decode(payload_b64)
        private_key_bytes = base64.b64decode(private_key_b64)

        # ── Handle 89-byte payload: remove byte at index 4 (same as Dart) ──────
        if len(payload) > 88:
            payload = bytes(payload[:4]) + bytes(payload[5:])

        if len(payload) < 84:
            logger.debug("Payload too short after normalization: %d bytes", len(payload))
            return None

        # ── Extract payload components ─────────────────────────────────────────
        timestamp_raw = payload[0:4]          # 4 bytes big-endian int32
        confidence    = payload[4]             # 1 byte
        ephem_bytes   = bytes(payload[5:62])  # 57 bytes: 0x04 + 28-byte X + 28-byte Y
        enc_data      = bytes(payload[62:72]) # 10 bytes AES-GCM ciphertext
        payload_tag   = bytes(payload[72:])   # 12 bytes GCM auth tag

        # ── Decode Apple timestamp ─────────────────────────────────────────────
        seen_ts = struct.unpack(">i", timestamp_raw)[0]
        timestamp = APPLE_EPOCH + timedelta(seconds=seen_ts)

        # ── Load EC private key ────────────────────────────────────────────────
        private_key_int = int.from_bytes(private_key_bytes, "big")
        private_key = derive_private_key(private_key_int, SECP224R1(), default_backend())

        # ── Load ephemeral public key from uncompressed point (0x04 || X || Y) ─
        if len(ephem_bytes) != 57 or ephem_bytes[0] != 0x04:
            logger.debug("Ephemeral key has unexpected format (len=%d, prefix=0x%02x)",
                         len(ephem_bytes), ephem_bytes[0] if ephem_bytes else 0)
            return None

        x_int = int.from_bytes(ephem_bytes[1:29], "big")
        y_int = int.from_bytes(ephem_bytes[29:57], "big")
        ephemeral_pub = EllipticCurvePublicNumbers(x_int, y_int, SECP224R1()).public_key(default_backend())

        # ── ECDH: derive 28-byte shared secret (x-coordinate of shared point) ──
        shared_secret = private_key.exchange(ECDH(), ephemeral_pub)
        shared_secret = shared_secret.rjust(28, b"\x00")  # Ensure exactly 28 bytes

        # ── ANSI X9.63 KDF ────────────────────────────────────────────────────
        # SHA-256(shared_secret || counter(1 as 4-byte BE) || ephemeral_pub_key)
        counter = struct.pack(">I", 1)
        h = hashlib.sha256()
        h.update(shared_secret)
        h.update(counter)
        h.update(ephem_bytes)
        derived = h.digest()  # 32 bytes

        dec_key = derived[:16]   # AES-128 key
        nonce   = derived[16:]   # 16-byte GCM nonce (same as Dart code)

        # ── AES-GCM decrypt ────────────────────────────────────────────────────
        # The payload_tag IS the GCM authentication tag.
        # We try to verify; if it fails we still use the plaintext (Dart doesn't verify).
        cipher = Cipher(
            algorithms.AES(dec_key),
            modes.GCM(nonce, tag=payload_tag, min_tag_length=12),
            backend=default_backend(),
        )
        decryptor = cipher.decryptor()
        plaintext = decryptor.update(enc_data)
        try:
            decryptor.finalize()
        except InvalidTag:
            return None

        if len(plaintext) < 10:
            return None

        # ── Decode lat / lon / accuracy / battery ──────────────────────────────
        lat_raw = struct.unpack(">I", plaintext[0:4])[0]
        lon_raw = struct.unpack(">I", plaintext[4:8])[0]
        accuracy = plaintext[8]
        status   = plaintext[9]

        lat = lat_raw / 10_000_000.0
        lon = lon_raw / 10_000_000.0

        # Overflow correction (coordinates outside valid range)
        if lat > 90:
            lat -= POINT_CORRECTION
        if lat < -90:
            lat += POINT_CORRECTION
        if lon > 180:
            lon -= POINT_CORRECTION
        if lon < -180:
            lon += POINT_CORRECTION

        # ── Battery status ─────────────────────────────────────────────────────
        battery_status = None
        if status & 0b00100000 != 0 or status > 0:
            level = status >> 6  # Top 2 bits
            battery_map = {0: "ok", 1: "medium", 2: "low", 3: "criticalLow"}
            battery_status = battery_map.get(level)

        return {
            "latitude":       lat,
            "longitude":      lon,
            "accuracy":       accuracy,
            "battery_status": battery_status,
            "timestamp":      timestamp,
            "confidence":     confidence,
        }

    except Exception as e:
        logger.debug("decrypt_report failed: %s", e)
        return None


async def decrypt_pending_reports_background(db_factory) -> int:
    """
    Decrypt all location_reports that have no latitude yet.
    Runs once at server startup as a background task.
    Returns the number of reports newly decrypted.
    """
    from sqlalchemy import select, update
    from app.models import LocationReport, Device
    from sqlalchemy.ext.asyncio import AsyncSession

    total_decrypted = 0
    try:
        async with db_factory() as db:
            # Load all devices → build key map: hashed_adv_key → private_key_b64
            dev_result = await db.execute(select(Device))
            devices = dev_result.scalars().all()
            key_map: dict[str, str | None] = {}
            for dev in devices:
                pk = extract_private_key_from_device_json(dev.private_key_b64)
                key_map[dev.hashed_adv_key] = pk

            # Fetch all undecrypted reports
            stmt = select(LocationReport).where(LocationReport.latitude.is_(None))
            result = await db.execute(stmt)
            pending = result.scalars().all()
            logger.info(f"[DECRYPT_MIGRATION] Found {len(pending)} undecrypted reports.")

            # Track newest decrypted per device for updating devices.last_lat etc.
            newest: dict[str, dict] = {}  # hashed_adv_key → {lat, lon, ts, battery}

            for rep in pending:
                pk_b64 = key_map.get(rep.hashed_adv_key)
                if not pk_b64:
                    continue  # No private key for this report's key
                result_dec = decrypt_report(rep.payload_b64, pk_b64)
                if result_dec:
                    rep.latitude       = result_dec["latitude"]
                    rep.longitude      = result_dec["longitude"]
                    rep.accuracy       = result_dec["accuracy"]
                    rep.battery_status = result_dec["battery_status"]
                    rep.decrypted_at   = datetime.now(timezone.utc)
                    total_decrypted += 1

                    # Track newest per device
                    ts = result_dec["timestamp"]
                    prev = newest.get(rep.hashed_adv_key)
                    if prev is None or ts > prev["ts"]:
                        newest[rep.hashed_adv_key] = {
                            "ts": ts, "lat": result_dec["latitude"],
                            "lon": result_dec["longitude"],
                            "battery": result_dec["battery_status"]
                        }

            await db.commit()

            # Update Device.last_lat/lon/seen_at/battery for each device
            for dev in devices:
                n = newest.get(dev.hashed_adv_key)
                if n:
                    # Only update if this is newer than what's already stored
                    if dev.last_seen_at is None or n["ts"].replace(tzinfo=timezone.utc) > dev.last_seen_at.replace(tzinfo=timezone.utc):
                        dev.last_lat    = n["lat"]
                        dev.last_lon    = n["lon"]
                        dev.last_seen_at = n["ts"].replace(tzinfo=None)  # Store as naive UTC
                        dev.last_battery = n["battery"]

            await db.commit()
            logger.info(f"[DECRYPT_MIGRATION] Completed: {total_decrypted} reports decrypted.")
    except Exception as e:
        logger.error(f"[DECRYPT_MIGRATION] Failed: {e}", exc_info=True)
    return total_decrypted
