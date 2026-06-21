# Changelog

All notable changes to the Windows Diagnostic & Problem-Fixer tool.

## [1.1.0]

### Added
- **Standalone executables.** `build/Build-Exe.ps1` bundles the whole tool into
  `WindowsDiagnostic.exe` (GUI) and `WindowsDiagnostic-CLI.exe` via ps2exe, and a
  **Build EXE** GitHub Actions workflow compiles them on Windows and publishes
  them as downloadable artifacts / Release assets.
- **Pro GUI** (`Show-DiagnosticGui`): a dark, modern WPF dashboard with summary
  cards, severity-coloured grid, text search + severity filter, a details pane,
  progress, an in-app "Run as admin" button, "Fix Selected" / "Fix All Safe",
  and HTML/JSON/CSV export.
- **14 new detection rules** (30 total): storage controller resets, NTFS,
  DCOM 10010, dirty shutdown (6008), WMI errors, TCP/IP stack, Windows Search
  corruption, Perflib, MSI installer, driver load, VSS/backup, Group Policy,
  user-profile, account lockout, and **Microsoft Defender threat / signature**
  detection.
- **8 new fix actions** (17 total): `refresh-grouppolicy`, `restart-spooler`,
  `dism-componentcleanup`, `repair-wmi`, `rebuild-search`, `defender-scan`,
  `restart-explorer`, `reset-firewall`.
- **`Repair-WindowsProblem -ApplyFix <id>`** — run any fix action directly,
  without needing a detected problem (e.g. `-ApplyFix restart-spooler`).
- **JSON / CSV export** via `-JsonPath` and `-CsvPath` on
  `Invoke-WindowsDiagnostic` / `Get-WindowsDiagnosticReport` for automation.
- **Scan progress** (`Write-Progress`) while reading event logs.
- **GitHub Actions CI** that parse-checks, runs Pester, and performs a real
  end-to-end scan on `windows-latest` (plus logic tests on Linux).

### Changed
- **More reliable detection:** the scanner now also queries each rule's specific
  event IDs *regardless of log level*, so events logged at Information level
  (e.g. BugCheck 1001) are no longer missed.
- Simplified the severity model to a single `-MinSeverity` knob (replaces the
  separate `-IncludeWarnings` switch). The scan window's levels follow it.

### Fixed
- Empty event scans no longer cause a parameter-binding error (PowerShell
  unrolling an empty collection to `$null`).
- Avoided `@()`/`,` directly over `List[object]` values, which throws
  "Argument types do not match" on some PowerShell builds.

## [1.0.0]

### Added
- Initial release: event-log scanning across the key Windows logs, rule-based
  problem detection, live health checks (disk space, pending reboot, SMART),
  automatic fixes (SFC/DISM, chkdsk, service recovery, Windows Update reset,
  DNS/DHCP, network reset, time resync, cleanup), console + self-contained HTML
  reporting, an optional WPF GUI, a standalone launcher with self-elevation,
  and a Pester test suite.
