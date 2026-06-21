function Repair-WindowsProblem {
    <#
    .SYNOPSIS
        Applies automatic fixes to specific problems -- either findings piped in
        from a scan, or problems selected by rule ID.

    .DESCRIPTION
        Use this after reviewing a report to repair selected problems, rather than
        fixing everything at once. It supports -WhatIf and -Confirm and creates a
        System Restore point before the first fix. Fixes that require a reboot are
        excluded unless -IncludeRebootFixes is specified.

    .PARAMETER Finding
        Finding object(s) from Invoke-WindowsDiagnostic/Get-WindowsDiagnosticReport
        (accepts pipeline input).

    .PARAMETER RuleId
        Instead of piping findings, scan now and fix only these rule IDs.

    .EXAMPLE
        Get-WindowsDiagnosticReport | Where-Object Category -eq 'Network' | Repair-WindowsProblem

    .EXAMPLE
        Repair-WindowsProblem -RuleId UPD-FAILURE, NET-DNS-FAIL

    .EXAMPLE
        Repair-WindowsProblem -RuleId SYS-DISK-ERROR -WhatIf

    .EXAMPLE
        Repair-WindowsProblem -ApplyFix clean-temp, flush-dns
        Run specific fix actions directly, without needing a detected problem.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByFinding')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline, ParameterSetName = 'ByFinding')]
        [object[]]$Finding,

        [Parameter(Mandatory, ParameterSetName = 'ByRule')]
        [string[]]$RuleId,

        [Parameter(ParameterSetName = 'ByRule')]
        [ValidateRange(1, 365)] [int]$Days = 7,

        # Power-user mode: run a fix action directly by its id (see Get-DiagFixAction
        # ids via Get-WindowsDiagnosticRule). Some fixes (e.g. restart-service) need
        # event context and are best driven from a finding instead.
        [Parameter(Mandatory, ParameterSetName = 'ByFix')]
        [string[]]$ApplyFix,

        [switch]$NoRestorePoint,
        [switch]$IncludeRebootFixes,
        [switch]$PassThru
    )

    begin {
        if ($null -eq $script:DiagLog) { $script:DiagLog = New-Object System.Collections.Generic.List[object] }
        $collected   = New-Object System.Collections.Generic.List[object]
        $restoreDone = $false
        $fixActions  = Get-DiagFixAction

        if (-not (Test-DiagAdministrator)) {
            Write-DiagLog -Level Warning -Message "Not elevated. Most repairs require Administrator rights and will be skipped."
        }
    }

    process {
        if ($Finding) { foreach ($f in $Finding) { $collected.Add($f) } }
    }

    end {
        # ByRule mode: run a scan limited to the requested rules.
        if ($PSCmdlet.ParameterSetName -eq 'ByRule') {
            Write-DiagLog -Level Info -Message "Scanning to locate problems for: $($RuleId -join ', ')"
            $rules = @(Get-DiagRule | Where-Object { $RuleId -contains $_.Id })
            if (-not $rules.Count) {
                Write-DiagLog -Level Error -Message "No rules matched the supplied RuleId(s). See Get-WindowsDiagnosticRule."
                return
            }
            $logs = @($rules.LogName | Where-Object { $_ -and $_ -ne '(live check)' } | Select-Object -Unique)
            $eventIdByLog = @{}
            foreach ($grp in ($rules | Group-Object LogName)) {
                if ($grp.Name -eq '(live check)') { continue }
                $ids = @($grp.Group | ForEach-Object { $_.EventId } | Where-Object { $_ } | Select-Object -Unique)
                if ($ids.Count) { $eventIdByLog[$grp.Name] = $ids }
            }
            $events = if ($logs.Count) { @(Get-DiagEvent -LogName $logs -Days $Days -EventIdByLog $eventIdByLog) } else { @() }
            foreach ($f in (Get-DiagFinding -Event $events -Rule $rules)) { $collected.Add($f) }
            # Include live-check problems that match a requested rule id.
            foreach ($f in (Test-DiagHealthCheck)) { if ($RuleId -contains $f.RuleId) { $collected.Add($f) } }
        }

        # ByFix mode: synthesize a finding per requested fix id so the same
        # confirm/restore-point/apply pipeline runs.
        if ($PSCmdlet.ParameterSetName -eq 'ByFix') {
            foreach ($id in $ApplyFix) {
                $action = $fixActions[$id]
                if (-not $action) {
                    Write-DiagLog -Level Error -Message "Unknown fix id '$id'. See (Get-WindowsDiagnosticRule).FixId for valid ids."
                    continue
                }
                $collected.Add([pscustomobject]@{
                    Rule = [pscustomobject]@{ Recommendation = $action.Description }
                    RuleId = "manual:$id"; Name = $action.Name; Category = 'Manual'; Severity = 'Warning'
                    SeverityRank = 1; Count = 0; FirstSeen = $null; LastSeen = (Get-Date); Breakdown = 'manual fix'
                    SampleMessage = $action.Description; Events = @(); FixId = $id; HasFix = $true
                    FixApplied = $false; FixResult = $null
                })
            }
        }

        $fixable = $collected | Where-Object { $_.HasFix }
        if (-not $IncludeRebootFixes) {
            $fixable = $fixable | Where-Object { -not $fixActions[$_.FixId].RequiresReboot }
        }
        $fixable = @($fixable)

        if (-not $fixable.Count) {
            Write-DiagLog -Level Info -Message "Nothing to repair (no fixable problems were supplied/found)."
            if ($PassThru) { return $collected }
            return
        }

        foreach ($t in $fixable) {
            $action = $fixActions[$t.FixId]
            if ($PSCmdlet.ShouldProcess("[$($t.RuleId)] $($t.Name)", "Apply fix '$($action.Name)'")) {
                if (-not $restoreDone -and -not $NoRestorePoint) {
                    New-DiagRestorePoint | Out-Null
                    $restoreDone = $true
                }
                Invoke-DiagFix -Finding $t | Out-Null
            }
        }

        if ($collected | Where-Object { $_.FixResult -and $_.FixResult.RebootRequired }) {
            Write-DiagLog -Level Warning -Message "One or more fixes need a reboot to finish."
        }

        if ($PassThru) { return $collected }
    }
}
