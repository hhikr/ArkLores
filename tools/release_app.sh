#!/usr/bin/env bash
# Publishes an app-only release (pre-release unless STABLE=1) from the current commit (Linux / cloud,
# uses the gh CLI; in a cloud session gh authenticates through the GitHub
# proxy, no token needed). Windows: tools/release_app.ps1.
#
#   [STABLE=1] tools/release_app.sh <version> <notes.md>
#
# Before: bump pubspec.yaml (patch + build number), README, CLAUDE.md and
# CHANGELOG, commit and push the feature branch. This script then
#   1. pushes the commit to release/v<version> (triggers android-release.yml,
#      which builds and signs the APK and checks the certificate),
#   2. waits for that run, downloads the APK artifact,
#   3. creates the release v<version> with ArkLores-<version>.apk.
# release/v<version> must not exist yet: a second push rebuilds the APK and
# changes its hash.
set -euo pipefail
cd "$(dirname "$0")/.."

ver="${1:?usage: tools/release_app.sh <version> <notes.md>}"
notes="${2:?usage: tools/release_app.sh <version> <notes.md>}"
repo="hhikr/ArkLores"

[ -f "$notes" ] || { echo "notes file not found: $notes" >&2; exit 1; }
grep -q "^version: ${ver}+" pubspec.yaml \
  || { echo "pubspec.yaml version is not $ver" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] \
  || { echo "working tree is not clean" >&2; exit 1; }
if git ls-remote --exit-code origin "refs/heads/release/v$ver" >/dev/null 2>&1; then
  echo "release/v$ver already exists" >&2
  exit 1
fi

sha="$(git rev-parse HEAD)"
git push origin "HEAD:refs/heads/release/v$ver"
echo "pushed $sha to release/v$ver; waiting for the Android release run"

run=""
for _ in $(seq 1 90); do
  sleep 30
  read -r id status conclusion < <(gh run list -R "$repo" \
      --workflow android-release.yml --commit "$sha" --limit 1 \
      --json databaseId,status,conclusion \
      -q '.[0] | "\(.databaseId) \(.status) \(.conclusion)"' 2>/dev/null \
      || echo "- - -")
  if [ "$status" = "completed" ]; then
    [ "$conclusion" = "success" ] \
      || { echo "run $id finished: $conclusion" >&2; exit 1; }
    run="$id"
    break
  fi
done
[ -n "$run" ] || { echo "timed out waiting for the run" >&2; exit 1; }

tmp="$(mktemp -d)"
gh run download "$run" -R "$repo" -n arklores-apk -D "$tmp"
apk="$(find "$tmp" -name '*.apk' | head -n 1)"
named="$tmp/ArkLores-$ver.apk"
[ "$apk" = "$named" ] || mv "$apk" "$named"
echo "APK: $(stat -c %s "$named") bytes, SHA-256 $(sha256sum "$named" | awk '{print $1}')"

gh release create "v$ver" "$named" -R "$repo" --target "$sha" \
  --title "v$ver" ${STABLE:+--latest} ${STABLE:---prerelease} --notes-file "$notes"
echo "https://github.com/$repo/releases/tag/v$ver"
