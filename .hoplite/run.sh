#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/.tools/flutter/bin:$PATH"
(cd frontend && flutter build web --release --web-renderer canvaskit --no-web-resources-cdn)
export FRONTEND_DIR="$PWD/frontend/build/web"
export DOWNLOAD_DIR="$PWD/backend/downloads"
cd backend
exec ../.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-3000}" --workers 1
