function Test-DiagAdministrator {
    <#
    .SYNOPSIS
        Returns $true when the current PowerShell session is running with
        elevated (Administrator) privileges.

    .DESCRIPTION
        Most repair actions (sfc, DISM, chkdsk, service control, Windows Update
        reset, network stack reset) require an elevated token. The diagnostic
        scan itself works without elevation for most logs, but the Security log
        and all fixes do not. On non-Windows hosts this safely returns $false.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($env:OS -ne 'Windows_NT' -and $PSVersionTable.Platform -eq 'Unix') {
        return $false
    }

    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}
