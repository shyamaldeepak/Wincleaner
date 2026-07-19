# Clean.ps1 — known-safe, rebuildable Windows storage. Each catalog entry
# names a directory whose CONTENTS get cleaned (not the directory itself,
# which Windows/apps expect to keep existing). Every entry is chosen because
# it is rebuildable/disposable — locally rebuildable, disposable, or backed
# by exact app/package evidence — this is a small, deliberately conservative
# catalog, not an attempt to cover everything Windows could theoretically
# clean.
#
# Safety default: Invoke-WinCleanClean ALWAYS previews and NEVER deletes
# unless called with -Apply. This is stricter than relying on PowerShell's
# ShouldProcess/-WhatIf defaults, which would delete on a bare call.

function Get-WinCleanCleanCatalog {
    $entries = @(
        [PSCustomObject]@{
            Name            = 'User Temp'
            Path            = $env:TEMP
            FilePattern     = '*'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Per-user temporary files left behind by installers and apps.'
        }
        [PSCustomObject]@{
            Name            = 'Windows Temp'
            Path            = (Join-Path $env:SystemRoot 'Temp')
            FilePattern     = '*'
            RequiresAdmin   = $true
            Enabled         = $true
            Description     = 'System-wide temporary files.'
        }
        [PSCustomObject]@{
            Name            = 'Internet Cache'
            Path            = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache')
            FilePattern     = '*'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Browser/system web cache (IE/Edge WebView2 shared cache).'
        }
        [PSCustomObject]@{
            Name            = 'Error Reporting Queue'
            Path            = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportQueue')
            FilePattern     = '*'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Queued crash reports waiting to be sent to Microsoft.'
        }
        [PSCustomObject]@{
            Name            = 'Error Reporting Archive'
            Path            = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive')
            FilePattern     = '*'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Already-sent crash reports kept for local reference.'
        }
        [PSCustomObject]@{
            Name            = 'Windows Update Download Cache'
            Path            = (Join-Path $env:SystemRoot 'SoftwareDistribution\Download')
            FilePattern     = '*'
            RequiresAdmin   = $true
            Enabled         = $true
            Description     = 'Downloaded update payloads Windows re-downloads on demand.'
        }
        [PSCustomObject]@{
            Name            = 'Thumbnail Cache'
            Path            = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer')
            FilePattern     = 'thumbcache_*.db'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Explorer thumbnail preview cache — rebuilds automatically, may cause a brief blank-thumbnail flash.'
        }
        [PSCustomObject]@{
            Name            = 'Prefetch'
            Path            = (Join-Path $env:SystemRoot 'Prefetch')
            FilePattern     = '*.pf'
            RequiresAdmin   = $true
            Enabled         = $false
            Description     = 'Launch-acceleration data — off by default; clearing it can slightly slow the next launch of each app while it rebuilds.'
        }
    )
    return $entries
}

function Get-WinCleanCleanPreview {
    param([switch]$IncludeDisabled)

    $isAdmin = Test-WinCleanIsAdmin
    $catalog = Get-WinCleanCleanCatalog

    foreach ($entry in $catalog) {
        if (-not $entry.Enabled -and -not $IncludeDisabled) { continue }
        if (-not $entry.Path -or -not (Test-Path -LiteralPath $entry.Path -PathType Container)) {
            continue
        }

        $files = @(Get-ChildItem -LiteralPath $entry.Path -Filter $entry.FilePattern -Force -ErrorAction SilentlyContinue)
        $totalSize = ($files | ForEach-Object {
            if ($_.PSIsContainer) {
                (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer } |
                    Measure-Object -Property Length -Sum).Sum
            } else {
                $_.Length
            }
        } | Measure-Object -Sum).Sum
        if ($null -eq $totalSize) { $totalSize = 0 }

        [PSCustomObject]@{
            Name          = $entry.Name
            Path          = $entry.Path
            ItemCount     = $files.Count
            SizeBytes     = [long]$totalSize
            RequiresAdmin = $entry.RequiresAdmin
            Skipped       = ($entry.RequiresAdmin -and -not $isAdmin)
            Enabled       = $entry.Enabled
            Description   = $entry.Description
            Files         = $files
        }
    }
}

function Invoke-WinCleanClean {
    param(
        [switch]$Apply,
        [switch]$IncludeDisabled,
        [switch]$Json
    )

    $preview = @(Get-WinCleanCleanPreview -IncludeDisabled:$IncludeDisabled)

    if ($Json) {
        $preview | Select-Object Name, Path, ItemCount, SizeBytes, RequiresAdmin, Skipped, Enabled, Description |
            ConvertTo-Json -Depth 3
        if (-not $Apply) { return }
    } elseif (-not $Apply) {
        Write-Host ''
        Write-Host 'Win Clean — clean preview (nothing deleted; pass -Apply to actually clean)' -ForegroundColor Cyan
        Write-Host ''
        foreach ($item in $preview) {
            $status = if ($item.Skipped) { ' [needs admin — re-run elevated]' } else { '' }
            Write-Host ('  {0,10}  {1,-28} {2} items{3}' -f (Format-WinCleanBytes -Bytes $item.SizeBytes), $item.Name, $item.ItemCount, $status)
        }
        $total = ($preview | Where-Object { -not $_.Skipped } | Measure-Object -Property SizeBytes -Sum).Sum
        if ($null -eq $total) { $total = 0 }
        Write-Host ''
        Write-Host ('  Reclaimable now: {0}' -f (Format-WinCleanBytes -Bytes ([long]$total)))
        return
    }

    foreach ($item in $preview) {
        if ($item.Skipped) {
            Write-Warning "Win Clean: skipping '$($item.Name)' — requires administrator, re-run elevated to include it."
            continue
        }
        foreach ($file in $item.Files) {
            Remove-WinCleanItem -Path $file.FullName -Confirm:$false | Out-Null
        }
    }

    if (-not $Json) {
        Write-Host "Win Clean: clean complete. See $(Get-WinCleanLogPath) for the full log." -ForegroundColor Green
    }
}
