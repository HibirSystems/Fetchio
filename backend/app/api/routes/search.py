"""Search endpoints."""
from __future__ import annotations

from fastapi import APIRouter, Query

from app.models.search import MediaType, SearchResponse
from app.services import search_service

router = APIRouter(prefix="/search", tags=["search"])


@router.get("", response_model=SearchResponse)
async def search(
    q: str = Query(..., min_length=1, max_length=500, description="Search query"),
    page: int = Query(default=1, ge=1, description="Page number"),
    per_page: int = Query(default=20, ge=1, le=100, description="Results per page"),
    media_type: MediaType | None = Query(default=None, description="Filter by media type"),
) -> SearchResponse:
    """Search for media content across supported platforms."""
    return await search_service.search(
        query=q,
        page=page,
        per_page=per_page,
        media_type=media_type,
    )
