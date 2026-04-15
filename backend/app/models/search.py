"""Pydantic models for search-related data."""
from __future__ import annotations

from enum import Enum
from typing import Any

from pydantic import BaseModel, Field, HttpUrl


class MediaType(str, Enum):
    video = "video"
    audio = "audio"
    playlist = "playlist"
    unknown = "unknown"


class SearchResultItem(BaseModel):
    id: str
    title: str
    url: str
    thumbnail: str | None = None
    duration: int | None = None  # seconds
    view_count: int | None = None
    uploader: str | None = None
    upload_date: str | None = None
    media_type: MediaType = MediaType.video
    platform: str | None = None
    description: str | None = None

    model_config = {"from_attributes": True}


class SearchResponse(BaseModel):
    query: str
    results: list[SearchResultItem]
    total: int
    page: int = 1
    per_page: int = 20
    provider: str = "yt-dlp"


class SearchRequest(BaseModel):
    q: str = Field(..., min_length=1, max_length=500)
    page: int = Field(default=1, ge=1)
    per_page: int = Field(default=20, ge=1, le=100)
    media_type: MediaType | None = None
