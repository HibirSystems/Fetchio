import asyncio
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from tenacity import wait_none
from yt_dlp.utils import DownloadError

from app.core.extraction_errors import MediaExtractionError, extraction_error
from app.core.ytdlp_engine import YtDlpEngine, _build_base_opts
from app.main import create_app
from app.services import media_service


@pytest.mark.parametrize(('message', 'code', 'hint'), [
    ("Sign in to confirm you’re not a bot", 'verification_required', 'YTDLP_COOKIES_FILE'),
    ('[vimeo] 152738080: Failed to fetch macos OAuth token: HTTP Error 401: Unauthorized', 'upstream_authentication_failed', 'Vimeo rejected'),
    ('[vimeo] The web client only works when logged-in', 'authentication_required', 'authorized cookies'),
    ('[TikTok] Unexpected response from webpage request', 'tiktok_extraction_failed', 'transport_version'),
    ('Private video. Sign in', 'authentication_required', 'authorized cookies'),
    ('No supported JavaScript runtime', 'javascript_challenge_failed', 'Node.js'),
    ('Unsupported URL: https://example.com', 'unsupported_url', 'original media page'),
    ('Video unavailable', 'media_unavailable', 'unavailable'),
    ('Unable to download webpage: timed out', 'upstream_connection_failed', 'connection'),
    ('unexpected upstream failure /server/private/path', 'extraction_failed', 'backend operator'),
])
def test_actionable_extraction_errors(message, code, hint):
    error = extraction_error(DownloadError(message))
    assert error.code == code
    assert hint in str(error)
    assert 'RetryError' not in str(error)
    assert '/server/private/path' not in str(error)


def test_get_info_maps_underlying_error_to_public_error():
    engine = YtDlpEngine()
    with patch.object(engine, '_get_info_sync', side_effect=DownloadError("Sign in to confirm you're not a bot")):
        with pytest.raises(MediaExtractionError) as raised:
            asyncio.run(engine.get_info('https://example.com/video'))
    assert raised.value.code == 'verification_required'
    assert 'RetryError' not in str(raised.value)


def test_retry_reraises_underlying_download_error():
    engine = YtDlpEngine()
    with patch('app.core.ytdlp_engine.yt_dlp.YoutubeDL') as ydl:
        ydl.return_value.__enter__.return_value.extract_info.side_effect = DownloadError('Video unavailable')
        fast_retry = engine._get_info_sync.retry_with(wait=wait_none())
        with pytest.raises(DownloadError, match='Video unavailable'):
            fast_retry(engine, 'https://example.com/video')
        assert ydl.return_value.__enter__.return_value.extract_info.call_count == 3


def test_enables_locally_installed_javascript_runtimes_without_remote_code_fetch():
    options = _build_base_opts()
    assert options['js_runtimes'] == {'deno': {}, 'node': {}}
    assert not options.get('remote_components')


def test_media_route_returns_safe_actionable_error(monkeypatch):
    async def fail(url):
        raise MediaExtractionError('Backend sign-in verification required.', 'verification_required')
    monkeypatch.setattr(media_service, 'get_media_info', fail)
    with TestClient(create_app()) as client:
        response = client.get('/api/v1/media/info', params={'url': 'https://example.com/video'})
    assert response.status_code == 502
    assert response.json()['detail'] == 'Backend sign-in verification required.'
    assert response.headers['X-Extraction-Error'] == 'verification_required'


def test_media_route_does_not_leak_unexpected_server_error(monkeypatch):
    async def fail(url):
        raise RuntimeError('/private/server/file')
    monkeypatch.setattr(media_service, 'get_media_info', fail)
    with TestClient(create_app()) as client:
        response = client.get('/api/v1/media/info', params={'url': 'https://example.com/video'})
    assert response.status_code == 502
    assert '/private/server' not in response.text
