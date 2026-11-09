"""Pydantic models for download management."""
from __future__ import annotations

import re
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Literal
from urllib.parse import urlsplit

from pydantic import BaseModel, Field, field_validator, model_validator


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
    url: str = Field(..., min_length=5, max_length=2048)
    format_id: str | None = Field(default=None, min_length=1, max_length=256)
    format_selector: str = Field(default=DownloadFormat.best_video.value, min_length=1, max_length=512)
    audio_only: bool = False
    convert_to: Literal["mp3", "m4a", "opus", "vorbis", "mp4"] | None = None
    embed_thumbnail: bool = True
    embed_subtitles: bool = False
    subtitle_lang: str = Field(default="en", min_length=1, max_length=32)
    start_time: str | None = None   # e.g. "00:01:30"
    end_time: str | None = None     # e.g. "00:05:00"
    playlist_items: str | None = Field(default=None, min_length=1, max_length=128)  # e.g. "1-3,5"

    @field_validator("url")
    @classmethod
    def validate_http_url(cls, value: str) -> str:
        value = value.strip()
        parsed = urlsplit(value)
        if parsed.scheme.lower() not in ("http", "https") or not parsed.hostname:
            raise ValueError("url must be an absolute http(s) URL")
        try:
            parsed.port
        except ValueError as exc:
            raise ValueError("url has an invalid port") from exc
        return value

    @field_validator("format_id", "format_selector", "subtitle_lang", "playlist_items")
    @classmethod
    def strip_bounded_strings(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            raise ValueError("value must not be empty")
        return value

    @field_validator("start_time", "end_time")
    @classmethod
    def validate_clip_time(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if len(value) > 24:
            raise ValueError("clip time is too long")
        if not re.fullmatch(r"\d+(?:\.\d+)?|\d+:\d{1,2}:\d{1,2}(?:\.\d+)?", value):
            raise ValueError("clip time must be seconds or HH:MM:SS")
        if ":" in value:
            hours, minutes, seconds = value.split(":")
            if int(minutes) > 59 or float(seconds) >= 60:
                raise ValueError("clip time minutes and seconds must be below 60")
        elif float(value) < 0:
            raise ValueError("clip time must not be negative")
        return value

    @model_validator(mode="after")
    def validate_clip_range(self) -> DownloadRequest:
        if self.start_time is not None and self.end_time is not None:
            if self._seconds(self.end_time) <= self._seconds(self.start_time):
                raise ValueError("end_time must be later than start_time")
        return self

    @staticmethod
    def _seconds(value: str) -> float:
        if ":" not in value:
            return float(value)
        hours, minutes, seconds = value.split(":")
        return int(hours) * 3600 + int(minutes) * 60 + float(seconds)


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
