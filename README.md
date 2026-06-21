# Windows Diagnostic & Problem-Fixer

A PowerShell tool that **scans the Windows Event Logs (and live system state) for
known problems, then applies safe, automatic fixes.** Think of it as an
Event-Viewer triage assistant: instead of scrolling through thousands of red
error entries, you get a prioritized list of *real* problems — and one command to
repair the ones that have a known fix.

```
==============================================================================
  WINDOWS DIAGNOSTIC REPORT
==============================================================================
  Computer : DESKTOP-A1B2C3  (Windows 11 Pro)
  Uptime   : 4d 6h 12m    Elevated: True

  SUMMARY
  -------
  Critical : 1
  Errors   : 3
  Warnings : 2
  Auto-fixable problems : 4 of 6

  DETECTED PROBLEMS
  -----------------
  [1] CRITICAL Disk I/O / bad block errors  (Disk)
       Occurrences : 12    Last seen : 2026-06-20 22:41
       Auto-fix    : Scan system drive for errors (chkdsk /scan)
  [2] ERROR    Service crashed or failed to start  (Services)
       Occurrences : 5     Last seen : 2026-06-21 08:03
       Auto-fix    : Restart crashed services & set auto-recovery
  ...
```

---

## What it does

1. **Scans** the relevant event logs (`System`, `Application`, `Setup`,
   `Security`, the *Diagnostics-Performance* operational log) for
   Critical/Error (optionally Warning) events over a time window.
2. **Detects** known problems by matching events against a catalog of rules,
   and runs **live health checks** (low disk space, pending reboot, SMART
   predictive-failure).
3. **Fixes** each detected problem that has a known, safe remedy — SFC/DISM,
   `chkdsk`, service restart + recovery, Windows Update reset, DNS/DHCP, network
   stack reset, time resync, temp-file cleanup.
4. **Reports** to the console *and* a self-contained **HTML report** (plus JSON/CSV),
   with a polished **desktop app (GUI)**.

Safety is built in: fixes are **opt-in** (`-AutoFix`), support **`-WhatIf`**
previews, **confirm before each change** by default, and create a **System
Restore point** first.

---

## Get the app (.exe)

You don't need to install PowerShell modules — grab the compiled app:

1. Open the repo's **Actions** tab → the latest **Build EXE** run → download the
   **`WindowsDiagnostic-exe`** artifact. It contains:
   - **`WindowsDiagnostic.exe`** — the GUI app (double-click to run)
   - **`WindowsDiagnostic-CLI.exe`** — the command-line version
2. Run `WindowsDiagnostic.exe`. Click **Scan**, then **Fix Selected** /
   **Fix All Safe**. Use the in-app **Run as admin** button to enable repairs.

Tagged releases (`v*`) also attach the EXEs to the GitHub **Releases** page.

Prefer to build it yourself on Windows? `pwsh -File build\Build-Exe.ps1`
(auto-installs `ps2exe`, writes the EXEs to `dist\`).

---

## Requirements

| | |
|---|---|
| OS | Windows 10 / 11 / Server 2016+ |
| PowerShell | Windows PowerShell 5.1 **or** PowerShell 7+ (on Windows) |
| Privileges | Scanning works as a standard user; **fixes and the Security log require Administrator** |

> The detection/reporting logic is cross-platform for testing, but the actual
> scanning (`Get-WinEvent`) and fixes only run on Windows.

---

## Quick start

```powershell
# Clone, then from the repo folder:

# 1. Just look (read-only) — scan last 7 days, write console + HTML report
.\Invoke-Diagnostic.ps1

# 2. Open the HTML report automatically, look back 30 days
.\Invoke-Diagnostic.ps1 -Days 30 -OpenReport

# 3. Preview every fix without changing anything
.\Invoke-Diagnostic.ps1 -AutoFix -WhatIf

# 4. Relaunch elevated and apply fixes (you confirm each one)
.\Invoke-Diagnostic.ps1 -AutoFix -Elevate

# 5. Apply everything unattended, elevated
.\Invoke-Diagnostic.ps1 -AutoFix -Confirm:$false -Elevate
```

Or import the module and use the cmdlets directly:

```powershell
Import-Module .\WindowsDiagnosticTool.psd1
Invoke-WindowsDiagnostic                 # scan + report
Invoke-WindowsDiagnostic -AutoFix        # scan + fix (confirms each)
```

GUI (pro desktop dashboard — scan, filter/search, fix selected, export):

```powershell
.\gui\Start-DiagnosticGui.ps1            # or just run WindowsDiagnostic.exe
Import-Module .\WindowsDiagnosticTool.psd1; Show-DiagnosticGui   # from the module
```

If you get an execution-policy error, start PowerShell with
`-ExecutionPolicy Bypass`, or run `Set-ExecutionPolicy -Scope Process Bypass`.

---

## Commands

| Command | Purpose |
|---|---|
| `Invoke-WindowsDiagnostic` | Main entry point: scan, analyze, optionally fix, and report. |
| `Get-WindowsDiagnosticReport` | Read-only scan that returns findings and writes a report (never fixes). |
| `Repair-WindowsProblem` | Apply fixes to selected findings (pipeline) or by `-RuleId`. |
| `Get-WindowsDiagnosticRule` | List everything the tool can detect and fix. |

### Key parameters for `Invoke-WindowsDiagnostic`

| Parameter | Description | Default |
|---|---|---|
| `-Days <int>` | How far back to scan the logs. | `7` |
| `-MinSeverity <level>` | Lowest severity to report/fix: `Warning`, `Error`, or `Critical`. | `Warning` |
| `-AutoFix` | Apply automatic fixes for detected problems. | off |
| `-FixId <ids>` | Only fix these rule IDs / fix IDs. | all |
| `-ExcludeFixId <ids>` | Skip these. | none |
| `-Category <names>` | Limit to categories (Disk, Network, Services, …). | all |
| `-IncludeRebootFixes` | Allow fixes that need a reboot (e.g. network reset). | off |
| `-NoRestorePoint` | Don’t create a System Restore point before fixing. | off |
| `-ReportPath <path>` | Where to write the HTML report. | temp folder |
| `-NoHtmlReport` / `-Quiet` | Suppress the HTML report / console output. | off |
| `-JsonPath` / `-CsvPath <path>` | Also export findings as JSON / CSV for automation. | none |
| `-PassThru` | Emit finding objects to the pipeline. | off |
| `-WhatIf` / `-Confirm` | Standard PowerShell safety switches. | confirm on |

---

## What it detects and fixes

| Rule ID | Problem | Category | Severity | Automatic fix |
|---|---|---|---|---|
| `SYS-DISK-ERROR` | Disk I/O / bad-block errors | Disk | Critical | `chkdsk /scan` |
| `SYS-NTFS-CORRUPT` | NTFS file-system corruption | Disk | Error | `chkdsk /scan` |
| `SYS-KERNELPOWER-41` | Unexpected shutdown / power loss | System | Critical | *manual guidance* |
| `SYS-BUGCHECK-1001` | Blue Screen / bug check | System | Critical | SFC + DISM |
| `SYS-TIME-SERVICE` | Clock out of sync | System | Warning | `w32tm /resync` |
| `SYS-DCOM-10016` / `SYS-DCOM-10010` | DCOM permission / timeout | System | Warning | *manual guidance* |
| `SYS-SERVICE-CRASH` | Service crashed / failed to start | Services | Error | restart + set auto-recovery |
| `SYS-UNEXPECTED-SHUTDOWN` | Dirty shutdown (6008) | System | Error | *manual guidance* |
| `SYS-WMI-ERROR` | WMI / management errors | System | Error | verify/repair WMI |
| `UPD-FAILURE` | Windows Update failures | Updates | Error | reset Update components |
| `NET-DNS-FAIL` | DNS resolution failures | Network | Warning | flush DNS |
| `NET-DHCP-FAIL` | DHCP / IP address failures | Network | Warning | release/renew DHCP |
| `NET-TCPIP` | TCP/IP stack errors | Network | Warning | renew / reset stack |
| `APP-CRASH-1000` | Application crashes | Application | Error | SFC + DISM |
| `APP-HANG-1002` | Application hangs | Application | Warning | *manual guidance* |
| `APP-NET-RUNTIME` | .NET runtime crashes | Application | Error | SFC + DISM |
| `APP-SEARCH-INDEX` | Windows Search corruption | Application | Warning | rebuild search index |
| `APP-MSI-FAIL` | Windows Installer (MSI) failures | Application | Error | *manual guidance* |
| `APP-PERFLIB` | Performance counter errors | Performance | Warning | *manual guidance* |
| `HW-WHEA-ERROR` | Hardware errors (WHEA) | Hardware | Critical | *manual guidance* |
| `SYS-DRIVER-LOAD` | Device driver failed to load | Hardware | Warning | *manual guidance* |
| `SYS-VSS-ERROR` | Volume Shadow Copy (backup) errors | System | Error | *manual guidance* |
| `SYS-GROUPPOLICY` | Group Policy processing errors | System | Warning | `gpupdate /force` |
| `APP-USER-PROFILE` | User profile load problems | System | Error | *manual guidance* |
| `PERF-SLOW-BOOT` | Slow boot / shutdown | Performance | Warning | clean temp files |
| `SEC-LOGON-FAIL` | Repeated failed sign-ins | Security | Warning | *manual guidance* |
| `SEC-ACCOUNT-LOCKOUT` | Account lockouts | Security | Warning | *manual guidance* |
| `SEC-DEFENDER-THREAT` | Malware detected by Defender | Security | Critical | update + quick scan |
| `SEC-DEFENDER-UPDATE` | Defender signatures out of date | Security | Warning | update + quick scan |
| `LIVE-DISK-SPACE` | Low free disk space | Disk | Warning/Critical | clean temp files |
| `LIVE-REBOOT-PENDING` | Pending reboot | System | Warning | *manual guidance* |
| `LIVE-SMART-FAIL` | Drive predicting failure (SMART) | Hardware | Critical | *manual guidance* |

…and more — **30 detection rules** in total. `Get-WindowsDiagnosticRule | Format-Table`
shows them all live, including which fixes need elevation or a reboot.

### The fix actions

`sfc-dism` · `chkdsk-scan` · `restart-service` · `reset-windowsupdate` ·
`flush-dns` · `renew-dhcp` · `reset-network` (reboot) · `resync-time` ·
`clean-temp` · `refresh-grouppolicy` · `restart-spooler` ·
`dism-componentcleanup` · `repair-wmi` · `rebuild-search` · `defender-scan` ·
`restart-explorer` · `reset-firewall` (**17 fixes**). Each is implemented in
[`src/Private/Get-DiagFixAction.ps1`](src/Private/Get-DiagFixAction.ps1) and
returns a structured result (success, reboot-required, message, full output).

You can also run a fix action directly, without a detected problem:

```powershell
Repair-WindowsProblem -ApplyFix restart-spooler          # fix "can't print"
Repair-WindowsProblem -ApplyFix clean-temp, flush-dns    # run several
Repair-WindowsProblem -ApplyFix reset-network -IncludeRebootFixes
```

### Export results for automation

```powershell
# Machine-readable output alongside the report (great for scheduled runs):
Invoke-WindowsDiagnostic -JsonPath C:\Logs\diag.json -CsvPath C:\Logs\diag.csv -Quiet
```

---

## Safety model

- **Read-only by default.** Without `-AutoFix`, nothing is changed.
- **Dry run.** `-AutoFix -WhatIf` prints exactly which fixes would run.
- **Confirmation.** Fixes are `ConfirmImpact = High`, so you’re asked before each
  change unless you pass `-Confirm:$false`.
- **Restore point.** A System Restore point is created before the first fix
  (skip with `-NoRestorePoint`).
- **Reversible-leaning fixes.** Caches are *renamed* (not deleted) so Windows can
  rebuild them; `chkdsk` runs in online read-only `/scan` mode and only *reports*
  if an offline `/f` is needed; reboot-requiring fixes are excluded unless you opt
  in with `-IncludeRebootFixes`.
- **Full transcript.** Pass `-LogFile <path>` to record every action; the HTML
  report also embeds the run log.

> ⚠️ These fixes change system state. Review the report first, keep backups, and
> prefer `-WhatIf` before a first unattended run. Hardware problems (WHEA, SMART)
> have **no** software fix — back up and replace failing hardware.

---

## Project layout

```
Invoke-Diagnostic.ps1            # standalone launcher (no install needed)
WindowsDiagnosticTool.psd1/.psm1 # module manifest + loader
src/
  Private/                       # engine: scanner, rules, fixes, analysis, reports
  Public/                        # exported cmdlets + Show-DiagnosticGui
gui/Start-DiagnosticGui.ps1      # GUI launcher (calls Show-DiagnosticGui)
build/Build-Exe.ps1              # compiles the GUI + CLI executables (ps2exe)
.github/workflows/               # CI (tests) + Build EXE (publishes the .exe)
tests/                           # Pester tests (cross-platform)
examples/Example-Usage.ps1       # copy/paste recipes
```

## Extending it

Add a detection rule in `src/Private/Get-DiagRule.ps1` (set `FixId = $null` for
advisory-only), and—if it needs a new repair—add an action in
`src/Private/Get-DiagFixAction.ps1`. The Pester suite checks that every rule’s
`FixId` resolves to a real action, so run the tests after editing.

## Testing

```powershell
Invoke-Pester -Path .\tests
```

The tests validate rule/fix integrity, event→finding matching, thresholds,
sorting, and HTML generation without touching the live event log.

## License

MIT — see [LICENSE](LICENSE).
