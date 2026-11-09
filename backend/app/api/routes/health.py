"""Health-check endpoint."""
from __future__ import annotations

from datetime import datetime, timezone
from importlib.metadata import PackageNotFoundError, version

from fastapi import APIRouter

from app.config import settings

router = APIRouter(prefix="/health", tags=["health"])


@router.get("")
async def health() -> dict[str, str]:
    try:
        ejs_version = version("yt-dlp-ejs")
    except PackageNotFoundError:
        ejs_version = "not-installed"
    try:
        transport_version = version("curl-cffi")
    except PackageNotFoundError:
        transport_version = "not-installed"
    return {
        "status": "ok",
        "app": settings.app_name,
        "version": settings.app_version,
        "extractor_version": version("yt-dlp"),
        "ejs_version": ejs_version,
        "transport_version": transport_version,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
