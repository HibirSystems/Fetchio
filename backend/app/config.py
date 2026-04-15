from __future__ import annotations

import os
from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # ── Application ───────────────────────────────────────────────────────────
    app_name: str = "Fetchio API"
    app_version: str = "1.0.0"
    debug: bool = False
    environment: Literal["development", "staging", "production"] = "production"

    # ── Server ────────────────────────────────────────────────────────────────
    host: str = "0.0.0.0"
    port: int = 8000
    workers: int = 4
    allowed_origins: list[str] = ["*"]

    # ── Database ──────────────────────────────────────────────────────────────
    database_url: str = "sqlite+aiosqlite:///./fetchio.db"

    # ── Redis ─────────────────────────────────────────────────────────────────
    redis_url: str = "redis://localhost:6379/0"
    cache_ttl_seconds: int = 300

    # ── Downloads ─────────────────────────────────────────────────────────────
    download_dir: str = "./downloads"
    max_concurrent_downloads: int = 3
    max_file_size_mb: int = 2048

    # ── yt-dlp ────────────────────────────────────────────────────────────────
    ytdlp_proxy: str | None = None
    ytdlp_cookies_file: str | None = None
    ytdlp_max_retries: int = 3

    # ── Rate limiting ─────────────────────────────────────────────────────────
    rate_limit_per_minute: int = 60

    # ── Security ──────────────────────────────────────────────────────────────
    secret_key: str = "change-me-in-production-use-long-random-string"
    api_key_header: str = "X-API-Key"
    api_keys: list[str] = []


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
