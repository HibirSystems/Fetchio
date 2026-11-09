import asyncio
import threading
from unittest.mock import patch

import pytest
from yt_dlp.utils import DownloadError

from app.core.extraction_errors import MediaExtractionError
from app.core.ytdlp_engine import DownloadCancelled, YtDlpEngine


def test_transfer_403_reextracts_original_source_once():
    source = 'https://www.youtube.com/watch?v=example'
    engine = YtDlpEngine()
    with patch.object(engine, '_download_sync', side_effect=[DownloadError('unable to download video data: HTTP Error 403: Forbidden'), '/tmp/final.mp4']) as download:
        assert asyncio.run(engine.download(source, '/tmp/download', 'best')) == '/tmp/final.mp4'
    assert download.call_count == 2
    assert [call.args[0] for call in download.call_args_list] == [source, source]
    assert [call.args[2] for call in download.call_args_list] == ['best', 'best']


def test_persistent_transfer_403_has_bounded_retry_and_safe_error():
    engine = YtDlpEngine()
    with patch.object(engine, '_download_sync', side_effect=DownloadError('unable to download video data: HTTP Error 403: Forbidden https://secret.example/?signature=private')) as download:
        with pytest.raises(MediaExtractionError) as raised:
            asyncio.run(engine.download('https://example.com/video', '/tmp/download', 'best'))
    assert download.call_count == 2
    assert raised.value.code == 'media_transfer_forbidden'
    assert 'signature' not in str(raised.value)


def test_login_failure_is_not_retried_as_expired_transfer():
    engine = YtDlpEngine()
    with patch.object(engine, '_download_sync', side_effect=DownloadError('Login required')) as download:
        with pytest.raises(MediaExtractionError) as raised:
            asyncio.run(engine.download('https://example.com/video', '/tmp/download', 'best'))
    assert download.call_count == 1
    assert raised.value.code == 'authentication_required'


def test_cancellation_prevents_reextraction_after_failure():
    engine = YtDlpEngine()
    cancelled = threading.Event()
    def fail(*args):
        cancelled.set()
        raise DownloadError('unable to download video data: HTTP Error 403: Forbidden')
    with patch.object(engine, '_download_sync', side_effect=fail) as download:
        with pytest.raises(DownloadCancelled):
            asyncio.run(engine.download('https://example.com/video', '/tmp/download', 'best', cancel_event=cancelled))
    assert download.call_count == 1


def test_uses_upstream_format_selection_without_forced_preflight(tmp_path):
    final = tmp_path / 'final.mp4'
    def download(urls):
        final.write_bytes(b'video')
    with patch('app.core.ytdlp_engine.yt_dlp.YoutubeDL') as ydl:
        ydl.return_value.__enter__.return_value.download.side_effect = download
        result = YtDlpEngine()._download_sync('https://example.com/video', str(tmp_path), 'best', None, {})
    assert result == str(final)
    assert 'check_formats' not in ydl.call_args.args[0]
