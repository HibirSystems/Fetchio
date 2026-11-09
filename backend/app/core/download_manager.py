"""Async download manager with durable per-download state."""
from __future__ import annotations

import asyncio
import json
import logging
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.config import settings
from app.core.ytdlp_engine import engine
from app.models.download import DownloadProgress, DownloadRequest, DownloadStatus

logger = logging.getLogger(__name__)

_downloads: dict[str, DownloadProgress] = {}
_requests: dict[str, DownloadRequest] = {}
_tasks: dict[str, asyncio.Task[None]] = {}
_cancel_events: dict[str, threading.Event] = {}
_semaphore: asyncio.Semaphore | None = None
_persist_lock = threading.RLock()
_RECORD_NAME = ".download.json"
_TERMINAL = {DownloadStatus.completed, DownloadStatus.failed, DownloadStatus.cancelled}


def _get_semaphore() -> asyncio.Semaphore:
    global _semaphore
    if _semaphore is None:
        _semaphore = asyncio.Semaphore(settings.max_concurrent_downloads)
    return _semaphore


def _download_dir(download_id: str) -> Path:
    return Path(settings.download_dir) / download_id


def _persist(download_id: str) -> None:
    progress = _downloads.get(download_id)
    request = _requests.get(download_id)
    if progress is None or request is None:
        return
    directory = _download_dir(download_id)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / _RECORD_NAME
    temporary = path.with_suffix(".json.tmp")
    with _persist_lock:
        temporary.write_text(
            json.dumps(
                {"progress": progress.model_dump(mode="json"), "request": request.model_dump(mode="json")},
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        temporary.replace(path)


def restore_downloads() -> int:
    """Restore saved history and fail jobs that were interrupted by a restart."""
    root = Path(settings.download_dir)
    if not root.is_dir():
        return 0
    restored = 0
    for record in root.glob(f"*/{_RECORD_NAME}"):
        try:
            data = json.loads(record.read_text(encoding="utf-8"))
            progress = DownloadProgress.model_validate(data["progress"])
            request = DownloadRequest.model_validate(data["request"])
            if record.parent.name != progress.download_id:
                continue
            if progress.status not in _TERMINAL:
                progress.status = DownloadStatus.failed
                progress.error = "Download interrupted by application restart"
                progress.updated_at = datetime.now(timezone.utc)
            _downloads[progress.download_id] = progress
            _requests[progress.download_id] = request
            _persist(progress.download_id)
            restored += 1
        except Exception as exc:  # noqa: BLE001
            logger.warning("Skipping invalid download history %s: %s", record, exc)
    return restored


restore_downloads()


async def create_download(request: DownloadRequest) -> DownloadProgress:
    """Queue a new download and start it asynchronously."""
    download_id = str(uuid.uuid4())
    progress = DownloadProgress(download_id=download_id, status=DownloadStatus.queued, url=request.url)
    _downloads[download_id] = progress
    _requests[download_id] = request.model_copy(deep=True)
    _cancel_events[download_id] = threading.Event()
    _persist(download_id)

    task = asyncio.create_task(_run_download(download_id, request))
    _tasks[download_id] = task

    def _finished(done: asyncio.Task[None]) -> None:
        if _tasks.get(download_id) is done:
            _tasks.pop(download_id, None)
            _cancel_events.pop(download_id, None)

    task.add_done_callback(_finished)
    return progress


async def get_download(download_id: str) -> DownloadProgress | None:
    return _downloads.get(download_id)


async def list_downloads() -> list[DownloadProgress]:
    return list(_downloads.values())


async def cancel_download(download_id: str) -> bool:
    task = _tasks.get(download_id)
    progress = _downloads.get(download_id)
    if task is None or task.done() or progress is None or progress.status in _TERMINAL:
        return False
    was_queued = progress.status == DownloadStatus.queued
    cancel_event = _cancel_events.get(download_id)
    if cancel_event is not None:
        cancel_event.set()
    progress.status = DownloadStatus.cancelled
    progress.updated_at = datetime.now(timezone.utc)
    _persist(download_id)
    if was_queued:
        task.cancel()
    return True


async def retry_download(download_id: str) -> DownloadProgress | None:
    """Retry a failed or cancelled job from its persisted request."""
    request = _requests.get(download_id)
    if request is None:
        return None
    progress = _downloads.get(download_id)
    if progress is None:
        return None
    if progress.status in (
        DownloadStatus.queued,
        DownloadStatus.downloading,
        DownloadStatus.processing,
        DownloadStatus.completed,
    ):
        raise ValueError(f"Cannot retry a {progress.status.value} download")
    return await create_download(request.model_copy(deep=True))


async def clear_completed() -> int:
    completed_ids = [did for did, dp in _downloads.items() if dp.status in _TERMINAL]
    for download_id in completed_ids:
        _downloads.pop(download_id, None)
        _requests.pop(download_id, None)
        try:
            (_download_dir(download_id) / _RECORD_NAME).unlink(missing_ok=True)
        except OSError as exc:
            logger.warning("Could not remove history for download %s: %s", download_id, exc)
    return len(completed_ids)


async def _run_download(download_id: str, request: DownloadRequest) -> None:
    sem = _get_semaphore()
    progress = _downloads[download_id]
    cancel_event = _cancel_events[download_id]
    try:
        async with sem:
            if cancel_event.is_set():
                return
            progress.status = DownloadStatus.downloading
            progress.updated_at = datetime.now(timezone.utc)
            _persist(download_id)

            format_selector = _build_format_selector(request)
            extra_opts = _build_extra_opts(request)
            output_dir = str(_download_dir(download_id))

            def _hook(data: dict[str, Any]) -> None:
                _process_hook(download_id, data)

            try:
                try:
                    info = await engine.get_info(request.url)
                    if not cancel_event.is_set():
                        progress.title = info.title
                        progress.thumbnail = info.thumbnail
                        progress.updated_at = datetime.now(timezone.utc)
                        _persist(download_id)
                except Exception:  # noqa: BLE001
                    if cancel_event.is_set():
                        return

                if cancel_event.is_set():
                    return
                filename = await engine.download(
                    url=request.url,
                    output_dir=output_dir,
                    format_selector=format_selector,
                    progress_hook=_hook,
                    extra_opts=extra_opts,
                    cancel_event=cancel_event,
                )
                if cancel_event.is_set():
                    return
                progress.status = DownloadStatus.completed
                progress.percent = 100.0
                progress.filename = filename
                progress.completed_at = datetime.now(timezone.utc)
                progress.updated_at = datetime.now(timezone.utc)
                _persist(download_id)
            except asyncio.CancelledError:
                if not cancel_event.is_set():
                    progress.status = DownloadStatus.cancelled
                    progress.updated_at = datetime.now(timezone.utc)
                    _persist(download_id)
                raise
            except Exception as exc:  # noqa: BLE001
                if cancel_event.is_set():
                    return
                logger.error("Download %s failed: %s", download_id, exc, exc_info=True)
                progress.status = DownloadStatus.failed
                progress.error = str(exc)
                progress.updated_at = datetime.now(timezone.utc)
                _persist(download_id)
    finally:
        if progress.status == DownloadStatus.cancelled:
            _persist(download_id)


def _process_hook(download_id: str, data: dict[str, Any]) -> None:
    progress = _downloads.get(download_id)
    cancel_event = _cancel_events.get(download_id)
    if progress is None or (cancel_event and cancel_event.is_set()) or progress.status in _TERMINAL:
        return

    status = data.get("status", "")
    if status == "downloading":
        progress.status = DownloadStatus.downloading
        downloaded = data.get("downloaded_bytes", 0) or 0
        total = data.get("total_bytes") or data.get("total_bytes_estimate")
        progress.downloaded_bytes = downloaded
        progress.total_bytes = total
        if total:
            progress.percent = round((downloaded / total) * 100, 1)
        if data.get("speed"):
            progress.speed = data["speed"]
        if data.get("eta") is not None:
            progress.eta = int(data["eta"])
        if data.get("filename"):
            progress.filename = data["filename"]
    elif status == "finished":
        progress.status = DownloadStatus.processing
        progress.percent = 99.0
        progress.filename = data.get("filename", progress.filename)
    elif status == "error":
        progress.status = DownloadStatus.failed
        progress.error = str(data.get("error", "Unknown error"))
    else:
        return
    progress.updated_at = datetime.now(timezone.utc)
    _persist(download_id)


def _build_format_selector(request: DownloadRequest) -> str:
    if request.format_id:
        return request.format_id
    if request.audio_only:
        return "bestaudio/best"
    selector = request.format_selector
    return selector.value if hasattr(selector, "value") else str(selector)


def _build_extra_opts(request: DownloadRequest) -> dict[str, Any]:
    opts: dict[str, Any] = {}
    if request.audio_only and request.convert_to in ("mp3", "m4a", "opus", "vorbis"):
        codec = request.convert_to
        quality = "192" if codec == "mp3" else "5"
        opts["postprocessors"] = [
            {"key": "FFmpegExtractAudio", "preferredcodec": codec, "preferredquality": quality}
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
