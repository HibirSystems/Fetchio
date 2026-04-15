"""API router – aggregates all route modules."""
from __future__ import annotations

from fastapi import APIRouter

from app.api.routes import downloads, health, media, search

api_router = APIRouter()

api_router.include_router(health.router)
api_router.include_router(search.router)
api_router.include_router(media.router)
api_router.include_router(downloads.router)
