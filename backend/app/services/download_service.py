"""Download service – thin façade over the core download manager."""
from __future__ import annotations

from app.core import download_manager as dm
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


async def clear_completed() -> int:
    return await dm.clear_completed()
