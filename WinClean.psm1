# WinClean.psm1 — root module. Dot-sources the safety core first (every
# command depends on it), then the command modules, then exports everything
# so Pester can test internals directly via Import-Module.

$core = @(
    'Modules/Core/Format.ps1'
    'Modules/Core/Safety.ps1'
    'Modules/Core/Logging.ps1'
    'Modules/Core/Elevation.ps1'
    'Modules/Core/Remove-Safely.ps1'
)

$commands = @(
    'Modules/Status.ps1'
    'Modules/Analyze.ps1'
    'Modules/Clean.ps1'
    'Modules/Uninstall.ps1'
    'Modules/History.ps1'
    'Modules/Startup.ps1'
    'Modules/Menu.ps1'
    'Modules/Health.ps1'
    'Modules/Trash.ps1'
)

foreach ($relativePath in ($core + $commands)) {
    . (Join-Path $PSScriptRoot $relativePath)
}

Export-ModuleMember -Function *
