from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi import HTTPException

from app.api.routes import downloads
from app.config import settings
from app.core.download_manager import _build_format_selector
from app.models.download import DownloadFormat, DownloadProgress, DownloadRequest, DownloadStatus
from app.services import download_service


def progress(download_id: str, status: DownloadStatus, filename: str | None = None) -> DownloadProgress:
    return DownloadProgress(
        download_id=download_id,
        status=status,
        url="https://example.com/video",
        filename=filename,
        created_at=datetime.now(timezone.utc),
    )


def test_request_accepts_custom_format_selector_and_keeps_default() -> None:
    custom = DownloadRequest(
        url="https://example.com/video",
        format_selector="bestvideo[height<=1440]+bestaudio/best",
    )
    default = DownloadRequest(url="https://example.com/video")

    assert custom.format_selector == "bestvideo[height<=1440]+bestaudio/best"
    assert default.format_selector == DownloadFormat.best_video.value


def test_explicit_format_id_takes_precedence_over_selector() -> None:
    request = DownloadRequest(
        url="https://example.com/video",
        format_id="137+140",
        format_selector="bestvideo+bestaudio/best",
    )

    assert _build_format_selector(request) == "137+140"


@pytest.mark.parametrize("url", ["ftp://example.com/video", "file:///tmp/video", "not a URL"])
def test_request_rejects_non_http_urls(url: str) -> None:
    with pytest.raises(ValueError):
        DownloadRequest(url=url)


@pytest.mark.parametrize("data", [
    {"convert_to": "wav"},
    {"format_selector": "   "},
    {"start_time": "00:90:00"},
    {"start_time": "00:01:00", "end_time": "00:01:00"},
])
def test_request_rejects_invalid_download_options(data: dict[str, str]) -> None:
    with pytest.raises(ValueError):
        DownloadRequest(url="https://example.com/video", **data)


def test_request_accepts_supported_conversion_and_clip_range() -> None:
    request = DownloadRequest(
        url="https://example.com/video",
        convert_to="mp3",
        audio_only=True,
        start_time="30",
        end_time="00:01:00",
    )

    assert request.convert_to == "mp3"


def test_resolve_download_file_allows_only_files_inside_download_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(settings, "download_dir", str(tmp_path))
    download_dir = tmp_path / "download-1"
    download_dir.mkdir()
    media_file = download_dir / "video.mp4"
    media_file.write_bytes(b"video")

    assert download_service.resolve_download_file(
        progress("download-1", DownloadStatus.completed, str(media_file))
    ) == media_file
    assert download_service.resolve_download_file(
        progress("download-1", DownloadStatus.completed, "../outside.mp4")
    ) is None


def test_resolve_download_file_rejects_symlink_escape(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(settings, "download_dir", str(tmp_path / "downloads"))
    root = tmp_path / "downloads"
    download_dir = root / "download-1"
    download_dir.mkdir(parents=True)
    outside = tmp_path / "outside.mp4"
    outside.write_bytes(b"outside")
    (download_dir / "video.mp4").symlink_to(outside)

    assert download_service.resolve_download_file(
        progress("download-1", DownloadStatus.completed, "video.mp4")
    ) is None


def test_file_endpoint_returns_conflict_until_download_completes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def get_download(_: str) -> DownloadProgress:
        return progress("download-1", DownloadStatus.downloading, "video.mp4")

    monkeypatch.setattr(downloads.download_service, "get_download", get_download)
    with pytest.raises(HTTPException) as error:
        asyncio.run(downloads.download_file("download-1"))

    assert error.value.status_code == 409


def test_file_endpoint_serves_a_completed_file_from_its_download_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(settings, "download_dir", str(tmp_path))
    download_dir = tmp_path / "download-1"
    download_dir.mkdir()
    media_file = download_dir / "video.mp4"
    media_file.write_bytes(b"video")

    async def get_download(_: str) -> DownloadProgress:
        return progress("download-1", DownloadStatus.completed, str(media_file))

    monkeypatch.setattr(downloads.download_service, "get_download", get_download)
    response = asyncio.run(downloads.download_file("download-1"))

    assert response.status_code == 200
    assert Path(response.path) == media_file.resolve()
    assert "attachment" in response.headers["content-disposition"]


def test_file_endpoint_returns_404_for_unknown_download(monkeypatch: pytest.MonkeyPatch) -> None:
    async def get_download(_: str) -> None:
        return None

    monkeypatch.setattr(downloads.download_service, "get_download", get_download)
    with pytest.raises(HTTPException) as error:
        asyncio.run(downloads.download_file("missing"))

    assert error.value.status_code == 404


def test_retry_endpoint_maps_manager_results_and_conflicts(monkeypatch: pytest.MonkeyPatch) -> None:
    expected = progress("download-1", DownloadStatus.queued)

    async def retry(_: str) -> DownloadProgress:
        return expected

    monkeypatch.setattr(downloads.download_service, "retry_download", retry)
    assert asyncio.run(downloads.retry_download("download-1")) is expected

    async def conflict(_: str) -> DownloadProgress:
        raise ValueError("Download is already active")

    monkeypatch.setattr(downloads.download_service, "retry_download", conflict)
    with pytest.raises(HTTPException) as error:
        asyncio.run(downloads.retry_download("download-1"))
    assert error.value.status_code == 409


def test_retry_endpoint_returns_404_when_download_is_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    async def retry(_: str) -> None:
        return None

    monkeypatch.setattr(downloads.download_service, "retry_download", retry)
    with pytest.raises(HTTPException) as error:
        asyncio.run(downloads.retry_download("missing"))

    assert error.value.status_code == 404
