# Publishes an app-only pre-release from the current commit (Windows; GitHub
# REST with the PAT in the gitignored tools/github_pat, never printed).
# Linux / cloud: tools/release_app.sh. Same steps:
#   1. push HEAD to release/v<version> (android-release.yml builds and signs),
#   2. wait for the run and download the APK artifact,
#   3. create the pre-release v<version> with ArkLores-<version>.apk.
#
#   .\tools\release_app.ps1 -Version 0.10.4 -NotesFile notes.md
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$NotesFile
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Test-Path $NotesFile)) { throw "notes file not found: $NotesFile" }
if (-not (Select-String -Path pubspec.yaml -Pattern "^version: $([regex]::Escape($Version))\+" -Quiet)) {
  throw "pubspec.yaml version is not $Version"
}
if (git status --porcelain) { throw 'working tree is not clean' }

$pat = (Get-Content tools\github_pat -Raw).Trim()
$headers = @{ Authorization = "Bearer $pat"; Accept = 'application/vnd.github+json' }
$repo = 'https://api.github.com/repos/hhikr/ArkLores'
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$pat"))

$sha = (git rev-parse HEAD).Trim()
# Native git writes progress and "remote:" notes to stderr, which Windows
# PowerShell 5.1 turns into terminating errors under 'Stop': run git under
# 'Continue' and judge it by its exit code.
$ErrorActionPreference = 'Continue'
$remote = git -c "http.extraHeader=Authorization: Basic $basic" ls-remote origin "refs/heads/release/v$Version" 2> $null
$ErrorActionPreference = 'Stop'
$remoteSha = if ($remote) { ("$remote" -split '\s+')[0] } else { '' }
if ($remoteSha -and $remoteSha -ne $sha) {
  throw "release/v$Version already exists at $remoteSha (HEAD is $sha); re-pushing would rebuild the APK"
}
if ($remoteSha -eq $sha) {
  "release/v$Version already points at $sha; resuming without pushing"
} else {
  $ErrorActionPreference = 'Continue'
  git -c "http.extraHeader=Authorization: Basic $basic" push -q origin "HEAD:refs/heads/release/v$Version" 2> $null
  $pushed = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($pushed -ne 0) { throw 'push failed' }
  "pushed $sha to release/v$Version; waiting for the Android release run"
}

$run = $null
for ($i = 0; $i -lt 90 -and -not $run; $i++) {
  Start-Sleep 30
  try {
    $runs = Invoke-RestMethod -Headers $headers "$repo/actions/runs?head_sha=$sha"
  } catch { continue }  # transient network errors
  $r = $runs.workflow_runs | Where-Object { $_.path -like '*android-release.yml' } | Select-Object -First 1
  if ($r -and $r.status -eq 'completed') {
    if ($r.conclusion -ne 'success') { throw "run $($r.id) finished: $($r.conclusion)" }
    $run = $r
  }
}
if (-not $run) { throw 'timed out waiting for the run' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) "arklores_release_$Version"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory $tmp | Out-Null
$artifact = (Invoke-RestMethod -Headers $headers "$repo/actions/runs/$($run.id)/artifacts").artifacts |
  Where-Object { $_.name -eq 'arklores-apk' } | Select-Object -First 1
Invoke-WebRequest -Headers $headers -Uri $artifact.archive_download_url -OutFile "$tmp\apk.zip"
Expand-Archive "$tmp\apk.zip" "$tmp\apk"
$named = Join-Path $tmp "ArkLores-$Version.apk"
Copy-Item (Get-ChildItem "$tmp\apk" -Recurse -Filter *.apk | Select-Object -First 1).FullName $named
"APK: $((Get-Item $named).Length) bytes, SHA-256 $((Get-FileHash $named -Algorithm SHA256).Hash.ToLower())"

$body = @{
  tag_name = "v$Version"; target_commitish = $sha; name = "v$Version"
  body = [IO.File]::ReadAllText((Resolve-Path $NotesFile)); prerelease = $true; draft = $false
} | ConvertTo-Json
$release = Invoke-RestMethod -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' `
  -Uri "$repo/releases" -Body ([Text.Encoding]::UTF8.GetBytes($body))
$upload = $release.upload_url -replace '\{.*\}', ''
$asset = Invoke-RestMethod -Method Post -Headers $headers -ContentType 'application/vnd.android.package-archive' `
  -Uri "${upload}?name=ArkLores-$Version.apk" -InFile $named
"asset: $($asset.browser_download_url)"
$release.html_url
