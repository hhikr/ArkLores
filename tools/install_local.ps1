# Installs a locally built ArkLores APK on a phone connected by USB (adb), and
# can put a locally built knowledge base next to it. Nothing goes through
# GitHub.
#
#   .\tools\install_local.ps1 -Build          # build the APK from this tree, then install
#   .\tools\install_local.ps1                 # install the newest local APK
#   .\tools\install_local.ps1 -Kb             # ... and copy the knowledge base
#   .\tools\install_local.ps1 -Kb -KbOnly     # only the knowledge base
#   .\tools\install_local.ps1 -Ef             # ... and the Endfield knowledge base
#   .\tools\install_local.ps1 -DryRun         # show what would happen
#
# The APK is build\local_release\ArkLores-*-local.apk, else the newest
# *.apk under build\ (the last `flutter build apk --release`). Without
# -Build nothing is compiled: an APK older than the last commit is reported.
# -Build runs `flutter build apk --release` with the knowledge base URL and
# SHA of tools/release_gamedata.env (as the release workflow does) and signs
# it with the release key (tools/arklores-release.jks +
# tools/android_signing.properties, never printed), so it updates an app
# installed from a release without uninstalling. The knowledge base is
# build\gamedata_v5\arklores_gamedata_zh.db.gz.
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
  [switch]$Build,
  [switch]$Kb,
  [switch]$KbOnly,
  # Also copy the Endfield knowledge base (build\endfield\arklores_endfield_zh.db.gz).
  [switch]$Ef,
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
  # Emulators (MuMu and the like listen on 127.0.0.1 or are called emulator-*)
  # are not the phone: when exactly one device is not one, that is it.
  $phones = @($ready | Where-Object { $_ -notmatch '^(127\.0\.0\.1|localhost|emulator-)' })
  if ($phones.Count -ne 1) {
    throw "several devices, choose one with -Device <serial>: $($ready -join '; ')"
  }
  $Device = ($phones[0] -split '\s+')[0]
  Write-Host "several devices; using the only non-emulator one: $Device"
}

# --- Build ---
if ($Build -and -not $KbOnly -and -not $Apk) {
  $envText = Get-Content tools\release_gamedata.env -Raw
  $url = [regex]::Match($envText, '(?m)^GAMEDATA_DB_URL=(\S+)').Groups[1].Value
  $sha = [regex]::Match($envText, '(?m)^GAMEDATA_DB_SHA256=(\S+)').Groups[1].Value
  if (-not $url -or -not $sha) { throw 'tools/release_gamedata.env has no GAMEDATA_DB_URL / GAMEDATA_DB_SHA256' }
  # Optional second game (0.12): absent until an Endfield asset exists.
  $efUrl = [regex]::Match($envText, '(?m)^ENDFIELD_DB_URL=(\S+)').Groups[1].Value
  $efSha = [regex]::Match($envText, '(?m)^ENDFIELD_DB_SHA256=(\S+)').Groups[1].Value
  $version = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([^+\s]+)').Groups[1].Value
  $out = "build\local_release\ArkLores-$version-local.apk"
  Write-Host "building $out (knowledge base SHA $($sha.Substring(0, 12))...)"
  # `flutter config --android-sdk/--jdk-dir` is stored per user profile and
  # may be missing in this shell: point Flutter at this machine's SDK and JDK
  # through the environment when nothing else is set.
  if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT -and (Test-Path 'C:\Users\hhikr\dev\android-sdk')) {
    $env:ANDROID_HOME = 'C:\Users\hhikr\dev\android-sdk'
  }
  if (-not $env:JAVA_HOME -and (Test-Path 'C:\Users\hhikr\dev\jdk-17')) {
    $env:JAVA_HOME = 'C:\Users\hhikr\dev\jdk-17'
  }
  if (-not $DryRun) {
    # Gradle and Flutter write warnings to stderr; only the exit code counts.
    $ErrorActionPreference = 'Continue'
    & flutter build apk --release "--dart-define=ARKLORES_GAMEDATA_DB_URL=$url" "--dart-define=ARKLORES_GAMEDATA_DB_SHA256=$sha" "--dart-define=ARKLORES_ENDFIELD_DB_URL=$efUrl" "--dart-define=ARKLORES_ENDFIELD_DB_SHA256=$efSha"
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
    New-Item -ItemType Directory -Force build\local_release | Out-Null
    $built = 'build\app\outputs\flutter-apk\app-release.apk'
    # Without android/key.properties the build is signed with the debug key;
    # re-sign it with the release key when it is here.
    $propsFile = 'tools\android_signing.properties'
    $sdk = 'C:\Users\hhikr\dev\android-sdk'
    $bt = Get-ChildItem "$sdk\build-tools" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    if ((Test-Path $propsFile) -and $bt) {
      $props = @{}
      Get-Content $propsFile | Where-Object { $_ -match '^\w+=' } | ForEach-Object { $k, $v = $_ -split '=', 2; $props[$k] = $v }
      $ks = $props['storeFile']
      if (-not $ks -or -not [IO.Path]::IsPathRooted($ks)) { $ks = Join-Path (Resolve-Path tools).Path ([IO.Path]::GetFileName("$ks")) }
      if (-not (Test-Path $ks)) { $ks = (Resolve-Path tools\arklores-release.jks).Path }
      if (-not $env:JAVA_HOME -and (Test-Path 'C:\Users\hhikr\dev\jdk-17')) { $env:JAVA_HOME = 'C:\Users\hhikr\dev\jdk-17' }
      $env:ARK_KSP = $props['storePassword']; $env:ARK_KEYP = $props['keyPassword']
      try {
        & "$($bt.FullName)\apksigner.bat" sign --ks $ks --ks-key-alias $props['keyAlias'] --ks-pass env:ARK_KSP --key-pass env:ARK_KEYP --out $out $built
        if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }
      } finally {
        Remove-Item Env:ARK_KSP, Env:ARK_KEYP -ErrorAction SilentlyContinue
      }
      Remove-Item "$out.idsig" -ErrorAction SilentlyContinue
      Write-Host 'signed with the release key.'
    } else {
      Copy-Item $built $out -Force
      Write-Warning 'release key not found: the APK keeps the debug signature and cannot update an app installed from a release.'
    }
    $ErrorActionPreference = 'Stop'
    $Apk = (Resolve-Path $out).Path
  }
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
  $lastCommit = [DateTimeOffset]::FromUnixTimeSeconds([int64](git log -1 --format=%ct)).LocalDateTime
  if (-not $Build -and $apkItem.LastWriteTime -lt $lastCommit) {
    Write-Warning ("this APK is older than the last commit ({0}): it does not have the latest changes. Run with -Build to build it from this tree." -f $lastCommit)
  }
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

# --- Endfield knowledge base (0.12) ---
if ($Ef) {
  $efFile = 'build\endfield\arklores_endfield_zh.db.gz'
  if (-not (Test-Path $efFile)) { throw "Endfield knowledge base not found: $efFile (run tools\unpack_endfield.ps1)" }
  $efItem = Get-Item $efFile
  $efSha = (Get-FileHash $efItem.FullName -Algorithm SHA256).Hash.ToLower()
  Write-Host ("Endfield knowledge base: {0:N1} MB, SHA-256 {1}" -f ($efItem.Length / 1MB), $efSha)
  $envText2 = if (Test-Path tools\release_gamedata.env) { Get-Content tools\release_gamedata.env -Raw } else { '' }
  if ($envText2 -notmatch [regex]::Escape($efSha)) {
    Write-Warning 'this SHA-256 is not ENDFIELD_DB_SHA256 in tools/release_gamedata.env: an APK built from this tree will not accept the file.'
  }
  if (-not $DryRun) {
    $efName = 'arklores_endfield_zh.db.download.gz'
    Adb shell mkdir -p $appDir
    Adb push $efItem.FullName "$appDir/$efName"
    Write-Host 'Endfield knowledge base copied. In the app: Settings > Knowledge base > Endfield > Download.'
  }
}

if ($DryRun) { Write-Host '(dry run: nothing was changed)'; return }
if (-not $NoLaunch -and -not $KbOnly) {
  Adb shell monkey -p $package -c android.intent.category.LAUNCHER 1 | Out-Null
}
