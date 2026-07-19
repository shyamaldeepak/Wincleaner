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
    # $env:SystemRoot / $env:LOCALAPPDATA are empty on non-Windows hosts
    # (this project is developed/tested on macOS — see CLAUDE.md), and
    # Join-Path throws a ParameterBindingValidationException on a null Path
    # argument instead of degrading gracefully — this crashed the entire
    # catalog (and therefore every 'clean' invocation) on any non-Windows
    # host before Clean.ps1 had any test coverage to catch it. Compute
    # fallbacks once, matching the pattern Get-WinCleanProtectedRoots
    # (Safety.ps1) and Get-WinCleanLogPath (Logging.ps1) already use.
    #
    # $systemRoot entries below use string concatenation, not Join-Path,
    # for the same reason CLAUDE.md documents for Safety.ps1: Join-Path
    # against ANY "C:\..." path — not just a bare "C:" — throws "Cannot
    # find drive" wherever no live PSDrive named "C" exists, which is
    # always true on non-Windows and can be true in constrained Windows
    # environments too.
    $systemDrive = $env:SystemDrive
    if (-not $systemDrive) { $systemDrive = 'C:' }
    $systemRoot = $env:SystemRoot
    if (-not $systemRoot) { $systemRoot = "$systemDrive\Windows" }
    $localAppData = $env:LOCALAPPDATA
    if (-not $localAppData) {
        $localAppData = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'AppData\Local' } else { [System.IO.Path]::GetTempPath() }
    }

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
            Path            = "$systemRoot\Temp"
            FilePattern     = '*'
            RequiresAdmin   = $true
            Enabled         = $true
            Description     = 'System-wide temporary files.'
        }
        [PSCustomObject]@{
            Name            = 'Internet Cache'
            Path            = (Join-Path $localAppData 'Microsoft\Windows\INetCache')
            FilePattern     = '*'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Browser/system web cache (IE/Edge WebView2 shared cache).'
        }
        [PSCustomObject]@{
            Name            = 'Error Reporting Queue'
            Path            = (Join-Path $localAppData 'Microsoft\Windows\WER\ReportQueue')
            FilePattern     = '*'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Queued crash reports waiting to be sent to Microsoft.'
        }
        [PSCustomObject]@{
            Name            = 'Error Reporting Archive'
            Path            = (Join-Path $localAppData 'Microsoft\Windows\WER\ReportArchive')
            FilePattern     = '*'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Already-sent crash reports kept for local reference.'
        }
        [PSCustomObject]@{
            Name            = 'Windows Update Download Cache'
            Path            = "$systemRoot\SoftwareDistribution\Download"
            FilePattern     = '*'
            RequiresAdmin   = $true
            Enabled         = $true
            Description     = 'Downloaded update payloads Windows re-downloads on demand.'
        }
        [PSCustomObject]@{
            Name            = 'Thumbnail Cache'
            Path            = (Join-Path $localAppData 'Microsoft\Windows\Explorer')
            FilePattern     = 'thumbcache_*.db'
            RequiresAdmin   = $false
            Enabled         = $true
            Description     = 'Explorer thumbnail preview cache — rebuilds automatically, may cause a brief blank-thumbnail flash.'
        }
        [PSCustomObject]@{
            Name            = 'Prefetch'
            Path            = "$systemRoot\Prefetch"
            FilePattern     = '*.pf'
            RequiresAdmin   = $true
            Enabled         = $false
            Description     = 'Launch-acceleration data — off by default; clearing it can slightly slow the next launch of each app while it rebuilds.'
        }
    )
    return $entries
}

function Get-WinCleanRecycleBinPreview {
    <#
    .SYNOPSIS
    Reports current Recycle Bin contents without touching them. Uses the
    Shell.Application COM object — the same API Explorer's own "Empty
    Recycle Bin" uses — rather than enumerating $Recycle.Bin on disk, which
    is a protected root (Get-WinCleanProtectedRoots) that Win Clean
    deliberately never reads or writes directly: its on-disk layout
    (per-SID subfolders, paired $I../$R.. bookkeeping files) is opaque OS
    internals, not a directory a general-purpose scan should parse. Never
    throws — reports Available = $false on any host without the Shell COM
    object (e.g. non-Windows, where this project is developed/tested).
    #>
    try {
        $shell = New-Object -ComObject Shell.Application -ErrorAction Stop
        $bin = $shell.Namespace(0xA)
        if (-not $bin) { return [PSCustomObject]@{ ItemCount = 0; SizeBytes = 0L; Available = $false } }
        $items = @($bin.Items())
        $size = ($items | ForEach-Object { [long]$_.Size } | Measure-Object -Sum).Sum
        if ($null -eq $size) { $size = 0L }
        return [PSCustomObject]@{ ItemCount = $items.Count; SizeBytes = [long]$size; Available = $true }
    } catch {
        return [PSCustomObject]@{ ItemCount = 0; SizeBytes = 0L; Available = $false }
    }
}

function Clear-WinCleanRecycleBin {
    <#
    .SYNOPSIS
    Empties the Recycle Bin via the built-in Clear-RecycleBin cmdlet.
    Deliberately does NOT go through Remove-WinCleanItem /
    Test-WinCleanPathSafeToDelete: those gate a caller-supplied filesystem
    path, and this action takes none — Clear-RecycleBin operates on the
    OS's own Recycle Bin bookkeeping for a fixed set of drives, the same
    mechanism Explorer's own "Empty Recycle Bin" menu item uses. This is
    irreversible by definition (there is no further trash to fall back to,
    unlike a normal Remove-WinCleanItem call), so it only ever runs behind
    Invoke-WinCleanClean's own -Apply gate — never implicitly.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param()

    if (-not (Get-Command -Name Clear-RecycleBin -ErrorAction SilentlyContinue)) {
        Write-WinCleanLog -Action 'empty-recycle-bin' -Status 'unavailable' -Detail 'Clear-RecycleBin cmdlet not present on this host'
        return $false
    }

    $before = Get-WinCleanRecycleBinPreview
    if (-not $PSCmdlet.ShouldProcess('Recycle Bin', 'Empty')) {
        Write-WinCleanLog -Action 'empty-recycle-bin' -Status 'dry-run' -SizeBytes $before.SizeBytes
        return $true
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-WinCleanLog -Action 'empty-recycle-bin' -Status 'ok' -SizeBytes $before.SizeBytes
        return $true
    } catch {
        Write-WinCleanLog -Action 'empty-recycle-bin' -Status 'error' -SizeBytes $before.SizeBytes -Detail $_.Exception.Message
        Write-Error "Win Clean failed to empty the Recycle Bin: $($_.Exception.Message)"
        return $false
    }
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

    # Recycle Bin is opt-in only (Enabled = $false), same as Prefetch above:
    # emptying it is the one entry in this catalog that is genuinely
    # irreversible (every other entry moves TO the Recycle Bin; this empties
    # it), so it never appears — and never gets applied — without
    # -IncludeDisabled making that an explicit choice.
    if ($IncludeDisabled) {
        $binPreview = Get-WinCleanRecycleBinPreview
        if ($binPreview.Available) {
            [PSCustomObject]@{
                Name          = 'Recycle Bin'
                Path          = $null
                ItemCount     = $binPreview.ItemCount
                SizeBytes     = $binPreview.SizeBytes
                RequiresAdmin = $false
                Skipped       = $false
                Enabled       = $false
                Description   = 'Already-deleted files waiting in the Recycle Bin. Emptying is permanent — there is no further trash to recover from.'
                Files         = @()
                IsRecycleBin  = $true
            }
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
        # ConvertTo-Json -InputObject (not piped): piping an empty array into
        # ConvertTo-Json unrolls it to zero pipeline objects and produces NO
        # output at all (not "[]"), which breaks any script parsing -Json
        # output on a legitimately-empty result (e.g. nothing to clean).
        # -InputObject passes the array as a single argument instead, so an
        # empty result still serializes to "[]".
        $selected = @($preview | Select-Object Name, Path, ItemCount, SizeBytes, RequiresAdmin, Skipped, Enabled, Description)
        ConvertTo-Json -InputObject $selected -Depth 3
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
        if ($item.IsRecycleBin) {
            Clear-WinCleanRecycleBin -Confirm:$false | Out-Null
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
