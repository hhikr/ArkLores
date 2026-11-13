#!/usr/bin/env bash
# Downloads the released knowledge bases (URLs and SHA-256 from the live
# channel file, else tools/release_gamedata.env, which lags behind once the
# server has updated the Arknights one, docs/GAMEDATA_BUILD_PIPELINE.md 7.1): Arknights to
# build/gamedata_mobile/arklores_gamedata_zh.db (the default DB of
# test/live/ask_pipeline_live_test.dart) and Endfield to
# build/endfield/arklores_endfield_zh.db (pass it as ARKLORES_ENDFIELD_DB).
# Only the live tests need them; a few hundred MB.
set -euo pipefail
cd "$(dirname "$0")/../.."

# shellcheck disable=SC1091
source tools/release_gamedata.env

# fetch <url> <sha256> <db path>
fetch() {
  local url="$1" sha="$2" db="$3"
  local gz="$db.gz"
  if [ -z "$url" ]; then
    echo "no URL for $db in tools/release_gamedata.env; skipped"
    return 0
  fi
  mkdir -p "$(dirname "$db")"
  if [ -f "$db" ]; then
    echo "already present: $db"
    return 0
  fi
  curl -fL --retry 3 -o "$gz" "$url"
  local actual
  actual="$(sha256sum "$gz" | awk '{print $1}')"
  if [ "$actual" != "$sha" ]; then
    echo "SHA-256 mismatch for $gz: got $actual, expected $sha" >&2
    rm -f "$gz"
    exit 1
  fi
  gunzip -c "$gz" > "$db"
  rm -f "$gz"
  echo "ready: $db"
}

# The channel file says what is published now (the server replaces the
# Arknights files in place); the env values only when it cannot be read.
channel="$(curl -fsSL --retry 2 "${GAMEDATA_CHANNEL_URL:-}" 2>/dev/null || true)"
# channel_value <game> <field>: a field of the channel file, or empty.
channel_value() {
  [ -n "$channel" ] || return 0
  printf '%s' "$channel" | python3 -c \
    'import json,sys; print((json.load(sys.stdin).get(sys.argv[1]) or {}).get(sys.argv[2]) or "")' \
    "$1" "$2" 2>/dev/null || true
}

ak_url="$(channel_value arknights url)"; ak_sha="$(channel_value arknights sha256)"
ef_url="$(channel_value endfield url)"; ef_sha="$(channel_value endfield sha256)"
fetch "${ak_url:-$GAMEDATA_DB_URL}" "${ak_sha:-$GAMEDATA_DB_SHA256}" build/gamedata_mobile/arklores_gamedata_zh.db
fetch "${ef_url:-${ENDFIELD_DB_URL:-}}" "${ef_sha:-${ENDFIELD_DB_SHA256:-}}" build/endfield/arklores_endfield_zh.db
