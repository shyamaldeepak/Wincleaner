# Logging.ps1 — append-only forensic log for every delete/uninstall action,
# independent of console output: the log is the audit trail even if the
# terminal output scrolled away or was piped elsewhere.

function Get-WinCleanLogPath {
    # $env:LOCALAPPDATA is always set on real Windows; fall back for the
    # same reason Get-WinCleanProtectedRoots does — degrade instead of
    # crashing if the execution environment is stripped down.
    $base = $env:LOCALAPPDATA
    if (-not $base) {
        $base = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'AppData\Local' } else { [System.IO.Path]::GetTempPath() }
    }
    $dir = Join-Path $base 'WinClean\logs'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return Join-Path $dir 'operations.jsonl'
}

function Write-WinCleanLog {
    <#
    .SYNOPSIS
    Appends one JSON line to the operations log. Never throws — a broken log
    (read-only volume, missing directory permissions) must not block the
    actual cleanup/uninstall action; it prints a one-time warning instead.
    #>
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Status,
        [string]$Path,
        [Nullable[long]]$SizeBytes,
        [string]$Detail
    )

    $entry = [PSCustomObject]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        action    = $Action
        status    = $Status
        path      = $Path
        sizeBytes = $SizeBytes
        detail    = $Detail
    }

    try {
        $logPath = Get-WinCleanLogPath
        ($entry | ConvertTo-Json -Compress) | Add-Content -LiteralPath $logPath -Encoding utf8
    } catch {
        if (-not $script:WinCleanLogWarned) {
            Write-Warning "Win Clean: operations log is unwritable ($($_.Exception.Message)) — continuing without an audit trail for this run."
            $script:WinCleanLogWarned = $true
        }
    }
}
