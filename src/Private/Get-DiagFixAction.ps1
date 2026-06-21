function Get-DiagFixAction {
    <#
    .SYNOPSIS
        Returns the catalog of automatic repair actions keyed by FixId.

    .DESCRIPTION
        Each diagnostic rule may reference a FixId. This function is the single
        source of truth for what those fixes actually do. Every action is a
        script block that accepts one argument -- the matched finding (so the fix
        can read the offending events, e.g. to learn which service crashed) --
        and returns a standard result object:

            [pscustomobject]@{
                Success        = [bool]
                RebootRequired = [bool]
                Message        = [string]   # short summary
                Detail         = [string]   # full command output / extra detail
            }

        Actions never prompt; the *decision* to run them (ShouldProcess, admin
        check, restore point) is made by the caller. This keeps the fixes pure
        and unit-testable in isolation.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $actions = [ordered]@{}

    # ------------------------------------------------------------------ #
    # System file & component store repair (DISM + SFC)
    # ------------------------------------------------------------------ #
    $actions['sfc-dism'] = [pscustomobject]@{
        Id             = 'sfc-dism'
        Name           = 'Repair system files (DISM + SFC)'
        Description    = 'Restores the component store with DISM /RestoreHealth, then runs sfc /scannow to repair protected system files.'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $reboot  = $false
            $details = New-Object System.Collections.Generic.List[string]

            $dism = Invoke-DiagProcess -FilePath 'DISM.exe' `
                -ArgumentList '/Online', '/Cleanup-Image', '/RestoreHealth' `
                -SuccessExitCodes 0, 3010
            $details.Add("DISM (exit $($dism.ExitCode)):`n$($dism.Output)")
            if ($dism.ExitCode -eq 3010) { $reboot = $true }

            $sfc = Invoke-DiagProcess -FilePath 'sfc.exe' -ArgumentList '/scannow'
            $details.Add("SFC (exit $($sfc.ExitCode)):`n$($sfc.Output)")

            $ok  = $dism.Success
            $msg = if ($ok) {
                'Component store and protected system files were checked/repaired.'
            } else {
                'DISM reported an error; review the detail and consider a repair-install.'
            }
            [pscustomobject]@{ Success = $ok; RebootRequired = $reboot; Message = $msg; Detail = ($details -join "`n`n") }
        }
    }

    # ------------------------------------------------------------------ #
    # Disk scan (chkdsk online scan -- no reboot needed)
    # ------------------------------------------------------------------ #
    $actions['chkdsk-scan'] = [pscustomobject]@{
        Id             = 'chkdsk-scan'
        Name           = 'Scan system drive for errors (chkdsk /scan)'
        Description    = 'Runs an online chkdsk scan on the system drive. This is read-only-safe and does not require a reboot. If corruption is found that needs an offline fix, the tool reports that a chkdsk /f is required.'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $drive = ($env:SystemDrive); if (-not $drive) { $drive = 'C:' }
            # /scan performs an online scan; exit 0 = clean, 1 = errors found.
            $res = Invoke-DiagProcess -FilePath 'chkdsk.exe' -ArgumentList $drive, '/scan' -SuccessExitCodes 0, 1
            $needsOffline = $res.ExitCode -eq 1 -or $res.Output -match 'spot fix|run chkdsk|/F'
            $msg = if ($res.ExitCode -eq 0) {
                "No problems found on $drive."
            } elseif ($needsOffline) {
                "$drive has issues that need an offline fix. Run 'chkdsk $drive /f' and reboot."
            } else {
                "chkdsk completed on $drive (exit $($res.ExitCode))."
            }
            [pscustomobject]@{ Success = $res.Success; RebootRequired = $false; Message = $msg; Detail = $res.Output }
        }
    }

    # ------------------------------------------------------------------ #
    # Restart crashed services and harden their recovery options
    # ------------------------------------------------------------------ #
    $actions['restart-service'] = [pscustomobject]@{
        Id             = 'restart-service'
        Name           = 'Restart crashed services & set auto-recovery'
        Description    = 'Identifies the services named in the Service Control Manager events, starts any that are stopped, and configures them to restart automatically on future failures.'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $details = New-Object System.Collections.Generic.List[string]
            $handled = New-Object System.Collections.Generic.List[string]
            $failed  = $false

            # The first insertion string of SCM events is the service display name.
            $names = @()
            foreach ($evt in $Context.Events) {
                try {
                    if ($evt.Properties -and $evt.Properties.Count -ge 1) {
                        $val = [string]$evt.Properties[0].Value
                        if ($val) { $names += $val.Trim() }
                    }
                } catch { }
            }
            $names = $names | Where-Object { $_ } | Select-Object -Unique

            if (-not $names) {
                return [pscustomobject]@{ Success = $false; RebootRequired = $false; Message = 'Could not determine which service(s) to restart from the events.'; Detail = '' }
            }

            foreach ($name in $names) {
                $svc = Get-Service -DisplayName $name -ErrorAction SilentlyContinue
                if (-not $svc) { $svc = Get-Service -Name $name -ErrorAction SilentlyContinue }
                if (-not $svc) {
                    $details.Add("[$name] service not found (may have been removed).")
                    continue
                }

                try {
                    if ($svc.Status -ne 'Running') {
                        Start-Service -InputObject $svc -ErrorAction Stop
                        $details.Add("[$($svc.Name)] started (was $($svc.Status)).")
                    } else {
                        $details.Add("[$($svc.Name)] already running.")
                    }
                    # Configure auto-recovery: restart after 60s on 1st/2nd failure,
                    # reset the failure counter daily.
                    $sc = Invoke-DiagProcess -FilePath 'sc.exe' `
                        -ArgumentList 'failure', $svc.Name, 'reset=', '86400', 'actions=', 'restart/60000/restart/60000/restart/60000'
                    $details.Add("[$($svc.Name)] recovery configured (sc exit $($sc.ExitCode)).")
                    $handled.Add($svc.Name)
                }
                catch {
                    $failed = $true
                    $details.Add("[$name] could not be restarted: $($_.Exception.Message)")
                }
            }

            $msg = if ($handled.Count) { "Handled service(s): $($handled -join ', ')." }
                   else { 'No services could be restarted.' }
            [pscustomobject]@{ Success = (-not $failed -and $handled.Count -gt 0); RebootRequired = $false; Message = $msg; Detail = ($details -join "`n") }
        }
    }

    # ------------------------------------------------------------------ #
    # Reset Windows Update components
    # ------------------------------------------------------------------ #
    $actions['reset-windowsupdate'] = [pscustomobject]@{
        Id             = 'reset-windowsupdate'
        Name           = 'Reset Windows Update components'
        Description    = 'Stops the Update/BITS/Cryptographic services, renames the SoftwareDistribution and catroot2 caches so Windows rebuilds them, then restarts the services. This is the standard fix for stuck or failing updates.'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $details  = New-Object System.Collections.Generic.List[string]
            $services = 'wuauserv', 'bits', 'cryptsvc'
            $ok       = $true

            foreach ($s in $services) {
                try { Stop-Service -Name $s -Force -ErrorAction Stop; $details.Add("Stopped $s.") }
                catch { $details.Add("Could not stop $s ($($_.Exception.Message)).") }
            }

            $stamp   = Get-Date -Format 'yyyyMMddHHmmss'
            $targets = @(
                (Join-Path $env:SystemRoot 'SoftwareDistribution'),
                (Join-Path $env:SystemRoot 'System32\catroot2')
            )
            foreach ($path in $targets) {
                if (Test-Path -LiteralPath $path) {
                    $backup = "$path.$stamp.bak"
                    try {
                        Rename-Item -LiteralPath $path -NewName (Split-Path $backup -Leaf) -ErrorAction Stop
                        $details.Add("Renamed '$path' -> '$(Split-Path $backup -Leaf)'.")
                    }
                    catch {
                        $ok = $false
                        $details.Add("Could not rename '$path' ($($_.Exception.Message)). A reboot may be required.")
                    }
                }
            }

            foreach ($s in $services) {
                try { Start-Service -Name $s -ErrorAction Stop; $details.Add("Started $s.") }
                catch { $ok = $false; $details.Add("Could not start $s ($($_.Exception.Message)).") }
            }

            $msg = if ($ok) { 'Windows Update components were reset. Check for updates again.' }
                   else { 'Windows Update reset completed with warnings (see detail).' }
            [pscustomobject]@{ Success = $ok; RebootRequired = $false; Message = $msg; Detail = ($details -join "`n") }
        }
    }

    # ------------------------------------------------------------------ #
    # Flush DNS resolver cache
    # ------------------------------------------------------------------ #
    $actions['flush-dns'] = [pscustomobject]@{
        Id             = 'flush-dns'
        Name           = 'Flush DNS resolver cache'
        Description    = 'Clears the DNS client cache (ipconfig /flushdns) and restarts the DNS Client service to resolve name-resolution failures.'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $flush = Invoke-DiagProcess -FilePath 'ipconfig.exe' -ArgumentList '/flushdns'
            $detail = $flush.Output
            try { Restart-Service -Name 'Dnscache' -Force -ErrorAction Stop; $detail += "`nRestarted Dnscache service." }
            catch { $detail += "`nDnscache restart skipped: $($_.Exception.Message)" }
            [pscustomobject]@{ Success = $flush.Success; RebootRequired = $false; Message = 'DNS cache flushed.'; Detail = $detail }
        }
    }

    # ------------------------------------------------------------------ #
    # Renew DHCP lease
    # ------------------------------------------------------------------ #
    $actions['renew-dhcp'] = [pscustomobject]@{
        Id             = 'renew-dhcp'
        Name           = 'Renew IP address (DHCP)'
        Description    = 'Releases and renews the DHCP lease (ipconfig /release then /renew) to recover from IP address conflicts or lease failures. Briefly interrupts network connectivity.'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $rel = Invoke-DiagProcess -FilePath 'ipconfig.exe' -ArgumentList '/release'
            $ren = Invoke-DiagProcess -FilePath 'ipconfig.exe' -ArgumentList '/renew'
            [pscustomobject]@{
                Success        = $ren.Success
                RebootRequired = $false
                Message        = 'Released and renewed the DHCP lease.'
                Detail         = "RELEASE:`n$($rel.Output)`n`nRENEW:`n$($ren.Output)"
            }
        }
    }

    # ------------------------------------------------------------------ #
    # Reset the network stack (Winsock + TCP/IP) -- needs reboot
    # ------------------------------------------------------------------ #
    $actions['reset-network'] = [pscustomobject]@{
        Id             = 'reset-network'
        Name           = 'Reset network stack (Winsock + TCP/IP)'
        Description    = 'Resets the Winsock catalog and the TCP/IP stack to defaults. Use this for persistent connectivity problems. A reboot is required to complete the reset.'
        RequiresAdmin  = $true
        RequiresReboot = $true
        Action         = {
            param($Context)
            $w = Invoke-DiagProcess -FilePath 'netsh.exe' -ArgumentList 'winsock', 'reset'
            $i = Invoke-DiagProcess -FilePath 'netsh.exe' -ArgumentList 'int', 'ip', 'reset'
            [pscustomobject]@{
                Success        = ($w.Success -and $i.Success)
                RebootRequired = $true
                Message        = 'Network stack reset. Reboot to complete.'
                Detail         = "WINSOCK:`n$($w.Output)`n`nTCP/IP:`n$($i.Output)"
            }
        }
    }

    # ------------------------------------------------------------------ #
    # Resync the system clock
    # ------------------------------------------------------------------ #
    $actions['resync-time'] = [pscustomobject]@{
        Id             = 'resync-time'
        Name           = 'Resynchronize system time'
        Description    = 'Ensures the Windows Time service is running and forces a resync with the configured time source (w32tm /resync).'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $detail = ''
            try {
                Set-Service -Name 'W32Time' -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue
                $detail += "Ensured W32Time service is running.`n"
            } catch { }
            $cfg    = Invoke-DiagProcess -FilePath 'w32tm.exe' -ArgumentList '/config', '/update'
            $resync = Invoke-DiagProcess -FilePath 'w32tm.exe' -ArgumentList '/resync', '/force'
            $detail += "CONFIG:`n$($cfg.Output)`n`nRESYNC:`n$($resync.Output)"
            [pscustomobject]@{ Success = $resync.Success; RebootRequired = $false; Message = 'System time resynchronized.'; Detail = $detail }
        }
    }

    # ------------------------------------------------------------------ #
    # Clean temporary files / free disk space
    # ------------------------------------------------------------------ #
    $actions['clean-temp'] = [pscustomobject]@{
        Id             = 'clean-temp'
        Name           = 'Clean temporary files & recycle bin'
        Description    = 'Deletes the contents of the user and system TEMP folders and empties the Recycle Bin to reclaim disk space. Files in use are skipped safely.'
        RequiresAdmin  = $false
        RequiresReboot = $false
        Action         = {
            param($Context)
            $details = New-Object System.Collections.Generic.List[string]
            $before  = 0L
            try {
                $sysDrive = ($env:SystemDrive); if (-not $sysDrive) { $sysDrive = 'C:' }
                $vol = Get-PSDrive -Name $sysDrive.TrimEnd(':') -ErrorAction SilentlyContinue
                if ($vol) { $before = [int64]$vol.Free }
            } catch { }

            $paths = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) |
                Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
            foreach ($p in $paths) {
                try {
                    Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    $details.Add("Cleared $p")
                } catch { $details.Add("Partially cleared $p ($($_.Exception.Message))") }
            }

            try { Clear-RecycleBin -Force -ErrorAction Stop; $details.Add('Emptied Recycle Bin.') }
            catch { $details.Add("Recycle Bin not emptied: $($_.Exception.Message)") }

            $freed = 0L
            try {
                $sysDrive = ($env:SystemDrive); if (-not $sysDrive) { $sysDrive = 'C:' }
                $vol = Get-PSDrive -Name $sysDrive.TrimEnd(':') -ErrorAction SilentlyContinue
                if ($vol) { $freed = [int64]$vol.Free - $before }
            } catch { }
            $freedMB = [math]::Round($freed / 1MB, 1)

            [pscustomobject]@{
                Success        = $true
                RebootRequired = $false
                Message        = "Temporary files cleaned (~$freedMB MB freed)."
                Detail         = ($details -join "`n")
            }
        }
    }

    # ------------------------------------------------------------------ #
    # Refresh Group Policy
    # ------------------------------------------------------------------ #
    $actions['refresh-grouppolicy'] = [pscustomobject]@{
        Id             = 'refresh-grouppolicy'
        Name           = 'Refresh Group Policy (gpupdate /force)'
        Description    = 'Forces a full re-application of computer and user Group Policy, which clears transient failures to read or apply policy.'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $res = Invoke-DiagProcess -FilePath 'gpupdate.exe' -ArgumentList '/force'
            [pscustomobject]@{ Success = $res.Success; RebootRequired = ($res.Output -match 'restart|reboot'); Message = 'Group Policy refreshed.'; Detail = $res.Output }
        }
    }

    # ------------------------------------------------------------------ #
    # Restart the Print Spooler and clear stuck print jobs
    # ------------------------------------------------------------------ #
    $actions['restart-spooler'] = [pscustomobject]@{
        Id             = 'restart-spooler'
        Name           = 'Restart Print Spooler & clear the print queue'
        Description    = 'Stops the Print Spooler, deletes stuck jobs in the spool folder, and restarts it. Resolves the common "spooler keeps crashing / cannot print" problem.'
        RequiresAdmin  = $true
        RequiresReboot = $false
        Action         = {
            param($Context)
            $details = New-Object System.Collections.Generic.List[string]
            try { Stop-Service -Name 'Spooler' -Force -ErrorAction Stop; $details.Add('Stopped Spooler.') }
            catch { $details.Add("Could not stop Spooler: $($_.Exception.Message)") }
            $spool = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
            if (Test-Path -LiteralPath $spool) {
                try {
                    Get-ChildItem -LiteralPath $spool -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                    $details.Add('Cleared queued print jobs.')
                } catch { $details.Add("Could not clear queue: $($_.Exception.Message)") }
            }
            $started = $false
            try { Start-Service -Name 'Spooler' -ErrorAction Stop; $started = $true; $details.Add('Started Spooler.') }
            catch { $details.Add("Could not start Spooler: $($_.Exception.Message)") }
            [pscustomobject]@{ Success = $started; RebootRequired = $false; Message = 'Print Spooler restarted and queue cleared.'; Detail = ($details -join "`n") }
        }
    }

    return $actions
}
