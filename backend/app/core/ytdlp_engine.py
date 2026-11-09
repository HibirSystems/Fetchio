"""Core yt-dlp engine wrapper – thread-safe, async-friendly."""
from __future__ import annotations

import asyncio
import logging
import threading
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlsplit

import yt_dlp
from tenacity import retry, stop_after_attempt, wait_exponential
from yt_dlp.utils import DownloadError

from app.config import settings
from app.core.extraction_errors import extraction_error
from app.models.media import MediaInfo, VideoFormat
from app.models.search import MediaType, SearchResultItem

logger = logging.getLogger(__name__)


class DownloadCancelled(Exception):
    """Raised from a progress hook when a download is cooperatively cancelled."""


def _build_base_opts(extra: dict[str, Any] | None = None) -> dict[str, Any]:
    opts: dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "retries": settings.ytdlp_max_retries,
        "socket_timeout": 30,
        "nocheckcertificate": False,
        "geo_bypass": True,
        "js_runtimes": {"deno": {}, "node": {}},
    }
    if settings.ytdlp_proxy:
        opts["proxy"] = settings.ytdlp_proxy
    if settings.ytdlp_cookies_file:
        opts["cookiefile"] = settings.ytdlp_cookies_file
    if extra:
        opts.update(extra)
    return opts


def _parse_media_type(info: dict[str, Any]) -> MediaType:
    if info.get("_type") == "playlist":
        return MediaType.playlist
    vcodec = info.get("vcodec", "")
    acodec = info.get("acodec", "")
    if vcodec and vcodec != "none":
        return MediaType.video
    if acodec and acodec != "none":
        return MediaType.audio
    return MediaType.video


def _select_thumbnail(info: dict[str, Any]) -> str | None:
    candidates: list[tuple[tuple[float, float, float, int], str]] = []
    scalar = info.get("thumbnail")
    thumbnail_entries = info.get("thumbnails")
    entries = [scalar]
    if isinstance(thumbnail_entries, list):
        entries.extend(thumbnail_entries)

    for index, entry in enumerate(entries):
        if isinstance(entry, dict):
            url = entry.get("url")
            width, height = entry.get("width"), entry.get("height")
            preference = entry.get("preference")
        else:
            url = entry
            width = height = preference = None
        if not isinstance(url, str):
            continue
        url = url.strip()
        try:
            parsed = urlsplit(url)
        except ValueError:
            continue
        if parsed.scheme.lower() not in {"http", "https"} or not parsed.netloc:
            continue

        def numeric(value: Any) -> float:
            try:
                number = float(value)
            except (TypeError, ValueError):
                return 0.0
            return number if number > 0 and number < float("inf") else 0.0

        width_value, height_value = numeric(width), numeric(height)
        candidates.append(
            (
                (
                    width_value * height_value,
                    width_value,
                    numeric(preference),
                    int(index == 0),
                ),
                url,
            )
        )

    return max(candidates, key=lambda candidate: candidate[0])[1] if candidates else None


def _parse_search_item(entry: dict[str, Any]) -> SearchResultItem:
    return SearchResultItem(
        id=entry.get("id", ""),
        title=entry.get("title", "Untitled"),
        url=entry.get("webpage_url") or entry.get("url", ""),
        thumbnail=_select_thumbnail(entry),
        duration=entry.get("duration"),
        view_count=entry.get("view_count"),
        uploader=entry.get("uploader") or entry.get("channel"),
        upload_date=entry.get("upload_date"),
        media_type=_parse_media_type(entry),
        platform=entry.get("extractor_key") or entry.get("extractor"),
        description=entry.get("description"),
    )


def _parse_format(fmt: dict[str, Any]) -> VideoFormat:
    resolution = fmt.get("resolution")
    if not resolution:
        height = fmt.get("height")
        width = fmt.get("width")
        if height and width:
            resolution = f"{width}x{height}"
        elif height:
            resolution = f"{height}p"
    return VideoFormat(
        format_id=fmt.get("format_id", ""),
        ext=fmt.get("ext", ""),
        resolution=resolution,
        fps=fmt.get("fps"),
        vcodec=fmt.get("vcodec"),
        acodec=fmt.get("acodec"),
        filesize=fmt.get("filesize"),
        filesize_approx=fmt.get("filesize_approx"),
        tbr=fmt.get("tbr"),
        vbr=fmt.get("vbr"),
        abr=fmt.get("abr"),
        quality=fmt.get("quality"),
        format_note=fmt.get("format_note"),
        protocol=fmt.get("protocol"),
    )


def _parse_media_info(info: dict[str, Any]) -> MediaInfo:
    formats = [_parse_format(f) for f in info.get("formats", [])]
    return MediaInfo(
        id=info.get("id", ""),
        title=info.get("title", "Untitled"),
        url=info.get("webpage_url") or info.get("url", ""),
        webpage_url=info.get("webpage_url"),
        thumbnail=_select_thumbnail(info),
        thumbnails=[
            thumbnail
            for thumbnail in (info.get("thumbnails") or [])
            if isinstance(thumbnail, dict)
        ] if isinstance(info.get("thumbnails") or [], list) else [],
        description=info.get("description"),
        duration=info.get("duration"),
        uploader=info.get("uploader") or info.get("channel"),
        uploader_id=info.get("uploader_id") or info.get("channel_id"),
        upload_date=info.get("upload_date"),
        view_count=info.get("view_count"),
        like_count=info.get("like_count"),
        comment_count=info.get("comment_count"),
        tags=info.get("tags") or [],
        categories=info.get("categories") or [],
        media_type=_parse_media_type(info),
        platform=info.get("extractor_key") or info.get("extractor"),
        formats=formats,
        subtitles=info.get("subtitles", {}),
        chapters=info.get("chapters") or [],
    )


class YtDlpEngine:
    """Async-safe wrapper around yt-dlp operations."""

    # ── Search ────────────────────────────────────────────────────────────────

    async def search(
        self,
        query: str,
        limit: int = 20,
        media_type: str | None = None,
    ) -> list[SearchResultItem]:
        return await asyncio.to_thread(self._search_sync, query, limit)

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=8), reraise=True)
    def _search_sync(self, query: str, limit: int) -> list[SearchResultItem]:
        search_url = f"ytsearch{limit}:{query}"
        opts = _build_base_opts(
            {
                "extract_flat": "in_playlist",
                "skip_download": True,
                "dump_single_json": True,
            }
        )
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(search_url, download=False)

        entries = info.get("entries", []) if info else []
        results: list[SearchResultItem] = []
        for entry in entries:
            if entry:
                try:
                    results.append(_parse_search_item(entry))
                except Exception as exc:  # noqa: BLE001
                    logger.warning("Failed to parse search entry: %s", exc)
        return results

    # ── Metadata ──────────────────────────────────────────────────────────────

    async def get_info(self, url: str) -> MediaInfo:
        try:
            return await asyncio.to_thread(self._get_info_sync, url)
        except DownloadError as exc:
            logger.warning("Media extraction failed", exc_info=True)
            raise extraction_error(exc) from exc

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=8), reraise=True)
    def _get_info_sync(self, url: str) -> MediaInfo:
        opts = _build_base_opts({"skip_download": True})
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
        if not info:
            raise ValueError(f"Could not extract info for URL: {url}")
        return _parse_media_info(info)

    # ── Download ──────────────────────────────────────────────────────────────

    async def download(
        self,
        url: str,
        output_dir: str,
        format_selector: str,
        progress_hook: Callable[[dict[str, Any]], None] | None = None,
        extra_opts: dict[str, Any] | None = None,
        cancel_event: threading.Event | None = None,
    ) -> str:
        """Run yt-dlp in a thread pool and return the final postprocessed path."""
        for attempt in range(2):
            if cancel_event is not None and cancel_event.is_set():
                raise DownloadCancelled("Download cancelled")
            try:
                return await asyncio.to_thread(
                    self._download_sync,
                    url,
                    output_dir,
                    format_selector,
                    progress_hook,
                    extra_opts or {},
                    cancel_event,
                )
            except DownloadError as exc:
                message = str(exc).lower()
                transfer_forbidden = "403" in message and any(
                    term in message for term in ("video data", "fragment", "segment")
                )
                if attempt == 0 and transfer_forbidden:
                    logger.info("Refreshing extraction once after a forbidden media transfer")
                    continue
                raise extraction_error(exc) from exc
        raise RuntimeError("Download attempts exhausted")

    def _download_sync(
        self,
        url: str,
        output_dir: str,
        format_selector: str,
        progress_hook: Callable[[dict[str, Any]], None] | None,
        extra_opts: dict[str, Any],
        cancel_event: threading.Event | None = None,
    ) -> str:
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        outtmpl = str(Path(output_dir) / "%(title)s [%(id)s].%(ext)s")
        opts = _build_base_opts(
            {
                "format": format_selector,
                "outtmpl": outtmpl,
                "quiet": True,
                "check_formats": "selected",
                "progress_hooks": [progress_hook] if progress_hook else [],
                "merge_output_format": "mp4",
                "writethumbnail": False,
                "postprocessors": [],
                **extra_opts,
            }
        )
        progress_filenames: list[str] = []
        postprocessor_filenames: list[str] = []

        original_hook = opts.get("progress_hooks", [])[:]
        original_postprocessor_hooks = opts.get("postprocessor_hooks", [])[:]

        def _capture_hook(d: dict[str, Any]) -> None:
            if cancel_event is not None and cancel_event.is_set():
                raise DownloadCancelled("Download cancelled")
            if d.get("status") == "finished":
                filename = d.get("filename")
                if filename:
                    progress_filenames.append(filename)
            for hook in original_hook:
                if hook and callable(hook):
                    hook(d)

        def _capture_postprocessor(data: dict[str, Any]) -> None:
            if data.get("status") == "finished":
                info = data.get("info_dict") or {}
                for key in ("filepath", "_filename"):
                    if info.get(key):
                        postprocessor_filenames.append(info[key])
                for requested in info.get("requested_downloads") or []:
                    if requested.get("filepath"):
                        postprocessor_filenames.append(requested["filepath"])
            for hook in original_postprocessor_hooks:
                if hook and callable(hook):
                    hook(data)

        opts["progress_hooks"] = [_capture_hook]
        opts["postprocessor_hooks"] = [_capture_postprocessor]

        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([url])

        for filename in postprocessor_filenames + list(reversed(progress_filenames)):
            path = Path(filename)
            if not path.is_absolute():
                path = Path(output_dir) / path
            if path.is_file():
                return str(path.resolve())

        media_extensions = {
            ".3gp", ".aac", ".avi", ".flac", ".flv", ".m4a", ".m4v", ".mkv",
            ".mov", ".mp3", ".mp4", ".mpeg", ".mpg", ".oga", ".ogg", ".opus",
            ".ts", ".wav", ".webm", ".wma", ".wmv",
        }
        media_files = sorted(
            path.resolve()
            for path in Path(output_dir).rglob("*")
            if path.is_file() and path.suffix.lower() in media_extensions
        )
        if len(media_files) == 1:
            return str(media_files[0])
        raise FileNotFoundError("yt-dlp completed without identifying a final media file")


# Module-level singleton
engine = YtDlpEngine()
