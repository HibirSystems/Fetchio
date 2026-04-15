# Fetchio

A **production-grade cross-platform media downloader** built with Flutter (frontend) and FastAPI + yt-dlp (backend).

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

## Production deployment

1. Set a strong `SECRET_KEY` in `.env`
2. Configure `ALLOWED_ORIGINS` to your domain
3. Mount a persistent volume for `DOWNLOAD_DIR`
4. Put an Nginx reverse proxy in front of the API
5. Use `docker-compose up -d --build`

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
