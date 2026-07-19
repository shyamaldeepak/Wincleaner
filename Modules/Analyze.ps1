# Analyze.ps1 — disk usage scan, sorted largest -> smallest, with an
# interactive keyboard drill-down and in-place delete. Delete always routes
# through Remove-WinCleanItem (Core/Remove-Safely.ps1) — nothing here calls
# Remove-Item directly.

function Get-WinCleanChildSizes {
    <#
    .SYNOPSIS
    Returns the immediate children of Path (files and directories) with
    their total size, sorted descending. Directory sizes are computed
    recursively; unreadable subtrees are skipped rather than failing the
    whole scan — degrade to partial output, never hang.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $children = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $children) { return @() }

    $useParallel = $PSVersionTable.PSVersion.Major -ge 7

    if ($useParallel) {
        $results = $children | ForEach-Object -Parallel {
            $item = $_
            $size = 0
            try {
                if ($item.PSIsContainer) {
                    $sum = (Get-ChildItem -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { -not $_.PSIsContainer } |
                        Measure-Object -Property Length -Sum).Sum
                    $size = if ($null -eq $sum) { 0 } else { [long]$sum }
                } else {
                    $size = $item.Length
                }
            } catch {
                $size = 0
            }
            [PSCustomObject]@{
                Name      = $item.Name
                FullPath  = $item.FullName
                IsDir     = [bool]$item.PSIsContainer
                SizeBytes = $size
            }
        } -ThrottleLimit 8
    } else {
        $results = foreach ($item in $children) {
            $size = 0
            try {
                if ($item.PSIsContainer) {
                    $sum = (Get-ChildItem -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { -not $_.PSIsContainer } |
                        Measure-Object -Property Length -Sum).Sum
                    $size = if ($null -eq $sum) { 0 } else { [long]$sum }
                } else {
                    $size = $item.Length
                }
            } catch {
                $size = 0
            }
            [PSCustomObject]@{
                Name      = $item.Name
                FullPath  = $item.FullName
                IsDir     = [bool]$item.PSIsContainer
                SizeBytes = $size
            }
        }
    }

    return @($results | Sort-Object -Property SizeBytes -Descending)
}

function Show-WinCleanAnalyzeTable {
    param(
        [Parameter(Mandatory)][string]$CurrentPath,
        [Parameter(Mandatory)][array]$Items,
        [int]$SelectedIndex = 0
    )

    Clear-Host
    Write-Host "Win Clean — analyze: $CurrentPath" -ForegroundColor Cyan
    Write-Host '  Up/Down move, Enter open folder, Backspace go up, d delete, q quit' -ForegroundColor DarkGray
    Write-Host ''

    if ($Items.Count -eq 0) {
        Write-Host '  (empty)'
        return
    }

    $maxSize = ($Items | Measure-Object -Property SizeBytes -Maximum).Maximum
    if (-not $maxSize -or $maxSize -le 0) { $maxSize = 1 }

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        $barLength = [math]::Round(($item.SizeBytes / $maxSize) * 24)
        $bar = ('#' * $barLength).PadRight(24)
        $sizeStr = (Format-WinCleanBytes -Bytes $item.SizeBytes).PadLeft(10)
        $marker = if ($item.IsDir) { '/' } else { ' ' }
        $line = "  {0} {1} {2}{3}" -f $sizeStr, $bar, $item.Name, $marker

        if ($i -eq $SelectedIndex) {
            Write-Host $line -ForegroundColor Black -BackgroundColor White
        } else {
            Write-Host $line
        }
    }
}

function Invoke-WinCleanAnalyze {
    param(
        [string]$Path = (Get-Location).Path,
        [int]$Top = 25,
        [switch]$Json,
        [switch]$NonInteractive
    )

    $resolvedPath = try { [System.IO.Path]::GetFullPath($Path) } catch { $null }
    if (-not $resolvedPath -or -not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
        Write-Error "Win Clean: '$Path' is not a directory."
        return
    }

    if ($Json -or $NonInteractive -or -not [Environment]::UserInteractive) {
        $items = Get-WinCleanChildSizes -Path $resolvedPath | Select-Object -First $Top
        if ($Json) {
            $items | ConvertTo-Json -Depth 3
        } else {
            $items | Format-Table -Property @{ L = 'Size'; E = { Format-WinCleanBytes -Bytes $_.SizeBytes } }, Name, FullPath -AutoSize
        }
        return
    }

    $currentPath = $resolvedPath
    $items = @(Get-WinCleanChildSizes -Path $currentPath | Select-Object -First $Top)
    $selected = 0

    while ($true) {
        Show-WinCleanAnalyzeTable -CurrentPath $currentPath -Items $items -SelectedIndex $selected
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        switch ($key.VirtualKeyCode) {
            38 { if ($selected -gt 0) { $selected-- } }               # Up
            40 { if ($selected -lt $items.Count - 1) { $selected++ } } # Down
            13 {                                                        # Enter
                if ($items.Count -gt 0 -and $items[$selected].IsDir) {
                    $currentPath = $items[$selected].FullPath
                    $items = @(Get-WinCleanChildSizes -Path $currentPath | Select-Object -First $Top)
                    $selected = 0
                }
            }
            8 {                                                         # Backspace
                $parent = Split-Path -Path $currentPath -Parent
                if ($parent) {
                    $currentPath = $parent
                    $items = @(Get-WinCleanChildSizes -Path $currentPath | Select-Object -First $Top)
                    $selected = 0
                }
            }
            68 {                                                        # 'd'
                if ($items.Count -gt 0) {
                    $target = $items[$selected]
                    Write-Host ''
                    $confirm = Read-Host "Delete '$($target.FullPath)' ($(Format-WinCleanBytes -Bytes $target.SizeBytes))? Moves to Recycle Bin. [y/N]"
                    if ($confirm -eq 'y') {
                        Remove-WinCleanItem -Path $target.FullPath -Confirm:$false | Out-Null
                        $items = @(Get-WinCleanChildSizes -Path $currentPath | Select-Object -First $Top)
                        $selected = [math]::Min($selected, [math]::Max(0, $items.Count - 1))
                    }
                }
            }
            81 { return }                                               # 'q'
        }
    }
}
