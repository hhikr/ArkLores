# Publishes official knowledge bases in place on the fixed `gamedata-channel`
# Release, the one place every app (v0.14.5 on) checks for knowledge bases.
# GitHub REST with the PAT in the gitignored tools/github_pat, never printed.
#
#   1. tools/release_gamedata.env: the new SHA-256 (and commit / date / min build);
#      the URLs stay gamedata-channel/<file>.
#   2. .\tools\publish_gamedata.ps1 -Files build\gamedata_rebuild\arklores_gamedata_zh.db.gz,build\gamedata_rebuild\gamedata_manifest.json
#      Each file is uploaded as <name>.new, the old asset deleted and the new one
#      renamed, so the old file is gone only for that moment. The channel file is
#      written from the env (tools/write_gamedata_channel.dart) and replaced last,
#      after the knowledge bases it points at are in place.
#   -ChannelOnly: only rewrite and replace the channel file.
param(
  [string[]]$Files = @(),
  [switch]$ChannelOnly,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$pat = (Get-Content tools\github_pat -Raw).Trim()
$headers = @{ Authorization = "Bearer $pat"; Accept = 'application/vnd.github+json' }
$repo = 'https://api.github.com/repos/hhikr/ArkLores'
$release = Invoke-RestMethod -Headers $headers "$repo/releases/tags/gamedata-channel"
$upload = $release.upload_url -replace '\{.*\}', ''

function Replace-Asset([string]$path) {
  $name = Split-Path $path -Leaf
  $sha = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
  if ($DryRun) { "would replace $name ($sha)"; return }
  $type = if ($name -like '*.gz') { 'application/gzip' } else { 'application/json' }
  $fresh = Invoke-RestMethod -Method Post -Headers $headers -ContentType $type `
    -Uri "${upload}?name=$name.new" -InFile $path -TimeoutSec 3600
  if ($fresh.digest -and $fresh.digest -ne "sha256:$sha") { throw "$name uploaded as $($fresh.digest), expected $sha" }
  $assets = (Invoke-RestMethod -Headers $headers "$repo/releases/$($release.id)/assets?per_page=100")
  foreach ($old in $assets | Where-Object { $_.name -eq $name }) {
    Invoke-RestMethod -Method Delete -Headers $headers "$repo/releases/assets/$($old.id)" | Out-Null
  }
  $body = @{ name = $name } | ConvertTo-Json
  Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json' `
    -Uri "$repo/releases/assets/$($fresh.id)" -Body $body | Out-Null
  "replaced $name ($sha)"
}

if (-not $ChannelOnly) {
  foreach ($file in $Files) {
    if (-not (Test-Path $file)) { throw "not found: $file" }
    Replace-Asset (Resolve-Path $file).Path
  }
}
dart run tools/write_gamedata_channel.dart
Replace-Asset (Resolve-Path build\gamedata_channel.json).Path
