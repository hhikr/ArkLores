#!/usr/bin/env bash
# Downloads the released knowledge bases (URLs and SHA-256 from
# tools/release_gamedata.env): Arknights to
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

fetch "$GAMEDATA_DB_URL" "$GAMEDATA_DB_SHA256" build/gamedata_mobile/arklores_gamedata_zh.db
fetch "${ENDFIELD_DB_URL:-}" "${ENDFIELD_DB_SHA256:-}" build/endfield/arklores_endfield_zh.db
