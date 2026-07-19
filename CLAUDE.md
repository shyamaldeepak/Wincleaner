# Win Clean — Agent Guide

Shared source of truth for AI agents working on this repo. Read
`SECURITY.md` first if you're touching anything that deletes, uninstalls,
or resolves a path — this file covers architecture, tooling, and PowerShell
pitfalls specific to this codebase.

## Project

Win Clean is a native PowerShell terminal CLI for Windows 10/11: disk usage
analysis (`analyze`), known-safe cache cleanup (`clean`), app uninstall
(`uninstall`), and RAM/CPU/disk diagnostics (`status`). No WSL, no compiled
binary, no other runtime — PowerShell 5.1 (ships with Windows) or
PowerShell 7+ only. It intentionally does not try to be cross-platform; it
is the Windows-native counterpart to a similar idea, not a port of one.

## Repository map

- `winclean.ps1` — the CLI entry point. Deliberately has **no typed
  `param()` block**; read its `.NOTES` block before changing argument
  parsing, it documents two confirmed PowerShell splatting gotchas (below).
- `winclean.cmd` — PATH shim so `winclean` resolves from cmd.exe and
  PowerShell alike (a bare `.ps1` isn't directly executable from PATH).
- `WinClean.psd1` / `WinClean.psm1` — module manifest / root module. The
  root module dot-sources `Modules/Core/*.ps1` before `Modules/*.ps1`
  (safety core must load first) and exports every function so Pester can
  test internals directly.
- `Modules/Core/` — shared by every command:
  - `Safety.ps1` — `Test-WinCleanPathSafeToDelete`, the protected-root
    deny-list, reparse-point resolution. Read `SECURITY.md` before editing.
  - `Remove-Safely.ps1` — `Remove-WinCleanItem`, the only function allowed
    to delete anything.
  - `Logging.ps1` — the JSON-lines operation log.
  - `Elevation.ps1` — `Test-WinCleanIsAdmin` only. There is deliberately no
    self-elevation helper — Win Clean never relaunches itself with
    `Start-Process -Verb RunAs`; admin-required actions just skip with a
    message. (An earlier `Invoke-WinCleanElevated` was removed for having
    zero callers — see "dead code" note below.)
  - `Format.ps1` — `Format-WinCleanBytes`, shared byte-count display.
- `Modules/Status.ps1`, `Analyze.ps1`, `Clean.ps1`, `Uninstall.ps1` — one
  command each, all built on the Core layer above.
- `Tests/*.Tests.ps1` — Pester, one file per module.
- `install.ps1` — per-user install (copies to
  `%LOCALAPPDATA%\Programs\WinClean`, adds to user `PATH`). No admin
  required, no separate uninstaller script yet (delete the folder + PATH
  entry manually).

## Commands

```powershell
Invoke-Pester ./Tests/                              # full suite
Invoke-Pester ./Tests/Safety.Tests.ps1               # one file
Import-Module ./WinClean.psd1 -Force                 # load for interactive testing
.\winclean.ps1 status -Json
.\winclean.ps1 analyze -Path C:\Users\me -NonInteractive -Top 20
.\winclean.ps1 clean                                 # preview only
.\winclean.ps1 clean -Apply                          # actually deletes
.\winclean.ps1 uninstall -Filter <name>
```

This project was built and is regularly exercised on **macOS** with
PowerShell 7 installed via `brew install powershell` specifically so Pester
can run for real instead of being reviewed by eye. If `pwsh` isn't
installed in your environment, install it before claiming any change here
is verified — static review of PowerShell is not a substitute for running
it, and running it here already caught four real bugs (below) that a
by-eye review missed.

## Critical safety rules

- Never call `Remove-Item` (or any other delete) on a user-supplied or
  scan-derived path outside `Remove-WinCleanItem`
  (`Modules/Core/Remove-Safely.ps1`).
- Every new deletion or uninstall path must go through
  `Test-WinCleanPathSafeToDelete` before touching the filesystem.
- Never add a leftover/uninstall matcher that isn't an exact registry
  value or exact bundle/package identity. No name-prefix, vendor-wide, or
  wildcard matching — see `SECURITY.md` § Layer 4 for why.
- Never add a self-elevation path (`Start-Process -Verb RunAs` relaunching
  the whole app). Admin-required actions skip with a message instead.
- `winclean clean` must keep previewing by default; `-Apply` (not
  `-Confirm:$false`, not a bare call) is the only thing that should ever
  cause it to delete.
- A failed Recycle Bin move must fail closed (return `$false`, never fall
  back to permanent delete) — this is the load-bearing invariant in
  `Remove-WinCleanItem`, keep the try/catch structure that enforces it.

## PowerShell pitfalls hit on this codebase (real bugs, not theoretical)

These cost real debugging time during initial development. Re-read before
touching the same area.

- **Splatting `@array` only preserves `-Flag` recognition for the literal
  variable `$args`, reassigned via a direct statement — not an `if/else`
  expression, and not any other variable name.** Confirmed by direct
  testing: `$Rest = $args[1..($args.Count-1)]; Inner @Rest` silently
  degrades to *positional* binding (`-Json` gets bound character-by-
  character to unrelated `int` parameters — you'll see garbage numbers
  like ASCII codes in the output, that's the tell). Renaming the variable
  back to `$args` fixes the first half of the bug; using `$args = if (...)
  {a} else {b}` (an if/else *expression*) instead of `if (...) { $args = a
  } else { $args = b }` (if/else as a *statement*, each branch assigning
  directly) reintroduces it even with the right variable name. This is why
  `winclean.ps1` has no typed `param()` block and reassigns `$args` to
  itself with a statement-form `if`. If you ever see a numeric parameter
  receiving what looks like an ASCII/char-code value when a flag was
  passed, this is almost certainly the cause — check how the array being
  splatted was constructed.
- **`Join-Path` on a bare drive letter (`"C:"`, no trailing path segment)
  throws "Cannot find drive"** if there's no live PSDrive with that name —
  which is always true on non-Windows and can be true in constrained
  Windows environments. `Get-WinCleanProtectedRoots` originally used
  `Join-Path $systemDrive 'Users'` for several deny-list entries; fixed to
  plain string concatenation (`"$systemDrive\Users"`). Prefer string
  concatenation over `Join-Path` for anything built from a bare drive
  letter.
- **A `[Parameter(Mandatory)][string]$Path` parameter rejects an empty
  string `''` at PowerShell's own binder**, before your function body ever
  runs — with a generic `ParameterBindingValidationException`, not your
  own error message. If a function's contract is "handle empty input
  gracefully and return a typed rejection object" (as
  `Test-WinCleanPathSafeToDelete` does), add `[AllowEmptyString()]`
  explicitly so empty input actually reaches your logic instead of
  crashing one level up.
- **Windows-only env vars (`$env:SystemRoot`, `$env:ProgramFiles`,
  `$env:ProgramData`, `$env:LOCALAPPDATA`) are empty on non-Windows hosts**,
  and `Join-Path`/functions with `[Parameter(Mandatory)]` on their `-Path`
  parameter throw immediately on `$null`. `Get-WinCleanProtectedRoots` and
  `Get-WinCleanLogPath` both have hardcoded Windows-shaped fallbacks for
  exactly this reason — not just to make macOS testing possible, but
  because a safety-critical deny-list crashing (or silently protecting
  nothing) in *any* stripped-down execution environment is a real
  regression, not just a test-host inconvenience. Apply the same pattern
  (fallback default, not just an assumption the env var is set) to any new
  code that reads one of these variables.
- **`.NET path APIs don't understand Windows drive syntax on non-Windows
  hosts.** `[System.IO.Path]::GetFullPath("C:\Windows")` on macOS/Linux
  treats the backslash as a literal character and prepends the current
  working directory instead of normalizing a Windows path;
  `IsPathRooted("C:\Windows")` returns `$false` there. This means
  `Safety.Tests.ps1`'s "path validation gate" tests that call
  `Test-WinCleanPathSafeToDelete` (which goes through real path
  resolution) can pass for accidentally-right reasons on a non-Windows
  test host, while tests that call `Test-WinCleanProtectedPath` directly
  (pure string matching, no `.NET` path parsing) are genuinely
  platform-independent. Know which kind of test you're writing.
- **Reading `$args[N]` via a single-bound range (`$args[1..1]` when
  exactly one element remains) collapses to a scalar, not a one-element
  array**, when the result flows through certain assignment contexts.
  Wrap in `@(...)` if you need to guarantee array-ness — but note this
  alone does not fix the splat-flag-recognition issue above; both fixes
  are needed together.
- **Dead code check before merging**: `Invoke-WinCleanElevated` was
  written per the original design (an elevation-relaunch helper) but never
  wired to any caller — `Clean.ps1`'s admin-required catalog entries just
  skip with a message instead. Caught by grepping for zero non-definition
  references and removed. Before adding a new Core helper "for future use
  by X", either wire it up in the same change or don't add it — this repo
  has already had one orphaned helper.

## Verification

- `Invoke-Pester ./Tests/` — must be 0 failed before any change is
  considered done. 2 tests are expected to skip on non-Windows
  (`RemoveSafely.Tests.ps1`, guarded by `-Skip:(-not $IsWindows)`).
- For anything touching `winclean.ps1` itself (argument parsing/dispatch),
  run actual CLI invocations, not just the Pester suite — the splat bug
  above was invisible to unit tests that call module functions directly
  and only showed up when running `.\winclean.ps1 status -Json` for real.
- For anything touching `Safety.ps1` or `Remove-Safely.ps1`, add a Pester
  case before merging — see `SECURITY.md` § Test coverage.
- Nothing in this repo has been run on real Windows 10/11 yet (built and
  tested on macOS with PowerShell 7). Treat any Windows-only code path
  (Recycle Bin, registry uninstall, Appx) as unverified until it's actually
  run there, and say so plainly rather than implying it's been tested.
