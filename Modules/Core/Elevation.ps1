# Elevation.ps1 — admin-rights check. Win Clean runs as the invoking user by
# default; commands that hit an admin-only target (e.g. the Windows Update
# download cache in Clean.ps1) check this and skip that one item with a
# "re-run elevated" message rather than relaunching themselves — Win Clean
# never self-elevates.

function Test-WinCleanIsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
