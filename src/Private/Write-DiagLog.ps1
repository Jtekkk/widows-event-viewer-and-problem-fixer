function Write-DiagLog {
    <#
    .SYNOPSIS
        Writes a structured, colorized log line to the console and the in-memory
        session log (and to a transcript file when one is configured).

    .DESCRIPTION
        Central logging helper used throughout the Windows Diagnostic Tool. Every
        message is timestamped, tagged with a level, echoed to the host with a
        sensible color, appended to the module-scoped $script:DiagLog buffer, and
        — when $script:DiagLogFile is set — appended to that file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Action', 'Debug')]
        [string]$Level = 'Info',

        # Suppress console output (still recorded to buffer/file).
        [switch]$Quiet
    )

    $timestamp = Get-Date
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] [{1,-7}] {2}' -f $timestamp, $Level.ToUpper(), $Message

    # Append to the in-memory buffer so reports can include the full run log.
    if ($null -ne $script:DiagLog) {
        [void]$script:DiagLog.Add([pscustomobject]@{
            Time    = $timestamp
            Level   = $Level
            Message = $Message
        })
    }

    # Append to the transcript file if configured.
    if ($script:DiagLogFile) {
        try { Add-Content -LiteralPath $script:DiagLogFile -Value $line -Encoding UTF8 -ErrorAction Stop }
        catch { Write-Verbose "Unable to write to log file '$script:DiagLogFile': $($_.Exception.Message)" }
    }

    if ($Level -eq 'Debug') {
        # Route debug detail through the verbose stream instead of the host.
        Write-Verbose $Message
        return
    }

    if ($Quiet) { return }

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Action'  { 'Cyan' }
        default   { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
}
