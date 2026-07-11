# new-project.ps1 — thin Windows wrapper (D-20). All logic lives in new-project.sh;
# this just forwards the invocation into WSL2, the canonical dev environment.
#
# Usage (from PowerShell):
#   .\new-project.ps1 my-worker --template cf-worker-app --visibility public
#Requires -Version 7
$ErrorActionPreference = 'Stop'

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
  Write-Error 'WSL2 is required (D-20). Install it: wsl --install'
  exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wslPath = & wsl wslpath -a ($scriptDir -replace '\\', '/')
$wslPath = "$($wslPath.Trim())/new-project.sh"

# Forward every argument verbatim to the bash script under WSL2.
& wsl bash "$wslPath" @args
exit $LASTEXITCODE
