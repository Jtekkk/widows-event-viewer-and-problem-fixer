function Invoke-DiagProcess {
    <#
    .SYNOPSIS
        Runs an external command line tool, capturing stdout+stderr and the exit
        code into a single result object.

    .DESCRIPTION
        Repair actions frequently shell out to built-in Windows tools such as
        sfc.exe, DISM.exe, chkdsk.exe, netsh.exe, ipconfig.exe and w32tm.exe.
        This wrapper standardizes how those are invoked so every fix records the
        command, its output and whether it succeeded.

    .EXAMPLE
        Invoke-DiagProcess -FilePath 'ipconfig.exe' -ArgumentList '/flushdns'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        # Treat these non-zero exit codes as success (e.g. DISM 3010 = reboot req).
        [int[]]$SuccessExitCodes = @(0)
    )

    $display = ('{0} {1}' -f $FilePath, ($ArgumentList -join ' ')).Trim()
    Write-DiagLog -Level Action -Message "Running: $display"

    $output = ''
    $exit   = -1
    try {
        # The call operator captures merged stdout/stderr; $LASTEXITCODE holds the code.
        $output = (& $FilePath @ArgumentList 2>&1 | Out-String).TrimEnd()
        $exit   = $LASTEXITCODE
        if ($null -eq $exit) { $exit = 0 }  # Some commands don't set it.
    }
    catch {
        $output = $_.Exception.Message
        $exit   = -1
    }

    $success = $SuccessExitCodes -contains $exit

    [pscustomobject]@{
        Command  = $display
        ExitCode = $exit
        Success  = $success
        Output   = $output
    }
}
