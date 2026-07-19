# Win Clean

A native PowerShell terminal CLI for Windows 10/11 storage analysis, cache
cleanup, app uninstall, and RAM diagnostics. No WSL, no extra runtime —
just PowerShell 5.1+ (ships with Windows) or PowerShell 7+.

## Commands

```
winclean status                     CPU/RAM/disk snapshot, top processes by memory (high -> low)
winclean status -Close <pid>        Close a specific process
winclean status -Restart <pid>      Restart a specific process (best effort)
winclean status -TrimWorkingSets    Marginal, explicitly opt-in RAM trim (not a "boost")

winclean analyze                    Interactive disk browser, largest -> smallest, drill-down + delete
winclean analyze -Path C:\Users\me  Scan a specific folder
winclean analyze -Json              Non-interactive JSON output

winclean clean                      Preview known-safe rebuildable storage (nothing deleted)
winclean clean -Apply               Actually clean it

winclean uninstall                  List installed applications
winclean uninstall -Filter Zoom     Search by name
winclean uninstall -Remove 3        Uninstall the app at that index
```

## Safety model

Every delete goes through one function: `Remove-WinCleanItem`
(`Modules/Core/Remove-Safely.ps1`). It:

1. Validates the path (`Modules/Core/Safety.ps1`): must be absolute, no path
   traversal (`..`), no control characters, and — after resolving any
   symlink/junction to its real target — must not fall inside a protected
   root (`C:\Windows`, `C:\Program Files`, a bare drive root, a bare user
   home root, `System Volume Information`, etc.). A junction can't be used
   to walk a scan into a protected tree; resolution happens before the
   deny-list check runs.
2. Moves the item to the Recycle Bin by default. A failed Recycle Bin move
   **fails closed** — it never silently falls back to a permanent delete.
   `-Permanent` is required for a real, unrecoverable delete.
3. Logs every attempt (`%LOCALAPPDATA%\WinClean\logs\operations.jsonl`),
   independent of whatever the command printed to the console.

`winclean clean` previews by default; it only deletes with `-Apply`. This is
stricter than relying on PowerShell's own `-WhatIf`/`-Confirm` defaults,
which would otherwise proceed on a bare call for a command below the "High"
confirm-impact threshold.

`winclean uninstall` runs the *app's own* uninstaller (registry
`UninstallString` / `Remove-AppxPackage`) — it never hand-deletes an install
folder by guessing at a name or vendor. If a registry `InstallLocation`
still exists after a successful uninstall, Win Clean reports its path and
size and leaves deleting it to you via `winclean analyze`, rather than
guessing it's safe to remove automatically.

"Clean RAM" is intentionally not a headline feature: Windows manages its own
memory, and force-trimming a process's working set rarely frees anything
durable. `winclean status` shows real, actionable data (what's using memory,
sorted high to low) and lets you close/restart a specific process;
`-TrimWorkingSets` exists as a separate, clearly-labeled, never-implicit
option for anyone who wants it anyway.

## Install

```powershell
.\install.ps1
```

Copies Win Clean to `%LOCALAPPDATA%\Programs\WinClean` and adds it to your
user `PATH` (no admin rights required). Open a new terminal and run
`winclean help`.

To run without installing, from this folder:

```powershell
.\winclean.ps1 status
```

## Tests

```powershell
Invoke-Pester .\Tests\
```

`Safety.Tests.ps1` and `RemoveSafely.Tests.ps1` cover the protected-path
deny-list and the delete/Recycle-Bin contract — the two things every other
command depends on.

## Project layout

```
winclean.ps1              Entry router
winclean.cmd               PATH shim so `winclean` works from cmd.exe too
WinClean.psd1 / .psm1       Module manifest / root module
Modules/Core/                Safety.ps1, Remove-Safely.ps1, Logging.ps1,
                              Elevation.ps1, Format.ps1 — shared by every command
Modules/Status.ps1           RAM/CPU/disk snapshot, process actions
Modules/Analyze.ps1          Disk usage scan and interactive browser
Modules/Clean.ps1            Known-safe cleanup catalog
Modules/Uninstall.ps1        App inventory and removal
Tests/                       Pester tests
```

## Status

v0.1.0 — first working version of all four commands. Built and reviewed on
macOS (no `pwsh` available in that environment to run Pester directly);
needs a real smoke test on Windows 10/11 before being treated as verified.
