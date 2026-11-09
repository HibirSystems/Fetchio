"""Download service – thin façade over the core download manager."""
from __future__ import annotations

import stat
from pathlib import Path

from app.core import download_manager as dm
from app.config import settings
from app.models.download import (
    DownloadListResponse,
    DownloadProgress,
    DownloadRequest,
    DownloadStatus,
)


async def start_download(request: DownloadRequest) -> DownloadProgress:
    return await dm.create_download(request)


async def get_download(download_id: str) -> DownloadProgress | None:
    return await dm.get_download(download_id)


async def list_downloads() -> DownloadListResponse:
    all_downloads = await dm.list_downloads()
    active = sum(
        1
        for d in all_downloads
        if d.status in (DownloadStatus.queued, DownloadStatus.downloading, DownloadStatus.processing)
    )
    completed = sum(1 for d in all_downloads if d.status == DownloadStatus.completed)
    failed = sum(1 for d in all_downloads if d.status == DownloadStatus.failed)
    return DownloadListResponse(
        downloads=all_downloads,
        total=len(all_downloads),
        active=active,
        completed=completed,
        failed=failed,
    )


async def cancel_download(download_id: str) -> bool:
    return await dm.cancel_download(download_id)


async def retry_download(download_id: str) -> DownloadProgress | None:
    return await dm.retry_download(download_id)


def resolve_download_file(progress: DownloadProgress) -> Path | None:
    """Resolve a completed download file without leaving its per-download directory."""
    if progress.status != DownloadStatus.completed or not progress.filename:
        return None

    try:
        download_root = Path(settings.download_dir).resolve()
        download_directory = (download_root / progress.download_id).resolve()
        if download_directory == download_root or not download_directory.is_relative_to(download_root):
            return None

        filename = Path(progress.filename)
        candidate = filename if filename.is_absolute() else download_directory / filename
        resolved_file = candidate.resolve(strict=True)
        if not resolved_file.is_relative_to(download_directory):
            return None
        if not stat.S_ISREG(resolved_file.stat().st_mode):
            return None
        return resolved_file
    except (OSError, RuntimeError, ValueError):
        return None


async def clear_completed() -> int:
    return await dm.clear_completed()
