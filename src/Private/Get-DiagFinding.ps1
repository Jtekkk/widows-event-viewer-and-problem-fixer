function Get-DiagFinding {
    <#
    .SYNOPSIS
        Matches collected events against the diagnostic rules and produces
        "finding" objects (a detected problem + its supporting evidence).

    .DESCRIPTION
        This is the analysis stage. Every rule is evaluated against the in-memory
        event set (no extra log queries). A rule fires when the number of matching
        events meets or exceeds its MinCount threshold. The resulting finding
        carries the matched events so a fix can inspect them (for example, to learn
        which service crashed) and so the report can show representative samples.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Event,

        [Parameter(Mandatory)]
        [pscustomobject[]]$Rule,

        # Cap on events stored per finding (keeps memory/report sane).
        [int]$MaxEventsPerFinding = 200
    )

    $severityRank = @{ 'Critical' = 3; 'Error' = 2; 'Warning' = 1 }
    $findings     = New-Object System.Collections.Generic.List[object]

    # An empty scan (or a collection that PowerShell unrolled to $null) simply
    # yields no findings.
    if (-not $Event) { return @() }

    foreach ($r in $Rule) {
        $providers = @($r.ProviderName)

        # NOTE: do not name this $matches -- that is PowerShell's automatic
        # variable, overwritten by the -match/-notmatch operators used below.
        $matched = foreach ($e in $Event) {
            if ($e.LogName -ne $r.LogName) { continue }
            if ($providers.Count -and ($providers -notcontains $e.ProviderName)) { continue }
            if ($r.EventId.Count -and ($r.EventId -notcontains [int]$e.Id)) { continue }
            if ($null -ne $r.Level -and ($r.Level -notcontains [int]$e.Level)) { continue }
            if ($r.MessagePattern -and ($e.Message -notmatch $r.MessagePattern)) { continue }
            $e
        }
        $matched = @($matched)

        if ($matched.Count -lt $r.MinCount) { continue }

        $times    = $matched | ForEach-Object { $_.TimeCreated } | Where-Object { $_ }
        $firstSeen = if ($times) { ($times | Measure-Object -Minimum).Minimum } else { $null }
        $lastSeen  = if ($times) { ($times | Measure-Object -Maximum).Maximum } else { $null }

        # A representative, de-duplicated set of event-id/source pairs.
        $breakdown = $matched | Group-Object Id | Sort-Object Count -Descending |
            ForEach-Object { "Event $($_.Name) x$($_.Count)" }

        $sample = ($matched | Sort-Object TimeCreated -Descending | Select-Object -First 1).Message
        if ($sample) { $sample = ($sample -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 4) -join ' ' }

        $stored = @($matched | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEventsPerFinding)

        $findings.Add([pscustomobject]@{
            Rule          = $r
            RuleId        = $r.Id
            Name          = $r.Name
            Category      = $r.Category
            Severity      = $r.Severity
            SeverityRank  = [int]$severityRank[$r.Severity]
            Count         = $matched.Count
            FirstSeen     = $firstSeen
            LastSeen      = $lastSeen
            Breakdown     = ($breakdown -join ', ')
            SampleMessage = $sample
            Events        = $stored
            FixId         = $r.FixId
            HasFix        = [bool]$r.FixId
            # Mutable fields populated when a fix is applied:
            FixApplied    = $false
            FixResult     = $null
        })
    }

    # Most severe and most frequent first.
    @($findings | Sort-Object -Property @{ Expression = 'SeverityRank'; Descending = $true },
                                        @{ Expression = 'Count'; Descending = $true })
}
