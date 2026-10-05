# Installs a locally built ArkLores APK on a phone connected by USB (adb), and
# can put a locally built knowledge base next to it. Nothing goes through
# GitHub.
#
#   .\tools\install_local.ps1                 # install the newest local APK
#   .\tools\install_local.ps1 -Kb             # ... and copy the knowledge base
#   .\tools\install_local.ps1 -Kb -KbOnly     # only the knowledge base
#   .\tools\install_local.ps1 -DryRun         # show what would happen
#
# The APK is build\local_release\ArkLores-*-local.apk, else the newest
# *.apk under build\ (the last `flutter build apk --release`). The knowledge
# base is build\gamedata_v5\arklores_gamedata_zh.db.gz.
#
# The knowledge base is copied as `arklores_gamedata_zh.db.download.gz` into
# the app's own folder on the phone. Open the app, Settings > Knowledge base,
# tap "Download": the app finds the file, checks its SHA-256 against the one
# built into the APK and installs it (no network needed). So the APK must have
# been built with this file's SHA (see tools/release_gamedata.env).
param(
  [string]$Apk,
  [string]$KbFile,
  [string]$Device,
  [switch]$Kb,
  [switch]$KbOnly,
  [switch]$NoLaunch,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$package = 'com.arklores.arklores'
$appDir = "/sdcard/Android/data/$package/files"
$kbName = 'arklores_gamedata_zh.db.download.gz'

# adb: PATH first, then the SDK installed for this project.
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) {
  $adb = 'C:\Users\hhikr\dev\android-sdk\platform-tools\adb.exe'
}
if (-not (Test-Path $adb)) { throw 'adb not found (install platform-tools or add adb to PATH)' }

function Adb {
  $all = @()
  if ($Device) { $all += @('-s', $Device) }
  $all += $args
  & $adb @all
  if ($LASTEXITCODE -ne 0) { throw "adb $($args -join ' ') failed ($LASTEXITCODE)" }
}

# A phone must be connected and authorised.
$lines = & $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() }
$ready = @($lines | Where-Object { $_ -match '\sdevice$' })
if ($Device) {
  if (-not ($ready | Where-Object { $_ -like "$Device*" })) { throw "device $Device is not connected" }
} elseif ($ready.Count -eq 0) {
  $why = if ($lines) { "found: $($lines -join '; ') (unlock the phone and allow USB debugging)" } else { 'no device: unlock the phone, pull the notification shade and set USB to file transfer (not charging only), check Developer options > USB debugging is on and accept the "allow USB debugging" prompt; then run `adb kill-server` and try again (an emulator such as MuMu may hold adb)' }
  throw $why
} elseif ($ready.Count -gt 1) {
  throw "several devices, choose one with -Device <serial>: $($ready -join '; ')"
}

# --- App ---
if (-not $KbOnly) {
  if (-not $Apk) {
    $found = Get-ChildItem build\local_release -Filter 'ArkLores-*-local.apk' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) {
      $found = Get-ChildItem build -Recurse -Filter '*.apk' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if (-not $found) { throw 'no APK found: run `flutter build apk --release` first, or pass -Apk <file>' }
    $Apk = $found.FullName
  }
  if (-not (Test-Path $Apk)) { throw "APK not found: $Apk" }
  $apkItem = Get-Item $Apk
  Write-Host ("APK: {0} ({1:N1} MB, {2})" -f $apkItem.Name, ($apkItem.Length / 1MB), $apkItem.LastWriteTime)
  if (-not $DryRun) {
    # -r keeps the app's data; an APK signed with another key cannot replace
    # the installed app (INSTALL_FAILED_UPDATE_INCOMPATIBLE): uninstall it first
    # (this deletes the app's data, including the knowledge base).
    Adb install -r $apkItem.FullName
    Write-Host 'installed.'
  }
}

# --- Knowledge base ---
if ($Kb -or $KbOnly) {
  if (-not $KbFile) { $KbFile = 'build\gamedata_v5\arklores_gamedata_zh.db.gz' }
  if (-not (Test-Path $KbFile)) { throw "knowledge base not found: $KbFile" }
  $kbItem = Get-Item $KbFile
  $sha = (Get-FileHash $kbItem.FullName -Algorithm SHA256).Hash.ToLower()
  Write-Host ("Knowledge base: {0} ({1:N1} MB)`n  SHA-256 {2}" -f $kbItem.Name, ($kbItem.Length / 1MB), $sha)
  $env = if (Test-Path tools\release_gamedata.env) { Get-Content tools\release_gamedata.env -Raw } else { '' }
  if ($env -notmatch [regex]::Escape($sha)) {
    Write-Warning 'this SHA-256 is not the one in tools/release_gamedata.env: an APK built from this tree will not accept the file.'
  }
  if (-not $DryRun) {
    Adb shell mkdir -p $appDir
    Adb push $kbItem.FullName "$appDir/$kbName"
    $size = (& $adb @(if ($Device) { '-s'; $Device }) shell stat -c %s "$appDir/$kbName").Trim()
    if ([int64]$size -ne $kbItem.Length) { throw "copy incomplete: $size of $($kbItem.Length) bytes on the phone" }
    Write-Host 'knowledge base copied. In the app: Settings > Knowledge base > Download (it installs the file without the network).'
  }
}

if ($DryRun) { Write-Host '(dry run: nothing was changed)'; return }
if (-not $NoLaunch -and -not $KbOnly) {
  Adb shell monkey -p $package -c android.intent.category.LAUNCHER 1 | Out-Null
}
