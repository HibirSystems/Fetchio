"""Core yt-dlp engine wrapper – thread-safe, async-friendly."""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Callable

import yt_dlp
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import settings
from app.models.media import MediaInfo, VideoFormat
from app.models.search import MediaType, SearchResultItem

logger = logging.getLogger(__name__)


def _build_base_opts(extra: dict[str, Any] | None = None) -> dict[str, Any]:
    opts: dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "retries": settings.ytdlp_max_retries,
        "socket_timeout": 30,
        "nocheckcertificate": False,
        "geo_bypass": True,
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


def _parse_search_item(entry: dict[str, Any]) -> SearchResultItem:
    return SearchResultItem(
        id=entry.get("id", ""),
        title=entry.get("title", "Untitled"),
        url=entry.get("webpage_url") or entry.get("url", ""),
        thumbnail=entry.get("thumbnail"),
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
        url=info.get("url") or info.get("webpage_url", ""),
        webpage_url=info.get("webpage_url"),
        thumbnail=info.get("thumbnail"),
        thumbnails=info.get("thumbnails", []),
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

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=8))
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
        return await asyncio.to_thread(self._get_info_sync, url)

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(min=1, max=8))
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
    ) -> str:
        """Run download in a thread pool; returns output filename."""
        return await asyncio.to_thread(
            self._download_sync,
            url,
            output_dir,
            format_selector,
            progress_hook,
            extra_opts or {},
        )

    def _download_sync(
        self,
        url: str,
        output_dir: str,
        format_selector: str,
        progress_hook: Callable[[dict[str, Any]], None] | None,
        extra_opts: dict[str, Any],
    ) -> str:
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        outtmpl = str(Path(output_dir) / "%(title)s [%(id)s].%(ext)s")
        opts = _build_base_opts(
            {
                "format": format_selector,
                "outtmpl": outtmpl,
                "quiet": False,
                "progress_hooks": [progress_hook] if progress_hook else [],
                "merge_output_format": "mp4",
                "writethumbnail": False,
                "postprocessors": [],
                **extra_opts,
            }
        )
        filename_holder: list[str] = []

        original_hook = opts.get("progress_hooks", [])[:]

        def _capture_hook(d: dict[str, Any]) -> None:
            if d.get("status") == "finished":
                filename_holder.append(d.get("filename", ""))
            for hook in original_hook:
                if hook and callable(hook):
                    hook(d)

        opts["progress_hooks"] = [_capture_hook]

        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([url])

        return filename_holder[0] if filename_holder else ""


# Module-level singleton
engine = YtDlpEngine()
