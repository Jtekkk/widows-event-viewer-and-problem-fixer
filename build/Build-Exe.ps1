#Requires -Version 5.1
<#
.SYNOPSIS
    Builds standalone Windows executables for the Windows Diagnostic &
    Problem-Fixer tool.

.DESCRIPTION
    Bundles every module function plus an entry point into a single self-contained
    .ps1 and compiles it to an .exe with ps2exe. Produces:

      dist\WindowsDiagnostic.exe       - the pro GUI (no console window)
      dist\WindowsDiagnostic-CLI.exe   - the command-line scanner/fixer

    No external files are needed at runtime: the module is embedded in the exe.

.NOTES
    Windows only. Requires the ps2exe module (auto-installed from the PowerShell
    Gallery if missing). The GUI also needs .NET WPF, which ships with Windows.

.EXAMPLE
    pwsh -File build\Build-Exe.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [switch]$GuiOnly,
    [switch]$CliOnly
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if ($env:OS -ne 'Windows_NT') {
    throw "Build-Exe must run on Windows: ps2exe produces a Windows PE executable."
}

# -- Read version from the manifest -------------------------------------- #
$manifest = Import-PowerShellDataFile (Join-Path $repo 'WindowsDiagnosticTool.psd1')
$version  = $manifest.ModuleVersion

# -- Ensure ps2exe is available ------------------------------------------ #
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe from the PowerShell Gallery..." -ForegroundColor Cyan
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    Install-Module -Name ps2exe -Scope CurrentUser -Force -ErrorAction Stop
}
Import-Module ps2exe -ErrorAction Stop

# -- Gather the source in the same order the module loads it ------------- #
$privateFiles = Get-ChildItem (Join-Path $repo 'src\Private') -Filter *.ps1 | Sort-Object Name
$publicFiles  = Get-ChildItem (Join-Path $repo 'src\Public')  -Filter *.ps1 | Sort-Object Name

function Get-Preamble {
    @"
# ------------------------------------------------------------------------
# Auto-generated bundle for the Windows Diagnostic & Problem-Fixer tool.
# Built from /src by build/Build-Exe.ps1  (version $version). Do not edit.
# ------------------------------------------------------------------------
Set-StrictMode -Version Latest
`$script:DiagLog = New-Object System.Collections.Generic.List[object]
`$script:DiagLogFile = `$null
"@
}

function Get-Functions {
    $sb = [System.Text.StringBuilder]::new()
    foreach ($f in @($privateFiles + $publicFiles)) {
        [void]$sb.AppendLine("# --- $($f.Name) ---")
        [void]$sb.AppendLine((Get-Content -LiteralPath $f.FullName -Raw))
        [void]$sb.AppendLine('')
    }
    $sb.ToString()
}

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wdt_build_{0}" -f ([guid]::NewGuid()))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$common = @{
    company = 'Windows Diagnostic Tool'
    product = 'Windows Diagnostic & Problem Fixer'
    version = $version
    copyright = '(c) Windows Diagnostic Tool contributors. MIT.'
}
$icon = Join-Path $PSScriptRoot 'app.ico'

try {
    # ---- GUI executable ------------------------------------------------ #
    if (-not $CliOnly) {
        $guiPs1 = Join-Path $tmp 'gui-bundle.ps1'
        $guiContent = (Get-Preamble) + "`n" + (Get-Functions) + "`nShow-DiagnosticGui`n"
        Set-Content -LiteralPath $guiPs1 -Value $guiContent -Encoding UTF8

        $guiExe = Join-Path $OutputDir 'WindowsDiagnostic.exe'
        $opts = @{ inputFile = $guiPs1; outputFile = $guiExe; noConsole = $true; title = 'Windows Diagnostic & Problem Fixer' } + $common
        if (Test-Path $icon) { $opts['iconFile'] = $icon }
        Write-Host "Building GUI exe -> $guiExe" -ForegroundColor Cyan
        Invoke-ps2exe @opts
    }

    # ---- CLI executable ------------------------------------------------ #
    if (-not $GuiOnly) {
        $cliParam = @'
# Windows Diagnostic & Problem-Fixer (CLI). Run -? for parameters.
param(
    [int]$Days = 7,
    [switch]$AutoFix,
    [string[]]$FixId,
    [string[]]$ExcludeFixId,
    [string[]]$Category,
    [ValidateSet('Critical','Error','Warning')] [string]$MinSeverity = 'Warning',
    [switch]$IncludeRebootFixes,
    [switch]$NoRestorePoint,
    [switch]$SkipHealthChecks,
    [string]$ReportPath,
    [switch]$NoHtmlReport,
    [string]$JsonPath,
    [string]$CsvPath,
    [string]$LogFile,
    [switch]$Quiet
)
'@
        $cliTail = @'

$forward = @{}
foreach ($k in $PSBoundParameters.Keys) { $forward[$k] = $PSBoundParameters[$k] }
Invoke-WindowsDiagnostic @forward
if (-not $Quiet) { Write-Host ""; Read-Host "Press Enter to close" | Out-Null }
'@
        $cliPs1 = Join-Path $tmp 'cli-bundle.ps1'
        $cliContent = $cliParam + "`n" + (Get-Preamble) + "`n" + (Get-Functions) + $cliTail
        Set-Content -LiteralPath $cliPs1 -Value $cliContent -Encoding UTF8

        $cliExe = Join-Path $OutputDir 'WindowsDiagnostic-CLI.exe'
        $opts = @{ inputFile = $cliPs1; outputFile = $cliExe; title = 'Windows Diagnostic CLI' } + $common
        if (Test-Path $icon) { $opts['iconFile'] = $icon }
        Write-Host "Building CLI exe -> $cliExe" -ForegroundColor Cyan
        Invoke-ps2exe @opts
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nDone. Executables in: $OutputDir" -ForegroundColor Green
Get-ChildItem $OutputDir -Filter *.exe | Select-Object Name, @{n='SizeMB';e={[math]::Round($_.Length/1MB,2)}}

