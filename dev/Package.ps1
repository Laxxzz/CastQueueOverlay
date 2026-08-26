# Builds a distributable zip of the addon.
#
# This is a LOCAL PREVIEW of what the CI release produces. Real releases go out
# through .github/workflows/release.yml on an annotated tag push, which runs
# BigWigsMods/packager and uploads to CurseForge - this script does not publish
# anything. Use it to check what a release would contain before tagging one, or
# to hand a build to a tester.
#
# Three things it gets deliberately right, each of which has broken an addon zip
# before:
#
#   * ONE top-level CastQueueOverlay folder. A flat zip scatters loose Lua files
#     into Interface\AddOns; a doubly-nested one produces
#     AddOns\CastQueueOverlay\CastQueueOverlay, which the client ignores in
#     silence.
#   * FORWARD-SLASH entry paths, written through the .NET ZipArchive API.
#     PowerShell's Compress-Archive writes backslashes, and macOS extracts such
#     an archive as a single file with a mangled name.
#   * art\ is included even though it is in no .toc. Textures are loaded on
#     demand by path, so a zip built from the .toc alone hands someone an addon
#     whose rounded corners silently degrade to square.
#
# The Lua file list comes from the .toc, so it cannot drift from what the client
# actually loads.

param(
    [string]$OutDir = (Split-Path -Parent $PSScriptRoot),
    # Keep zips for older versions instead of removing them.
    [switch]$KeepOld
)

$ErrorActionPreference = "Stop"
$src  = Split-Path -Parent $PSScriptRoot
$name = "CastQueueOverlay"

$toc = Join-Path $src "$name.toc"
if (-not (Test-Path $toc)) { throw "No $name.toc in $src" }

$version = (Select-String -Path $toc -Pattern '^##\s*Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()

# Everything the client loads, plus the .toc itself.
$files = @("$name.toc")
$files += Get-Content $toc | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) { $line }
}

# Art is referenced by path from the style file, never listed in a .toc.
$artDir = Join-Path $src "art"
if (Test-Path $artDir) {
    $files += @(Get-ChildItem $artDir -File | ForEach-Object { "art\$($_.Name)" })
}

# Everything else is excluded, matching .pkgmeta's ignore list - so this zip is a
# faithful preview of the CurseForge build rather than a second opinion about
# what ships. README, LICENSE and CHANGELOG live on the project page there.

Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

$zip = Join-Path $OutDir "$name-$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $written = 0
    foreach ($rel in $files) {
        $from = Join-Path $src $rel
        if (-not (Test-Path $from)) {
            Write-Host "  missing, skipped: $rel" -ForegroundColor Yellow
            continue
        }
        # The entry name, not the source path, decides the layout inside the zip.
        # Forward slashes throughout, under one top-level folder.
        $entry = "$name/" + ($rel -replace '\\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, (Get-Item $from).FullName, $entry,
            [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        $written++
    }
} finally {
    $archive.Dispose()
}

# Older versions are removed, not kept.
#
# The point is that there is exactly one zip and it is the current build. A
# directory holding four versions is how someone hands a tester last week's build
# and then spends an evening on a bug that was already fixed - the filename is
# the only thing telling them apart, and nobody reads it carefully.
#
# Safe to do automatically because nothing is lost: every version's SOURCE is in
# git history, so any old build can be rebuilt from a checkout. Deletions are
# printed rather than done silently.
if (-not $KeepOld) {
    Get-ChildItem -Path $OutDir -Filter "$name-*.zip" -File |
        Where-Object { $_.FullName -ne $zip } |
        ForEach-Object {
            Write-Host "  removed stale build: $($_.Name)" -ForegroundColor DarkGray
            Remove-Item $_.FullName -Force
        }
}

$size = [math]::Round((Get-Item $zip).Length / 1KB, 1)
Write-Host ""
Write-Host "Built $zip  ($size KB)" -ForegroundColor Green
Write-Host "Contains $written file(s). Extract into Interface\AddOns." -ForegroundColor Cyan
Write-Host ""
Write-Host "This does NOT publish. To release:" -ForegroundColor DarkGray
Write-Host "  git tag -a v$version -m `"v$version`" && git push origin v$version" -ForegroundColor DarkGray
