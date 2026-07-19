# History.ps1 — read-only viewer for the operations log Logging.ps1 writes.
# Never writes to the log itself. A corrupt or partial line (e.g. the
# process was killed mid-write) is skipped rather than failing the whole
# read — the log is append-only forensic data, so one bad line shouldn't
# hide the rest of the history.

function Get-WinCleanHistory {
    param(
        [string]$Action,
        [string]$Status,
        [datetime]$Since,
        [int]$Last = 0
    )

    $logPath = Get-WinCleanLogPath
    if (-not (Test-Path -LiteralPath $logPath)) { return @() }

    $entries = foreach ($line in Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
    }
    $entries = @($entries)

    if ($Action) { $entries = @($entries | Where-Object { $_.action -eq $Action }) }
    if ($Status) { $entries = @($entries | Where-Object { $_.status -eq $Status }) }
    if ($PSBoundParameters.ContainsKey('Since')) {
        $entries = @($entries | Where-Object { try { [datetime]$_.timestamp -ge $Since } catch { $false } })
    }

    # ISO 8601 UTC ('o' format) timestamps sort correctly as plain strings —
    # no need to parse each one back into a [datetime] just to order them.
    $entries = @($entries | Sort-Object -Property timestamp -Descending)
    if ($Last -gt 0) { $entries = @($entries | Select-Object -First $Last) }
    return $entries
}

function Invoke-WinCleanHistory {
    param(
        [string]$Action,
        [string]$Status,
        [datetime]$Since,
        [int]$Last = 50,
        [switch]$Json
    )

    $params = @{ Last = $Last }
    if ($Action) { $params.Action = $Action }
    if ($Status) { $params.Status = $Status }
    if ($PSBoundParameters.ContainsKey('Since')) { $params.Since = $Since }

    $entries = @(Get-WinCleanHistory @params)

    if ($Json) {
        # -InputObject, not piped: piping an empty array into ConvertTo-Json
        # unrolls it to zero pipeline objects and produces NO output (not
        # "[]"), breaking any script parsing -Json when there's no matching
        # history.
        ConvertTo-Json -InputObject $entries -Depth 3
        return
    }

    Write-Host ''
    Write-Host 'Win Clean — history' -ForegroundColor Cyan
    Write-Host ''
    if ($entries.Count -eq 0) {
        Write-Host '  (no matching history entries)'
        return
    }
    $entries | Format-Table -Property `
        @{ Label = 'Time'; Expression = { $_.timestamp } }, `
        @{ Label = 'Action'; Expression = { $_.action } }, `
        @{ Label = 'Status'; Expression = { $_.status } }, `
        @{ Label = 'Size'; Expression = { Format-WinCleanBytes -Bytes $_.sizeBytes } }, `
        @{ Label = 'Path'; Expression = { $_.path } } -AutoSize
    Write-Host "  Full log: $(Get-WinCleanLogPath)"
}
