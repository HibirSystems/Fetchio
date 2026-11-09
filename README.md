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
# Install Node.js >=22 (Docker bundles Node 22.14.0): https://nodejs.org/en/download
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
- Completed server files can be copied to Android **Downloads/Fetchio** automatically after backend extraction. Tapping a completed card opens it in an installed player with a granted content URI. Server extraction and device saving are separate stages.
- Failed and cancelled downloads can be retried with their original options.
- History and original requests persist as atomic `.download.json` records in each download directory. On restart, interrupted jobs become failed entries that can be retried; jobs are not automatically resumed.
- Cancellation cooperatively stops yt-dlp at its next progress hook. Metadata extraction and FFmpeg processing may finish before the worker exits; its concurrency slot stays occupied until then.
- Clearing finished history leaves media files on disk. Storage cleanup remains an operator responsibility.
- The client retains its last known list during connection errors and polls for recovery every three seconds.

## Android files and playback

Downloads started on this Android device automatically transfer to public **Internal storage → Download (Downloads) → Fetchio** when backend extraction finishes. There is no separate Save button. The Active tab shows device-transfer progress; Completed means the device copy has finished. Tap a finished audio/video card to launch an installed player—no separate player button is needed.

- Saving is managed by the download provider, not by whether the Downloads screen is open. Keep the app running during device transfers. If the app is terminated, tracked jobs are restored and saving resumes on the next launch; this is not an Android foreground/background download service.
- Only jobs started/retried on this phone, or explicitly tapped legacy entries, are enrolled for automatic device saving. A shared backend's unrelated history is not silently copied onto every phone.
- Saved URIs are remembered across launches; opening an existing file does not transfer it again. If a device save fails, the item appears in History with a retry action that retries only the device transfer, not backend extraction.
- Tap an older server-completed entry to fetch its file and play it. A compatible installed player is required; missing players do not delete the downloaded file.
- Android 10+ uses MediaStore without broad storage permission. Android 7–9 prompts for storage permission. Public files remain accessible in file explorers. Clearing backend history does not delete device files.

Install a newly built Android APK to apply this behavior. Browser previews can verify layout and controls, not Android MediaStore or installed-player dispatch.

## Troubleshooting media info and thumbnails

### TikTok transport support

TikTok's current extractor requests browser-compatible networking. The backend includes `curl-cffi==0.17.0`, the version pinned by yt-dlp 2026.10.26, so its supported transport can be used. This is backend-only and does not increase APK size. `GET /api/v1/health` should report `transport_version: "0.17.0"`. A missing transport can produce `Unexpected response from webpage request`, even for a public short link. A transport update is not a guarantee for private, removed, regional or login-restricted content.

### YouTube sessions on Railway

A sign-in verification response is separate from TikTok's transport problem. For media you are authorized to access, Railway operators can now supply an authorized session without creating a persistent file manually:

1. Export a **Netscape-format** cookies file for the intended site from a session you control, following [yt-dlp's official cookies guidance](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp). Do not send the file or its contents to chat.
2. Base64-encode the file locally. Base64 is **not encryption**: treat the encoded value as a credential.
3. In the Railway API service's private **runtime variables**, set `YTDLP_COOKIES_BASE64` to that value. Leave `YTDLP_COOKIES_FILE` unset. Do not put it in GitHub Actions inputs, APKs, source code, Docker build arguments, or logs.
4. Redeploy the backend. Startup validates the file and writes it to a temporary service-only directory (0700) with file mode 0600. It is passed to yt-dlp and removed on graceful shutdown. Invalid or conflicting cookie sources fail startup without echoing the value. Updated cookies are temporary and do not overwrite the Railway variable.
5. Test a new metadata request and download. Cookies may expire or be rejected for the backend's network; an authenticated session is **not a guaranteed fix**. Rotate/revoke sessions when no longer needed. Account use can carry restrictions or suspension risk.

**Do not configure an operator account session on an unrestricted public API.** Protect the backend with access controls first: all users of a shared backend could otherwise request content available to that session. This configuration enables the operator to supply authorized access; it does not bypass YouTube verification or grant access to other accounts. This repository has no Railway-management integration, so runtime variables are not configured automatically.

The backend pins yt-dlp **2026.10.26** with matching **yt-dlp-ejs 0.8.0**. Site extractors need coordinated, tested updates; the old February pin does not track later YouTube, Vimeo, Instagram or Facebook changes. Python 3.11+ is required by this extractor release (the image uses 3.12). The release APK remains Android-only and does not bundle these backend dependencies.

Fractional durations returned by sites (for example Facebook's `67.596` seconds) are normalized to integer seconds (`67`) before API serialization; unknown/nonfinite durations are omitted. Search and media details use the same rule.

Downloads use yt-dlp's normal format selection. A transfer-level HTTP 403 triggers **one** fresh extraction from the original URL with the same format/options. Persistent refusals stop with a specific error rather than looping or silently lowering quality. This can recover stale links; it does not grant access to restricted content or guarantee a YouTube download.

`GET /api/v1/health` exposes `extractor_version` and `ejs_version` so you can verify which backend was actually deployed. It does not expose cookies, proxy configuration or server paths. After deployment, check that it reports `2026.10.26` and `0.8.0`; a successful APK build alone does not update Railway's backend.

Downloads preserve the URL originally opened or pasted in the app. Metadata stream links (such as signed `googlevideo.com/videoplayback` URLs) are not reused as the download source. After deploying this fix, rebuild/install the Android APK as well as restarting the backend. For failed history entries created by older versions with a stream URL, open the original video page and start a **new** download; retrying an old entry retains its saved request.

Flat search entries can return a `thumbnails` list instead of a single image URL. The backend normalizes that list for Android clients; deploy/restart the backend to clear cached search responses after updating.

YouTube extraction needs both the pinned `yt-dlp-ejs` Python dependency (included in `backend/requirements.txt`) and a supported JavaScript runtime. The Docker image includes Node.js 22.14.0 and explicitly enables it in yt-dlp. For non-Docker deployments, install Node.js >=22 on the backend's PATH. These are backend dependencies; rebuilding the APK alone does not install them.

If YouTube metadata loads but the **file transfer returns HTTP 403**, that is a different failure from a missing page URL. The site may require current client/JavaScript support, Proof-of-Origin (PO) tokens, or authorized account access, and may restrict the backend's network. Follow the [official YouTube extractor guidance](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#youtube) and [PO-token guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide). No token provider is installed automatically and no credentials are collected by the app. Tokens/cookies are not universal guarantees.

If metadata fails with **sign-in/bot verification required**, search may still work because flat search does not fetch downloadable formats. The API now returns an actionable explanation instead of `RetryError[<Future ...>]`. Server IP restrictions, login requirements and unavailable media are not fixed by a new APK or by a JavaScript runtime alone.

For media you are authorized to access, the backend operator may configure a Netscape-format cookies file with `YTDLP_COOKIES_FILE`. Keep it private, readable only by the service user, and outside the repository, APK, Docker image and logs. With Docker Compose, mount the file read-only (for example, `/secure/path/cookies.txt:/run/secrets/ytdlp-cookies.txt:ro`) and add `YTDLP_COOKIES_FILE=/run/secrets/ytdlp-cookies.txt` to the API service environment. Restart the backend after configuration changes. Never send cookies or credentials in chat or paste them into the Android app. Account verification can still be required by the site; cookies do not guarantee access.

A Vimeo `Failed to fetch macos OAuth token: HTTP Error 401` is separate from the stream-URL bug: Vimeo rejected the extractor authentication request. The supported web client can require login. Authorized Vimeo cookies may be necessary, but are not a guaranteed fix; this is not resolved by forcing an anonymous client.

Rebuild the backend image with `docker compose up -d --build api`, or reinstall `backend/requirements.txt` and restart the server for a local deployment. See [yt-dlp JavaScript support](https://github.com/yt-dlp/yt-dlp/wiki/EJS) and [official cookies guidance](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp).

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
flutter build web --release --web-renderer canvaskit --no-web-resources-cdn
```

Implementation references: [yt-dlp embedding and output paths (2026.10.26)](https://github.com/yt-dlp/yt-dlp/tree/2026.10.26#embedding-yt-dlp), [Flutter network loading/error states](https://docs.flutter.dev/cookbook/networking/fetch-data).

---

## Building an Android release APK (manual only)

The **Build Android Release APK** workflow in `.github/workflows/release-apk.yml` runs **only** through GitHub's **Run workflow** button. Commits, pull requests and pushed tags do not trigger it. It builds Android APKs only—no web, iOS or app bundle builds—and does not automatically publish a GitHub Release.

### One-time repository secrets

In **Settings → Secrets and variables → Actions**, configure:

| Secret | Description |
|--------|-------------|
| `KEYSTORE_BASE64` | Base64-encoded Android release `.jks` keystore |
| `KEY_ALIAS` | Signing-key alias |
| `KEY_PASSWORD` | Signing-key password |
| `STORE_PASSWORD` | Keystore password |
| `PRODUCTION_API_URL` | HTTPS backend URL ending in `/api/v1`; alternatively supply it when running the workflow |

Use your existing release keystore for updates. To create one for a new app:

```bash
keytool -genkeypair -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias fetchio
base64 -w0 release.jks
```

Keep a secure backup of the keystore and passwords. Missing signing secrets fail the build; there is **no debug APK fallback**.

### Run and download

1. Ensure the workflow is on the repository's default branch so GitHub displays **Run workflow**.
2. Open **Actions → Build Android Release APK → Run workflow**.
3. Select the branch/tag, enter a version such as `1.0.0`, and optionally enter the backend URL. The backend must be reachable from the phone; the Android emulator's localhost address is not a production endpoint.
4. After the run succeeds, download the `fetchio-<version>-android-release-<run>` artifact and extract it.
5. Install **one** APK matching the device: `arm64-v8a` for most current phones, `armeabi-v7a` for older 32-bit phones, or `x86_64` for compatible emulators/devices. Android 7.0/API 24 or later is required.

### Size optimizations

The build uses release/AOT mode, per-ABI APKs (no universal/fat APK), icon tree shaking, R8 code shrinking, Android resource shrinking and external Dart debug symbols. Symbols and the R8 mapping are uploaded separately, not bundled with installable APKs. Existing compressed native-library packaging is retained. Because the current app downloads through its backend, the workflow does **not** download or bundle the large unused yt-dlp/FFmpeg executables. A reachable backend is required.

Exact APK sizes are measured in MiB in the run summary; they cannot be guaranteed before the first build. APK artifacts include SHA-256 checksums. Uploads expire after 30 days; symbol artifacts after 90 days, so archive symbols for releases you distribute. Each run uses its GitHub run number as the Android version code; use a new run (not a re-run) for a new app update.

Build guidance: [Flutter Android deployment and ABI splitting](https://docs.flutter.dev/deployment/android), [AGP 8.6 / Gradle 8.7 / JDK 17 compatibility](https://developer.android.com/build/releases/past-releases/agp-8-6-0-release-notes).

---

## License

MIT
