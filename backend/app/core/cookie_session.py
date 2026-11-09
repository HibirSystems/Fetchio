"""Load operator-supplied sessions without baking credentials into an image."""
from __future__ import annotations

import base64
import binascii
import os
import tempfile
import warnings
from contextlib import contextmanager
from http.cookiejar import MozillaCookieJar
from pathlib import Path
from typing import Iterator

from app.config import Settings


@contextmanager
def configured_cookie_session(config: Settings) -> Iterator[None]:
    secret = config.ytdlp_cookies_base64
    if not secret or not secret.get_secret_value():
        yield
        return
    if config.ytdlp_cookies_file:
        raise ValueError("Set only one of YTDLP_COOKIES_FILE or YTDLP_COOKIES_BASE64")
    try:
        payload = base64.b64decode(''.join(secret.get_secret_value().split()), validate=True)
    except (ValueError, binascii.Error):
        raise ValueError("YTDLP_COOKIES_BASE64 must contain a base64-encoded Netscape cookies file") from None
    if not payload or len(payload) > 1024 * 1024:
        raise ValueError("YTDLP_COOKIES_BASE64 must decode to a nonempty file under 1 MiB")

    with tempfile.TemporaryDirectory(prefix="fetchio-session-") as directory:
        path = Path(directory) / "cookies.txt"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as file:
            file.write(payload)
        try:
            jar = MozillaCookieJar(str(path))
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                jar.load(ignore_discard=True, ignore_expires=True)
            if not list(jar):
                raise ValueError("Empty cookie jar")
        except Exception:
            raise ValueError("YTDLP_COOKIES_BASE64 must decode to a valid Netscape cookies file with cookies") from None
        config.ytdlp_cookies_file = str(path)
        try:
            yield
        finally:
            config.ytdlp_cookies_file = None
