# Menu.ps1 -- Mole-style interactive dashboard with arrow-key navigation,
# live system status header, and 1-7 / Q hotkey shortcuts.

function Show-WinCleanMenuHeader {
    $cpuStr = "N/A"
    $ramStr = "N/A"
    $diskStr = "N/A"

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average
        if ($cpu -and $null -ne $cpu.Average) { $cpuStr = "$([math]::Round($cpu.Average))%" }

        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os -and $os.TotalVisibleMemorySize -gt 0) {
            $usedMB = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1KB
            $totalMB = $os.TotalVisibleMemorySize / 1KB
            $pct = [math]::Round(($usedMB / $totalMB) * 100)
            $ramStr = "$([math]::Round($usedMB / 1024, 1))/$([math]::Round($totalMB / 1024, 1)) GB ($pct%)"
        }

        $cDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($cDrive -and $cDrive.FreeSpace) {
            $diskStr = "$([math]::Round($cDrive.FreeSpace / 1GB, 1)) GB Free"
        }
    } catch {}

    Write-Host ''
    Write-Host '  +-------------------------------------------------------------+' -ForegroundColor Cyan
    Write-Host '  |   Win Clean v0.3.0 -- Interactive Dashboard                 |' -ForegroundColor Cyan
    Write-Host ("  |   CPU: {0,-5} | RAM: {1,-18} | Disk C: {2,-11} |" -f $cpuStr, $ramStr, $diskStr) -ForegroundColor DarkCyan
    Write-Host '  +-------------------------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '  Use [Up/Down] arrows & [Enter] to select, or press [1-8] / [Q] to quit:' -ForegroundColor Gray
    Write-Host ''
}

function Invoke-WinCleanMenu {
    <#
    .SYNOPSIS
    Launches the interactive TUI menu loop for Win Clean.
    Supports Up/Down arrow navigation, Enter selection, and 1-8/Q hotkeys.
    #>
    param()

    $options = @(
        @{ Key = '1'; Label = '1. System Status       (CPU, RAM, Disks, Memory Processes)'; Action = { Invoke-WinCleanStatus } }
        @{ Key = '2'; Label = '2. Analyze Disk Space  (Interactive folder size browser)';    Action = { Invoke-WinCleanAnalyze } }
        @{ Key = '3'; Label = '3. Find Large Files    (Locate & delete large files >100MB)'; Action = { Invoke-WinCleanAnalyze -LargeFiles } }
        @{ Key = '4'; Label = '4. Clean Storage       (Preview & reclaim safe caches)';      Action = { Invoke-WinCleanClean } }
        @{ Key = '5'; Label = '5. Uninstall Software  (Interactive application remover)';   Action = { Invoke-WinCleanUninstall -Interactive } }
        @{ Key = '6'; Label = '6. Recycle Bin Manager (Check size & empty Recycle Bin)';    Action = { Invoke-WinCleanTrash } }
        @{ Key = '7'; Label = '7. Startup Programs    (Logon registry & startup entries)';   Action = { Invoke-WinCleanStartup } }
        @{ Key = '8'; Label = '8. Health & Optimize   (Health score & DNS resolver flush)';  Action = { Invoke-WinCleanHealth -FlushDns } }
        @{ Key = 'Q'; Label = 'Q. Exit';                                                    Action = $null }
    )

    $selectedIndex = 0
    $isInteractive = $true
    try {
        if (-not [System.Console]::IsInputRedirected) {
            # Test key reading capability
        } else {
            $isInteractive = $false
        }
    } catch {
        $isInteractive = $false
    }

    if (-not $isInteractive) {
        Show-WinCleanMenuHeader
        foreach ($opt in $options) {
            Write-Host ("  {0}" -f $opt.Label)
        }
        return
    }

    while ($true) {
        Clear-Host
        Show-WinCleanMenuHeader

        for ($i = 0; $i -lt $options.Count; $i++) {
            $prefix = if ($i -eq $selectedIndex) { ' > ' } else { '   ' }
            if ($i -eq $selectedIndex) {
                Write-Host ("{0}{1}" -f $prefix, $options[$i].Label) -ForegroundColor Black -BackgroundColor Cyan
            } else {
                Write-Host ("{0}{1}" -f $prefix, $options[$i].Label) -ForegroundColor White
            }
        }

        Write-Host ''
        Write-Host '  Shortcuts: [1-8] Direct Action | [Up/Down] Move | [Enter] Select | [Q/Esc] Quit' -ForegroundColor DarkGray

        $keyInfo = $null
        try {
            $keyInfo = [System.Console]::ReadKey($true)
        } catch {
            break
        }

        if ($null -eq $keyInfo) { break }

        $key = $keyInfo.Key
        $char = $keyInfo.KeyChar.ToString().ToUpperInvariant()

        if ($key -eq [System.ConsoleKey]::UpArrow) {
            $selectedIndex = ($selectedIndex - 1 + $options.Count) % $options.Count
            continue
        }
        elseif ($key -eq [System.ConsoleKey]::DownArrow) {
            $selectedIndex = ($selectedIndex + 1) % $options.Count
            continue
        }
        elseif ($key -eq [System.ConsoleKey]::Enter) {
            $chosen = $options[$selectedIndex]
            if ($null -eq $chosen.Action) { break } # Exit
            Clear-Host
            & $chosen.Action
            Write-Host ''
            Write-Host '  Press any key to return to menu...' -ForegroundColor Gray
            [System.Console]::ReadKey($true) | Out-Null
            continue
        }
        elseif ($key -eq [System.ConsoleKey]::Escape -or $char -eq 'Q') {
            break
        }
        else {
            # Check numeric hotkeys 1-8
            $matchOpt = $options | Where-Object { $_.Key -eq $char }
            if ($matchOpt) {
                if ($null -eq $matchOpt.Action) { break } # Exit
                Clear-Host
                & $matchOpt.Action
                Write-Host ''
                Write-Host '  Press any key to return to menu...' -ForegroundColor Gray
                [System.Console]::ReadKey($true) | Out-Null
                continue
            }
        }
    }
}
