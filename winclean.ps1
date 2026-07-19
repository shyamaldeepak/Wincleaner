#Requires -Version 5.1
<#
.SYNOPSIS
Win Clean — terminal CLI for Windows storage analysis, cleanup, app
uninstall, and RAM diagnostics.

.EXAMPLE
.\winclean.ps1 status
.\winclean.ps1 analyze -Path C:\Users\me
.\winclean.ps1 clean
.\winclean.ps1 clean -Apply
.\winclean.ps1 uninstall -Filter Zoom

.NOTES
Deliberately has NO typed param() block. Two PowerShell quirks, confirmed
by direct testing, rule that out:
  1. Once a script declares ANY param() block, an unrecognized -Flag token
     that doesn't match a declared parameter name is a hard parse-time
     error — it does NOT fall through to $args like you'd expect.
  2. Splatting (@variable) only re-parses "-Name value" elements as named
     parameters when the variable being splatted is literally named $args
     AND was assigned via a direct statement, not the *result* of an
     if/else used as an expression (`$args = if (...) {a} else {b}`) —
     confirmed by direct testing: piping the exact same array through an
     if/else expression's output stream silently strips whatever internal
     marker tells the splat operator "these were written as -Name tokens",
     degrading it to positional binding (so "-Json" ends up bound to the
     first int parameter instead of the -Json switch). That's why the
     reassignment below uses if/else as a plain STATEMENT, with a direct
     `$args = ...` assignment inside each branch, instead of one
     expression-style assignment covering both branches.
#>

if ($args.Count -eq 0) {
    $Command = 'help'
    $args = @()
} else {
    $Command = $args[0]
    if ($args.Count -gt 1) {
        $args = @($args[1..($args.Count - 1)])
    } else {
        $args = @()
    }
}

Import-Module (Join-Path $PSScriptRoot 'WinClean.psd1') -Force

function Show-WinCleanBanner {
    <#
    .SYNOPSIS
    Small ASCII banner printed at the top of every interactive terminal
    invocation — this is "how the CLI looks in the terminal," live rather
    than a static screenshot/GIF, so it never goes stale. Plain ASCII box
    characters only (+/-/|), not Unicode box-drawing glyphs, to avoid any
    code-page rendering surprise on Windows PowerShell 5.1 consoles. Skipped
    whenever the invocation looks machine-consumed, so scripts/tests parsing
    stdout never see it mixed into their output.
    #>
    Write-Host ''
    Write-Host '  +-------------------------------------------+' -ForegroundColor Cyan
    Write-Host '  |   Win Clean -- Windows storage & app CLI   |' -ForegroundColor Cyan
    Write-Host '  +-------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ''
}

function Show-WinCleanHelp {
    @'
Win Clean — a native PowerShell CLI for Windows storage/app cleanup.

Usage: winclean <command> [options]

Commands:
  status      Show CPU/RAM/disk snapshot and top processes by memory.
              -Close <pid> / -Restart <pid> act on a process.
              -TrimWorkingSets runs a marginal, explicitly-opt-in RAM trim.
  analyze     Interactive disk usage browser, largest -> smallest.
              -Path <dir> -Top <n> -Json -NonInteractive
              -Duplicates finds exact-duplicate files by content hash.
  clean       Preview known-safe rebuildable storage to clean.
              -Apply actually deletes (default is preview-only).
              -IncludeDisabled also shows/applies opt-in-only entries
              (Prefetch, emptying the Recycle Bin).
  uninstall   List installed applications. -Filter <text> to search.
              -Remove <index> to uninstall a specific app.
  startup     List programs configured to launch at logon (registry Run
              keys + Startup folders). Read-only.
  history     Show past clean/uninstall/delete actions from the operations
              log. -Action <name> -Status <ok|error|rejected|...>
              -Last <n> -Json
  version     Print the Win Clean version.
  help        Show this message.

Deletions always move to the Recycle Bin unless -Permanent is used inside
the module directly. Every action is logged to:
  %LOCALAPPDATA%\WinClean\logs\operations.jsonl
'@ | Write-Host
}

# Automation/tests parse stdout directly, so the banner is suppressed
# whenever -Json or -NonInteractive appears anywhere in the arguments —
# case-insensitive substring match is deliberate here since these are
# display-only flags, not safety-critical input needing exact parsing.
$suppressBanner = ($args | Where-Object { $_ -is [string] -and $_ -match '^-(Json|NonInteractive)$' }).Count -gt 0
if (-not $suppressBanner) { Show-WinCleanBanner }

switch ($Command.ToLowerInvariant()) {
    'status' { Invoke-WinCleanStatus @args }
    'analyze' { Invoke-WinCleanAnalyze @args }
    'clean' { Invoke-WinCleanClean @args }
    'uninstall' { Invoke-WinCleanUninstall @args }
    'startup' { Invoke-WinCleanStartup @args }
    'history' { Invoke-WinCleanHistory @args }
    'version' { Write-Host 'Win Clean 0.1.0' }
    'help' { Show-WinCleanHelp }
    default {
        Write-Error "Win Clean: unknown command '$Command'. Run 'winclean help'."
        exit 1
    }
}
