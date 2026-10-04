#!/usr/bin/env bash
# ArkLores cloud environment setup script.
#
# Paste this whole file into the "Setup script" field of the ArkLores-Cloud
# environment at claude.ai/code. It runs as root on Ubuntu 24.04 before
# Claude Code starts and is cached as a filesystem snapshot (when it finishes
# in about five minutes), so it only installs the toolchain. Project steps
# (pub get, key files, git identity) are in tools/cloud/session_start.sh,
# which the agent runs at the start of each session.
#
# It must exit 0, or the session does not start.
set -uo pipefail

FLUTTER_VERSION="3.47.5"
FLUTTER_HOME="/opt/flutter"

log() { echo "[arklores-setup] $*"; }

# libsqlite3.so for sqflite FFI in tests; xz/unzip for the Flutter archive.
apt-get update -qq >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  libsqlite3-dev xz-utils unzip curl >/dev/null 2>&1 \
  || log "apt install failed (continuing)"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  log "installing Flutter $FLUTTER_VERSION"
  # A shallow clone of the release tag is much smaller than the 1.5 GB
  # archive; the archive is the fallback when the clone is not reachable.
  if ! git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_HOME"; then
    rm -rf "$FLUTTER_HOME"
    archive="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    curl -fsSL -o "/tmp/$archive" \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$archive" \
      && tar -xJf "/tmp/$archive" -C /opt \
      && rm -f "/tmp/$archive" \
      || log "Flutter archive download failed"
  fi
fi

if [ -x "$FLUTTER_HOME/bin/flutter" ]; then
  git config --global --add safe.directory "$FLUTTER_HOME" || true
  ln -sf "$FLUTTER_HOME/bin/flutter" /usr/local/bin/flutter
  ln -sf "$FLUTTER_HOME/bin/dart" /usr/local/bin/dart
  export CI=true
  flutter config --no-analytics >/dev/null 2>&1 || true
  dart --disable-analytics >/dev/null 2>&1 || true
  # Only `flutter test` / `analyze` run here: no Android, web or desktop
  # artifacts (APKs are built by GitHub Actions).
  flutter config --no-enable-android --no-enable-web \
    --no-enable-linux-desktop >/dev/null 2>&1 || true
  flutter precache >/dev/null 2>&1 || log "flutter precache failed (will retry on first use)"
  flutter --version || true
else
  log "Flutter is NOT installed; the session can still start"
fi

exit 0
