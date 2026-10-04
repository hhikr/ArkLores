#!/usr/bin/env bash
# Downloads the released knowledge base (URL and SHA-256 from
# tools/release_gamedata.env) to build/gamedata_mobile/arklores_gamedata_zh.db,
# the default DB of test/live/ask_pipeline_live_test.dart. Only the live
# tests need it; a few hundred MB.
set -euo pipefail
cd "$(dirname "$0")/../.."

# shellcheck disable=SC1091
source tools/release_gamedata.env
out=build/gamedata_mobile
db="$out/arklores_gamedata_zh.db"
gz="$out/arklores_gamedata_zh.db.gz"
mkdir -p "$out"

if [ -f "$db" ]; then
  echo "already present: $db"
  exit 0
fi

curl -fL --retry 3 -o "$gz" "$GAMEDATA_DB_URL"
actual="$(sha256sum "$gz" | awk '{print $1}')"
if [ "$actual" != "$GAMEDATA_DB_SHA256" ]; then
  echo "SHA-256 mismatch: got $actual, expected $GAMEDATA_DB_SHA256" >&2
  rm -f "$gz"
  exit 1
fi
gunzip -c "$gz" > "$db"
rm -f "$gz"
echo "ready: $db"
