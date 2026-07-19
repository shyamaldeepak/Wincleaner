# Uninstall.ps1 — app inventory and removal. This is the highest-risk
# command in Win Clean, so it deliberately does the least: it inventories
# apps from the registry Uninstall keys and Appx packages, and removes an
# app by running THAT APP'S OWN uninstaller (UninstallString / MSI /
# Remove-AppxPackage) — it never hand-deletes an install folder by guessing
# at a name or vendor. Guess-based leftover matching (a wildcard on app name
# or vendor) is a well-known way for this kind of cleanup to match far more
# than intended, so this v1 intentionally does NOT attempt automatic
# leftover-folder cleanup at all: if the registry's own
# InstallLocation value still exists after a successful uninstall, Win Clean
# reports its path and size and leaves deleting it to the user (via
# `winclean analyze`), rather than guessing it's safe to remove.

function Get-WinCleanRegistryApps {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if (-not $props.DisplayName) { return }
            if ($props.SystemComponent -eq 1) { return }
            if (-not $props.UninstallString) { return }

            [PSCustomObject]@{
                Source            = 'Registry'
                Name              = $props.DisplayName
                Publisher         = $props.Publisher
                Version           = $props.DisplayVersion
                EstimatedSizeKB   = $props.EstimatedSize
                UninstallString   = $props.UninstallString
                QuietUninstall    = $props.QuietUninstallString
                InstallLocation   = $props.InstallLocation
                RegistryKeyPath   = $_.PSPath
                PackageFullName   = $null
            }
        }
    }
}

function Get-WinCleanAppxApps {
    try {
        Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage } |
            ForEach-Object {
                [PSCustomObject]@{
                    Source          = 'Appx'
                    Name            = $_.Name
                    Publisher       = $_.Publisher
                    Version         = $_.Version
                    EstimatedSizeKB = $null
                    UninstallString = $null
                    QuietUninstall  = $null
                    InstallLocation = $_.InstallLocation
                    RegistryKeyPath = $null
                    PackageFullName = $_.PackageFullName
                }
            }
    } catch {
        @()
    }
}

function Get-WinCleanInstalledApps {
    param([string]$Filter)

    $apps = @(Get-WinCleanRegistryApps) + @(Get-WinCleanAppxApps)
    $apps = $apps | Sort-Object -Property Name -Unique

    if ($Filter) {
        $apps = $apps | Where-Object { $_.Name -like "*$Filter*" }
    }
    return @($apps)
}

function Uninstall-WinCleanApp {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][PSCustomObject]$App)

    if (-not $PSCmdlet.ShouldProcess($App.Name, 'Uninstall')) { return $false }

    if ($App.Source -eq 'Appx') {
        try {
            Remove-AppxPackage -Package $App.PackageFullName -ErrorAction Stop
            Write-WinCleanLog -Action 'uninstall' -Status 'ok' -Path $App.Name -Detail $App.PackageFullName
            return $true
        } catch {
            Write-WinCleanLog -Action 'uninstall' -Status 'error' -Path $App.Name -Detail $_.Exception.Message
            Write-Error "Win Clean failed to remove Appx package '$($App.Name)': $($_.Exception.Message)"
            return $false
        }
    }

    $command = if ($App.QuietUninstall) { $App.QuietUninstall } else { $App.UninstallString }
    if (-not $command) {
        Write-Error "Win Clean: '$($App.Name)' has no uninstall command in the registry."
        return $false
    }

    try {
        # UninstallString is a full command line (e.g. `MsiExec.exe /X{GUID}` or
        # `"C:\...\uninstall.exe" /args`) — run it through cmd.exe /c exactly as
        # the installer wrote it, rather than trying to re-parse and re-quote it.
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $command) -Wait -PassThru -ErrorAction Stop
        $ok = ($process.ExitCode -eq 0)
        Write-WinCleanLog -Action 'uninstall' -Status $(if ($ok) { 'ok' } else { 'exit-code-nonzero' }) -Path $App.Name -Detail "exitCode=$($process.ExitCode)"

        if ($ok -and $App.InstallLocation -and (Test-Path -LiteralPath $App.InstallLocation)) {
            $size = Get-WinCleanItemSize -Path $App.InstallLocation
            Write-Host "Win Clean: '$($App.Name)' uninstalled. Its registered install folder still exists:" -ForegroundColor Yellow
            Write-Host "  $($App.InstallLocation) ($(Format-WinCleanBytes -Bytes $size))"
            Write-Host "  Win Clean does not guess whether leftovers are safe to delete — review it with 'winclean analyze' and delete manually if you want it gone."
        }
        return $ok
    } catch {
        Write-WinCleanLog -Action 'uninstall' -Status 'error' -Path $App.Name -Detail $_.Exception.Message
        Write-Error "Win Clean failed to run the uninstaller for '$($App.Name)': $($_.Exception.Message)"
        return $false
    }
}

function Invoke-WinCleanUninstall {
    param(
        [string]$Filter,
        [int]$Remove,
        [switch]$Json
    )

    $apps = Get-WinCleanInstalledApps -Filter $Filter

    if ($PSBoundParameters.ContainsKey('Remove')) {
        if ($Remove -lt 1 -or $Remove -gt $apps.Count) {
            Write-Error "Win Clean: no app at index $Remove. Run 'winclean uninstall' to see the list."
            return
        }
        $target = $apps[$Remove - 1]
        Write-Host "About to uninstall: $($target.Name) ($($target.Publisher))" -ForegroundColor Yellow
        $confirm = Read-Host 'Continue? [y/N]'
        if ($confirm -eq 'y') {
            Uninstall-WinCleanApp -App $target -Confirm:$false
        }
        return
    }

    if ($Json) {
        $apps | ConvertTo-Json -Depth 3
        return
    }

    Write-Host ''
    Write-Host 'Win Clean — installed applications' -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $apps.Count; $i++) {
        $sizeStr = if ($apps[$i].EstimatedSizeKB) { Format-WinCleanBytes -Bytes ([long]$apps[$i].EstimatedSizeKB * 1024) } else { '' }
        Write-Host ('  [{0,3}] {1,-45} {2,-20} {3}' -f ($i + 1), $apps[$i].Name, $apps[$i].Publisher, $sizeStr)
    }
    Write-Host ''
    Write-Host '  Use -Remove <index> to uninstall a specific app.'
}
