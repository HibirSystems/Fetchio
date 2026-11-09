from __future__ import annotations

from typing import Any, Callable

import pytest
from pydantic import ValidationError

from app.core.ytdlp_engine import _parse_media_info, _parse_search_item


@pytest.mark.parametrize(
    ("duration", "expected"),
    [
        (67.596, 67),
        (0, 0),
        (None, None),
        (float("nan"), None),
        (float("inf"), None),
        (float("-inf"), None),
        ("67.596", 67),
    ],
)
@pytest.mark.parametrize(
    "parse",
    [
        lambda duration: _parse_media_info({"duration": duration}),
        lambda duration: _parse_search_item({"duration": duration}),
    ],
)
def test_parser_normalizes_duration(
    parse: Callable[[Any], Any], duration: Any, expected: int | None
) -> None:
    assert parse(duration).duration == expected


@pytest.mark.parametrize(
    "parse",
    [
        lambda duration: _parse_media_info({"duration": duration}),
        lambda duration: _parse_search_item({"duration": duration}),
    ],
)
@pytest.mark.parametrize("duration", [-0.1, "-1", "not a duration"])
def test_parser_rejects_invalid_negative_or_malformed_duration(
    parse: Callable[[Any], Any], duration: Any
) -> None:
    with pytest.raises(ValidationError):
        parse(duration)
