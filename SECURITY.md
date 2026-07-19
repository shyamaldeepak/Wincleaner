# Win Clean — safety design

This documents the contract every destructive command in Win Clean must
follow, and why it's shaped this way. Read this before adding a new
deletion or uninstall path.

## Threat model

Win Clean assumes the invoking user runs it intentionally on their own
machine and isn't attacking themselves — but does make mistakes: a typo'd
path, a stale filter, an unexpected symlink/junction. What it defends
against:

- Deleting inside a protected system root (`C:\Windows`, `C:\Program
  Files`, `C:\Program Files (x86)`, `C:\ProgramData` itself, a bare drive
  root, a bare user home root, `System Volume Information`, `$Recycle.Bin`,
  `Recovery`, `PerfLogs`, boot files) — directly or via a reparse point
  that resolves into one.
- Guessing at leftovers during uninstall. Win Clean only removes what the
  app's own registry entry or `Remove-AppxPackage` removes; it never
  hand-deletes an install folder by pattern-matching a vendor or app name.
- Silently escalating a failed safe delete into a permanent one.

What it explicitly does **not** defend against: a user running as
Administrator and deliberately passing `-Permanent` at a path they chose on
purpose; a compromised machine where the Win Clean scripts themselves have
been tampered with; supply-chain compromise of PowerShell itself. Those are
out of scope for an unsigned, locally-run script tool.

## Layer 1 — path validation (`Modules/Core/Safety.ps1`)

`Test-WinCleanPathSafeToDelete` is the single gate every delete must pass.
Order matters — allow-checks are cheap and run first, deny-checks are
absolute and run last, so nothing downstream can accidentally widen what's
allowed:

1. Reject empty/null (using `[AllowEmptyString()]` deliberately, so an
   empty path reaches this graceful rejection instead of crashing on
   PowerShell's own mandatory-parameter binder — see `CLAUDE.md`).
2. Reject non-absolute paths (`[System.IO.Path]::IsPathRooted`).
3. Reject control characters.
4. Reject path traversal (`..` as a path *component*, not a substring — a
   literal folder named `name..files` must survive).
5. Resolve the real target via `GetFinalPathNameByHandle` (P/Invoke —
   `Resolve-WinCleanRealPath`), which follows symlinks/junctions all the
   way down. This runs on both the literal path and its resolved form, so
   a junction can't be used to walk a scan into a protected tree.
6. Check the resolved path against the protected-root deny-list
   (`Test-WinCleanProtectedPath`).

`Get-WinCleanProtectedRoots` builds that deny-list from Windows environment
variables (`SystemRoot`, `ProgramFiles`, `ProgramFiles(x86)`, `ProgramData`,
`SystemDrive`) with hardcoded fallbacks for each — not because a real
Windows session ever lacks them, but because a gate this safety-critical
must degrade to "protect everything" rather than "protect nothing" if it's
ever run in a stripped-down environment. This was a real bug caught during
initial testing, not theoretical hardening. See `CLAUDE.md` for the exact
failure mode.

Two protected-root shapes are distinguished:

- **Subtree** (`C:\Windows`, `C:\Program Files`, ...): the root and
  everything under it is protected.
- **Bare** (`C:\ProgramData`, `C:\Users`, a specific `C:\Users\<name>`
  home root, the drive root itself): only the exact folder is protected —
  children are fair game (`C:\ProgramData\SomeVendor\Cache` is deletable;
  `C:\ProgramData` itself is not).

## Layer 2 — the single choke point (`Modules/Core/Remove-Safely.ps1`)

`Remove-WinCleanItem` is the only function allowed to delete anything.
Nothing else in this project should call `Remove-Item` directly on a
user-supplied or scan-derived path. It:

- No-ops silently on a path that doesn't exist (matches "the desired end
  state already holds," not an error).
- Runs every path through `Test-WinCleanPathSafeToDelete` and logs +
  refuses on rejection.
- Moves to the Recycle Bin by default
  (`Microsoft.VisualBasic.FileIO.FileSystem`, `SendToRecycleBin`).
  **A failed Recycle Bin move fails closed** — it returns `$false` and
  logs `trash-failed`; it never falls back to a permanent delete. Only an
  explicit `-Permanent` switch performs a real, unrecoverable delete.
- Supports `-WhatIf`/`-Confirm` natively via `SupportsShouldProcess`.
- Logs every attempt — success, rejection, or failure — to
  `%LOCALAPPDATA%\WinClean\logs\operations.jsonl`, independent of whatever
  the command printed to the console. A broken log (unwritable directory)
  warns once and continues; it never blocks the underlying action.

## Layer 3 — `clean` previews by default

`Invoke-WinCleanClean` always shows a preview and only deletes when called
with `-Apply`. This is intentionally *stricter* than relying on
PowerShell's own `-WhatIf`/`-Confirm` machinery, which would proceed
without prompting on a bare call for anything below the "High"
confirm-impact threshold. The catalog itself
(`Get-WinCleanCleanCatalog`) is small and deliberately conservative: every
entry must be locally rebuildable or disposable (temp files, browser
cache, Windows Update download cache, thumbnail cache, error-report
queue). Admin-required entries (Windows Update cache) are skipped with a
message rather than self-elevating — Win Clean never relaunches itself
with `Start-Process -Verb RunAs`.

## Layer 4 — `uninstall` never guesses

`Uninstall-WinCleanApp` runs the app's own uninstall command (registry
`UninstallString`/`QuietUninstallString`, or `Remove-AppxPackage` for
Store apps) rather than deleting files itself. If a registry
`InstallLocation` value still points at an existing folder after a
successful uninstall, Win Clean reports its path and size and stops —
it does not delete it automatically. Automating that specific step is the
single highest-risk feature this project could add, because "does this
folder still belong to the app I just removed" is exactly the kind of
judgment call that turns into a wildcard/vendor-prefix match if rushed.
Any future PR attempting that needs deliberately narrow, exact-match logic
(the registry's own recorded path, nothing derived from the app's name)
and its own dedicated test coverage before merge.

## Test coverage

- `Tests/Safety.Tests.ps1` — protected-root membership and the full
  validation gate. Platform-independent (pure string logic), runs on any
  OS with PowerShell installed.
- `Tests/RemoveSafely.Tests.ps1` — the delete/Recycle-Bin/fail-closed
  contract. Two tests need a real `C:\Windows` and a real Recycle Bin and
  are skipped off Windows (`-Skip:(-not $IsWindows)`); a third test proves
  the fail-closed behavior using whatever this platform's Recycle Bin
  failure actually looks like.
- `Tests/Uninstall.Tests.ps1` — inventory logic and the "never fabricate
  an uninstall command" guarantee.

Before merging any change to `Modules/Core/Safety.ps1` or
`Modules/Core/Remove-Safely.ps1`, run the full suite
(`Invoke-Pester ./Tests/`) and add a case for the new behavior — these two
files are the only thing standing between a bad path and a real delete.
