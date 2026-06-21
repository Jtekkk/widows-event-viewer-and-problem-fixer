function Get-WindowsDiagnosticReport {
    <#
    .SYNOPSIS
        Scans the event logs and live system state and returns the detected
        problems (findings) without changing anything.

    .DESCRIPTION
        A read-only convenience wrapper around Invoke-WindowsDiagnostic. It never
        applies fixes; it produces the console + HTML report and emits the finding
        objects to the pipeline so you can review or selectively repair them, e.g.:

            Get-WindowsDiagnosticReport | Where-Object Severity -eq 'Critical' | Repair-WindowsProblem

    .EXAMPLE
        Get-WindowsDiagnosticReport -Days 14 -MinSeverity Error
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$LogName,
        [ValidateRange(1, 365)] [int]$Days = 7,
        [ValidateRange(100, 100000)] [int]$MaxEventsPerLog = 4000,
        [string[]]$Category,
        [ValidateSet('Critical', 'Error', 'Warning')] [string]$MinSeverity = 'Warning',
        [switch]$SkipHealthChecks,
        [string]$ReportPath,
        [switch]$NoHtmlReport,
        [string]$JsonPath,
        [string]$CsvPath,
        [string]$LogFile,
        [switch]$Quiet
    )

    $forward = @{}
    foreach ($key in $PSBoundParameters.Keys) { $forward[$key] = $PSBoundParameters[$key] }
    $forward['PassThru'] = $true

    Invoke-WindowsDiagnostic @forward
}
