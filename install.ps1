#Requires -Version 5.1
<#
.SYNOPSIS
Installs Win Clean into the current user's local Programs folder and adds it
to the user PATH so `winclean` works from any terminal (cmd.exe or
PowerShell). No admin rights required — this is a per-user install.
#>
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\WinClean')
)

$source = $PSScriptRoot

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$itemsToCopy = @('winclean.ps1', 'winclean.cmd', 'wc.cmd', 'WinClean.psd1', 'WinClean.psm1', 'LICENSE', 'Modules')
foreach ($item in $itemsToCopy) {
    Copy-Item -Path (Join-Path $source $item) -Destination $InstallDir -Recurse -Force
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
if ($userPath.Split(';') -notcontains $InstallDir) {
    $newPath = if ($userPath) { "$userPath;$InstallDir" } else { $InstallDir }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "Added $InstallDir to your user PATH."
}

# Update running session PATH immediately
if ($env:Path.Split(';') -notcontains $InstallDir) {
    $env:Path = "$InstallDir;$env:Path"
}

Write-Host ''
Write-Host "Win Clean installed to $InstallDir" -ForegroundColor Green
Write-Host "You can now run 'wc' or 'winclean' immediately in this session!" -ForegroundColor Cyan

