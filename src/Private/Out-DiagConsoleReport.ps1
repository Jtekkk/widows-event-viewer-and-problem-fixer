function Out-DiagConsoleReport {
    <#
    .SYNOPSIS
        Renders the diagnostic results to the console in a readable, colorized
        layout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $SystemInfo,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Finding,
        [AllowEmptyCollection()] [object[]]$Event = @()
    )

    $line = ('=' * 78)
    Write-Host ''
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host '  WINDOWS DIAGNOSTIC REPORT' -ForegroundColor White
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host ("  Computer : {0}  ({1})" -f $SystemInfo.ComputerName, $SystemInfo.OSName)
    Write-Host ("  Version  : {0} (build {1}) {2}" -f $SystemInfo.OSVersion, $SystemInfo.OSBuild, $SystemInfo.Architecture)
    Write-Host ("  Uptime   : {0}    Elevated: {1}" -f $SystemInfo.UptimeText, $SystemInfo.IsAdmin)
    Write-Host ("  Scanned  : {0:yyyy-MM-dd HH:mm:ss}" -f $SystemInfo.ScanTime)
    Write-Host ''

    # ---- Summary by severity ----------------------------------------- #
    $crit = @($Finding | Where-Object Severity -eq 'Critical').Count
    $err  = @($Finding | Where-Object Severity -eq 'Error').Count
    $warn = @($Finding | Where-Object Severity -eq 'Warning').Count
    $fixable = @($Finding | Where-Object HasFix).Count

    Write-Host '  SUMMARY' -ForegroundColor White
    Write-Host ('  -------')
    if ($Finding.Count -eq 0) {
        Write-Host '  No known problems were detected. ' -ForegroundColor Green -NoNewline
        Write-Host 'System looks healthy.'
    }
    else {
        $critColor = if ($crit) { 'Red' }    else { 'Gray' }
        $errColor  = if ($err)  { 'Yellow' } else { 'Gray' }
        $warnColor = if ($warn) { 'Yellow' } else { 'Gray' }
        Write-Host ("  Critical : {0}" -f $crit) -ForegroundColor $critColor
        Write-Host ("  Errors   : {0}" -f $err)  -ForegroundColor $errColor
        Write-Host ("  Warnings : {0}" -f $warn) -ForegroundColor $warnColor
        Write-Host ("  Auto-fixable problems : {0} of {1}" -f $fixable, $Finding.Count) -ForegroundColor Cyan
    }
    Write-Host ''

    # ---- Findings detail --------------------------------------------- #
    if ($Finding.Count) {
        Write-Host '  DETECTED PROBLEMS' -ForegroundColor White
        Write-Host ('  -----------------')
        $idx = 0
        foreach ($f in $Finding) {
            $idx++
            $sevColor = switch ($f.Severity) { 'Critical' { 'Red' } 'Error' { 'Yellow' } default { 'DarkYellow' } }
            Write-Host ("  [{0}] " -f $idx) -NoNewline
            Write-Host ("{0,-8}" -f $f.Severity.ToUpper()) -ForegroundColor $sevColor -NoNewline
            Write-Host (" {0}  ({1})" -f $f.Name, $f.Category)
            Write-Host ("       Occurrences : {0}    Last seen : {1}" -f $f.Count, $(if ($f.LastSeen) { '{0:yyyy-MM-dd HH:mm}' -f $f.LastSeen } else { 'n/a' }))
            if ($f.SampleMessage) {
                $msg = $f.SampleMessage
                if ($msg.Length -gt 160) { $msg = $msg.Substring(0, 157) + '...' }
                Write-Host ("       Example     : {0}" -f $msg) -ForegroundColor DarkGray
            }
            if ($f.HasFix) {
                $fix = (Get-DiagFixAction)[$f.FixId]
                Write-Host ("       Auto-fix    : {0}" -f $fix.Name) -ForegroundColor Cyan
            }
            else {
                Write-Host ("       Action      : {0}" -f $f.Rule.Recommendation) -ForegroundColor DarkCyan
            }
            if ($f.FixApplied -and $f.FixResult) {
                $rc = if ($f.FixResult.Success) { 'Green' } else { 'Red' }
                Write-Host ("       Fix result  : {0}" -f $f.FixResult.Message) -ForegroundColor $rc
            }
            Write-Host ''
        }
    }

    # ---- Raw "all problems" overview from the logs ------------------- #
    if ($Event.Count) {
        $top = $Event | Where-Object { [int]$_.Level -in 1, 2 } |
            Group-Object ProviderName, Id |
            Sort-Object Count -Descending | Select-Object -First 12
        if ($top) {
            Write-Host '  TOP ERROR SOURCES IN LOGS (all critical/error events)' -ForegroundColor White
            Write-Host ('  ----------------------------------------------------')
            Write-Host ('  {0,-6} {1,-45} {2}' -f 'Count', 'Source', 'Event ID') -ForegroundColor DarkGray
            foreach ($g in $top) {
                $parts  = $g.Group | Select-Object -First 1
                Write-Host ('  {0,-6} {1,-45} {2}' -f $g.Count, $parts.ProviderName, $parts.Id)
            }
            Write-Host ''
        }
    }

    Write-Host $line -ForegroundColor DarkCyan
}
