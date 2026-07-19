# Startup.ps1 — read-only inventory of programs configured to launch at
# logon: the HKCU/HKLM Run registry keys and the per-user/all-users Startup
# shell folders. Deliberately read-only in v1 — no disable/remove action.
# See CLAUDE.md's "dead code" note: a Core helper only gets added once it
# has a real caller, and "should this Run entry be safe to remove" is
# exactly the kind of judgment call SECURITY.md's uninstall section warns
# against automating without dedicated, narrow logic and its own tests.

function Get-WinCleanStartupRegistryEntries {
    <#
    .SYNOPSIS
    Reads HKCU/HKLM Run keys. The registry PSDrive doesn't exist off
    Windows, so each hive is wrapped in its own try/catch and simply
    contributes nothing there rather than failing the whole command — same
    degrade-not-crash pattern as Get-WinCleanProtectedRoots.
    #>
    $entries = @()
    $roots = @(
        @{ Scope = 'CurrentUser'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
        @{ Scope = 'AllUsers'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' }
    )

    foreach ($root in $roots) {
        try {
            if (-not (Test-Path -LiteralPath $root.Path)) { continue }
            $key = Get-Item -LiteralPath $root.Path -ErrorAction Stop
            foreach ($name in $key.GetValueNames()) {
                if ([string]::IsNullOrEmpty($name)) { continue }
                $entries += [PSCustomObject]@{
                    Source  = 'Registry'
                    Scope   = $root.Scope
                    Name    = $name
                    Command = $key.GetValue($name)
                    Path    = $root.Path
                }
            }
        } catch {
            continue
        }
    }
    return $entries
}

function Get-WinCleanStartupFolderEntries {
    <#
    .SYNOPSIS
    Lists shortcuts/files in the current-user and all-users Startup shell
    folders. $env:APPDATA / $env:ProgramData are empty on non-Windows
    hosts; the Test-Path guard below already skips a folder whose path is
    falsy or missing, so this degrades to "nothing found" rather than
    throwing — no separate fallback needed since nothing here is
    safety-critical (read-only inventory, not a deny-list).
    #>
    $entries = @()
    $folders = @(
        @{ Scope = 'CurrentUser'; Path = $(if ($env:APPDATA) { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup' }) }
        @{ Scope = 'AllUsers'; Path = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup' }) }
    )

    foreach ($folder in $folders) {
        if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $folder.Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $entries += [PSCustomObject]@{
                Source  = 'StartupFolder'
                Scope   = $folder.Scope
                Name    = $_.Name
                Command = $_.FullName
                Path    = $folder.Path
            }
        }
    }
    return $entries
}

function Get-WinCleanStartupEntries {
    @(Get-WinCleanStartupRegistryEntries) + @(Get-WinCleanStartupFolderEntries)
}

function Invoke-WinCleanStartup {
    param([switch]$Json)

    $entries = @(Get-WinCleanStartupEntries)

    if ($Json) {
        # -InputObject, not piped: piping an empty array into ConvertTo-Json
        # unrolls it to zero pipeline objects and produces NO output (not
        # "[]"), breaking any script parsing -Json when nothing is found.
        ConvertTo-Json -InputObject $entries -Depth 3
        return
    }

    Write-Host ''
    Write-Host 'Win Clean — startup programs' -ForegroundColor Cyan
    Write-Host ''
    if ($entries.Count -eq 0) {
        Write-Host '  (none found)'
        return
    }
    $entries | Format-Table -Property Source, Scope, Name, Command -AutoSize
    Write-Host '  Read-only: Win Clean does not disable or remove startup entries.'
}
