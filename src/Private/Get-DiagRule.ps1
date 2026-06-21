function Get-DiagRule {
    <#
    .SYNOPSIS
        Returns the catalog of diagnostic rules used to detect known Windows
        problems in the event logs.

    .DESCRIPTION
        Each rule describes a recognizable problem signature (which log, which
        provider/source, which event IDs) plus human-readable context and an
        optional FixId that links to an automatic repair in Get-DiagFixAction.

        Rule schema:
            Id             unique identifier (e.g. SYS-DISK-ERROR)
            Name           short human-readable title
            Category       Disk | System | Services | Network | Updates |
                           Application | Hardware | Performance | Security
            Severity       Critical | Error | Warning
            LogName        event log to search
            ProviderName   event source(s) -- string or string[]
            EventId        int[] of matching event IDs (empty = any)
            Level          int[] override (1=Critical 2=Error 3=Warning); optional
            MessagePattern optional regex the message must match
            MinCount       minimum occurrences before flagged (default 1)
            Description    what the problem is
            Impact         why it matters
            Recommendation guidance (shown when there is no auto-fix)
            FixId          key into Get-DiagFixAction, or $null for advisory-only
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param()

    # Helper to keep each definition terse and consistent.
    $rule = {
        param($h)
        [pscustomobject]@{
            Id             = $h.Id
            Name           = $h.Name
            Category       = $h.Category
            Severity       = $h.Severity
            LogName        = $h.LogName
            ProviderName   = $h.ProviderName
            EventId        = @($h.EventId)
            Level          = if ($h.ContainsKey('Level')) { @($h.Level) } else { $null }
            MessagePattern = if ($h.ContainsKey('MessagePattern')) { $h.MessagePattern } else { $null }
            MinCount       = if ($h.ContainsKey('MinCount')) { [int]$h.MinCount } else { 1 }
            Description    = $h.Description
            Impact         = $h.Impact
            Recommendation = $h.Recommendation
            FixId          = if ($h.ContainsKey('FixId')) { $h.FixId } else { $null }
        }
    }

    @(
        # ----------------------------- DISK ----------------------------- #
        & $rule @{
            Id = 'SYS-DISK-ERROR'; Name = 'Disk I/O / bad block errors'; Category = 'Disk'; Severity = 'Critical'
            LogName = 'System'; ProviderName = @('disk', 'Disk', 'storahci', 'iaStorA', 'storport', 'stornvme'); EventId = @(7, 11, 51, 52, 129, 153)
            Description = 'The disk/storage subsystem logged controller, bad-block, reset or I/O errors.'
            Impact      = 'Often an early warning of a failing drive or cabling/controller fault; can cause data loss and crashes.'
            Recommendation = 'Back up important data now. Check SMART status and replace the drive if it is failing.'
            FixId = 'chkdsk-scan'
        }
        & $rule @{
            Id = 'SYS-NTFS-CORRUPT'; Name = 'NTFS file-system corruption'; Category = 'Disk'; Severity = 'Error'
            LogName = 'System'; ProviderName = @('Ntfs', 'Microsoft-Windows-Ntfs'); EventId = @(55, 98, 130, 137, 140)
            Description = 'NTFS reported file-system corruption on a volume.'
            Impact      = 'Corruption can make files unreadable and lead to application or boot failures.'
            Recommendation = 'Run chkdsk on the affected volume. If it recurs, check the drive health.'
            FixId = 'chkdsk-scan'
        }

        # ---------------------------- SYSTEM ---------------------------- #
        & $rule @{
            Id = 'SYS-KERNELPOWER-41'; Name = 'Unexpected shutdown / power loss (Kernel-Power 41)'; Category = 'System'; Severity = 'Critical'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; EventId = @(41)
            Description = 'The system rebooted without cleanly shutting down first.'
            Impact      = 'Indicates a hard crash, power loss, overheating, or a failing PSU/battery.'
            Recommendation = 'Check for overheating, loose power connections and failing PSU/battery. Update chipset and BIOS. Review BugCheck (1001) events for a related BSOD.'
            FixId = $null
        }
        & $rule @{
            Id = 'SYS-BUGCHECK-1001'; Name = 'Blue Screen / bug check (BSOD)'; Category = 'System'; Severity = 'Critical'
            LogName = 'System'; ProviderName = @('Microsoft-Windows-WER-SystemErrorReporting', 'BugCheck'); EventId = @(1001)
            Description = 'Windows recovered from a bug check (Blue Screen of Death).'
            Impact      = 'A kernel-level crash. Common causes are faulty drivers, bad RAM, or corrupted system files.'
            Recommendation = 'Note the bug-check code in the event. Update/rollback recent drivers and run Windows Memory Diagnostic (mdsched.exe). The tool can also repair system files.'
            FixId = 'sfc-dism'
        }
        & $rule @{
            Id = 'SYS-TIME-SERVICE'; Name = 'System clock out of sync'; Category = 'System'; Severity = 'Warning'
            LogName = 'System'; ProviderName = @('Microsoft-Windows-Time-Service', 'W32Time'); EventId = @(129, 131, 134, 144)
            Description = 'The Windows Time service could not synchronize the clock.'
            Impact      = 'A wrong clock breaks HTTPS/TLS, Kerberos authentication and scheduled tasks.'
            Recommendation = 'Resynchronize time with a reliable NTP source.'
            FixId = 'resync-time'
        }
        & $rule @{
            Id = 'SYS-DCOM-10016'; Name = 'DCOM permission errors (10016)'; Category = 'System'; Severity = 'Warning'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-DistributedCOM'; EventId = @(10016); MinCount = 3
            Description = 'Applications were denied Local Activation/Launch permission to a COM component.'
            Impact      = 'Usually benign log noise, but a flood can hide real problems.'
            Recommendation = 'Most 10016 events are by-design and safe to ignore (Microsoft guidance). Only adjust the component Launch/Activation permissions in dcomcnfg if a specific app is broken.'
            FixId = $null
        }
        & $rule @{
            Id = 'SYS-DCOM-10010'; Name = 'DCOM server timeout (10010)'; Category = 'System'; Severity = 'Warning'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-DistributedCOM'; EventId = @(10010); MinCount = 3
            Description = 'A DCOM server did not register with the system within the timeout period.'
            Impact      = 'Can cause slow logons, app launch delays, or features that intermittently fail.'
            Recommendation = 'Note the CLSID/AppID in the events; reinstall or repair the owning application. Often transient.'
            FixId = $null
        }
        & $rule @{
            Id = 'SYS-UNEXPECTED-SHUTDOWN'; Name = 'Previous shutdown was unexpected (6008)'; Category = 'System'; Severity = 'Error'
            LogName = 'System'; ProviderName = @('EventLog', 'Microsoft-Windows-Eventlog'); EventId = @(6008); MinCount = 1
            Description = 'Windows recorded that the previous shutdown was unexpected (dirty shutdown).'
            Impact      = 'Repeated dirty shutdowns risk data/file-system corruption and point to crashes or power problems.'
            Recommendation = 'Correlate with Kernel-Power 41 and BugCheck 1001. Check power, overheating and drivers.'
            FixId = $null
        }
        & $rule @{
            Id = 'SYS-WMI-ERROR'; Name = 'WMI / management errors'; Category = 'System'; Severity = 'Error'
            LogName = 'Application'; ProviderName = @('Microsoft-Windows-WMI', 'WinMgmt'); EventId = @(28, 63, 65); MinCount = 2
            Description = 'Windows Management Instrumentation reported provider or repository errors.'
            Impact      = 'Breaks monitoring, management tooling, some Settings pages and scripts that query WMI/CIM.'
            Recommendation = 'Verify and, if needed, salvage the WMI repository.'
            FixId = 'repair-wmi'
        }

        # -------------------------- PERFORMANCE ------------------------- #
        & $rule @{
            Id = 'APP-PERFLIB'; Name = 'Performance counter (Perflib) errors'; Category = 'Performance'; Severity = 'Warning'
            LogName = 'Application'; ProviderName = 'Microsoft-Windows-Perflib'; EventId = @(1008, 1023, 1010); MinCount = 3
            Description = 'A performance-counter library failed to load or collect data.'
            Impact      = 'Monitoring tools may show missing or wrong counters; usually low impact.'
            Recommendation = 'Rebuild performance counters with "lodctr /R" if monitoring is affected.'
            FixId = $null
        }

        # --------------------------- SERVICES --------------------------- #
        & $rule @{
            Id = 'SYS-SERVICE-CRASH'; Name = 'Service crashed or failed to start'; Category = 'Services'; Severity = 'Error'
            LogName = 'System'; ProviderName = 'Service Control Manager'; EventId = @(7000, 7001, 7009, 7011, 7022, 7023, 7024, 7031, 7034, 7038)
            Description = 'One or more Windows services terminated unexpectedly or failed to start.'
            Impact      = 'Crashed services can disable features (printing, networking, updates) and cause instability.'
            Recommendation = 'Restart the affected service and configure automatic recovery.'
            FixId = 'restart-service'
        }

        # ---------------------------- UPDATES --------------------------- #
        & $rule @{
            Id = 'UPD-FAILURE'; Name = 'Windows Update install/download failures'; Category = 'Updates'; Severity = 'Error'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; EventId = @(20, 24, 25, 31, 34, 35)
            Description = 'Windows Update failed to download or install one or more updates.'
            Impact      = 'Missing security updates leave the system vulnerable; failed updates can loop.'
            Recommendation = 'Reset the Windows Update components and retry.'
            FixId = 'reset-windowsupdate'
        }

        # ----------------------------- NETWORK -------------------------- #
        & $rule @{
            Id = 'NET-DNS-FAIL'; Name = 'DNS name-resolution failures'; Category = 'Network'; Severity = 'Warning'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-DNS-Client'; EventId = @(1014); MinCount = 3
            Description = 'The DNS client repeatedly failed to resolve names.'
            Impact      = 'Web sites and network services become unreachable even when the link is up.'
            Recommendation = 'Flush the DNS cache; if it persists, check the configured DNS servers.'
            FixId = 'flush-dns'
        }
        & $rule @{
            Id = 'NET-DHCP-FAIL'; Name = 'DHCP lease / IP address failures'; Category = 'Network'; Severity = 'Warning'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-Dhcp-Client'; EventId = @(1002, 1003, 1005); MinCount = 2
            Description = 'The DHCP client could not obtain or renew an IP address (possible address conflict).'
            Impact      = 'Without a valid lease the machine falls back to APIPA and loses network access.'
            Recommendation = 'Release and renew the DHCP lease.'
            FixId = 'renew-dhcp'
        }
        & $rule @{
            Id = 'NET-TCPIP'; Name = 'TCP/IP stack errors'; Category = 'Network'; Severity = 'Warning'
            LogName = 'System'; ProviderName = @('Tcpip', 'Tcpip6'); EventId = @(4199, 4227, 4231); MinCount = 3
            Description = 'The TCP/IP stack reported address conflicts or connection-resource problems.'
            Impact      = 'Intermittent connectivity drops and slow networking.'
            Recommendation = 'Renew the IP lease; for persistent issues reset the network stack (Winsock + TCP/IP) and reboot.'
            FixId = 'renew-dhcp'
        }

        # -------------------------- APPLICATION ------------------------- #
        & $rule @{
            Id = 'APP-CRASH-1000'; Name = 'Application crashes'; Category = 'Application'; Severity = 'Error'
            LogName = 'Application'; ProviderName = 'Application Error'; EventId = @(1000); MinCount = 3
            Description = 'One or more applications crashed (faulting module recorded).'
            Impact      = 'Repeated crashes of the same app point to corruption, a bad add-in, or a system file problem.'
            Recommendation = 'Identify the faulting application/module in the events. Update or reinstall it; running a system file repair often helps when the faulting module is a system DLL.'
            FixId = 'sfc-dism'
        }
        & $rule @{
            Id = 'APP-HANG-1002'; Name = 'Application hangs (not responding)'; Category = 'Application'; Severity = 'Warning'
            LogName = 'Application'; ProviderName = 'Application Hang'; EventId = @(1002); MinCount = 3
            Description = 'Applications stopped responding and were recorded as hangs.'
            Impact      = 'Frequent hangs hurt productivity and may indicate resource exhaustion or a bad add-in.'
            Recommendation = 'Update the affected application; check for low memory/disk and conflicting add-ins.'
            FixId = $null
        }
        & $rule @{
            Id = 'APP-NET-RUNTIME'; Name = '.NET runtime errors'; Category = 'Application'; Severity = 'Error'
            LogName = 'Application'; ProviderName = @('.NET Runtime', '.NET Runtime 4.0 Error Reporting'); EventId = @(1023, 1026); MinCount = 2
            Description = 'A .NET application threw an unhandled exception and crashed.'
            Impact      = 'The affected .NET app is unstable; a damaged .NET Framework can affect many apps.'
            Recommendation = 'Update the application and the .NET runtime. A system file repair can fix a damaged framework.'
            FixId = 'sfc-dism'
        }
        & $rule @{
            Id = 'APP-SEARCH-INDEX'; Name = 'Windows Search index corruption'; Category = 'Application'; Severity = 'Warning'
            LogName = 'Application'; ProviderName = @('Microsoft-Windows-Search', 'Microsoft-Windows-Search-ProfileNotify'); EventId = @(3013, 1008, 9, 7042); MinCount = 2
            Description = 'The Windows Search indexer reported corruption or repeated failures.'
            Impact      = 'Start-menu and File-Explorer search return incomplete or no results.'
            Recommendation = 'Rebuild the search index.'
            FixId = 'rebuild-search'
        }

        # ---------------------------- HARDWARE -------------------------- #
        & $rule @{
            Id = 'HW-WHEA-ERROR'; Name = 'Hardware errors (WHEA)'; Category = 'Hardware'; Severity = 'Critical'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; EventId = @(17, 18, 19, 20, 46, 47)
            Description = 'The Windows Hardware Error Architecture logged corrected or uncorrected hardware errors (CPU/PCIe/memory).'
            Impact      = 'Strongly indicates failing hardware: RAM, CPU, motherboard or an expansion card.'
            Recommendation = 'Run hardware diagnostics (memory test), reseat components, update BIOS/firmware. Uncorrected errors usually mean a component must be replaced.'
            FixId = $null
        }

        # -------------------------- PERFORMANCE ------------------------- #
        & $rule @{
            Id = 'PERF-SLOW-BOOT'; Name = 'Slow boot / shutdown'; Category = 'Performance'; Severity = 'Warning'
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
            ProviderName = 'Microsoft-Windows-Diagnostics-Performance'; EventId = @(100, 101, 102, 103, 109, 110); MinCount = 2
            Description = 'Windows recorded slow boot, shutdown, or startup-application degradation.'
            Impact      = 'Long start-up times, usually caused by heavy startup apps, a fragmented/failing disk, or low free space.'
            Recommendation = 'Disable unnecessary startup apps, free up disk space, and ensure the drive is healthy.'
            FixId = 'clean-temp'
        }

        # ---------------------------- DRIVERS --------------------------- #
        & $rule @{
            Id = 'SYS-DRIVER-LOAD'; Name = 'Device driver failed to load'; Category = 'Hardware'; Severity = 'Warning'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-PnP'; EventId = @(219); MinCount = 2
            Description = 'A driver failed to load for one or more devices.'
            Impact      = 'A device may not work, or Windows may fall back to a generic/limited driver.'
            Recommendation = 'Identify the device in Device Manager and install the correct/updated driver from the vendor or Windows Update.'
            FixId = $null
        }

        # ----------------------------- BACKUP --------------------------- #
        & $rule @{
            Id = 'SYS-VSS-ERROR'; Name = 'Volume Shadow Copy (VSS) errors'; Category = 'System'; Severity = 'Error'
            LogName = 'System'; ProviderName = @('VSS', 'volsnap'); EventId = @(8193, 8194, 12289, 12298, 25, 36); MinCount = 2
            Description = 'The Volume Shadow Copy Service reported errors creating or maintaining snapshots.'
            Impact      = 'Breaks System Restore, File History and most backup software.'
            Recommendation = 'Ensure the VSS and "Microsoft Software Shadow Copy Provider" services can start, and that the system drive has free space for shadow storage.'
            FixId = $null
        }

        # --------------------------- INSTALLER -------------------------- #
        & $rule @{
            Id = 'APP-MSI-FAIL'; Name = 'Windows Installer (MSI) failures'; Category = 'Application'; Severity = 'Error'
            LogName = 'Application'; ProviderName = 'MsiInstaller'; EventId = @(1024, 1033, 11708, 11707); MinCount = 2
            Description = 'Application installs or uninstalls via Windows Installer failed.'
            Impact      = 'Software cannot be installed, updated or removed cleanly.'
            Recommendation = 'Re-run the installer as Administrator. If it persists, use the Microsoft "Program Install and Uninstall" troubleshooter.'
            FixId = $null
        }

        # ------------------------- GROUP POLICY ------------------------- #
        & $rule @{
            Id = 'SYS-GROUPPOLICY'; Name = 'Group Policy processing errors'; Category = 'System'; Severity = 'Warning'
            LogName = 'System'; ProviderName = 'Microsoft-Windows-GroupPolicy'; EventId = @(1030, 1058, 1129); MinCount = 3
            Description = 'Windows could not read or apply Group Policy (often a domain connectivity or SYSVOL access issue).'
            Impact      = 'Policies, mapped drives and security settings may not apply correctly.'
            Recommendation = 'Check connectivity to a domain controller and DNS, then force a refresh.'
            FixId = 'refresh-grouppolicy'
        }

        # ------------------------- USER PROFILE ------------------------- #
        & $rule @{
            Id = 'APP-USER-PROFILE'; Name = 'User profile load problems'; Category = 'System'; Severity = 'Error'
            LogName = 'Application'; ProviderName = 'Microsoft-Windows-User Profiles Service'; EventId = @(1500, 1508, 1511, 1515, 1542); MinCount = 1
            Description = 'Windows had trouble loading a user profile (sometimes signing the user into a temporary profile).'
            Impact      = 'Users may lose their desktop/settings or be logged into a temporary profile where changes are discarded.'
            Recommendation = 'Check disk space and the profile under HKLM ProfileList. Back up data before repairing or recreating the profile.'
            FixId = $null
        }

        # ---------------------------- SECURITY -------------------------- #
        & $rule @{
            Id = 'SEC-LOGON-FAIL'; Name = 'Repeated failed sign-ins'; Category = 'Security'; Severity = 'Warning'
            LogName = 'Security'; ProviderName = 'Microsoft-Windows-Security-Auditing'; EventId = @(4625); Level = @(0, 4); MinCount = 10
            Description = 'A high number of failed logon attempts was recorded.'
            Impact      = 'May indicate a brute-force attempt or a service/scheduled task using stale credentials.'
            Recommendation = 'Review the source of the attempts. If external, tighten firewall/RDP exposure; if internal, fix the stale credentials.'
            FixId = $null
        }
        & $rule @{
            Id = 'SEC-ACCOUNT-LOCKOUT'; Name = 'Account lockouts'; Category = 'Security'; Severity = 'Warning'
            LogName = 'Security'; ProviderName = 'Microsoft-Windows-Security-Auditing'; EventId = @(4740); Level = @(0, 4); MinCount = 1
            Description = 'One or more accounts were locked out due to repeated bad passwords.'
            Impact      = 'Users are blocked from signing in; often caused by a stale saved password on a device or service.'
            Recommendation = 'Find the source device/service caching the old password (the caller computer is in the event), then update or clear it.'
            FixId = $null
        }
        & $rule @{
            Id = 'SEC-DEFENDER-THREAT'; Name = 'Malware detected by Defender'; Category = 'Security'; Severity = 'Critical'
            LogName = 'Microsoft-Windows-Windows Defender/Operational'
            ProviderName = 'Microsoft-Windows-Windows Defender'; EventId = @(1006, 1015, 1116, 1117, 1118, 1119); MinCount = 1
            Description = 'Microsoft Defender detected (and possibly acted on) malware or suspicious behavior.'
            Impact      = 'The system may be compromised; some threats need a full scan to fully remove.'
            Recommendation = 'Update Defender and run a full/quick scan; review quarantined items.'
            FixId = 'defender-scan'
        }
        & $rule @{
            Id = 'SEC-DEFENDER-UPDATE'; Name = 'Defender signatures out of date'; Category = 'Security'; Severity = 'Warning'
            LogName = 'Microsoft-Windows-Windows Defender/Operational'
            ProviderName = 'Microsoft-Windows-Windows Defender'; EventId = @(2001, 2003); MinCount = 1
            Description = 'Microsoft Defender failed to update its security intelligence (definitions).'
            Impact      = 'Out-of-date definitions miss new threats.'
            Recommendation = 'Force a definition update and quick scan.'
            FixId = 'defender-scan'
        }
    )
}
