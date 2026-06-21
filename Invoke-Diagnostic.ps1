#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone launcher for the Windows Diagnostic & Problem-Fixer tool.

.DESCRIPTION
    Imports the WindowsDiagnosticTool module from this folder and runs a scan,
    optionally applying automatic fixes. Use this when you just want to run the
    tool from a clone without installing the module.

    Add -Elevate to relaunch in an elevated session (required for fixes and the
    Security log). Add -OpenReport to open the HTML report when the run finishes.

.EXAMPLE
    .\Invoke-Diagnostic.ps1
    Scan the last 7 days and show a report (no changes).

.EXAMPLE
    .\Invoke-Diagnostic.ps1 -Days 30 -OpenReport

.EXAMPLE
    .\Invoke-Diagnostic.ps1 -AutoFix -Elevate
    Relaunch elevated, scan, and apply fixes (prompts before each change).

.EXAMPLE
    .\Invoke-Diagnostic.ps1 -AutoFix -Confirm:$false -Elevate
    Relaunch elevated and apply all applicable fixes unattended.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(1, 365)] [int]$Days = 7,
    [switch]$AutoFix,
    [string[]]$FixId,
    [string[]]$ExcludeFixId,
    [string[]]$Category,
    [ValidateSet('Critical', 'Error', 'Warning')] [string]$MinSeverity = 'Warning',
    [switch]$IncludeRebootFixes,
    [switch]$NoRestorePoint,
    [switch]$SkipHealthChecks,
    [string]$ReportPath,
    [switch]$NoHtmlReport,
    [switch]$OpenReport,
    [string]$LogFile,
    [switch]$Quiet,
    [switch]$Elevate
)

function Test-IsElevated {
    if ($env:OS -ne 'Windows_NT') { return $false }
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { $false }
}

# -- Optional self-elevation: relaunch this script as Administrator ----- #
if ($Elevate -and -not (Test-IsElevated)) {
    Write-Host 'Relaunching elevated (accept the UAC prompt)...' -ForegroundColor Cyan
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Key -eq 'Elevate') { continue }
        $val = $kv.Value
        if ($val -is [System.Management.Automation.SwitchParameter]) {
            if ($val.IsPresent) { $argList += "-$($kv.Key)" }
        }
        elseif ($val -is [array]) {
            $argList += "-$($kv.Key)"; $argList += ($val -join ',')
        }
        else {
            $argList += "-$($kv.Key)"; $argList += "$val"
        }
    }
    try {
        $hostExe = (Get-Process -Id $PID).Path
        if (-not $hostExe) { $hostExe = 'powershell.exe' }
        Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $argList
    }
    catch {
        Write-Warning "Could not elevate: $($_.Exception.Message). Re-run from an elevated prompt."
    }
    return
}

# -- Import the module from this folder --------------------------------- #
$manifest = Join-Path $PSScriptRoot 'WindowsDiagnosticTool.psd1'
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Cannot find WindowsDiagnosticTool.psd1 next to this script ($PSScriptRoot)."
}
Import-Module $manifest -Force -ErrorAction Stop

# -- Forward parameters to Invoke-WindowsDiagnostic --------------------- #
$forward = @{}
foreach ($kv in $PSBoundParameters.GetEnumerator()) {
    if ($kv.Key -in 'Elevate', 'OpenReport') { continue }
    $forward[$kv.Key] = $kv.Value
}

# Pre-compute a report path so we can open it afterwards if asked.
if ($OpenReport -and -not $NoHtmlReport -and -not $ReportPath) {
    $ReportPath = Join-Path ([System.IO.Path]::GetTempPath()) ("WindowsDiagnostic_{0:yyyyMMdd_HHmmss}.html" -f (Get-Date))
    $forward['ReportPath'] = $ReportPath
}

Invoke-WindowsDiagnostic @forward

if ($OpenReport -and $ReportPath -and (Test-Path -LiteralPath $ReportPath)) {
    try { Invoke-Item -LiteralPath $ReportPath }
    catch { Write-Warning "Could not open report: $($_.Exception.Message)" }
}
