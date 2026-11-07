# Lands a reviewed task on main as ONE action: merge the reviewed commit into
# the primary checkout, validate the merged tree, push main, then release-deploy
# it to the local game clients. It publishes nothing outside the dev repo; the
# public channels are dev/Publish.ps1, a separate step.
#
# The logic is shared by every addon: Land-WowAddon.ps1 in the wow-addon skill's
# scripts directory (its header documents all behaviour and dev/land.json). What is
# specific to CastQueueOverlay lives in dev/land.json next to this file: the checks (lint and the offline UI test), the client
# (retail) and the branch.
#
# Run it only through the workflow wrapper, after `review` recorded a receipt:
#   python agent_workflow.py run-integration --repo <primary checkout> --session <id> -- \
#     powershell.exe -NoProfile -File <task worktree>\dev\Land.ps1 -SessionId <id> -Validation '<what was checked>'
# Parameters pass straight through: -SessionId -Validation -AddonsDirs -SkipDeploy.
# WOW_LAND_SCRIPT, when set, names another copy of the shared script (an unlanded
# change to it, under test).

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)][string]$SessionId,
    [Parameter(Mandatory)][string]$Validation,
    [string[]]$AddonsDirs,
    [switch]$SkipDeploy
)

$ErrorActionPreference = "Stop"
$ref = (Get-Item "$HOME\.claude\skills\wow-addon").Target | Split-Path | Split-Path
$shared = if ($env:WOW_LAND_SCRIPT) { $env:WOW_LAND_SCRIPT } else { Join-Path $ref "scripts\Land-WowAddon.ps1" }
if (-not (Test-Path -LiteralPath $shared)) { throw "shared landing script not found: $shared" }

$forward = @{ Source = (Split-Path -Parent $PSScriptRoot) }
foreach ($key in $PSBoundParameters.Keys) { $forward[$key] = $PSBoundParameters[$key] }
& $shared @forward
