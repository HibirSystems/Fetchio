"""Search service – orchestrates search providers with caching."""
from __future__ import annotations

import hashlib
import json
import logging
from typing import Any

from app.core.ytdlp_engine import engine
from app.models.search import MediaType, SearchResponse, SearchResultItem

logger = logging.getLogger(__name__)

# Simple in-process LRU cache (replaced by Redis in production)
_cache: dict[str, Any] = {}
_CACHE_MAX = 200


def _cache_key(query: str, page: int, per_page: int) -> str:
    raw = f"{query.lower().strip()}:{page}:{per_page}"
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


async def search(
    query: str,
    page: int = 1,
    per_page: int = 20,
    media_type: MediaType | None = None,
) -> SearchResponse:
    key = _cache_key(query, page, per_page)
    if key in _cache:
        logger.debug("Cache hit for search key %s", key)
        cached = _cache[key]
        return SearchResponse(**cached)

    # Fetch slightly more to handle pagination
    fetch_limit = page * per_page
    results = await engine.search(query, limit=fetch_limit, media_type=media_type)

    if media_type:
        results = [r for r in results if r.media_type == media_type]

    start = (page - 1) * per_page
    end = start + per_page
    page_results = results[start:end]

    response = SearchResponse(
        query=query,
        results=page_results,
        total=len(results),
        page=page,
        per_page=per_page,
    )

    # Store in cache
    if len(_cache) >= _CACHE_MAX:
        oldest = next(iter(_cache))
        _cache.pop(oldest, None)
    _cache[key] = response.model_dump()

    return response
