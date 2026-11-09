from __future__ import annotations

import asyncio
import json
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from app.core import download_manager as manager
from app.core.ytdlp_engine import DownloadCancelled, YtDlpEngine
from app.models.download import DownloadProgress, DownloadRequest, DownloadStatus


class DownloadManagerTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.settings_patch = patch.object(manager.settings, "download_dir", self.tempdir.name)
        self.settings_patch.start()
        manager._downloads.clear()
        manager._requests.clear()
        manager._tasks.clear()
        manager._cancel_events.clear()
        manager._semaphore = asyncio.Semaphore(1)

    def tearDown(self) -> None:
        self.settings_patch.stop()
        self.tempdir.cleanup()

    async def test_cancellation_keeps_slot_until_worker_exits_and_ignores_late_progress(self) -> None:
        worker_started = asyncio.Event()
        worker_release = threading.Event()
        worker_ended = asyncio.Event()
        calls: list[str] = []

        async def get_info(url: str) -> SimpleNamespace:
            return SimpleNamespace(title="Example", thumbnail=None)

        async def download(**kwargs: object) -> str:
            calls.append(str(kwargs["url"]))
            if len(calls) == 1:
                worker_started.set()
                def wait_for_cancel_or_release() -> None:
                    worker_release.wait()
                await asyncio.to_thread(wait_for_cancel_or_release)
                kwargs["progress_hook"]({"status": "downloading", "downloaded_bytes": 90})
                worker_ended.set()
            return str(Path(str(kwargs["output_dir"])) / "media.mp4")

        with patch.object(manager.engine, "get_info", get_info), patch.object(
            manager.engine, "download", download
        ):
            first = await manager.create_download(DownloadRequest(url="https://example.com/one"))
            await worker_started.wait()
            second = await manager.create_download(DownloadRequest(url="https://example.com/two"))

            self.assertTrue(await manager.cancel_download(first.download_id))
            self.assertEqual(first.status, DownloadStatus.cancelled)
            await asyncio.sleep(0.05)
            self.assertEqual(calls, ["https://example.com/one"])

            worker_release.set()
            await worker_ended.wait()
            for _ in range(50):
                if len(calls) == 2:
                    break
                await asyncio.sleep(0.01)

        self.assertEqual(calls, ["https://example.com/one", "https://example.com/two"])
        self.assertEqual(first.downloaded_bytes, 0)
        self.assertEqual(second.status, DownloadStatus.completed)
        self.assertTrue((Path(self.tempdir.name) / first.download_id / ".download.json").is_file())

    async def test_restore_marks_interrupted_and_preserves_terminal_history(self) -> None:
        request = DownloadRequest(url="https://example.com/video")
        active = DownloadProgress(download_id="active", status=DownloadStatus.downloading, url=request.url)
        failed = DownloadProgress(download_id="failed", status=DownloadStatus.failed, url=request.url)
        completed = DownloadProgress(download_id="completed", status=DownloadStatus.completed, url=request.url)
        cancelled = DownloadProgress(download_id="cancelled", status=DownloadStatus.cancelled, url=request.url)
        for progress in (active, failed, completed, cancelled):
            directory = Path(self.tempdir.name) / progress.download_id
            directory.mkdir()
            (directory / ".download.json").write_text(
                json.dumps({"progress": progress.model_dump(mode="json"), "request": request.model_dump(mode="json")}),
                encoding="utf-8",
            )

        manager._downloads.clear()
        manager._requests.clear()
        self.assertEqual(manager.restore_downloads(), 4)
        self.assertEqual(manager._downloads["active"].status, DownloadStatus.failed)
        self.assertEqual(manager._downloads["failed"].status, DownloadStatus.failed)
        self.assertIn("restart", manager._downloads["active"].error or "")
        self.assertEqual(manager._downloads["completed"].status, DownloadStatus.completed)
        self.assertEqual(manager._downloads["cancelled"].status, DownloadStatus.cancelled)
        retry = DownloadProgress(download_id="retry", status=DownloadStatus.queued, url=request.url)
        with patch.object(manager, "create_download", new=AsyncMock(return_value=retry)) as create:
            self.assertIs(await manager.retry_download("failed"), retry)
            create.assert_awaited_once()

    async def test_retry_only_starts_terminal_unsuccessful_jobs(self) -> None:
        request = DownloadRequest(url="https://example.com/video")
        for status in (DownloadStatus.queued, DownloadStatus.downloading, DownloadStatus.processing,
                       DownloadStatus.completed):
            manager._downloads[status.value] = DownloadProgress(
                download_id=status.value, status=status, url=request.url
            )
            manager._requests[status.value] = request
            with self.assertRaises(ValueError):
                await manager.retry_download(status.value)

        manager._downloads["failed"] = DownloadProgress(
            download_id="failed", status=DownloadStatus.failed, url=request.url
        )
        manager._requests["failed"] = request
        retry = DownloadProgress(download_id="retry", status=DownloadStatus.queued, url=request.url)
        with patch.object(manager, "create_download", new=AsyncMock(return_value=retry)) as create:
            self.assertIs(await manager.retry_download("failed"), retry)
            create.assert_awaited_once()
        self.assertIsNone(await manager.retry_download("unknown"))

    def test_download_ranges_are_numeric_yt_dlp_sections(self) -> None:
        request = DownloadRequest(
            url="https://example.com/video", start_time="00:01:30", end_time="00:03:00"
        )
        ranges = manager._build_extra_opts(request)["download_ranges"]
        self.assertEqual(
            list(ranges({"duration": 600}, None)),
            [{"start_time": 90.0, "end_time": 180.0}],
        )

        open_ended = manager._build_extra_opts(
            DownloadRequest(url="https://example.com/video", start_time="00:00:45")
        )["download_ranges"]
        self.assertEqual(
            list(open_ended({"duration": 600}, None)),
            [{"start_time": 45.0, "end_time": float("inf")}],
        )

    def test_embedding_options_preserve_audio_postprocessors(self) -> None:
        options = manager._build_extra_opts(
            DownloadRequest(
                url="https://example.com/video",
                audio_only=True,
                convert_to="mp3",
                embed_thumbnail=True,
                embed_subtitles=True,
            )
        )
        self.assertTrue(options["writethumbnail"])
        self.assertTrue(options["writesubtitles"])
        self.assertEqual(
            [processor["key"] for processor in options["postprocessors"]],
            ["FFmpegExtractAudio", "EmbedThumbnail", "FFmpegEmbedSubtitle"],
        )


class YtDlpEngineTests(unittest.TestCase):
    def test_returns_postprocessed_media_path(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            temporary = Path(tempdir) / "source.webm"
            final = Path(tempdir) / "converted.mp3"

            class FakeYDL:
                def __init__(self, options: dict[str, object]) -> None:
                    self.options = options

                def __enter__(self) -> "FakeYDL":
                    return self

                def __exit__(self, *_: object) -> None:
                    return None

                def download(self, _: list[str]) -> None:
                    temporary.write_bytes(b"input")
                    self.options["progress_hooks"][0]({"status": "finished", "filename": str(temporary)})
                    final.write_bytes(b"output")
                    self.options["postprocessor_hooks"][0](
                        {"status": "finished", "info_dict": {"filepath": str(final)}}
                    )

            with patch("app.core.ytdlp_engine.yt_dlp.YoutubeDL", FakeYDL):
                result = YtDlpEngine()._download_sync(
                    "https://example.com/video", tempdir, "best", None, {}
                )
            self.assertEqual(result, str(final.resolve()))

    def test_cancel_event_raises_from_progress_hook(self) -> None:
        class FakeYDL:
            def __init__(self, options: dict[str, object]) -> None:
                self.options = options

            def __enter__(self) -> "FakeYDL":
                return self

            def __exit__(self, *_: object) -> None:
                return None

            def download(self, _: list[str]) -> None:
                self.options["progress_hooks"][0]({"status": "downloading"})

        cancel_event = threading.Event()
        cancel_event.set()
        with tempfile.TemporaryDirectory() as tempdir, patch(
            "app.core.ytdlp_engine.yt_dlp.YoutubeDL", FakeYDL
        ):
            with self.assertRaises(DownloadCancelled):
                YtDlpEngine()._download_sync(
                    "https://example.com/video", tempdir, "best", None, {}, cancel_event
                )


if __name__ == "__main__":
    unittest.main()
