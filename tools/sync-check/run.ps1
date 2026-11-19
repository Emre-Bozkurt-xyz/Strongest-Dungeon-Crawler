# Disk half of the Studio sync check.
#   .\tools\sync-check\run.ps1          generate a manifest, wait for Rojo to deliver it, print the Studio snippet
#   .\tools\sync-check\run.ps1 clean    delete every manifest this tool created
param(
	[ValidateSet("check", "clean")] [string]$Mode = "check",
	[int]$WaitSeconds = 4
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "node is required (not found on PATH)" }

if ($Mode -eq "clean") {
	node "$here\manifest.js" clean
	exit 0
}

# Drop manifests from earlier runs so Studio only ever sees the new one.
node "$here\manifest.js" clean
node "$here\manifest.js" generate
$rojo = node "$here\manifest.js" rojo
if ($rojo -ne "up") { Write-Host "WARNING: nothing answers on Rojo's default port 34872; is 'rojo serve' running?" -ForegroundColor Yellow }
Write-Host "waiting $WaitSeconds s for Rojo to deliver the manifest..."
Start-Sleep -Seconds $WaitSeconds
Write-Host ""
Write-Host "Run in Studio's command bar (Edit mode), then run '.\tools\sync-check\run.ps1 clean':"
Write-Host 'require(game.ServerScriptService.Server.dev.SyncCheck).run()'
Write-Host "(If it says no manifest was found, Rojo is not delivering: reconnect the plugin or restart Studio.)"
