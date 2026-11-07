# Publishes the current build as ONE action: the filtered public mirror of this repo
# (agent files stripped), a GitHub release on it, and CurseForge, all with the same zip.
#
# The logic is shared by every addon: Publish-WowAddon.ps1 in the wow-addon skill's
# scripts directory (its header documents all behaviour and parameters). What is
# specific to CastQueueOverlay lives in dev/publish.json next to this file: the public
# repo, the packager (dev/Package.ps1) and the zip checks.
#
# Run from the primary checkout at the published main commit; it publishes, so only
# with the user's go-ahead. Parameters pass straight through: -Repo -Notes -Only
# -CurseId -WagoId -WowiId -Replace -Unlanded -DryRun. WOW_PUBLISHER_SCRIPT, when set,
# names another copy of the shared script (an unlanded change to it, under test).

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Repo,
    [string]$Notes,
    [ValidateSet("mirror", "github", "wago", "curse", "wowi", "discord")]
    [string[]]$Only,
    [string]$CurseId,
    [string]$WagoId,
    [string]$WowiId,
    [switch]$Replace,
    [switch]$Unlanded,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ref = (Get-Item "$HOME\.claude\skills\wow-addon").Target | Split-Path | Split-Path
$shared = if ($env:WOW_PUBLISHER_SCRIPT) { $env:WOW_PUBLISHER_SCRIPT } else { Join-Path $ref "scripts\Publish-WowAddon.ps1" }
if (-not (Test-Path -LiteralPath $shared)) { throw "shared publisher not found: $shared" }

$forward = @{ Source = (Split-Path -Parent $PSScriptRoot) }
foreach ($key in $PSBoundParameters.Keys) { $forward[$key] = $PSBoundParameters[$key] }
& $shared @forward
