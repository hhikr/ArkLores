#!/usr/bin/env bash
# ArkLores cloud session start: run once at the start of each cloud session
#   bash tools/cloud/session_start.sh
# Idempotent and quick. Writes the gitignored key files from environment
# variables (never prints their values), sets the git identity and fetches
# Dart packages. Does nothing to files that already exist.
set -uo pipefail
cd "$(dirname "$0")/../.."

log() { echo "[arklores-session] $*"; }

# Commits are by hhikr only (CLAUDE.md "提交规范").
git config user.name hhikr
git config user.email ocitsots@gmail.com

# tools/api_info (API_KEY= / MODEL= / URL=) for the live Ask harness.
if [ ! -f tools/api_info ]; then
  if [ -n "${ARKLORES_API_KEY:-}" ] && [ -n "${ARKLORES_API_MODEL:-}" ] \
      && [ -n "${ARKLORES_API_URL:-}" ]; then
    umask 077
    printf 'API_KEY=%s\nMODEL=%s\nURL=%s\n' \
      "$ARKLORES_API_KEY" "$ARKLORES_API_MODEL" "$ARKLORES_API_URL" > tools/api_info
    log "wrote tools/api_info"
  else
    log "no ARKLORES_API_* variables: live API tests are unavailable"
  fi
fi

# tools/embedding-apiKey.csv (openAiCompatible,<url> / apiKey,<key>).
if [ ! -f tools/embedding-apiKey.csv ] && [ -n "${ARKLORES_EMBEDDING_API_KEY:-}" ]; then
  umask 077
  {
    [ -n "${ARKLORES_EMBEDDING_URL:-}" ] \
      && printf 'openAiCompatible,%s\n' "$ARKLORES_EMBEDDING_URL"
    printf 'apiKey,%s\n' "$ARKLORES_EMBEDDING_API_KEY"
  } > tools/embedding-apiKey.csv
  log "wrote tools/embedding-apiKey.csv"
fi

if command -v flutter >/dev/null 2>&1; then
  export CI=true
  flutter pub get >/dev/null && log "flutter pub get ok" \
    || log "flutter pub get FAILED"
else
  log "flutter not found: check the environment setup script (tools/cloud/environment_setup.sh)"
fi

if [ -f build/gamedata_mobile/arklores_gamedata_zh.db ]; then
  log "knowledge base present"
else
  log "no knowledge base; only needed for live tests: bash tools/cloud/fetch_gamedata.sh"
fi
