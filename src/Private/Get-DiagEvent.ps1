function Get-DiagEvent {
    <#
    .SYNOPSIS
        Reads events from the requested Windows event logs over a time window,
        combining a level-based "all problems" sweep with id-targeted queries so
        that no rule is missed because of how an event was logged.

    .DESCRIPTION
        This is the scanning stage. For each log it performs:

          1. A broad sweep filtered by Level (Critical/Error[/Warning]) -- this
             feeds the "top error sources" overview. The Security log is swept for
             failed-logon events (4625) instead, since audit events are level 0.

          2. An id-targeted query for the specific event IDs the active rules care
             about, WITHOUT a level filter. This guarantees rule events are
             captured even when Windows logs them at Information level (a classic
             gotcha for events such as BugCheck 1001).

        Results from both passes are de-duplicated by log + record id. A "no events
        found" condition surfaces from Get-WinEvent as a non-terminating error and
        is treated as an empty result.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$LogName,

        [int]$Days = 7,

        # Levels for the broad sweep: 1=Critical 2=Error 3=Warning.
        [int[]]$Level = @(1, 2, 3),

        # Optional map of LogName -> int[] event IDs to also pull regardless of level.
        [hashtable]$EventIdByLog = @{},

        [int]$MaxEventsPerLog = 4000
    )

    $startTime = (Get-Date).AddDays(-[math]::Abs($Days))
    $results   = New-Object System.Collections.Generic.List[object]
    $seen      = New-Object 'System.Collections.Generic.HashSet[string]'

    if (-not (Get-Command -Name Get-WinEvent -ErrorAction SilentlyContinue)) {
        Write-DiagLog -Level Error -Message "Get-WinEvent is unavailable. The scanner requires Windows PowerShell on Windows."
        return $results
    }

    # Adds events that haven't been seen yet (dedup by log + record id).
    function Add-DiagEventUnique {
        param($Events)
        $added = 0
        foreach ($e in $Events) {
            $key = '{0}/{1}' -f $e.LogName, $e.RecordId
            if ($seen.Add($key)) { $results.Add($e); $added++ }
        }
        return $added
    }

    # Runs one Get-WinEvent query, swallowing the benign "no events" noise.
    function Invoke-DiagWinEvent {
        param($Filter, $Label)
        try {
            $ev = Get-WinEvent -FilterHashtable $Filter -MaxEvents $MaxEventsPerLog -ErrorAction Stop
            return , @($ev)
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match 'No events were found') { return , @() }
            elseif ($msg -match 'access is denied|unauthorized') { Write-DiagLog -Level Warning -Message "  $Label : access denied (run elevated)." }
            elseif ($msg -match 'There is not an event log|could not be found') { Write-DiagLog -Level Debug -Message "  $Label : not present on this system." }
            else { Write-DiagLog -Level Warning -Message "  $Label : $msg" }
            return , @()
        }
    }

    $logIndex = 0
    foreach ($log in $LogName) {
        $logIndex++
        Write-Progress -Activity 'Scanning event logs' -Status "$log ($logIndex of $($LogName.Count))" `
            -PercentComplete (($logIndex / [math]::Max($LogName.Count, 1)) * 100)

        # ---- 1. Broad level-based sweep ------------------------------- #
        $filter = @{ LogName = $log; StartTime = $startTime }
        if ($log -eq 'Security') { $filter['Id'] = 4625 } else { $filter['Level'] = $Level }
        $sweep = Invoke-DiagWinEvent -Filter $filter -Label $log
        $n1 = Add-DiagEventUnique -Events $sweep

        # ---- 2. Id-targeted, level-agnostic capture ------------------- #
        $ids = @($EventIdByLog[$log] | Where-Object { $_ })
        $n2 = 0
        if ($ids.Count -and $log -ne 'Security') {
            $idFilter = @{ LogName = $log; StartTime = $startTime; Id = $ids }
            $targeted = Invoke-DiagWinEvent -Filter $idFilter -Label "$log (rule ids)"
            $n2 = Add-DiagEventUnique -Events $targeted
        }

        Write-DiagLog -Level Info -Message ("  {0,-56} {1,5} event(s)" -f $log, ($n1 + $n2))
    }
    Write-Progress -Activity 'Scanning event logs' -Completed

    Write-DiagLog -Level Info -Message "Collected $($results.Count) event(s) total across $($LogName.Count) log(s)."
    return $results
}
