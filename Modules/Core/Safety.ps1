# Safety.ps1 — path validation and the protected-path deny-list.
# Every deletion in Win Clean must pass Test-WinCleanPathSafeToDelete first.
# Design: allow-list first, deny-list second, resolve reparse points before
# either check so a junction can't be used to escape the gate.

Add-Type -AssemblyName System.Core -ErrorAction SilentlyContinue

# P/Invoke GetFinalPathNameByHandle so reparse points (symlinks/junctions)
# resolve to their real target on both Windows PowerShell 5.1 and PowerShell 7+
# (FileSystemInfo.LinkTarget only exists on .NET 6+ / PS 7.2+, so this can't
# rely on a managed-only API).
if (-not ('WinClean.NativePath' -as [type])) {
    Add-Type -Namespace WinClean -Name NativePath -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(
    string lpFileName, uint dwDesiredAccess, uint dwShareMode,
    IntPtr lpSecurityAttributes, uint dwCreationDisposition,
    uint dwFlagsAndAttributes, IntPtr hTemplateFile);

[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern uint GetFinalPathNameByHandle(
    Microsoft.Win32.SafeHandles.SafeFileHandle hFile,
    System.Text.StringBuilder lpszFilePath, uint cchFilePath, uint dwFlags);
'@
}

# FILE_FLAG_BACKUP_SEMANTICS lets CreateFile open a directory handle.
$script:FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
$script:OPEN_EXISTING = 3
$script:FILE_SHARE_ALL = 0x7 # read | write | delete

function Resolve-WinCleanRealPath {
    <#
    .SYNOPSIS
    Resolves a path to its final real path, following reparse points
    (symlinks/junctions) all the way down. Returns $null if the path cannot
    be opened (including "does not exist" — callers treat that as a no-op:
    a missing path is already the desired end state).
    #>
    param([Parameter(Mandatory)][string]$Path)

    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return $null }

    if (-not (Test-Path -LiteralPath $full -ErrorAction SilentlyContinue)) {
        # Path doesn't exist yet (or is a broken link) — nothing to resolve,
        # return the syntactically-normalized path so callers can still run
        # the deny-list check against it (a not-yet-created path under a
        # protected root should still be rejected).
        return $full
    }

    $handle = $null
    try {
        $handle = [WinClean.NativePath]::CreateFile(
            $full, 0, $script:FILE_SHARE_ALL, [IntPtr]::Zero,
            $script:OPEN_EXISTING, $script:FILE_FLAG_BACKUP_SEMANTICS, [IntPtr]::Zero)
        if ($null -eq $handle -or $handle.IsInvalid) { return $full }

        $sb = New-Object System.Text.StringBuilder 1024
        $len = [WinClean.NativePath]::GetFinalPathNameByHandle($handle, $sb, [uint32]$sb.Capacity, 0)
        if ($len -eq 0 -or $len -ge $sb.Capacity) { return $full }

        $resolved = $sb.ToString()
        if ($resolved.StartsWith('\\?\UNC\')) {
            $resolved = '\\' + $resolved.Substring(8)
        } elseif ($resolved.StartsWith('\\?\')) {
            $resolved = $resolved.Substring(4)
        }
        return $resolved
    } catch {
        return $full
    } finally {
        if ($null -ne $handle -and -not $handle.IsInvalid) { $handle.Dispose() }
    }
}

function Get-WinCleanProtectedRoots {
    <#
    .SYNOPSIS
    Returns the protected-path table. Split into "subtree" roots (the root
    and everything under it is protected) and "bare" roots (only the exact
    folder is protected — children are deletable, e.g. C:\ProgramData itself
    is off-limits but C:\ProgramData\SomeVendor\Cache is fair game).
    #>
    # Fall back to standard Windows defaults for any of these that are
    # unset. On real Windows these env vars are always populated by the OS;
    # the fallback exists so a stripped-down execution environment (a
    # locked-down scheduled task, a non-Windows CI/test host) degrades to
    # the normal deny-list instead of silently protecting nothing — for a
    # function that gates every delete, "assume happy path" is not safe.
    # String concatenation is used instead of Join-Path for the drive-root
    # cases below: Join-Path treats a bare "C:" as a PSDrive reference and
    # throws "Cannot find drive" if no live PSDrive named "C" exists, which
    # is a real, reproducible failure mode, not just a test-host artifact.
    $systemDrive = $env:SystemDrive
    if (-not $systemDrive) { $systemDrive = 'C:' }

    $systemRoot = $env:SystemRoot
    if (-not $systemRoot) { $systemRoot = "$systemDrive\Windows" }

    $programFiles = $env:ProgramFiles
    if (-not $programFiles) { $programFiles = "$systemDrive\Program Files" }

    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not $programFilesX86) { $programFilesX86 = "$systemDrive\Program Files (x86)" }

    $programData = $env:ProgramData
    if (-not $programData) { $programData = "$systemDrive\ProgramData" }

    $subtree = @(
        $systemRoot,
        $programFiles,
        $programFilesX86,
        "$systemDrive\System Volume Information",
        "$systemDrive\`$Recycle.Bin",
        "$systemDrive\Recovery",
        "$systemDrive\PerfLogs",
        "$systemRoot\System32\config"
    ) | Where-Object { $_ }

    $bare = @(
        "$systemDrive\",
        $systemDrive,
        $programData,
        "$systemDrive\Users",
        "$systemDrive\bootmgr",
        "$systemDrive\BOOTNXT"
    ) | Where-Object { $_ }

    [PSCustomObject]@{
        Subtree = $subtree
        Bare    = $bare
    }
}

function Test-WinCleanBareHomeRoot {
    # Matches "C:\Users\<name>" or "C:\Users\<name>\" exactly — a single
    # user's home root, which must never be deleted wholesale even though
    # its contents are fair game.
    param([Parameter(Mandatory)][string]$Path)
    return $Path -match '^[A-Za-z]:\\Users\\[^\\]+\\?$'
}

function Test-WinCleanDriveRoot {
    param([Parameter(Mandatory)][string]$Path)
    return $Path -match '^[A-Za-z]:\\?$'
}

function Test-WinCleanProtectedPath {
    <#
    .SYNOPSIS
    Returns $true if the given (already-resolved) path is protected and must
    never be deleted, directly or as an ancestor.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path.TrimEnd('\')
    if (Test-WinCleanDriveRoot $Path) { return $true }
    if (Test-WinCleanBareHomeRoot $Path) { return $true }

    $roots = Get-WinCleanProtectedRoots

    foreach ($root in $roots.Bare) {
        $rootNormalized = $root.TrimEnd('\')
        if ($normalized -ieq $rootNormalized) { return $true }
    }

    foreach ($root in $roots.Subtree) {
        $rootNormalized = $root.TrimEnd('\')
        if ($normalized -ieq $rootNormalized) { return $true }
        if ($normalized.StartsWith("$rootNormalized\", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    return $false
}

function Test-WinCleanPathSafeToDelete {
    <#
    .SYNOPSIS
    The full validation gate. Returns a PSCustomObject { IsSafe, Reason,
    ResolvedPath } — callers must check IsSafe before deleting anything and
    should log Reason on rejection.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)

    $reject = { param($reason) [PSCustomObject]@{ IsSafe = $false; Reason = $reason; ResolvedPath = $null } }

    if ([string]::IsNullOrWhiteSpace($Path)) { return (& $reject 'empty-path') }
    if (-not [System.IO.Path]::IsPathRooted($Path)) { return (& $reject 'not-absolute') }
    if ($Path -match '[\x00-\x1F]') { return (& $reject 'control-characters') }
    if ($Path -match '(^|[\\/])\.\.([\\/]|$)') { return (& $reject 'path-traversal') }

    $resolved = Resolve-WinCleanRealPath -Path $Path
    if ($null -eq $resolved) { return (& $reject 'unresolvable') }

    if (Test-WinCleanProtectedPath -Path $resolved) { return (& $reject 'protected-path') }
    # Re-check the literal (pre-resolution) path too, in case GetFullPath
    # normalization diverged from the reparse-resolved target in some edge
    # case the native resolver didn't catch.
    if (Test-WinCleanProtectedPath -Path ([System.IO.Path]::GetFullPath($Path))) {
        return (& $reject 'protected-path')
    }

    return [PSCustomObject]@{ IsSafe = $true; Reason = $null; ResolvedPath = $resolved }
}
