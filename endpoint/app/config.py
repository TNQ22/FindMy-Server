import os
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    DATABASE_URL: str = "sqlite+aiosqlite:///./data/findmy.db"
    GOOGLE_CLIENT_ID: str = ""
    ANISETTE_SERVER_URL: str = "http://anisette:6969"
    JWT_SECRET: str = "super-secret-findmy-key-change-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_DAYS: int = 30
    SYNC_INTERVAL_MINUTES: int = 15
    DEBUG_LOGS: bool = False
    ENDPOINT_USER: str = ""
    ENDPOINT_PASS: str = ""
    
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASS: str = ""
    SMTP_FROM: str = "FindMy Server <noreply@findmy.local>"
    ADMIN_EMAILS: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

settings = Settings()
