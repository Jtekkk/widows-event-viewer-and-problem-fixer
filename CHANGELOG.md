# Changelog

All notable changes to the Windows Diagnostic & Problem-Fixer tool.

## [1.1.0]

### Added
- **6 new detection rules:** device driver load failures (Kernel-PnP 219),
  Volume Shadow Copy / backup errors (VSS), Windows Installer (MSI) failures,
  Group Policy processing errors, user-profile load problems, and account
  lockouts.
- **2 new fix actions:** `refresh-grouppolicy` (gpupdate /force) and
  `restart-spooler` (restart Print Spooler and clear the stuck print queue).
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
