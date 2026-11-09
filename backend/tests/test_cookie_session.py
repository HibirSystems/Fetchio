import base64
from pathlib import Path

import pytest
from pydantic import SecretStr

from app.config import Settings
from app.core.cookie_session import configured_cookie_session
from app.core.ytdlp_engine import _build_base_opts

# Synthetic, nonfunctional test cookie.
COOKIE = b'# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\ttest_session\tsynthetic-value\n'


def config(**kwargs):
    return Settings(_env_file=None, **kwargs)


def test_session_is_private_available_during_lifespan_and_removed():
    settings = config(ytdlp_cookies_base64=base64.b64encode(COOKIE).decode())
    assert 'synthetic-value' not in repr(settings)
    with configured_cookie_session(settings):
        path = Path(settings.ytdlp_cookies_file)
        assert path.read_bytes() == COOKIE
        assert path.stat().st_mode & 0o777 == 0o600
        assert path.parent.stat().st_mode & 0o777 == 0o700
    assert settings.ytdlp_cookies_file is None
    assert not path.exists()


def test_existing_file_source_is_preserved():
    settings = config(ytdlp_cookies_file='/private/cookies.txt')
    with configured_cookie_session(settings):
        assert settings.ytdlp_cookies_file == '/private/cookies.txt'
    assert settings.ytdlp_cookies_file == '/private/cookies.txt'


@pytest.mark.parametrize('value', ['not-base64!', base64.b64encode(b'not a cookie file').decode()])
def test_invalid_session_fails_without_echoing_secret(value):
    settings = config(ytdlp_cookies_base64=value)
    with pytest.raises(ValueError) as raised:
        with configured_cookie_session(settings):
            pass
    assert value not in str(raised.value)


def test_rejects_conflicting_cookie_sources():
    settings = config(ytdlp_cookies_file='/private/cookies.txt', ytdlp_cookies_base64='abc')
    with pytest.raises(ValueError, match='only one'):
        with configured_cookie_session(settings):
            pass


def test_engine_receives_cookie_path_without_value_in_options(monkeypatch):
    from app.core import ytdlp_engine
    settings = config(ytdlp_cookies_base64=base64.b64encode(COOKIE).decode())
    with configured_cookie_session(settings):
        monkeypatch.setattr(ytdlp_engine, 'settings', settings)
        opts = _build_base_opts()
        assert opts['cookiefile'] == settings.ytdlp_cookies_file
        assert 'synthetic-value' not in repr(opts)


def test_app_lifespan_loads_session_then_cleans_it_up(monkeypatch):
    from fastapi.testclient import TestClient
    from app import main
    secret = SecretStr(base64.b64encode(COOKIE).decode())
    monkeypatch.setattr(main.settings, 'ytdlp_cookies_file', None)
    monkeypatch.setattr(main.settings, 'ytdlp_cookies_base64', secret)
    with TestClient(main.create_app()) as client:
        path = Path(main.settings.ytdlp_cookies_file)
        assert path.exists()
        response = client.get('/api/v1/health')
        assert response.status_code == 200
        assert 'synthetic-value' not in response.text
        assert secret.get_secret_value() not in response.text
        assert str(path) not in response.text
    assert not path.exists()
    assert main.settings.ytdlp_cookies_file is None
