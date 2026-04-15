"""Pydantic models for download management."""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class DownloadStatus(str, Enum):
    queued = "queued"
    downloading = "downloading"
    processing = "processing"
    completed = "completed"
    failed = "failed"
    cancelled = "cancelled"
    paused = "paused"


class DownloadFormat(str, Enum):
    best_video = "bestvideo+bestaudio/best"
    best_audio = "bestaudio/best"
    mp4_1080p = "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080][ext=mp4]/best[height<=1080]"
    mp4_720p = "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]/best[height<=720]"
    mp4_480p = "bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[height<=480][ext=mp4]/best[height<=480]"
    mp3 = "bestaudio/best"
    m4a = "bestaudio[ext=m4a]/bestaudio/best"
    webm = "bestvideo[ext=webm]+bestaudio[ext=webm]/best[ext=webm]"


class DownloadRequest(BaseModel):
    url: str = Field(..., min_length=5)
    format_id: str | None = None
    format_selector: DownloadFormat = DownloadFormat.best_video
    audio_only: bool = False
    convert_to: str | None = None  # e.g. "mp3", "mp4"
    embed_thumbnail: bool = True
    embed_subtitles: bool = False
    subtitle_lang: str = "en"
    start_time: str | None = None   # e.g. "00:01:30"
    end_time: str | None = None     # e.g. "00:05:00"
    playlist_items: str | None = None  # e.g. "1-3,5"


class DownloadProgress(BaseModel):
    download_id: str
    status: DownloadStatus
    url: str
    title: str | None = None
    thumbnail: str | None = None
    percent: float = 0.0
    downloaded_bytes: int = 0
    total_bytes: int | None = None
    speed: float | None = None       # bytes/sec
    eta: int | None = None           # seconds remaining
    format_id: str | None = None
    filename: str | None = None
    error: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    completed_at: datetime | None = None

    model_config = {"from_attributes": True}


class DownloadListResponse(BaseModel):
    downloads: list[DownloadProgress]
    total: int
    active: int
    completed: int
    failed: int
