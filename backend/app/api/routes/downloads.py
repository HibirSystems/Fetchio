"""Download management endpoints + WebSocket progress streaming."""
from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

from app.models.download import (
    DownloadListResponse,
    DownloadProgress,
    DownloadRequest,
    DownloadStatus,
)
from app.services import download_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/downloads", tags=["downloads"])


@router.post("", response_model=DownloadProgress, status_code=202)
async def start_download(request: DownloadRequest) -> DownloadProgress:
    """Queue a new download. Returns the download progress object immediately."""
    return await download_service.start_download(request)


@router.get("", response_model=DownloadListResponse)
async def list_downloads() -> DownloadListResponse:
    """List all downloads (active, completed, and failed)."""
    return await download_service.list_downloads()


@router.get("/{download_id}", response_model=DownloadProgress)
async def get_download(download_id: str) -> DownloadProgress:
    """Get progress for a specific download."""
    progress = await download_service.get_download(download_id)
    if not progress:
        raise HTTPException(status_code=404, detail="Download not found")
    return progress


@router.delete("/{download_id}")
async def cancel_download(download_id: str) -> dict[str, str]:
    """Cancel an active download."""
    cancelled = await download_service.cancel_download(download_id)
    if not cancelled:
        raise HTTPException(status_code=404, detail="Download not found or already finished")
    return {"status": "cancelled", "download_id": download_id}


@router.delete("")
async def clear_completed() -> dict[str, int]:
    """Remove all completed/failed/cancelled downloads from the list."""
    count = await download_service.clear_completed()
    return {"cleared": count}


@router.websocket("/{download_id}/ws")
async def download_progress_ws(websocket: WebSocket, download_id: str) -> None:
    """
    WebSocket endpoint that streams real-time download progress.

    Sends JSON-encoded DownloadProgress every 500ms until the download
    reaches a terminal state (completed/failed/cancelled).
    """
    await websocket.accept()
    try:
        while True:
            progress = await download_service.get_download(download_id)
            if not progress:
                await websocket.send_text(
                    json.dumps({"error": "Download not found", "download_id": download_id})
                )
                break

            await websocket.send_text(progress.model_dump_json())

            if progress.status in (
                DownloadStatus.completed,
                DownloadStatus.failed,
                DownloadStatus.cancelled,
            ):
                break

            await asyncio.sleep(0.5)
    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected from download %s", download_id)
    except Exception as exc:
        logger.error("WebSocket error for download %s: %s", download_id, exc)
        try:
            await websocket.close(code=1011)
        except Exception:  # noqa: BLE001
            pass
