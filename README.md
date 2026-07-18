# Wincleaner
# WinCleaner

> A fast Windows CLI for reclaiming disk space — junk cleaning, app uninstalling, and disk usage analysis, all from the terminal. The Windows answer to `mole`.

[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-blue)]()
[![Python](https://img.shields.io/badge/python-3.11%2B-green)]()
[![License](https://img.shields.io/badge/license-MIT-lightgrey)]()

---

## ⚠️ Read this first

WinCleaner performs **destructive, elevated operations**. Deleting the wrong files or uninstalling the wrong package can break your system.

- Every destructive command supports `--dry-run` — run it first.
- Nothing is deleted without confirmation unless you pass `--yes`.
- Some operations require an **Administrator** shell. WinCleaner will self-elevate (UAC prompt) when needed.
- Use at your own risk. No warranty.

---

## Features

| Command | What it does |
|---|---|
| `clean` | Removes temp files, caches, Update leftovers, Recycle Bin, logs, dumps, thumbnails, browser caches, and more |
| `analyze` | Scans a drive/folder and reports the largest files & folders, with an optional duplicate finder |
| `uninstall` | Lists installed programs (registry / MSI / winget / UWP) and removes them, including residual files and registry keys |
| `doctor` | One-shot storage health report: free space, reclaimable space, biggest offenders |

Cross-cutting:
- **Dry-run mode** on every destructive action
- **Machine-readable output** with `--json`
- **Protected-path whitelist** so system-critical folders are never touched
- **Auto-elevation** via UAC when admin rights are required
- **Registry backups** taken before any uninstall leftover purge

---

## Install

### From release (recommended)
Download `wincleaner.exe` from [Releases](#) and drop it anywhere on your `PATH`.

```powershell
# verify
wincleaner --version
```

### With pipx / pip

```powershell
pipx install wincleaner
# or
pip install wincleaner
```

### From source

```powershell
git clone https://github.com/<you>/wincleaner
cd wincleaner
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .
```

---

## Usage

```
wincleaner <command> [targets] [options]
```

### Clean

```powershell
# Preview everything that would be removed (safe)
wincleaner clean --all --dry-run

# Clean specific categories
wincleaner clean --temp --cache --recycle --thumbnails

# Full clean, skip confirmation
wincleaner clean --all --yes

# Everything except a folder you care about
wincleaner clean --all --exclude "C:\Users\me\AppData\Local\MyApp"
```

**Clean targets**

| Flag | Removes |
|---|---|
| `--temp` | `%TEMP%`, `C:\Windows\Temp`, Prefetch |
| `--cache` | Font cache, icon cache, Delivery Optimization files |
| `--updates` | `SoftwareDistribution\Download` (stops `wuauserv` first) |
| `--recycle` | Recycle Bin on all drives |
| `--logs` | `C:\Windows\Logs`, CBS logs, setup logs |
| `--dumps` | Minidumps and `MEMORY.DMP` |
| `--thumbnails` | Explorer thumbnail & icon cache DBs |
| `--browsers` | Chrome, Edge, Firefox caches |
| `--wer` | Windows Error Reporting archives |
| `--dns` | Flushes DNS resolver cache |
| `--component-store` | `DISM /StartComponentCleanup` (deep, slow) |
| `--windows-old` | Removes `C:\Windows.old` if present |
| `--all` | All of the above |

### Analyze

```powershell
# Largest 20 items on C:
wincleaner analyze C:\ --top 20

# Only show items over 500 MB
wincleaner analyze C:\Users --min-size 500MB

# Find duplicate files by hash
wincleaner analyze D:\ --duplicates

# JSON for scripting
wincleaner analyze C:\ --top 50 --json
```

### Uninstall

```powershell
# List installed programs, biggest first
wincleaner uninstall list --sort size

# Remove a program
wincleaner uninstall remove "Some App"

# Remove and purge leftover files + registry keys (backup taken automatically)
wincleaner uninstall remove "Some App" --leftovers

# Remove a UWP / Store app
wincleaner uninstall remove --uwp "Microsoft.SomePackage"
```

### Doctor

```powershell
wincleaner doctor
```

```
C:  464 GB total   38 GB free   ⚠ low
Reclaimable:  ~12.4 GB
  Windows Update cache ....... 6.1 GB
  Temp files ................. 2.8 GB
  Recycle Bin ................ 1.9 GB
  Browser caches ............. 1.1 GB
  Thumbnail cache ............ 0.5 GB
Run  wincleaner clean --all --dry-run  to review.
```

---

## Global options

| Option | Description |
|---|---|
| `-n, --dry-run` | Show what would happen, change nothing |
| `-y, --yes` | Skip confirmation prompts |
| `--json` | Machine-readable output |
| `-v, --verbose` | Per-file detail and timings |
| `--log <file>` | Append a run log |
| `--no-elevate` | Fail instead of prompting for UAC |

---

## Requirements

- Windows 10 (1809+) or Windows 11
- Python 3.11+ (source install only)
- `winget` — optional, enables extra uninstall coverage
- Administrator rights for `--updates`, `--component-store`, `--windows-old`, and some uninstalls

---

## How it works

WinCleaner is a thin, auditable layer over documented Windows mechanisms — it does not touch anything undocumented:

- **File ops** via `shutil` / `os`, gated by a protected-path whitelist.
- **Elevation** via `ctypes` → `ShellExecuteW("runas", ...)`.
- **Update cache** by stopping `wuauserv` / `bits`, clearing, and restarting.
- **Component store & Windows.old** via `DISM` and `cleanmgr`.
- **Program inventory** by reading the `Uninstall` registry hives (HKLM + HKCU, 32/64-bit views), MSI, `winget`, and `Get-AppxPackage`.
- **Uninstall** by invoking each program's own `UninstallString` / `QuietUninstallString`.

Before any leftover purge, the affected registry subtree is exported to `%LocalAppData%\WinCleaner\backups\`.

---

## Project structure

```
wincleaner/
├── wincleaner/
│   ├── __main__.py        # CLI entry / arg parsing
│   ├── elevate.py         # UAC self-elevation
│   ├── safety.py          # protected paths, confirmation, dry-run
│   ├── clean/             # one module per clean target
│   ├── analyze/           # disk walk, sizing, duplicate finder
│   ├── uninstall/         # registry/MSI/winget/UWP backends
│   └── report.py          # human + JSON output
├── tests/
├── pyproject.toml
└── README.md
```

---

## Roadmap

- [ ] Scheduled cleans via Task Scheduler
- [ ] Config file for default targets & excludes
- [ ] TUI mode (interactive treemap)
- [ ] Portable ARM64 build
- [ ] Restore point creation before deep cleans

---

## Disclaimer

WinCleaner deletes files and removes software. Review with `--dry-run`, keep backups, and understand each command before running it with `--yes`. The authors are not responsible for data loss or system damage.

## License

MIT
