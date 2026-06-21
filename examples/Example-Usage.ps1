<#
    Example-Usage.ps1
    Copy/paste these snippets (or run the file section by section). They assume
    you are in the repo root. For anything that changes the system, run from an
    elevated PowerShell session.
#>

# Import the module from the repo (or `Import-Module .\WindowsDiagnosticTool.psd1`).
Import-Module "$PSScriptRoot\..\WindowsDiagnosticTool.psd1" -Force

# 1) Quickest start -- scan the last 7 days, report only (no changes):
Invoke-WindowsDiagnostic

# 2) Look further back, focus on errors+critical only, write the report somewhere known:
Invoke-WindowsDiagnostic -Days 30 -MinSeverity Error -ReportPath "$HOME\Desktop\diag.html"

# 3) See everything the tool can detect and fix:
Get-WindowsDiagnosticRule | Format-Table Id, Category, Severity, FixName -AutoSize

# 4) Preview what WOULD be fixed, without changing anything (safe dry run):
Invoke-WindowsDiagnostic -AutoFix -WhatIf

# 5) Apply all applicable fixes, confirming each one (recommended; run elevated):
Invoke-WindowsDiagnostic -AutoFix

# 6) Apply all fixes unattended (no prompts; run elevated):
Invoke-WindowsDiagnostic -AutoFix -Confirm:$false

# 7) Scan, then repair only the network-related problems found:
Get-WindowsDiagnosticReport | Where-Object Category -eq 'Network' | Repair-WindowsProblem

# 8) Fix a specific problem by rule id (scans, then fixes just that one):
Repair-WindowsProblem -RuleId UPD-FAILURE

# 9) Auto-fix everything EXCEPT the disk scan, and allow reboot-requiring fixes:
Invoke-WindowsDiagnostic -AutoFix -ExcludeFixId SYS-DISK-ERROR -IncludeRebootFixes -Confirm:$false

# 10) Get the findings as objects for your own automation/reporting:
$problems = Invoke-WindowsDiagnostic -Quiet -NoHtmlReport -PassThru
$problems | Where-Object Severity -eq 'Critical' | Select-Object RuleId, Name, Count

# 11) Export machine-readable results (for scheduled tasks / dashboards):
Invoke-WindowsDiagnostic -Quiet -NoHtmlReport -JsonPath "$HOME\diag.json" -CsvPath "$HOME\diag.csv"

# 12) Run a specific fix action directly, no detected problem required:
Repair-WindowsProblem -ApplyFix restart-spooler            # "can't print"
Repair-WindowsProblem -ApplyFix clean-temp, flush-dns      # several at once

# 13) See every available fix action id:
(Get-WindowsDiagnosticRule).FixId | Sort-Object -Unique
