function Out-DiagHtmlReport {
    <#
    .SYNOPSIS
        Writes a self-contained HTML report (inline CSS, no external assets) and
        returns the path it was written to.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $SystemInfo,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Finding,
        [AllowEmptyCollection()] [object[]]$Event = @(),
        [AllowEmptyCollection()] [object[]]$LogEntry = @(),
        [Parameter(Mandatory)] [string]$Path
    )

    # HTML-encode helper (avoids requiring System.Web).
    function Enc([string]$s) {
        if ($null -eq $s) { return '' }
        $s = $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
        return $s
    }

    $fixActions = Get-DiagFixAction

    $crit = @($Finding | Where-Object Severity -eq 'Critical').Count
    $err  = @($Finding | Where-Object Severity -eq 'Error').Count
    $warn = @($Finding | Where-Object Severity -eq 'Warning').Count
    $fixable = @($Finding | Where-Object HasFix).Count

    # ---- Findings rows ----------------------------------------------- #
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($f in $Finding) {
        $sevClass = $f.Severity.ToLower()
        $fixCell  = '&mdash;'
        if ($f.HasFix -and $fixActions[$f.FixId]) {
            $fixCell = Enc $fixActions[$f.FixId].Name
        }
        $statusCell = ''
        if ($f.FixApplied -and $f.FixResult) {
            $cls = if ($f.FixResult.Success) { 'ok' } else { 'bad' }
            $statusCell = "<span class='pill $cls'>$(Enc $f.FixResult.Message)</span>"
        }
        $last = if ($f.LastSeen) { '{0:yyyy-MM-dd HH:mm}' -f $f.LastSeen } else { 'n/a' }
        $sample = Enc $f.SampleMessage
        $rec    = Enc $f.Rule.Recommendation

        $rows.Add(@"
<tr class="sev-$sevClass">
  <td><span class="badge $sevClass">$($f.Severity)</span></td>
  <td>$(Enc $f.Category)</td>
  <td><strong>$(Enc $f.Name)</strong><div class="muted">$(Enc $f.RuleId) &middot; $(Enc $f.Breakdown)</div></td>
  <td class="num">$($f.Count)</td>
  <td>$last</td>
  <td>$fixCell</td>
  <td>$statusCell</td>
</tr>
<tr class="detail"><td></td><td colspan="6"><div class="sample">$sample</div><div class="rec"><b>Recommendation:</b> $rec</div></td></tr>
"@)
    }
    if (-not $rows.Count) {
        $rows.Add('<tr><td colspan="7" class="good">No known problems were detected. The system looks healthy.</td></tr>')
    }

    # ---- Top error sources ------------------------------------------- #
    $srcRows = New-Object System.Collections.Generic.List[string]
    $top = $Event | Where-Object { [int]$_.Level -in 1, 2 } |
        Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 20
    foreach ($g in $top) {
        $first = $g.Group | Select-Object -First 1
        $srcRows.Add("<tr><td class='num'>$($g.Count)</td><td>$(Enc $first.ProviderName)</td><td class='num'>$($first.Id)</td><td>$(Enc $first.LogName)</td></tr>")
    }
    if (-not $srcRows.Count) { $srcRows.Add("<tr><td colspan='4' class='good'>No critical or error events found in the scanned window.</td></tr>") }

    # ---- Run log ----------------------------------------------------- #
    $logRows = New-Object System.Collections.Generic.List[string]
    foreach ($l in ($LogEntry | Select-Object -Last 400)) {
        $logRows.Add("<tr class='log-$($l.Level.ToLower())'><td class='muted'>$('{0:HH:mm:ss}' -f $l.Time)</td><td>$($l.Level)</td><td>$(Enc $l.Message)</td></tr>")
    }

    $generated = '{0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Windows Diagnostic Report - $(Enc $SystemInfo.ComputerName)</title>
<style>
  :root { --crit:#d6336c; --err:#e8590c; --warn:#f08c00; --ok:#2b8a3e; --bg:#0f172a; --card:#ffffff; }
  * { box-sizing: border-box; }
  body { font-family: 'Segoe UI', Roboto, Arial, sans-serif; margin:0; background:#f1f5f9; color:#1e293b; }
  header { background:linear-gradient(135deg,#0f172a,#1e3a8a); color:#fff; padding:28px 40px; }
  header h1 { margin:0 0 6px; font-size:24px; }
  header .meta { opacity:.85; font-size:13px; line-height:1.7; }
  .wrap { max-width:1100px; margin:0 auto; padding:24px 40px 60px; }
  .cards { display:flex; gap:16px; flex-wrap:wrap; margin:24px 0; }
  .card { background:var(--card); border-radius:12px; padding:18px 22px; flex:1; min-width:150px; box-shadow:0 1px 3px rgba(0,0,0,.08); }
  .card .n { font-size:34px; font-weight:700; }
  .card .l { font-size:12px; text-transform:uppercase; letter-spacing:.05em; color:#64748b; }
  .card.crit .n{color:var(--crit);} .card.err .n{color:var(--err);} .card.warn .n{color:var(--warn);} .card.fix .n{color:#1971c2;}
  h2 { margin:32px 0 12px; font-size:18px; border-bottom:2px solid #e2e8f0; padding-bottom:6px; }
  table { width:100%; border-collapse:collapse; background:#fff; border-radius:12px; overflow:hidden; box-shadow:0 1px 3px rgba(0,0,0,.06); }
  th { background:#f8fafc; text-align:left; padding:10px 12px; font-size:12px; text-transform:uppercase; letter-spacing:.04em; color:#475569; }
  td { padding:10px 12px; border-top:1px solid #eef2f7; vertical-align:top; font-size:14px; }
  td.num { text-align:right; font-variant-numeric:tabular-nums; }
  .badge { display:inline-block; padding:2px 9px; border-radius:999px; color:#fff; font-size:11px; font-weight:600; }
  .badge.critical{background:var(--crit);} .badge.error{background:var(--err);} .badge.warning{background:var(--warn);}
  tr.detail td { border-top:0; padding-top:0; }
  .sample { font-family:Consolas,monospace; font-size:12px; color:#334155; background:#f8fafc; padding:8px 10px; border-radius:8px; white-space:pre-wrap; }
  .rec { font-size:13px; margin-top:6px; color:#0f172a; }
  .muted { color:#94a3b8; font-size:12px; }
  .good { color:var(--ok); text-align:center; padding:18px; font-weight:600; }
  .pill { display:inline-block; padding:2px 8px; border-radius:6px; font-size:12px; }
  .pill.ok { background:#e6f4ea; color:var(--ok); } .pill.bad { background:#fde2e2; color:var(--crit); }
  details { margin-top:24px; } summary { cursor:pointer; font-weight:600; color:#475569; }
  .logtbl td { font-size:12px; font-family:Consolas,monospace; }
  tr.log-error td, tr.log-warning td { color:var(--err); }
  footer { text-align:center; color:#94a3b8; font-size:12px; padding:24px; }
</style>
</head>
<body>
<header>
  <h1>Windows Diagnostic Report</h1>
  <div class="meta">
    <div><b>$(Enc $SystemInfo.ComputerName)</b> &middot; $(Enc $SystemInfo.OSName) (build $(Enc $SystemInfo.OSBuild)) $(Enc $SystemInfo.Architecture)</div>
    <div>Uptime: $(Enc $SystemInfo.UptimeText) &middot; Elevated: $($SystemInfo.IsAdmin) &middot; PowerShell $(Enc $SystemInfo.PSVersion)</div>
    <div>Generated: $generated</div>
  </div>
</header>
<div class="wrap">
  <div class="cards">
    <div class="card crit"><div class="n">$crit</div><div class="l">Critical</div></div>
    <div class="card err"><div class="n">$err</div><div class="l">Errors</div></div>
    <div class="card warn"><div class="n">$warn</div><div class="l">Warnings</div></div>
    <div class="card fix"><div class="n">$fixable</div><div class="l">Auto-fixable</div></div>
  </div>

  <h2>Detected problems</h2>
  <table>
    <thead><tr><th>Severity</th><th>Category</th><th>Problem</th><th class="num">Count</th><th>Last seen</th><th>Auto-fix</th><th>Status</th></tr></thead>
    <tbody>
$($rows -join "`n")
    </tbody>
  </table>

  <h2>Top error sources in logs</h2>
  <table>
    <thead><tr><th class="num">Count</th><th>Source / Provider</th><th class="num">Event ID</th><th>Log</th></tr></thead>
    <tbody>
$($srcRows -join "`n")
    </tbody>
  </table>

  <details>
    <summary>Run log ($($LogEntry.Count) entries)</summary>
    <table class="logtbl">
      <thead><tr><th>Time</th><th>Level</th><th>Message</th></tr></thead>
      <tbody>
$($logRows -join "`n")
      </tbody>
    </table>
  </details>
</div>
<footer>Generated by the Windows Diagnostic &amp; Problem-Fixer Tool. Review changes before relying on automatic fixes.</footer>
</body>
</html>
"@

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $html -Encoding UTF8
    return $Path
}
