#Requires -Version 5.1
<#
    WindowsDiagnosticTool.psm1
    Loader for the Windows Diagnostic & Problem-Fixer module.

    Dot-sources every function under src/Private and src/Public, then exports the
    public surface. Module-scoped state (the run log buffer + optional transcript
    path) lives here so all functions share it.
#>

Set-StrictMode -Version Latest

# Shared module state.
$script:DiagLog     = New-Object System.Collections.Generic.List[object]
$script:DiagLogFile = $null

$srcRoot      = Join-Path $PSScriptRoot 'src'
$privateRoot  = Join-Path $srcRoot 'Private'
$publicRoot   = Join-Path $srcRoot 'Public'

$privateFiles = @(Get-ChildItem -Path $privateRoot -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name)
$publicFiles  = @(Get-ChildItem -Path $publicRoot  -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name)

foreach ($file in ($privateFiles + $publicFiles)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to load '$($file.FullName)': $($_.Exception.Message)"
    }
}

if ($publicFiles.Count) {
    Export-ModuleMember -Function ($publicFiles.BaseName)
}
