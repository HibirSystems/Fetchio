#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/.tools/flutter/bin:$PATH"
command -v flutter >/dev/null || { echo 'Flutter SDK is required on PATH (tested with 3.24.5).'; exit 1; }
python -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
(cd frontend && flutter pub get)
