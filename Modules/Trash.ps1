# Trash.ps1 -- Dedicated Recycle Bin status and cleanup module.
# Exposes Recycle Bin metrics (item count, total size) and safe emptying.

function Get-WinCleanRecycleBinStatus {
    <#
    .SYNOPSIS
    Queries the Windows Recycle Bin for total item count and total bytes stored.
    Returns a PSCustomObject with Count and SizeBytes.
    #>
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.NameSpace(10) # 0xa = ssfBITBUCKET / Recycle Bin
        if (-not $recycleBin) {
            return [PSCustomObject]@{ Count = 0; SizeBytes = 0; IsAvailable = $false }
        }

        $items = $recycleBin.Items()
        $count = $items.Count
        $totalBytes = 0

        foreach ($item in $items) {
            try {
                $size = $item.Size
                if ($size) { $totalBytes += [long]$size }
            } catch {}
        }

        return [PSCustomObject]@{
            Count       = [int]$count
            SizeBytes   = [long]$totalBytes
            IsAvailable = $true
        }
    } catch {
        return [PSCustomObject]@{ Count = 0; SizeBytes = 0; IsAvailable = $false }
    }
}

function Clear-WinCleanRecycleBinSafely {
    <#
    .SYNOPSIS
    Empties the Windows Recycle Bin using Clear-RecycleBin cmdlet or COM.
    #>
    param([switch]$Force)

    try {
        if (Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue) {
            Clear-RecycleBin -Force:$Force -ErrorAction Stop
            Write-WinCleanLog -Action 'trash-empty' -Status 'ok' -Path 'RecycleBin'
            return $true
        } else {
            # Fallback for systems where Clear-RecycleBin isn't available
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.NameSpace(10)
            if ($recycleBin) {
                # EmptyRecycleBin flag constants: SHERB_NOCONFIRMATION = 0x00000001, SHERB_NOPROGRESSUI = 0x00000002, SHERB_NOSOUND = 0x00000004
                $flags = if ($Force) { 7 } else { 0 }
                # 0x0 = ssfBITBUCKET
                $recycleBin.Self.InvokeVerb('EmptyRecycleBin')
                Write-WinCleanLog -Action 'trash-empty' -Status 'ok' -Path 'RecycleBin'
                return $true
            }
        }
    } catch {
        Write-WinCleanLog -Action 'trash-empty' -Status 'error' -Detail $_.Exception.Message
        Write-Error "Win Clean: Failed to empty Recycle Bin ($($_.Exception.Message))"
        return $false
    }
    return $false
}

function Invoke-WinCleanTrash {
    <#
    .SYNOPSIS
    Displays Recycle Bin metrics and optionally empties the bin.
    #>
    param(
        [switch]$Empty,
        [switch]$Apply,
        [switch]$Json
    )

    $status = Get-WinCleanRecycleBinStatus

    if ($Json) {
        ConvertTo-Json -InputObject $status -Depth 2
        return
    }

    Write-Host ''
    Write-Host 'Win Clean — Recycle Bin Manager' -ForegroundColor Cyan
    Write-Host ''

    if (-not $status.IsAvailable) {
        Write-Host '  Recycle Bin status unavailable on this platform.' -ForegroundColor Yellow
        return
    }

    $sizeDisplay = Format-WinCleanBytes -Bytes $status.SizeBytes
    Write-Host ("  Current Recycle Bin contents: {0} item(s), {1} total size" -f $status.Count, $sizeDisplay) -ForegroundColor White
    Write-Host ''

    if ($Empty -or $Apply) {
        if ($status.Count -eq 0) {
            Write-Host '  Recycle Bin is already empty.' -ForegroundColor Green
            return
        }

        if (-not $Apply) {
            Write-Host ("  About to permanently empty {0} item(s) ({1}) from the Recycle Bin." -f $status.Count, $sizeDisplay) -ForegroundColor Yellow
            $confirm = Read-Host '  Are you sure? This cannot be undone. [y/N]'
            if ($confirm -ne 'y') {
                Write-Host '  Operation cancelled.' -ForegroundColor Gray
                return
            }
        }

        Write-Host '  Emptying Recycle Bin...' -ForegroundColor Cyan
        $ok = Clear-WinCleanRecycleBinSafely -Force
        if ($ok) {
            Write-Host '  [OK] Recycle Bin successfully emptied.' -ForegroundColor Green
        }
    } else {
        if ($status.Count -gt 0) {
            Write-Host '  Tip: Pass -Empty or -Apply to empty the Recycle Bin, or run "wc trash -Apply".' -ForegroundColor Gray
        } else {
            Write-Host '  Recycle Bin is clean.' -ForegroundColor Green
        }
    }
}
