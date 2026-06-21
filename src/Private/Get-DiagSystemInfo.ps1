function Get-DiagSystemInfo {
    <#
    .SYNOPSIS
        Collects a snapshot of basic system information for the report header.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $os      = $null
    $cs      = $null
    $uptime  = $null
    try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { }
    try { $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } catch { }

    if ($os -and $os.LastBootUpTime) {
        try { $uptime = (Get-Date) - $os.LastBootUpTime } catch { }
    }

    [pscustomobject]@{
        ComputerName  = $env:COMPUTERNAME
        UserName      = $env:USERNAME
        OSName        = if ($os) { $os.Caption } else { 'Unknown' }
        OSVersion     = if ($os) { $os.Version } else { [string]$PSVersionTable.OS }
        OSBuild       = if ($os) { $os.BuildNumber } else { '' }
        Architecture  = if ($os) { $os.OSArchitecture } else { '' }
        Manufacturer  = if ($cs) { $cs.Manufacturer } else { '' }
        Model         = if ($cs) { $cs.Model } else { '' }
        LastBoot      = if ($os) { $os.LastBootUpTime } else { $null }
        UptimeText    = if ($uptime) { '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes } else { 'Unknown' }
        IsAdmin       = Test-DiagAdministrator
        PSVersion     = $PSVersionTable.PSVersion.ToString()
        ScanTime      = Get-Date
    }
}
