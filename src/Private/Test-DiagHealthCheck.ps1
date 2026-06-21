function Test-DiagHealthCheck {
    <#
    .SYNOPSIS
        Runs live system health checks that complement the event-log scan.

    .DESCRIPTION
        Some problems are best detected from current system state rather than
        from historical log entries -- low free disk space, a pending reboot, or
        a drive reporting imminent failure via SMART. Each check emits a finding
        object in the same shape produced by Get-DiagFinding so the report and the
        fixer treat them uniformly.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    $severityRank = @{ 'Critical' = 3; 'Error' = 2; 'Warning' = 1 }
    $findings     = New-Object System.Collections.Generic.List[object]

    function New-HealthFinding {
        param($Id, $Name, $Category, $Severity, $Count, $Detail, $Recommendation, $Impact, $FixId)
        $rule = [pscustomobject]@{
            Id = $Id; Name = $Name; Category = $Category; Severity = $Severity
            LogName = '(live check)'; ProviderName = @(); EventId = @(); Level = $null
            MessagePattern = $null; MinCount = 1
            Description = $Detail; Impact = $Impact; Recommendation = $Recommendation; FixId = $FixId
        }
        [pscustomobject]@{
            Rule = $rule; RuleId = $Id; Name = $Name; Category = $Category; Severity = $Severity
            SeverityRank = [int]$severityRank[$Severity]; Count = $Count
            FirstSeen = $null; LastSeen = (Get-Date); Breakdown = 'live check'
            SampleMessage = $Detail; Events = @(); FixId = $FixId; HasFix = [bool]$FixId
            FixApplied = $false; FixResult = $null
        }
    }

    # ---- 1. Low free space on fixed drives ---------------------------- #
    try {
        $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop
        foreach ($d in $drives) {
            if (-not $d.Size) { continue }
            $freePct = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1)
            $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
            if ($freePct -lt 10 -or $freeGB -lt 5) {
                $sev = if ($freePct -lt 5) { 'Critical' } else { 'Warning' }
                $findings.Add((New-HealthFinding -Id 'LIVE-DISK-SPACE' -Name "Low disk space on $($d.DeviceID)" `
                    -Category 'Disk' -Severity $sev -Count 1 `
                    -Detail "Drive $($d.DeviceID) has $freeGB GB free ($freePct%)." `
                    -Impact 'Low free space causes update failures, crashes, and severe slowdowns.' `
                    -Recommendation 'Free up space: empty temp folders and the Recycle Bin, uninstall unused apps, run Disk Cleanup.' `
                    -FixId 'clean-temp'))
            }
        }
    } catch { Write-DiagLog -Level Debug -Message "Disk space check skipped: $($_.Exception.Message)" }

    # ---- 2. Pending reboot ------------------------------------------- #
    try {
        $pending = $false
        $reasons = @()
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending = $true; $reasons += 'Component servicing' }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending = $true; $reasons += 'Windows Update' }
        $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
        if ($pfro -and $pfro.PendingFileRenameOperations) { $pending = $true; $reasons += 'Pending file rename' }
        if ($pending) {
            $findings.Add((New-HealthFinding -Id 'LIVE-REBOOT-PENDING' -Name 'Reboot required' `
                -Category 'System' -Severity 'Warning' -Count 1 `
                -Detail "A restart is pending ($($reasons -join ', '))." `
                -Impact 'Updates and fixes will not finish applying until the machine is restarted.' `
                -Recommendation 'Save your work and restart the computer.' `
                -FixId $null))
        }
    } catch { Write-DiagLog -Level Debug -Message "Pending-reboot check skipped: $($_.Exception.Message)" }

    # ---- 3. SMART / predictive drive failure ------------------------- #
    try {
        $smart = Get-CimInstance -Namespace 'root\wmi' -ClassName 'MSStorageDriver_FailurePredictStatus' -ErrorAction Stop
        foreach ($s in $smart) {
            if ($s.PredictFailure) {
                $findings.Add((New-HealthFinding -Id 'LIVE-SMART-FAIL' -Name 'Drive predicting failure (SMART)' `
                    -Category 'Hardware' -Severity 'Critical' -Count 1 `
                    -Detail "Disk '$($s.InstanceName)' reports SMART predictive failure (reason $($s.Reason))." `
                    -Impact 'The drive may fail soon. Data loss is likely without action.' `
                    -Recommendation 'Back up immediately and replace the drive. No software fix can repair failing hardware.' `
                    -FixId $null))
            }
        }
    } catch { Write-DiagLog -Level Debug -Message "SMART check skipped: $($_.Exception.Message)" }

    # Return a plain array. (Note: do not use @($findings) directly on a
    # List[object] -- some PowerShell builds throw "Argument types do not match"
    # converting a generic List with the array operator; .ToArray() is safe.)
    return $findings.ToArray()
}
