from importlib.metadata import version

from fastapi.testclient import TestClient

from app.main import create_app


def test_health_reports_installed_extractor_versions_without_private_configuration():
    with TestClient(create_app()) as client:
        response = client.get('/api/v1/health')
    assert response.status_code == 200
    data = response.json()
    assert data['extractor_version'] == version('yt-dlp')
    assert data['ejs_version'] == version('yt-dlp-ejs')
    assert 'cookies' not in response.text.lower()
    assert 'proxy' not in response.text.lower()
