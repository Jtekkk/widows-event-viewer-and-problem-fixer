#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the graphical front-end (pro UI) for the Windows Diagnostic &
    Problem-Fixer tool.

.DESCRIPTION
    Thin wrapper: imports the module from the repo and opens the WPF dashboard.
    Run from an elevated session (or use the in-app "Run as admin" button) so
    that fixes and the Security log are available.

.NOTES
    Windows only (requires .NET WPF). For the command line, use
    Invoke-WindowsDiagnostic / Repair-WindowsProblem instead.
#>
[CmdletBinding()]
param()

if ($env:OS -ne 'Windows_NT') { Write-Error 'The GUI requires Windows (WPF).'; return }

$root     = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'WindowsDiagnosticTool.psd1'
if (-not (Test-Path -LiteralPath $manifest)) { throw "Cannot find WindowsDiagnosticTool.psd1 in '$root'." }
Import-Module $manifest -Force -ErrorAction Stop

# Pass this script's path so the in-app "Run as admin" button can relaunch it.
Show-DiagnosticGui -RelaunchPath $PSCommandPath
