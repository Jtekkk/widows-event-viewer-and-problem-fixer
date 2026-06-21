function New-DiagRestorePoint {
    <#
    .SYNOPSIS
        Creates a System Restore point before applying repairs, when possible.

    .DESCRIPTION
        A safety net: before the tool changes services, the network stack, the
        Windows Update store or system files, it tries to create a restore point
        so the user can roll back. Requires Administrator rights and System
        Restore to be enabled on the system drive. Failure is non-fatal — it is
        logged and reported, and the caller decides whether to continue.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [string]$Description = "Windows Diagnostic Tool - before automatic fixes"
    )

    if (-not (Test-DiagAdministrator)) {
        Write-DiagLog -Level Warning -Message "Skipping restore point: Administrator rights are required."
        return $false
    }

    if (-not (Get-Command -Name Checkpoint-Computer -ErrorAction SilentlyContinue)) {
        Write-DiagLog -Level Warning -Message "Skipping restore point: Checkpoint-Computer is not available on this system."
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Create System Restore point")) {
        return $false
    }

    try {
        # Windows throttles restore points to one per ~24h by default; relax it
        # for this session so a pre-fix checkpoint is actually created.
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        if (Test-Path $key) {
            New-ItemProperty -Path $key -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        }

        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-DiagLog -Level Success -Message "Created System Restore point: '$Description'"
        return $true
    }
    catch {
        Write-DiagLog -Level Warning -Message "Could not create a restore point ($($_.Exception.Message)). System Restore may be disabled."
        return $false
    }
}
