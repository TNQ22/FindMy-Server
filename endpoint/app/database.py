import os
import sqlite3
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy import event, text
from app.config import settings

# Ensure data directory exists
os.makedirs("./data", exist_ok=True)

def run_direct_sqlite_migration():
    db_path = settings.DATABASE_URL.split("///")[-1] if "///" in settings.DATABASE_URL else "./data/findmy.db"
    if not os.path.exists(db_path):
        return
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # ── users ─────────────────────────────────────────────────────────────
        cursor.execute("PRAGMA table_info(users);")
        user_cols = [row[1] for row in cursor.fetchall()]
        if user_cols and "settings_json" not in user_cols:
            print("Direct Migration: Adding settings_json column to users table...")
            cursor.execute("ALTER TABLE users ADD COLUMN settings_json TEXT DEFAULT '{}';")

        # ── icloud_accounts ───────────────────────────────────────────────────
        cursor.execute("PRAGMA table_info(icloud_accounts);")
        columns = [row[1] for row in cursor.fetchall()]

        if columns:
            if "fetch_count" not in columns:
                print("Direct Migration: Adding fetch_count column to icloud_accounts...")
                cursor.execute("ALTER TABLE icloud_accounts ADD COLUMN fetch_count INTEGER DEFAULT 0;")
            if "last_used_at" not in columns:
                print("Direct Migration: Adding last_used_at column to icloud_accounts...")
                cursor.execute("ALTER TABLE icloud_accounts ADD COLUMN last_used_at DATETIME;")
            if "is_alerted" not in columns:
                print("Direct Migration: Adding is_alerted column to icloud_accounts...")
                cursor.execute("ALTER TABLE icloud_accounts ADD COLUMN is_alerted BOOLEAN DEFAULT 0;")
            if "last_error" not in columns:
                print("Direct Migration: Adding last_error column to icloud_accounts...")
                cursor.execute("ALTER TABLE icloud_accounts ADD COLUMN last_error TEXT;")

            cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='icloud_accounts';")
            row = cursor.fetchone()
            if row and row[0] and "UNIQUE" in row[0].upper():
                print("Direct Migration: Removing UNIQUE constraint from icloud_accounts table...")
                cursor.execute("""
                    CREATE TABLE icloud_accounts_new (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        user_id INTEGER NOT NULL,
                        apple_id VARCHAR(255) NOT NULL,
                        state_json TEXT NOT NULL DEFAULT '{}',
                        is_active BOOLEAN DEFAULT 1,
                        fetch_count INTEGER DEFAULT 0,
                        last_used_at DATETIME,
                        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY(user_id) REFERENCES users(id)
                    );
                """)
                cursor.execute("""
                    INSERT INTO icloud_accounts_new
                    (id, user_id, apple_id, state_json, is_active, fetch_count, last_used_at, updated_at)
                    SELECT id, user_id, apple_id, state_json, is_active, fetch_count, last_used_at, updated_at
                    FROM icloud_accounts;
                """)
                cursor.execute("DROP TABLE icloud_accounts;")
                cursor.execute("ALTER TABLE icloud_accounts_new RENAME TO icloud_accounts;")

        # ── devices: new location columns ─────────────────────────────────────
        cursor.execute("PRAGMA table_info(devices);")
        dev_cols = [row[1] for row in cursor.fetchall()]
        if dev_cols:
            for col, col_type in [
                ("last_lat",     "REAL"),
                ("last_lon",     "REAL"),
                ("last_seen_at", "DATETIME"),
                ("last_battery", "VARCHAR(50)"),
            ]:
                if col not in dev_cols:
                    print(f"Direct Migration: Adding {col} column to devices...")
                    cursor.execute(f"ALTER TABLE devices ADD COLUMN {col} {col_type};")

        # ── location_reports: new decrypted-location columns ──────────────────
        cursor.execute("PRAGMA table_info(location_reports);")
        rep_cols = [row[1] for row in cursor.fetchall()]
        if rep_cols:
            for col, col_type in [
                ("latitude",      "REAL"),
                ("longitude",     "REAL"),
                ("accuracy",      "INTEGER"),
                ("battery_status","VARCHAR(50)"),
                ("decrypted_at",  "DATETIME"),
            ]:
                if col not in rep_cols:
                    print(f"Direct Migration: Adding {col} column to location_reports...")
                    cursor.execute(f"ALTER TABLE location_reports ADD COLUMN {col} {col_type};")

        # ── zones, zone_devices, zone_alerts tables ───────────────────────────
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS zones (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                name VARCHAR(255) NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                radius REAL DEFAULT 100.0,
                alert_on_exit BOOLEAN DEFAULT 1,
                alert_on_enter BOOLEAN DEFAULT 0,
                cooldown_minutes INTEGER DEFAULT 15,
                is_active BOOLEAN DEFAULT 1,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(user_id) REFERENCES users(id)
            );
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zones_id ON zones (id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zones_user_id ON zones (user_id);")

        cursor.execute("PRAGMA table_info(zones);")
        zone_cols = [row[1] for row in cursor.fetchall()]
        if zone_cols:
            if "shape_type" not in zone_cols:
                print("Direct Migration: Adding shape_type column to zones...")
                cursor.execute("ALTER TABLE zones ADD COLUMN shape_type VARCHAR(20) DEFAULT 'circle';")
            if "polygon_points" not in zone_cols:
                print("Direct Migration: Adding polygon_points column to zones...")
                cursor.execute("ALTER TABLE zones ADD COLUMN polygon_points TEXT;")

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS zone_devices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                zone_id INTEGER NOT NULL,
                device_id INTEGER NOT NULL,
                last_status VARCHAR(20) DEFAULT 'UNKNOWN',
                last_alert_time DATETIME,
                last_alert_type VARCHAR(20),
                last_distance REAL,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(zone_id) REFERENCES zones(id) ON DELETE CASCADE,
                FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE CASCADE
            );
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zone_devices_id ON zone_devices (id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zone_devices_zone_id ON zone_devices (zone_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zone_devices_device_id ON zone_devices (device_id);")

        cursor.execute("PRAGMA table_info(zone_devices);")
        zd_cols = [row[1] for row in cursor.fetchall()]
        if zd_cols and "last_alert_type" not in zd_cols:
            cursor.execute("ALTER TABLE zone_devices ADD COLUMN last_alert_type VARCHAR(20);")

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS zone_alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                zone_id INTEGER NOT NULL,
                device_id INTEGER NOT NULL,
                alert_type VARCHAR(20) NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                distance REAL NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(user_id) REFERENCES users(id),
                FOREIGN KEY(zone_id) REFERENCES zones(id) ON DELETE CASCADE,
                FOREIGN KEY(device_id) REFERENCES devices(id) ON DELETE CASCADE
            );
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zone_alerts_id ON zone_alerts (id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zone_alerts_user_id ON zone_alerts (user_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zone_alerts_zone_id ON zone_alerts (zone_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zone_alerts_device_id ON zone_alerts (device_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_zone_alerts_created_at ON zone_alerts (created_at);")

        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Direct SQLite migration warning: {e}")

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    connect_args={"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {}
)

# Enable WAL mode for SQLite engines for better concurrency
if "sqlite" in settings.DATABASE_URL:
    @event.listens_for(engine.sync_engine, "connect")
    def set_sqlite_pragma(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL;")
        cursor.execute("PRAGMA synchronous=NORMAL;")
        cursor.close()

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False
)

class Base(DeclarativeBase):
    pass

async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()

async def init_db():
    run_direct_sqlite_migration()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
