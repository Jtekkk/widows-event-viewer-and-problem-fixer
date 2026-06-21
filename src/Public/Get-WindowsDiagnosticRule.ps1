function Get-WindowsDiagnosticRule {
    <#
    .SYNOPSIS
        Lists the diagnostic rules the tool uses, together with the automatic fix
        (if any) attached to each.

    .DESCRIPTION
        Useful for discovering what the tool can detect and repair, and for
        choosing values to pass to -FixId / -ExcludeFixId / -Category.

    .EXAMPLE
        Get-WindowsDiagnosticRule | Format-Table Id, Category, Severity, FixName

    .EXAMPLE
        Get-WindowsDiagnosticRule -Category Network
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$Category,
        [ValidateSet('Critical', 'Error', 'Warning')] [string[]]$Severity
    )

    $fixActions = Get-DiagFixAction
    $rules = Get-DiagRule
    if ($Category) { $rules = $rules | Where-Object { $Category -contains $_.Category } }
    if ($Severity) { $rules = $rules | Where-Object { $Severity -contains $_.Severity } }

    foreach ($r in $rules) {
        $fix = if ($r.FixId) { $fixActions[$r.FixId] } else { $null }
        [pscustomobject]@{
            Id             = $r.Id
            Name           = $r.Name
            Category       = $r.Category
            Severity       = $r.Severity
            LogName        = $r.LogName
            EventId        = ($r.EventId -join ', ')
            HasFix         = [bool]$r.FixId
            FixId          = $r.FixId
            FixName        = if ($fix) { $fix.Name } else { '(manual)' }
            RequiresAdmin  = if ($fix) { $fix.RequiresAdmin } else { $false }
            RequiresReboot = if ($fix) { $fix.RequiresReboot } else { $false }
            Recommendation = $r.Recommendation
        }
    }
}
