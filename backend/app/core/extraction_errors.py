"""Public extraction errors without retry internals or server paths."""
from __future__ import annotations


class MediaExtractionError(Exception):
    def __init__(self, message: str, code: str = "extraction_failed") -> None:
        super().__init__(message)
        self.code = code


def extraction_error(error: Exception) -> MediaExtractionError:
    message = str(error).lower().replace('’', "'")
    if "confirm you're not a bot" in message:
        return MediaExtractionError(
            "YouTube requires sign-in verification from the backend server. "
            "The backend operator should check site access requirements and configure authorized cookies with "
            "YTDLP_COOKIES_FILE. Rebuilding the Android app will not resolve this server-side restriction.",
            "verification_required",
        )
    if "[vimeo]" in message and "oauth token" in message and "401" in message:
        return MediaExtractionError(
            "Vimeo rejected the backend extractor's authentication request. "
            "The backend operator should check yt-dlp compatibility and authorized Vimeo access. "
            "A cookies file may be required; retrying the same request alone will not fix this.",
            "upstream_authentication_failed",
        )
    if any(term in message for term in ("sign in", "log in", "logged-in", "login required", "private video", "members-only", "age-restricted")):
        return MediaExtractionError(
            "This media requires an account with access. The backend operator can configure "
            "YTDLP_COOKIES_FILE using authorized cookies; never paste cookies into the app.",
            "authentication_required",
        )
    if any(term in message for term in ("javascript runtime", "challenge solving", "signature extraction", "n challenge")):
        return MediaExtractionError(
            "The backend could not solve the site's JavaScript challenge. Install the pinned "
            "yt-dlp-ejs dependency and a supported Node.js runtime, then restart the backend.",
            "javascript_challenge_failed",
        )
    if "403" in message and any(term in message for term in ("video data", "fragment", "segment")):
        return MediaExtractionError(
            "The media site refused the file transfer (HTTP 403), even after refreshing the video link. "
            "This is a backend/site access restriction, not a phone storage error. "
            "For YouTube, the operator should check current yt-dlp JavaScript and PO-token requirements; "
            "repeated retries or a new APK alone will not resolve an access restriction.",
            "media_transfer_forbidden",
        )
    if "unsupported url" in message:
        return MediaExtractionError("This URL is not supported. Paste the original media page URL.", "unsupported_url")
    if any(term in message for term in ("video unavailable", "not available", "has been removed", "http error 404")):
        return MediaExtractionError("This media is unavailable, removed, or restricted for the backend server.", "media_unavailable")
    if any(term in message for term in ("timed out", "unable to download", "http error", "connection", "network")):
        return MediaExtractionError(
            "The backend could not reach the media site. Check the backend connection and try again.",
            "upstream_connection_failed",
        )
    return MediaExtractionError(
        "The backend could not extract this media. Try the original media page URL; "
        "if it still fails, the backend operator should check yt-dlp logs and site support."
    )
