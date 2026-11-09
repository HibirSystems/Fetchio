from __future__ import annotations

from app.core.ytdlp_engine import _parse_media_info, _parse_search_item, _select_thumbnail


def test_flat_search_item_selects_highest_resolution_thumbnail() -> None:
    result = _parse_search_item(
        {
            "id": "video-id",
            "title": "Video",
            "url": "https://example.com/watch?v=video-id",
            "thumbnails": [
                {"url": "https://img.example.com/small.jpg", "width": 120, "height": 90},
                {"url": "https://img.example.com/large.jpg", "width": 1280, "height": 720},
            ],
        }
    )

    assert result.thumbnail == "https://img.example.com/large.jpg"


def test_scalar_thumbnail_wins_when_quality_is_unspecified() -> None:
    assert _select_thumbnail(
        {
            "thumbnail": "https://img.example.com/preferred.jpg",
            "thumbnails": [{"url": "https://img.example.com/alternate.jpg"}],
        }
    ) == "https://img.example.com/preferred.jpg"


def test_thumbnail_selection_skips_malformed_and_non_http_entries() -> None:
    assert _select_thumbnail(
        {
            "thumbnail": "not a URL",
            "thumbnails": [
                None,
                {},
                {"url": "file:///tmp/image.jpg", "width": 5000, "height": 5000},
                {"url": "https://img.example.com/valid.jpg", "width": "bad", "height": None},
            ],
        }
    ) == "https://img.example.com/valid.jpg"
    assert _select_thumbnail({"thumbnail": "//img.example.com/image.jpg"}) is None


def test_media_info_uses_canonical_page_url_and_normalizes_missing_thumbnails() -> None:
    result = _parse_media_info(
        {
            "id": "video-id",
            "title": "Video",
            "url": "https://cdn.example.com/signed-temporary-stream",
            "webpage_url": "https://example.com/watch?v=video-id",
            "thumbnail": None,
            "thumbnails": None,
        }
    )

    assert result.url == "https://example.com/watch?v=video-id"
    assert result.thumbnail is None
    assert result.thumbnails == []
