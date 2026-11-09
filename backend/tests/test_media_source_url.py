import asyncio
from unittest.mock import AsyncMock

from app.models.media import MediaInfo
from app.services import media_service


def test_media_info_keeps_original_url_in_fresh_and_cached_responses(monkeypatch):
    source = 'https://www.youtube.com/watch?v=p1cNW59M4Cs'
    stream = 'https://rr5.example.googlevideo.com/videoplayback?expire=123'
    info = MediaInfo(id='p1cNW59M4Cs', title='Video', url=stream)
    monkeypatch.setattr(media_service, '_cache', {})
    extract = AsyncMock(return_value=info)
    monkeypatch.setattr(media_service.engine, 'get_info', extract)
    fresh = asyncio.run(media_service.get_media_info(source))
    assert fresh.url == source
    cached = asyncio.run(media_service.get_media_info(source))
    assert cached.url == source
    assert extract.await_count == 1


def test_legacy_cached_stream_is_not_returned_as_download_source(monkeypatch):
    source = 'https://youtu.be/p1cNW59M4Cs'
    info = MediaInfo(id='p1cNW59M4Cs', title='Video', url='https://cdn.example.com/expiring-stream')
    monkeypatch.setattr(media_service, '_cache', {media_service._cache_key(source): info.model_dump()})
    extract = AsyncMock()
    monkeypatch.setattr(media_service.engine, 'get_info', extract)
    assert asyncio.run(media_service.get_media_info(source)).url == source
    extract.assert_not_awaited()
