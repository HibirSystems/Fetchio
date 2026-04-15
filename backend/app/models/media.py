"""Pydantic models for media metadata."""
from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

from app.models.search import MediaType


class VideoFormat(BaseModel):
    format_id: str
    ext: str
    resolution: str | None = None
    fps: float | None = None
    vcodec: str | None = None
    acodec: str | None = None
    filesize: int | None = None  # bytes
    filesize_approx: int | None = None
    tbr: float | None = None  # total bitrate kbps
    vbr: float | None = None
    abr: float | None = None
    quality: float | None = None
    format_note: str | None = None
    url: str | None = None
    protocol: str | None = None


class MediaInfo(BaseModel):
    id: str
    title: str
    url: str
    webpage_url: str | None = None
    thumbnail: str | None = None
    thumbnails: list[dict[str, Any]] = []
    description: str | None = None
    duration: int | None = None
    uploader: str | None = None
    uploader_id: str | None = None
    upload_date: str | None = None
    view_count: int | None = None
    like_count: int | None = None
    comment_count: int | None = None
    tags: list[str] = []
    categories: list[str] = []
    media_type: MediaType = MediaType.video
    platform: str | None = None
    formats: list[VideoFormat] = []
    subtitles: dict[str, Any] = {}
    chapters: list[dict[str, Any]] = []

    model_config = {"from_attributes": True}


class MediaInfoRequest(BaseModel):
    url: str = Field(..., min_length=5)
