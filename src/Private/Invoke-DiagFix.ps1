function Invoke-DiagFix {
    <#
    .SYNOPSIS
        Applies the automatic fix associated with a single finding and records
        the outcome on the finding object.

    .DESCRIPTION
        Looks up the finding's FixId in the action catalog, verifies that the
        required privileges are present, runs the action's script block (passing
        the finding as context) and stamps the result back onto the finding's
        FixApplied / FixResult properties. The decision to call this (confirmation,
        restore point) is the caller's responsibility -- this function just does
        the work.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Finding
    )

    if (-not $Finding.HasFix) {
        $res = [pscustomobject]@{ Success = $false; RebootRequired = $false; Message = 'No automatic fix is available; manual action required.'; Detail = $Finding.Rule.Recommendation }
        $Finding.FixApplied = $false
        $Finding.FixResult  = $res
        return $res
    }

    $action = (Get-DiagFixAction)[$Finding.FixId]
    if (-not $action) {
        $res = [pscustomobject]@{ Success = $false; RebootRequired = $false; Message = "Unknown fix id '$($Finding.FixId)'."; Detail = '' }
        $Finding.FixApplied = $false
        $Finding.FixResult  = $res
        return $res
    }

    if ($action.RequiresAdmin -and -not (Test-DiagAdministrator)) {
        $res = [pscustomobject]@{ Success = $false; RebootRequired = $false; Message = "Skipped: '$($action.Name)' requires Administrator rights."; Detail = 'Re-run the tool from an elevated PowerShell session.' }
        $Finding.FixApplied = $false
        $Finding.FixResult  = $res
        Write-DiagLog -Level Warning -Message $res.Message
        return $res
    }

    Write-DiagLog -Level Action -Message "Applying fix for [$($Finding.RuleId)] $($Finding.Name) -> $($action.Name)"
    try {
        $res = & $action.Action $Finding
        if ($null -eq $res) {
            $res = [pscustomobject]@{ Success = $false; RebootRequired = $false; Message = 'Fix produced no result.'; Detail = '' }
        }
    }
    catch {
        $res = [pscustomobject]@{ Success = $false; RebootRequired = $false; Message = "Fix threw an error: $($_.Exception.Message)"; Detail = ($_.ScriptStackTrace) }
    }

    $Finding.FixApplied = $true
    $Finding.FixResult  = $res

    if ($res.Success) { Write-DiagLog -Level Success -Message "  -> $($res.Message)" }
    else { Write-DiagLog -Level Error -Message "  -> $($res.Message)" }
    if ($res.RebootRequired) { Write-DiagLog -Level Warning -Message '  -> A reboot is required to complete this fix.' }

    return $res
}
