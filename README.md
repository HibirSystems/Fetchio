# Fetchio

A **self-hosted cross-platform media downloader** built with Flutter (frontend) and FastAPI + yt-dlp (backend).

---

## Architecture

```
Fetchio/
├── backend/          # Python FastAPI + yt-dlp API server
│   ├── app/
│   │   ├── api/      # REST route handlers + WebSocket
│   │   ├── core/     # yt-dlp engine + async download manager
│   │   ├── models/   # Pydantic schemas
│   │   └── services/ # Business logic layer
│   ├── Dockerfile
│   └── requirements.txt
├── frontend/         # Flutter Android-first app
│   └── lib/
│       ├── core/     # Theme, router, network, constants
│       ├── features/ # Screen-level widgets
│       ├── providers/ # Riverpod state + repositories
│       └── shared/   # Reusable widgets + models
└── docker-compose.yml
```

---

## Backend

### Tech stack
| Layer | Technology |
|-------|-----------|
| Framework | FastAPI 0.111 |
| Media engine | yt-dlp |
| Async downloads | asyncio + ThreadPoolExecutor |
| Caching | In-process LRU (Redis-ready) |
| Containerisation | Docker + docker-compose |

### API Reference

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/health` | Health check |
| `GET` | `/api/v1/search?q=<query>` | Search across 1000+ platforms |
| `GET` | `/api/v1/media/info?url=<url>` | Extract metadata + format list |
| `POST` | `/api/v1/downloads` | Queue a new download |
| `GET` | `/api/v1/downloads` | List all downloads |
| `GET` | `/api/v1/downloads/{id}` | Get single download progress |
| `GET` | `/api/v1/downloads/{id}/file` | Save a completed file to this device |
| `POST` | `/api/v1/downloads/{id}/retry` | Retry a failed or cancelled download |
| `DELETE` | `/api/v1/downloads/{id}` | Cancel active download |
| `DELETE` | `/api/v1/downloads` | Clear completed downloads |
| `WS` | `/api/v1/downloads/{id}/ws` | Real-time progress stream |

### Quick start (Docker)

```bash
docker-compose up -d
```

### Quick start (local)

```bash
cd backend
pip install -r requirements.txt
# Install ffmpeg: https://ffmpeg.org/download.html
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

API docs available at `http://localhost:8000/docs` when `DEBUG=true`.

### Configuration

Copy `.env.example` to `.env` in `backend/` and adjust:

```env
DEBUG=true
DOWNLOAD_DIR=./downloads
MAX_CONCURRENT_DOWNLOADS=3
YTDLP_PROXY=           # optional HTTP/SOCKS5 proxy
YTDLP_COOKIES_FILE=    # optional cookies.txt path
```

---

## Frontend (Flutter)

### Tech stack
| Layer | Technology |
|-------|-----------|
| State management | Riverpod 2 |
| Navigation | GoRouter |
| HTTP client | Dio (with retry) |
| WebSocket | web_socket_channel |
| Local storage | Hive |
| UI | Material 3, dark-first |

### Screens

| Screen | Route | Description |
|--------|-------|-------------|
| Splash | `/splash` | Animated launch screen |
| Home | `/` | URL paste + recent downloads + search history |
| Search Results | `/search?q=<query>` | Paginated search with lazy loading |
| Media Detail | `/media?url=<url>` | Metadata, formats, download trigger |
| Download Manager | `/downloads` | Active / Completed / History tabs with real-time progress |
| Settings | `/settings` | Theme, quality, API URL, audio prefs |

### Run locally

```bash
cd frontend
flutter pub get
flutter run
```

> **Android emulator note**: the default API URL is `http://10.0.2.2:8000/api/v1` which routes to the host machine from the Android emulator. Update it in Settings for physical devices.

---

## Supported platforms

yt-dlp supports **1000+** platforms out of the box, including:
- YouTube / YouTube Music
- TikTok, Instagram, Twitter/X
- Vimeo, Dailymotion, Twitch
- SoundCloud, Bandcamp
- Reddit, Facebook, and many more

---

## Download reliability

- Quality preferences and custom yt-dlp format selectors are accepted by the API.
- Completed files can be saved from the Downloads screen. Downloads run on the backend, not directly on the phone/browser.
- Failed and cancelled downloads can be retried with their original options.
- History and original requests persist as atomic `.download.json` records in each download directory. On restart, interrupted jobs become failed entries that can be retried; jobs are not automatically resumed.
- Cancellation cooperatively stops yt-dlp at its next progress hook. Metadata extraction and FFmpeg processing may finish before the worker exits; its concurrency slot stays occupied until then.
- Clearing finished history leaves media files on disk. Storage cleanup remains an operator responsibility.
- The client retains its last known list during connection errors and polls for recovery every three seconds.

## Integrated web preview

Prerequisites: Python 3.12, FFmpeg, and Flutter on `PATH` (verified with Flutter 3.24.5). The scripts also recognize a local SDK at `.tools/flutter`; they do not install an SDK.

```bash
bash .hoplite/setup.sh
bash .hoplite/run.sh
```

The web build and API are served together on port 3000. Browser clients default to the same-origin `/api/v1`, so HTTPS previews do not call an unreachable localhost backend. Native Android defaults to the emulator host address. For a separate backend, configure Settings or compile with `--dart-define=API_BASE_URL=https://your-api.example/api/v1`.

For a prebuilt web deployment, set `FRONTEND_DIR` to the Flutter `build/web` directory when starting the API. Without it the API remains standalone.

## Deployment boundaries

Use **one API worker**: the active queue, semaphore and progress stream are process-local. Docker is configured accordingly; multiple workers/replicas need shared job coordination before use. Mount a persistent `DOWNLOAD_DIR` to retain files and history.

This is a trusted-user/self-hosted service, **not an authenticated public download service**. `SECRET_KEY`, API-key and rate-limit settings do not currently enforce access control. Before exposing it publicly, add authentication and rate limiting at a reverse proxy, restrict allowed origins, restrict outbound network access (including private/internal destinations), and set storage quotas. HTTP(S) URL validation alone does not prevent SSRF. Only download media you own or are permitted to download; availability depends on upstream sites, access permissions and yt-dlp support.

## Verification

```bash
.venv/bin/pip install -r backend/requirements-dev.txt
PYTHONPATH=backend .venv/bin/python -m pytest backend/tests -q
cd frontend
flutter test
flutter analyze
flutter build web --release --web-renderer html --no-web-resources-cdn
```

Implementation references: [yt-dlp embedding and output paths (2026.02.21)](https://github.com/yt-dlp/yt-dlp/tree/2026.02.21#embedding-yt-dlp), [Flutter network loading/error states](https://docs.flutter.dev/cookbook/networking/fetch-data).

---

## Releasing a Production APK

The CI workflow in `.github/workflows/release-apk.yml` automatically builds and publishes a signed APK to GitHub Releases whenever you push a version tag.

### One-time setup (GitHub repository secrets)

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|--------|-------------|
| `KEYSTORE_BASE64` | Base64-encoded `.jks` keystore (`base64 -w0 release.jks`) |
| `KEY_ALIAS` | Signing key alias |
| `KEY_PASSWORD` | Password for the signing key |
| `STORE_PASSWORD` | Keystore password |
| `PRODUCTION_API_URL` | Production API base URL, e.g. `https://api.example.com/api/v1` |

#### Generating a keystore (first time only)

```bash
keytool -genkeypair -v \
  -keystore release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias fetchio
# then encode it:
base64 -w0 release.jks
```

Paste the output into the `KEYSTORE_BASE64` secret.

### Trigger a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow will build a release APK signed with your keystore, then publish it as a GitHub Release with the APK attached.

You can also trigger it manually from **Actions → Build & Release APK → Run workflow**.

---

## License

MIT
