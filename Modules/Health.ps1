# Health.ps1 -- Quick System Health Check, Score, and DNS Flush / Quick Optimize.

function Get-WinCleanHealthScore {
    <#
    .SYNOPSIS
    Calculates a overall System Health Score out of 100 based on disk space,
    RAM pressure, startup load, and temp junk accumulate.
    #>
    $score = 100
    $issues = @()
    $recommendations = @()

    # 1. Check System Drive Free Space
    try {
        $cDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($cDrive -and $cDrive.Size -gt 0) {
            $freeGB = [math]::Round($cDrive.FreeSpace / 1GB, 1)
            $freePct = [math]::Round(($cDrive.FreeSpace / $cDrive.Size) * 100, 1)
            if ($freePct -lt 10) {
                $score -= 25
                $issues += "Low disk space on C: ($freeGB GB free, $freePct%)"
                $recommendations += "Run 'wc clean -Apply' to free up disk space."
            } elseif ($freePct -lt 20) {
                $score -= 10
                $issues += "Moderate disk space on C: ($freeGB GB free, $freePct%)"
            }
        }
    } catch {}

    # 2. Check Memory Usage
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os -and $os.TotalVisibleMemorySize -gt 0) {
            $totalMB = $os.TotalVisibleMemorySize / 1KB
            $freeMB = $os.FreePhysicalMemory / 1KB
            $usedPct = [math]::Round((($totalMB - $freeMB) / $totalMB) * 100, 1)
            if ($usedPct -gt 85) {
                $score -= 20
                $issues += "High RAM usage ($usedPct% used)"
                $recommendations += "Use 'wc status' to inspect and close high-memory processes."
            } elseif ($usedPct -gt 75) {
                $score -= 10
                $issues += "Elevated RAM usage ($usedPct% used)"
            }
        }
    } catch {}

    # 3. Check Startup Apps Count
    try {
        $startupCount = @(Get-WinCleanStartupEntries).Count
        if ($startupCount -gt 12) {
            $score -= 15
            $issues += "High number of startup programs ($startupCount items)"
            $recommendations += "Review 'wc startup' items to reduce logon delay."
        } elseif ($startupCount -gt 8) {
            $score -= 5
            $issues += "Moderate number of startup programs ($startupCount items)"
        }
    } catch {}

    # Ensure score stays bounded between 0 and 100
    if ($score -lt 0) { $score = 0 }

    return [PSCustomObject]@{
        Score           = $score
        Issues          = $issues
        Recommendations = $recommendations
    }
}

function Invoke-WinCleanHealth {
    <#
    .SYNOPSIS
    Displays System Health Score, issues, recommendations, and allows quick
    DNS cache flushing.
    #>
    param([switch]$FlushDns)

    Write-Host ''
    Write-Host 'Win Clean -- System Health & Optimization' -ForegroundColor Cyan
    Write-Host ''

    Write-Host '  Evaluating system metrics...' -ForegroundColor Gray
    $health = Get-WinCleanHealthScore

    # Draw Health Bar
    $barLength = 20
    $filled = [math]::Round(($health.Score / 100) * $barLength)
    $unfilled = $barLength - $filled
    $bar = ('[' + ('=' * $filled) + ('.' * $unfilled) + ']')

    $color = if ($health.Score -ge 80) { 'Green' } elseif ($health.Score -ge 60) { 'Yellow' } else { 'Red' }
    $rating = if ($health.Score -ge 80) { 'EXCELLENT' } elseif ($health.Score -ge 60) { 'FAIR' } else { 'NEEDS ATTENTION' }

    Write-Host ("  Health Score: {0} {1}/100 ({2})" -f $bar, $health.Score, $rating) -ForegroundColor $color
    Write-Host ''

    if ($health.Issues.Count -eq 0) {
        Write-Host '  [OK] No major system resource bottlenecks detected.' -ForegroundColor Green
    } else {
        Write-Host '  Detected System Issues:' -ForegroundColor Yellow
        foreach ($issue in $health.Issues) {
            Write-Host ("   - {0}" -f $issue) -ForegroundColor DarkYellow
        }
    }

    if ($health.Recommendations.Count -gt 0) {
        Write-Host ''
        Write-Host '  Recommended Actions:' -ForegroundColor Cyan
        foreach ($rec in $health.Recommendations) {
            Write-Host ("   * {0}" -f $rec) -ForegroundColor White
        }
    }

    if ($FlushDns) {
        Write-Host ''
        Write-Host '  Flushing DNS Resolver Cache...' -ForegroundColor Cyan
        try {
            Clear-DnsClientCache -ErrorAction Stop
            Write-Host '  [OK] DNS Resolver Cache successfully flushed.' -ForegroundColor Green
        } catch {
            Write-Host ("  [WARN] Unable to flush DNS cache: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    } else {
        Write-Host ''
        Write-Host '  Tip: Pass -FlushDns to clear the Windows DNS resolver cache.' -ForegroundColor Gray
    }
}
