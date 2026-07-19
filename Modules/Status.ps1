# Status.ps1 — read-only system snapshot plus RAM diagnostics. This is the
# safest command in Win Clean (nothing is deleted by default) and the first
# one built, since it proves the module loads and the console renders
# correctly with zero delete risk.
#
# "Clean RAM" is intentionally NOT a headline feature here: Windows manages
# its own memory, and force-trimming a process's working set rarely frees
# anything durable (pages just get faulted back in). Instead this shows what
# is actually using memory, sorted high to low, and lets the user act on a
# specific process. -TrimWorkingSets exists as an explicit, separate,
# clearly-labeled-as-marginal switch — never run implicitly.

function Get-WinCleanMemorySnapshot {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalKB = [double]$os.TotalVisibleMemorySize
    $freeKB = [double]$os.FreePhysicalMemory
    $usedKB = $totalKB - $freeKB
    [PSCustomObject]@{
        TotalMB     = [math]::Round($totalKB / 1KB, 1)
        UsedMB      = [math]::Round($usedKB / 1KB, 1)
        FreeMB      = [math]::Round($freeKB / 1KB, 1)
        UsedPercent = if ($totalKB -gt 0) { [math]::Round(($usedKB / $totalKB) * 100, 1) } else { 0 }
    }
}

function Get-WinCleanCpuSnapshot {
    try {
        $samples = Get-CimInstance -ClassName Win32_Processor |
            Measure-Object -Property LoadPercentage -Average
        [PSCustomObject]@{ UsagePercent = [math]::Round([double]$samples.Average, 1) }
    } catch {
        [PSCustomObject]@{ UsagePercent = $null }
    }
}

function Get-WinCleanDiskSnapshot {
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' |
        ForEach-Object {
            $totalBytes = [double]$_.Size
            $freeBytes = [double]$_.FreeSpace
            $usedBytes = $totalBytes - $freeBytes
            [PSCustomObject]@{
                Drive       = $_.DeviceID
                TotalGB     = [math]::Round($totalBytes / 1GB, 1)
                UsedGB      = [math]::Round($usedBytes / 1GB, 1)
                FreeGB      = [math]::Round($freeBytes / 1GB, 1)
                UsedPercent = if ($totalBytes -gt 0) { [math]::Round(($usedBytes / $totalBytes) * 100, 1) } else { 0 }
            }
        }
}

function Get-WinCleanTopProcesses {
    param([int]$Top = 10)

    Get-Process | Where-Object { $_.Id -ne 0 } | ForEach-Object {
        $cpuPercent = $null
        try { $cpuPercent = $_.CPU } catch { }
        [PSCustomObject]@{
            Id          = $_.Id
            Name        = $_.ProcessName
            MemoryMB    = [math]::Round($_.WorkingSet64 / 1MB, 1)
            CpuSeconds  = $cpuPercent
            Path        = $(try { $_.Path } catch { $null })
        }
    } | Sort-Object -Property MemoryMB -Descending | Select-Object -First $Top
}

function Stop-WinCleanProcess {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][int]$Id)

    $proc = Get-Process -Id $Id -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Warning "Win Clean: no running process with Id $Id."
        return $false
    }
    if ($PSCmdlet.ShouldProcess("$($proc.ProcessName) (PID $Id)", 'Close')) {
        try {
            Stop-Process -Id $Id -Force -ErrorAction Stop
            Write-WinCleanLog -Action 'process-close' -Status 'ok' -Path $proc.ProcessName
            return $true
        } catch {
            Write-WinCleanLog -Action 'process-close' -Status 'error' -Path $proc.ProcessName -Detail $_.Exception.Message
            Write-Error "Win Clean failed to close PID $Id`: $($_.Exception.Message)"
            return $false
        }
    }
    return $false
}

function Restart-WinCleanProcess {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory)][int]$Id)

    $proc = Get-Process -Id $Id -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Warning "Win Clean: no running process with Id $Id."
        return $false
    }
    $path = $(try { $proc.Path } catch { $null })
    if (-not $path) {
        Write-Warning "Win Clean: cannot restart '$($proc.ProcessName)' (PID $Id) — its executable path isn't accessible. Close it manually and relaunch it yourself."
        return $false
    }
    if ($PSCmdlet.ShouldProcess("$($proc.ProcessName) (PID $Id)", 'Restart')) {
        try {
            Stop-Process -Id $Id -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 300
            Start-Process -FilePath $path
            Write-WinCleanLog -Action 'process-restart' -Status 'ok' -Path $path
            return $true
        } catch {
            Write-WinCleanLog -Action 'process-restart' -Status 'error' -Path $path -Detail $_.Exception.Message
            Write-Error "Win Clean failed to restart PID $Id`: $($_.Exception.Message)"
            return $false
        }
    }
    return $false
}

function Invoke-WinCleanTrimWorkingSets {
    <#
    .SYNOPSIS
    Best-effort, clearly-marginal action: asks Windows to trim each
    accessible process's working set via EmptyWorkingSet. This is NOT a
    "free up RAM" guarantee — trimmed pages are typically faulted back in as
    soon as the process touches them again. Offered because some users want
    it anyway, never run implicitly.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not ('WinClean.NativeMemory' -as [type])) {
        Add-Type -Namespace WinClean -Name NativeMemory -MemberDefinition @'
[DllImport("psapi.dll")]
public static extern bool EmptyWorkingSet(IntPtr hProcess);
'@
    }

    $trimmed = 0
    $skipped = 0
    foreach ($proc in Get-Process) {
        if (-not $PSCmdlet.ShouldProcess("$($proc.ProcessName) (PID $($proc.Id))", 'Trim working set')) { continue }
        try {
            if ([WinClean.NativeMemory]::EmptyWorkingSet($proc.Handle)) { $trimmed++ } else { $skipped++ }
        } catch {
            $skipped++
        }
    }
    Write-WinCleanLog -Action 'trim-working-sets' -Status 'ok' -Detail "trimmed=$trimmed skipped=$skipped"
    [PSCustomObject]@{ Trimmed = $trimmed; Skipped = $skipped }
}

function Invoke-WinCleanStatus {
    param(
        [int]$Top = 10,
        [switch]$Json,
        [int]$Close,
        [int]$Restart,
        [switch]$TrimWorkingSets
    )

    if ($PSBoundParameters.ContainsKey('Close')) { Stop-WinCleanProcess -Id $Close; return }
    if ($PSBoundParameters.ContainsKey('Restart')) { Restart-WinCleanProcess -Id $Restart; return }
    if ($TrimWorkingSets) { Invoke-WinCleanTrimWorkingSets | Format-Table; return }

    $snapshot = [PSCustomObject]@{
        Memory    = Get-WinCleanMemorySnapshot
        Cpu       = Get-WinCleanCpuSnapshot
        Disks     = @(Get-WinCleanDiskSnapshot)
        Processes = @(Get-WinCleanTopProcesses -Top $Top)
    }

    if ($Json) {
        $snapshot | ConvertTo-Json -Depth 5
        return
    }

    Write-Host ''
    Write-Host 'Win Clean — status' -ForegroundColor Cyan
    Write-Host ('  CPU     {0}%' -f $snapshot.Cpu.UsagePercent)
    Write-Host ('  Memory  {0} / {1} MB ({2}%)' -f $snapshot.Memory.UsedMB, $snapshot.Memory.TotalMB, $snapshot.Memory.UsedPercent)
    foreach ($disk in $snapshot.Disks) {
        Write-Host ('  Disk {0}  {1} / {2} GB ({3}%)' -f $disk.Drive, $disk.UsedGB, $disk.TotalGB, $disk.UsedPercent)
    }
    Write-Host ''
    Write-Host ("  Top {0} processes by memory:" -f $Top)
    $snapshot.Processes | Format-Table -Property Id, Name, MemoryMB -AutoSize
    Write-Host '  Use -Close <pid> or -Restart <pid> to act on a specific process.'
}
