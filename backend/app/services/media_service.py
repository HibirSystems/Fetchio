"""Media info service with caching."""
from __future__ import annotations

import hashlib
import logging
from typing import Any

from app.core.ytdlp_engine import engine
from app.models.media import MediaInfo

logger = logging.getLogger(__name__)

_cache: dict[str, Any] = {}
_CACHE_MAX = 100


def _cache_key(url: str) -> str:
    return hashlib.sha256(url.encode()).hexdigest()[:32]


async def get_media_info(url: str) -> MediaInfo:
    key = _cache_key(url)
    if key in _cache:
        logger.debug("Cache hit for media info key %s", key)
        return MediaInfo(**_cache[key])

    info = await engine.get_info(url)

    if len(_cache) >= _CACHE_MAX:
        oldest = next(iter(_cache))
        _cache.pop(oldest, None)
    _cache[key] = info.model_dump()

    return info
