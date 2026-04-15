"""Async download manager – tracks per-download state in memory + DB."""
from __future__ import annotations

import asyncio
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.config import settings
from app.core.ytdlp_engine import engine
from app.models.download import (
    DownloadProgress,
    DownloadRequest,
    DownloadStatus,
)

logger = logging.getLogger(__name__)

# In-memory store keyed by download_id
_downloads: dict[str, DownloadProgress] = {}
_tasks: dict[str, asyncio.Task[None]] = {}
_semaphore: asyncio.Semaphore | None = None


def _get_semaphore() -> asyncio.Semaphore:
    global _semaphore
    if _semaphore is None:
        _semaphore = asyncio.Semaphore(settings.max_concurrent_downloads)
    return _semaphore


# ── Public API ────────────────────────────────────────────────────────────────


async def create_download(request: DownloadRequest) -> DownloadProgress:
    """Queue a new download and start it asynchronously."""
    download_id = str(uuid.uuid4())
    progress = DownloadProgress(
        download_id=download_id,
        status=DownloadStatus.queued,
        url=request.url,
    )
    _downloads[download_id] = progress

    task = asyncio.create_task(_run_download(download_id, request))
    _tasks[download_id] = task
    task.add_done_callback(lambda t: _tasks.pop(download_id, None))

    return progress


async def get_download(download_id: str) -> DownloadProgress | None:
    return _downloads.get(download_id)


async def list_downloads() -> list[DownloadProgress]:
    return list(_downloads.values())


async def cancel_download(download_id: str) -> bool:
    task = _tasks.get(download_id)
    if task and not task.done():
        task.cancel()
        if download_id in _downloads:
            _downloads[download_id].status = DownloadStatus.cancelled
            _downloads[download_id].updated_at = datetime.now(timezone.utc)
        return True
    return False


async def clear_completed() -> int:
    completed_ids = [
        did
        for did, dp in _downloads.items()
        if dp.status in (DownloadStatus.completed, DownloadStatus.failed, DownloadStatus.cancelled)
    ]
    for did in completed_ids:
        _downloads.pop(did, None)
    return len(completed_ids)


# ── Internal ──────────────────────────────────────────────────────────────────


async def _run_download(download_id: str, request: DownloadRequest) -> None:
    sem = _get_semaphore()
    progress = _downloads[download_id]

    async with sem:
        progress.status = DownloadStatus.downloading
        progress.updated_at = datetime.now(timezone.utc)

        format_selector = _build_format_selector(request)
        extra_opts = _build_extra_opts(request)
        output_dir = str(Path(settings.download_dir) / download_id)

        def _hook(d: dict[str, Any]) -> None:
            _process_hook(download_id, d)

        try:
            # Fetch title first for progress display
            try:
                info = await engine.get_info(request.url)
                progress.title = info.title
                progress.thumbnail = info.thumbnail
                progress.updated_at = datetime.now(timezone.utc)
            except Exception:  # noqa: BLE001
                pass

            filename = await engine.download(
                url=request.url,
                output_dir=output_dir,
                format_selector=format_selector,
                progress_hook=_hook,
                extra_opts=extra_opts,
            )

            progress.status = DownloadStatus.completed
            progress.percent = 100.0
            progress.filename = filename
            progress.completed_at = datetime.now(timezone.utc)
            progress.updated_at = datetime.now(timezone.utc)

        except asyncio.CancelledError:
            progress.status = DownloadStatus.cancelled
            progress.updated_at = datetime.now(timezone.utc)
            raise
        except Exception as exc:  # noqa: BLE001
            logger.error("Download %s failed: %s", download_id, exc, exc_info=True)
            progress.status = DownloadStatus.failed
            progress.error = str(exc)
            progress.updated_at = datetime.now(timezone.utc)


def _process_hook(download_id: str, d: dict[str, Any]) -> None:
    progress = _downloads.get(download_id)
    if not progress:
        return

    status = d.get("status", "")
    if status == "downloading":
        progress.status = DownloadStatus.downloading
        downloaded = d.get("downloaded_bytes", 0)
        total = d.get("total_bytes") or d.get("total_bytes_estimate")
        progress.downloaded_bytes = downloaded or 0
        progress.total_bytes = total
        if total:
            progress.percent = round((downloaded / total) * 100, 1)
        speed = d.get("speed")
        if speed:
            progress.speed = speed
        eta = d.get("eta")
        if eta is not None:
            progress.eta = int(eta)
        filename = d.get("filename")
        if filename:
            progress.filename = filename
        progress.updated_at = datetime.now(timezone.utc)

    elif status == "finished":
        progress.status = DownloadStatus.processing
        progress.percent = 99.0
        progress.filename = d.get("filename", progress.filename)
        progress.updated_at = datetime.now(timezone.utc)

    elif status == "error":
        progress.status = DownloadStatus.failed
        progress.error = str(d.get("error", "Unknown error"))
        progress.updated_at = datetime.now(timezone.utc)


def _build_format_selector(request: DownloadRequest) -> str:
    if request.format_id:
        return request.format_id
    if request.audio_only:
        return "bestaudio/best"
    return request.format_selector.value


def _build_extra_opts(request: DownloadRequest) -> dict[str, Any]:
    opts: dict[str, Any] = {}

    if request.audio_only and request.convert_to in ("mp3", "m4a", "opus", "vorbis"):
        codec = request.convert_to
        quality = "192" if codec == "mp3" else "5"
        opts["postprocessors"] = [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": codec,
                "preferredquality": quality,
            }
        ]
        if request.embed_thumbnail:
            opts["postprocessors"].append({"key": "EmbedThumbnail"})

    elif request.convert_to == "mp4":
        opts["merge_output_format"] = "mp4"

    if request.embed_subtitles:
        opts["writesubtitles"] = True
        opts["subtitleslangs"] = [request.subtitle_lang]

    if request.start_time or request.end_time:
        download_ranges: dict[str, Any] = {}
        if request.start_time:
            download_ranges["start_time"] = request.start_time
        if request.end_time:
            download_ranges["end_time"] = request.end_time
        opts["download_ranges"] = download_ranges

    if request.playlist_items:
        opts["playlist_items"] = request.playlist_items

    return opts
