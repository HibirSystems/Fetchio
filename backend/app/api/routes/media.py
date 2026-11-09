"""Media info endpoints."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

from app.models.media import MediaInfo
from app.core.extraction_errors import MediaExtractionError
from app.services import media_service

router = APIRouter(prefix="/media", tags=["media"])


@router.get("/info", response_model=MediaInfo)
async def get_media_info(
    url: str = Query(..., min_length=5, description="Media URL to extract info from"),
) -> MediaInfo:
    """Extract metadata (title, thumbnail, formats, etc.) for a given URL."""
    try:
        return await media_service.get_media_info(url)
    except MediaExtractionError as exc:
        raise HTTPException(status_code=502, detail=str(exc), headers={"X-Extraction-Error": exc.code}) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="The backend could not extract this media. Please try again or contact the backend operator.") from exc
