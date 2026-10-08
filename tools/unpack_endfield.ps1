# Unpacks the Endfield text data from the locally installed game client
# (never starts the game) and builds the Endfield knowledge base.
#
#   .\tools\unpack_endfield.ps1                       # unpack + build
#   .\tools\unpack_endfield.ps1 -SkipUnpack           # build from the last unpack
#   .\tools\unpack_endfield.ps1 -Version 1.2.0
#   .\tools\unpack_endfield.ps1 -SkipUnpack -Embed    # also story vectors (paid;
#                                                     # cached chunks are free)
#
# Needs the AnimeStudio CLI of Variante/endfield_research_kit (built by its
# setup.bat; see docs/GAMEDATA_BUILD_PIPELINE.md §9) and its .NET 9 runtime.
# Two blocks are dumped from both layers of the client: the game tables
# (`table`) and the JSON data (`json-data`, for the mission definitions).
# Persistent is the hot-update layer: its files replace StreamingAssets'.
# The dump is run without `--packed-game-store` (the kit's packed SQLite
# store hung on this machine; it only holds lip-sync data).
# The dialog trees (`dlg_…` TextAssets: the order of a conversation's lines
# and choices) and the clips of cutscene timelines (`DialogTrunkPlayableAsset`
# with each line's start time, `DialogOptionPlayableAsset`) are Unity
# objects, exported from each layer's asset bundles by name; each export
# reads every bundle (about 20 minutes for StreamingAssets) and is the slow
# step.
param(
  [string]$GameRoot = 'C:\Program Files\Hypergryph Launcher\games\Arknights Endfield\Endfield_Data',
  [string]$Kit = 'C:\Users\hhikr\endfield\kit',
  [string]$Work = 'C:\Users\hhikr\endfield\unpack',
  [string]$Version = 'unknown',
  [switch]$SkipUnpack,
  [switch]$Embed
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$exe = Join-Path $Kit 'tools\AnimeStudio\AnimeStudio.CLI\bin\Release\net9.0-windows\AnimeStudio.CLI.exe'
$env:DOTNET_ROOT = Join-Path $Kit 'tools\AnimeStudio\.dotnet'

function Dump($layer, $out) {
  if (Test-Path $out) { Remove-Item $out -Recurse -Force -Confirm:$false }
  $source = Join-Path $GameRoot $layer
  $dumpArgs = @('dump', '-s', "`"$source`"", '-o', "`"$out`"", '-b', 'table', '-b', 'json-data')
  if ($layer -eq 'Persistent') {
    $dumpArgs += @('--fallback-assets', "`"$(Join-Path $GameRoot 'StreamingAssets')`"")
  }
  $p = Start-Process $exe -ArgumentList $dumpArgs -PassThru -NoNewWindow -Wait `
    -RedirectStandardOutput "$out.log" -RedirectStandardError "$out.err"
  if ($p.ExitCode -ne 0) { throw "AnimeStudio dump of $layer failed ($($p.ExitCode)); see $out.log" }
  Get-Content "$out.log" -Tail 4
}

# Unity objects of one class whose names match, from one layer's bundles.
function UnityObjects($layer, $out, $type, $names, $exportType) {
  if (Test-Path $out) { Remove-Item $out -Recurse -Force -Confirm:$false }
  $source = Join-Path $GameRoot $layer
  $objectArgs = @("`"$source`"", "`"$out`"", '--game', 'ArknightsEndfield', '--types', $type,
    '--names', $names, '--export_type', $exportType, '--logger_flags', 'Warning,Error')
  $p = Start-Process $exe -ArgumentList $objectArgs -PassThru -NoNewWindow -Wait `
    -RedirectStandardOutput "$out.log" -RedirectStandardError "$out.err"
  if ($p.ExitCode -ne 0) { throw "AnimeStudio $type export of $layer failed ($($p.ExitCode)); see $out.log" }
  "${type} of ${layer}: $((Get-ChildItem $out -Recurse -File | Measure-Object).Count) files"
}

$tables = Join-Path $Work 'tables'
$missions = Join-Path $Work 'missions'
# Dialog trees (TextAsset) and the clips of cutscene timelines (the lines a
# cutscene shows with their start times, and the options bound to them).
$treeDirs = @((Join-Path $Work 'tree_sa'), (Join-Path $Work 'tree_persistent'))
$clipDirs = @((Join-Path $Work 'clips_sa'), (Join-Path $Work 'clips_persistent'))
# The mission panel's chapters (`ChapterInfo` objects: main story chapters and
# processes, operators' chapters, each with its missions in order).
$chapterDirs = @((Join-Path $Work 'chapters_sa'), (Join-Path $Work 'chapters_persistent'))
if (-not $SkipUnpack) {
  if (-not (Test-Path $exe)) { throw "AnimeStudio CLI not found: $exe (run the kit's setup.bat once)" }
  New-Item -ItemType Directory -Force $Work | Out-Null
  Dump 'StreamingAssets' (Join-Path $Work 'sa')
  Dump 'Persistent' (Join-Path $Work 'persistent')
  foreach ($i in 0, 1) {
    $layer = @('StreamingAssets', 'Persistent')[$i]
    UnityObjects $layer $treeDirs[$i] 'TextAsset' '^dlg_' 'Convert'
    UnityObjects $layer $clipDirs[$i] 'MonoBehaviour' '^Dialog(Trunk|Option)PlayableAsset' 'JSON'
    UnityObjects $layer $chapterDirs[$i] 'MonoBehaviour' '^(main_e\d+|chr_\d+_[a-z]+_e\d+)$' 'JSON'
  }
  foreach ($dir in $tables, $missions) {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -Confirm:$false }
    New-Item -ItemType Directory -Force $dir | Out-Null
  }
  # StreamingAssets first, then Persistent over it.
  foreach ($layer in 'sa', 'persistent') {
    Copy-Item (Join-Path $Work "$layer\Table\*") $tables -Force
    $m = Join-Path $Work "$layer\Data\Json\MissionRuntimeAsset"
    if (Test-Path $m) { Copy-Item "$m\*" $missions -Force }
  }
  "tables: $((Get-ChildItem $tables -File).Count), missions: $((Get-ChildItem $missions -File).Count)"
}

& dart run tools/build_endfield_database.dart "--tables=$tables" "--missions=$missions" "--trees=$($treeDirs -join ';')" "--clips=$($clipDirs -join ';')" "--chapters=$($chapterDirs -join ';')" "--version=$Version" --output=build/endfield --force
if ($LASTEXITCODE -ne 0) { throw 'build failed' }
# A rebuild has no vectors; the embedding cache (build/embedding_cache) makes
# unchanged chunks free, only new or changed text is paid for.
if ($Embed) {
  & dart run tools/build_story_embeddings.dart "--db=$((Resolve-Path 'build\endfield\arklores_endfield_zh.db').Path)"
  if ($LASTEXITCODE -ne 0) { throw 'embedding failed' }
}

# The release asset and its SHA-256 (for tools/release_gamedata.env).
$db = 'build\endfield\arklores_endfield_zh.db'
$in = [IO.File]::OpenRead((Resolve-Path $db))
$out = [IO.File]::Create((Join-Path (Get-Location) "$db.gz"))
$gz = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionLevel]::Optimal)
$in.CopyTo($gz); $gz.Dispose(); $in.Dispose(); $out.Dispose()
$sha = (Get-FileHash "$db.gz" -Algorithm SHA256).Hash.ToLower()
"$db.gz: {0:N1} MB, SHA-256 $sha" -f ((Get-Item "$db.gz").Length / 1MB)
$envFile = 'tools\release_gamedata.env'
$envText = [IO.File]::ReadAllText((Resolve-Path $envFile))
[IO.File]::WriteAllText((Resolve-Path $envFile), ($envText -replace 'ENDFIELD_DB_SHA256=\w*', "ENDFIELD_DB_SHA256=$sha"))
"ENDFIELD_DB_SHA256 in $envFile updated (an APK built from this tree accepts this file)."
