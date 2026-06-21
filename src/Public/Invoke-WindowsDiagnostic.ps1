function Invoke-WindowsDiagnostic {
    <#
    .SYNOPSIS
        Scans Windows event logs (and live system state) for known problems and,
        optionally, applies automatic fixes.

    .DESCRIPTION
        The main entry point of the Windows Diagnostic & Problem-Fixer tool. It:
          1. Collects system information.
          2. Scans the relevant event logs for Critical/Error (and optionally
             Warning) events over a time window.
          3. Matches events against a catalog of known-problem rules and runs
             live health checks (disk space, pending reboot, SMART).
          4. Optionally applies the automatic fix for each detected problem.
          5. Prints a console report and writes a self-contained HTML report.

        SAFETY: This command supports -WhatIf and -Confirm. Because fixes change
        the system, each fix is confirmed by default (ConfirmImpact = High). Use
        -WhatIf to preview, or -Confirm:$false to apply unattended. Before any
        fixes run, a System Restore point is created when possible.

    .PARAMETER Days
        How many days back to scan the logs. Default 7.

    .PARAMETER AutoFix
        Apply the automatic fix for each detected, fixable problem.

    .PARAMETER FixId
        Limit auto-fix to these rule IDs or fix IDs (e.g. SYS-DISK-ERROR, flush-dns).

    .PARAMETER WhatIf
        Show which fixes would be applied without changing anything.

    .EXAMPLE
        Invoke-WindowsDiagnostic
        Scan the last 7 days and produce a report (no changes made).

    .EXAMPLE
        Invoke-WindowsDiagnostic -Days 30 -MinSeverity Error -ReportPath C:\Temp\diag.html

    .EXAMPLE
        Invoke-WindowsDiagnostic -AutoFix -WhatIf
        Preview every fix that would be applied.

    .EXAMPLE
        Invoke-WindowsDiagnostic -AutoFix -Confirm:$false
        Run a full scan and apply all applicable fixes without prompting (run elevated).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [string[]]$LogName,
        [ValidateRange(1, 365)] [int]$Days = 7,
        [ValidateRange(100, 100000)] [int]$MaxEventsPerLog = 4000,
        [string[]]$Category,
        [ValidateSet('Critical', 'Error', 'Warning')] [string]$MinSeverity = 'Warning',
        [switch]$SkipHealthChecks,
        [switch]$AutoFix,
        [string[]]$FixId,
        [string[]]$ExcludeFixId,
        [switch]$NoRestorePoint,
        [switch]$IncludeRebootFixes,
        [string]$ReportPath,
        [switch]$NoHtmlReport,
        [string]$JsonPath,
        [string]$CsvPath,
        [string]$LogFile,
        [switch]$Quiet,
        [switch]$PassThru
    )

    # -- Session log setup --------------------------------------------- #
    $script:DiagLog     = New-Object System.Collections.Generic.List[object]
    $script:DiagLogFile = $LogFile

    Write-DiagLog -Level Info -Message "Windows Diagnostic & Problem-Fixer starting (scan window: $Days day(s))." -Quiet:$Quiet

    if (-not (Get-Command -Name Get-WinEvent -ErrorAction SilentlyContinue)) {
        Write-DiagLog -Level Error -Message "This tool must run on Windows (Get-WinEvent is not available here)."
        return
    }

    $sysInfo = Get-DiagSystemInfo
    if (-not $sysInfo.IsAdmin) {
        Write-DiagLog -Level Warning -Message "Not running as Administrator. Some logs (e.g. Security) and most fixes will be unavailable."
    }

    $severityRank = @{ 'Critical' = 3; 'Error' = 2; 'Warning' = 1 }
    $minRank      = [int]$severityRank[$MinSeverity]

    # -- Build the active rule set ------------------------------------- #
    $rules = Get-DiagRule
    if ($Category)    { $rules = $rules | Where-Object { $Category -contains $_.Category } }
    $rules = $rules | Where-Object { [int]$severityRank[$_.Severity] -ge $minRank }
    $rules = @($rules)
    Write-DiagLog -Level Info -Message "Loaded $($rules.Count) detection rule(s)." -Quiet:$Quiet

    # -- Decide which logs to scan ------------------------------------- #
    if ($LogName) {
        $logsToScan = $LogName
    }
    else {
        $logsToScan = @($rules.LogName | Where-Object { $_ -and $_ -ne '(live check)' } | Select-Object -Unique)
        $logsToScan += 'Setup'   # extra coverage for the "top sources" overview
        $logsToScan = $logsToScan | Select-Object -Unique
        if (-not $sysInfo.IsAdmin) {
            $logsToScan = $logsToScan | Where-Object { $_ -ne 'Security' }
        }
    }
    $logsToScan = @($logsToScan)

    # Levels for the broad sweep follow the reporting floor; rule events are
    # captured regardless of level via the id-targeted pass below.
    $scanLevels = switch ($MinSeverity) {
        'Critical' { @(1) }
        'Error'    { @(1, 2) }
        default    { @(1, 2, 3) }
    }
    # Map each scanned log to the event IDs its active rules need.
    $eventIdByLog = @{}
    foreach ($grp in ($rules | Group-Object LogName)) {
        if ($grp.Name -eq '(live check)') { continue }
        $ids = @($grp.Group | ForEach-Object { $_.EventId } | Where-Object { $_ } | Select-Object -Unique)
        if ($ids.Count) { $eventIdByLog[$grp.Name] = $ids }
    }

    # -- Scan ----------------------------------------------------------- #
    Write-DiagLog -Level Info -Message "Scanning $($logsToScan.Count) event log(s)..." -Quiet:$Quiet
    # @() guards against PowerShell unrolling an empty result to $null.
    $events = @(Get-DiagEvent -LogName $logsToScan -Days $Days -Level $scanLevels -EventIdByLog $eventIdByLog -MaxEventsPerLog $MaxEventsPerLog)

    # -- Analyze -------------------------------------------------------- #
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($f in (Get-DiagFinding -Event $events -Rule $rules)) { $findings.Add($f) }

    if (-not $SkipHealthChecks) {
        Write-DiagLog -Level Info -Message "Running live health checks..." -Quiet:$Quiet
        foreach ($f in (Test-DiagHealthCheck)) {
            if ([int]$severityRank[$f.Severity] -ge $minRank) { $findings.Add($f) }
        }
    }

    $findings = @($findings | Sort-Object -Property @{ Expression = 'SeverityRank'; Descending = $true },
                                                     @{ Expression = 'Count'; Descending = $true })
    Write-DiagLog -Level Info -Message "Analysis complete: $($findings.Count) problem(s) detected." -Quiet:$Quiet

    # -- Apply fixes ---------------------------------------------------- #
    if ($AutoFix) {
        $targets = $findings | Where-Object { $_.HasFix }
        if ($FixId)        { $targets = $targets | Where-Object { $FixId -contains $_.RuleId -or $FixId -contains $_.FixId } }
        if ($ExcludeFixId) { $targets = $targets | Where-Object { $ExcludeFixId -notcontains $_.RuleId -and $ExcludeFixId -notcontains $_.FixId } }

        $fixActions = Get-DiagFixAction
        if (-not $IncludeRebootFixes) {
            $targets = $targets | Where-Object { -not $fixActions[$_.FixId].RequiresReboot }
        }
        $targets = @($targets)

        if (-not $targets.Count) {
            Write-DiagLog -Level Info -Message "No applicable automatic fixes to run." -Quiet:$Quiet
        }
        else {
            Write-DiagLog -Level Info -Message "$($targets.Count) fixable problem(s) queued." -Quiet:$Quiet

            if (-not $NoRestorePoint -and -not $WhatIfPreference) {
                New-DiagRestorePoint | Out-Null
            }

            foreach ($t in $targets) {
                $action = $fixActions[$t.FixId]
                $desc   = "Apply fix '$($action.Name)'"
                $target = "[$($t.RuleId)] $($t.Name)"
                if ($PSCmdlet.ShouldProcess($target, $desc)) {
                    Invoke-DiagFix -Finding $t | Out-Null
                }
                else {
                    Write-DiagLog -Level Info -Message "Skipped (not confirmed): $target" -Quiet:$Quiet
                }
            }

            if ($findings | Where-Object { $_.FixResult -and $_.FixResult.RebootRequired }) {
                Write-DiagLog -Level Warning -Message "One or more fixes need a reboot to finish. Restart when convenient."
            }
        }
    }

    # -- Report --------------------------------------------------------- #
    if (-not $Quiet) {
        Out-DiagConsoleReport -SystemInfo $sysInfo -Finding $findings -Event $events
    }

    if (-not $NoHtmlReport) {
        if (-not $ReportPath) {
            $ReportPath = Join-Path ([System.IO.Path]::GetTempPath()) ("WindowsDiagnostic_{0:yyyyMMdd_HHmmss}.html" -f (Get-Date))
        }
        try {
            $written = Out-DiagHtmlReport -SystemInfo $sysInfo -Finding $findings -Event $events -LogEntry $script:DiagLog -Path $ReportPath
            Write-DiagLog -Level Success -Message "HTML report written to: $written"
        }
        catch {
            Write-DiagLog -Level Warning -Message "Could not write HTML report: $($_.Exception.Message)"
        }
    }

    # -- Machine-readable export (JSON / CSV) --------------------------- #
    if ($JsonPath -or $CsvPath) {
        $export = @($findings | ForEach-Object {
            [pscustomobject]@{
                RuleId         = $_.RuleId
                Name           = $_.Name
                Category       = $_.Category
                Severity       = $_.Severity
                Count          = $_.Count
                FirstSeen      = $_.FirstSeen
                LastSeen       = $_.LastSeen
                Breakdown      = $_.Breakdown
                SampleMessage  = $_.SampleMessage
                HasFix         = $_.HasFix
                FixId          = $_.FixId
                FixApplied     = $_.FixApplied
                FixSuccess     = if ($_.FixResult) { $_.FixResult.Success } else { $null }
                FixMessage     = if ($_.FixResult) { $_.FixResult.Message } else { $null }
                RebootRequired = if ($_.FixResult) { [bool]$_.FixResult.RebootRequired } else { $false }
            }
        })
        if ($JsonPath) {
            try {
                $json = if ($export.Count) { $export | ConvertTo-Json -Depth 5 } else { '[]' }
                Set-Content -LiteralPath $JsonPath -Value $json -Encoding UTF8
                Write-DiagLog -Level Success -Message "JSON results written to: $JsonPath"
            }
            catch { Write-DiagLog -Level Warning -Message "Could not write JSON: $($_.Exception.Message)" }
        }
        if ($CsvPath) {
            try {
                $export | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
                Write-DiagLog -Level Success -Message "CSV results written to: $CsvPath"
            }
            catch { Write-DiagLog -Level Warning -Message "Could not write CSV: $($_.Exception.Message)" }
        }
    }

    if ($PassThru) {
        return $findings
    }
}
