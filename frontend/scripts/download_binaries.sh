#!/usr/bin/env bash
# Downloads yt-dlp and ffmpeg binaries and places them in Android jniLibs.
#
# Run this before `flutter build apk` when building locally:
#   cd frontend && bash scripts/download_binaries.sh
#
# The CI workflow (release-apk.yml) calls this automatically.
#
# Binary sources:
#   yt-dlp  – https://github.com/yt-dlp/yt-dlp/releases/latest
#   ffmpeg  – https://johnvansickle.com/ffmpeg/ (static Linux ARM builds)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JNILIBS_DIR="$SCRIPT_DIR/../android/app/src/main/jniLibs"
ASSET_BIN_DIR="$SCRIPT_DIR/../assets/binaries"

# ── yt-dlp ────────────────────────────────────────────────────────────────────

if [ -z "${YTDLP_VERSION:-}" ]; then
  YTDLP_VERSION="$(curl -sf https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
  if [ -z "$YTDLP_VERSION" ]; then
    echo "ERROR: Failed to detect the latest yt-dlp version from GitHub API." >&2
    echo "       Set YTDLP_VERSION manually, e.g.: YTDLP_VERSION=2024.07.25 $0" >&2
    exit 1
  fi
fi
YTDLP_BASE="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}"

echo "==> Downloading yt-dlp ${YTDLP_VERSION}"
download_ytdlp() {
  local abi="$1"
  local upstream_name="$2"
  local so_dest="${JNILIBS_DIR}/${abi}/libfetchio_ytdlp.so"
  local asset_dest="${ASSET_BIN_DIR}/${abi}/yt-dlp"
  mkdir -p "${JNILIBS_DIR}/${abi}"
  mkdir -p "${ASSET_BIN_DIR}/${abi}"
  echo "    [yt-dlp] ${abi} <- ${upstream_name}"
  curl -L --retry 3 -o "${so_dest}" "${YTDLP_BASE}/${upstream_name}"
  cp "${so_dest}" "${asset_dest}"
  chmod 755 "${so_dest}" "${asset_dest}"
}

download_ytdlp "arm64-v8a"   "yt-dlp_linux_aarch64"
download_ytdlp "armeabi-v7a" "yt-dlp_linux_armv7l"
download_ytdlp "x86_64"      "yt-dlp_linux_x86_64"

# ── ffmpeg ────────────────────────────────────────────────────────────────────
# John Van Sickle's static ARM builds are widely used for Android/Termux.
# We pull the "arm64" and "armhf" variants, which map to arm64-v8a and armeabi-v7a.
# For x86_64 we use the amd64 static build.

FFMPEG_BASE="https://johnvansickle.com/ffmpeg/releases"

echo "==> Downloading ffmpeg (static)"

download_ffmpeg() {
  local abi="$1"
  local archive_name="$2"
  local inner_binary="$3"   # path inside the tar.xz
  local so_dest="${JNILIBS_DIR}/${abi}/libfetchio_ffmpeg.so"
  local asset_dest="${ASSET_BIN_DIR}/${abi}/ffmpeg"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  mkdir -p "${JNILIBS_DIR}/${abi}"
  mkdir -p "${ASSET_BIN_DIR}/${abi}"

  echo "    [ffmpeg] ${abi} <- ${archive_name}"
  curl -L --retry 3 -o "${tmp_dir}/ffmpeg.tar.xz" "${FFMPEG_BASE}/${archive_name}"
  tar -xJf "${tmp_dir}/ffmpeg.tar.xz" -C "${tmp_dir}" --strip-components=1 --wildcards "*/${inner_binary}"
  mv "${tmp_dir}/${inner_binary}" "${so_dest}"
  cp "${so_dest}" "${asset_dest}"
  chmod 755 "${so_dest}" "${asset_dest}"
  rm -rf "${tmp_dir}"
}

download_ffmpeg "arm64-v8a"   "ffmpeg-release-arm64-static.tar.xz" "ffmpeg"
download_ffmpeg "armeabi-v7a" "ffmpeg-release-armhf-static.tar.xz" "ffmpeg"
download_ffmpeg "x86_64"      "ffmpeg-release-amd64-static.tar.xz" "ffmpeg"

echo ""
echo "==> Done.  Binaries written to android/app/src/main/jniLibs/"
ls -lh "${JNILIBS_DIR}/arm64-v8a/"
