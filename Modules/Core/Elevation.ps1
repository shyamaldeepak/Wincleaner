# Elevation.ps1 — admin-rights helpers. Win Clean runs as the invoking user
# by default; only the specific actions that truly need elevation (e.g. the
# Windows Update download cache) should call these, never the whole app.

function Test-WinCleanIsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-WinCleanElevated {
    <#
    .SYNOPSIS
    Relaunches the current script/command in an elevated PowerShell process.
    Returns $false without launching anything if the user declines the UAC
    prompt or it fails — callers must treat that as "skip this action", never
    as "proceed without elevation".
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )

    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = 'powershell.exe' }

    $quotedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"") + $ArgumentList

    try {
        Start-Process -FilePath $psExe -ArgumentList $quotedArgs -Verb RunAs -Wait
        return $true
    } catch {
        Write-Warning "Win Clean: elevation was declined or failed ($($_.Exception.Message)) — this action was skipped, not run without elevation."
        return $false
    }
}
