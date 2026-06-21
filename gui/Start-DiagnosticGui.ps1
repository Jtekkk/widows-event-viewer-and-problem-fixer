#Requires -Version 5.1
<#
.SYNOPSIS
    A simple WPF front-end for the Windows Diagnostic & Problem-Fixer tool.

.DESCRIPTION
    Click "Scan" to list detected problems, select one or more rows, then click
    "Fix Selected" to apply their automatic repairs. Run from an elevated session
    so that fixes (and the Security log) are available.

    This GUI is a convenience wrapper over the same module used by the CLI; the
    command line offers more options (-WhatIf previews, scoping by rule, etc.).

.NOTES
    Windows only (requires .NET WPF assemblies). The window runs the scan on the
    UI thread, so it will appear busy while scanning large logs.
#>
[CmdletBinding()]
param()

if ($env:OS -ne 'Windows_NT') {
    Write-Error 'The GUI requires Windows (WPF).'
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# -- Import the module from the repo root ------------------------------- #
$root     = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'WindowsDiagnosticTool.psd1'
if (-not (Test-Path -LiteralPath $manifest)) { throw "Cannot find WindowsDiagnosticTool.psd1 in '$root'." }
Import-Module $manifest -Force -ErrorAction Stop

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Diagnostic and Problem Fixer" Height="640" Width="1000"
        WindowStartupLocation="CenterScreen" Background="#F1F5F9">
  <DockPanel Margin="10">
    <Border DockPanel.Dock="Top" Background="#0F172A" CornerRadius="8" Padding="14" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Text="Windows Diagnostic and Problem Fixer" Foreground="White" FontSize="18" FontWeight="Bold"/>
        <TextBlock Name="SubText" Foreground="#94A3B8" FontSize="12" Text="Scan the event logs for problems, then fix the ones you select."/>
      </StackPanel>
    </Border>

    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
      <TextBlock Text="Days:" VerticalAlignment="Center" Margin="2,0,4,0"/>
      <TextBox Name="DaysBox" Width="50" Text="7" VerticalAlignment="Center"/>
      <CheckBox Name="WarnChk" Content="Include warnings" VerticalAlignment="Center" Margin="12,0,0,0"/>
      <Button Name="ScanBtn" Content="Scan" Width="90" Height="30" Margin="16,0,0,0" Background="#1971C2" Foreground="White"/>
      <Button Name="FixBtn" Content="Fix Selected" Width="110" Height="30" Margin="8,0,0,0" Background="#2B8A3E" Foreground="White" IsEnabled="False"/>
      <Button Name="ReportBtn" Content="Save HTML Report" Width="140" Height="30" Margin="8,0,0,0" IsEnabled="False"/>
    </StackPanel>

    <Border DockPanel.Dock="Bottom" Background="#E2E8F0" CornerRadius="6" Padding="8" Margin="0,10,0,0">
      <TextBlock Name="StatusText" Text="Ready." FontSize="12"/>
    </Border>

    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="2*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="1*"/>
      </Grid.RowDefinitions>

      <DataGrid Name="Grid" Grid.Row="0" AutoGenerateColumns="False" IsReadOnly="True"
                SelectionMode="Extended" SelectionUnit="FullRow" GridLinesVisibility="Horizontal"
                HeadersVisibility="Column" RowHeight="26" Background="White">
        <DataGrid.Columns>
          <DataGridTextColumn Header="Severity" Binding="{Binding Severity}" Width="80"/>
          <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="90"/>
          <DataGridTextColumn Header="Problem"  Binding="{Binding Name}" Width="*"/>
          <DataGridTextColumn Header="Count"    Binding="{Binding Count}" Width="60"/>
          <DataGridTextColumn Header="Last seen" Binding="{Binding LastSeen}" Width="120"/>
          <DataGridTextColumn Header="Auto-fix" Binding="{Binding FixName}" Width="200"/>
          <DataGridTextColumn Header="Status"   Binding="{Binding Status}" Width="160"/>
        </DataGrid.Columns>
      </DataGrid>

      <GridSplitter Grid.Row="1" Height="5" HorizontalAlignment="Stretch" Background="#CBD5E1"/>

      <Border Grid.Row="2" Background="White" CornerRadius="6" Margin="0,6,0,0" Padding="8">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <TextBlock Name="Detail" TextWrapping="Wrap" FontFamily="Consolas" FontSize="12"
                     Text="Select a problem to see details and the recommended action."/>
        </ScrollViewer>
      </Border>
    </Grid>
  </DockPanel>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win    = [Windows.Markup.XamlReader]::Load($reader)

# Resolve named controls.
$ctl = @{}
foreach ($n in 'SubText','DaysBox','WarnChk','ScanBtn','FixBtn','ReportBtn','StatusText','Grid','Detail') {
    $ctl[$n] = $win.FindName($n)
}

# Script-scoped state shared by handlers.
$state = [pscustomobject]@{ Findings = @(); Rows = @() }

function Set-Status([string]$text) { $ctl.StatusText.Text = $text }

# Admin awareness.
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
if (-not $isAdmin) {
    $ctl.SubText.Text = 'Not elevated - most fixes will be skipped. Re-launch as Administrator to apply repairs.'
}

function Update-Grid {
    param($Findings)
    $rows = foreach ($f in $Findings) {
        $fixName = if ($f.HasFix) { ((Get-WindowsDiagnosticRule | Where-Object Id -eq $f.RuleId | Select-Object -First 1).FixName) } else { '(manual)' }
        [pscustomobject]@{
            Severity = $f.Severity
            Category = $f.Category
            Name     = $f.Name
            Count    = $f.Count
            LastSeen = if ($f.LastSeen) { '{0:yyyy-MM-dd HH:mm}' -f $f.LastSeen } else { 'n/a' }
            FixName  = $fixName
            Status   = if ($f.FixApplied -and $f.FixResult) { $f.FixResult.Message } else { '' }
            Finding  = $f
        }
    }
    $state.Rows = @($rows)
    $ctl.Grid.ItemsSource = $state.Rows
}

# -- Scan ----------------------------------------------------------------- #
$ctl.ScanBtn.Add_Click({
    try {
        $ctl.ScanBtn.IsEnabled = $false
        Set-Status 'Scanning event logs, please wait...'
        $win.Dispatcher.Invoke([action]{}, 'Background')

        $days = 7; [void][int]::TryParse($ctl.DaysBox.Text, [ref]$days)
        if ($days -lt 1) { $days = 7 }
        $params = @{ Days = $days; Quiet = $true; NoHtmlReport = $true; PassThru = $true }
        $params['MinSeverity'] = if ($ctl.WarnChk.IsChecked) { 'Warning' } else { 'Error' }

        $state.Findings = @(Get-WindowsDiagnosticReport @params)
        Update-Grid -Findings $state.Findings

        $crit = @($state.Findings | Where-Object Severity -eq 'Critical').Count
        $fixable = @($state.Findings | Where-Object HasFix).Count
        Set-Status ("Found {0} problem(s): {1} critical, {2} auto-fixable. Select rows and click 'Fix Selected'." -f $state.Findings.Count, $crit, $fixable)
        $ctl.FixBtn.IsEnabled = ($fixable -gt 0 -and $isAdmin)
        $ctl.ReportBtn.IsEnabled = $true
    }
    catch {
        Set-Status "Scan failed: $($_.Exception.Message)"
    }
    finally {
        $ctl.ScanBtn.IsEnabled = $true
    }
})

# -- Fix selected --------------------------------------------------------- #
$ctl.FixBtn.Add_Click({
    $selected = @($ctl.Grid.SelectedItems)
    if (-not $selected.Count) { Set-Status 'Select one or more rows first.'; return }
    $targets = @($selected | ForEach-Object { $_.Finding } | Where-Object { $_.HasFix })
    if (-not $targets.Count) { Set-Status 'None of the selected rows have an automatic fix.'; return }

    $answer = [System.Windows.MessageBox]::Show(
        "Apply automatic fixes to $($targets.Count) selected problem(s)? A System Restore point will be created first.",
        'Confirm fixes', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }

    try {
        $ctl.FixBtn.IsEnabled = $false
        Set-Status 'Applying fixes...'
        $win.Dispatcher.Invoke([action]{}, 'Background')
        $targets | Repair-WindowsProblem -Confirm:$false | Out-Null
        Update-Grid -Findings $state.Findings
        Set-Status 'Fixes applied. Review the Status column. A reboot may be required for some fixes.'
    }
    catch {
        Set-Status "Fix failed: $($_.Exception.Message)"
    }
    finally {
        $ctl.FixBtn.IsEnabled = $true
    }
})

# -- Save HTML report ----------------------------------------------------- #
$ctl.ReportBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'HTML report (*.html)|*.html'
    $dlg.FileName = "WindowsDiagnostic_{0:yyyyMMdd_HHmmss}.html" -f (Get-Date)
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        Set-Status 'Generating HTML report...'
        $win.Dispatcher.Invoke([action]{}, 'Background')
        $days = 7; [void][int]::TryParse($ctl.DaysBox.Text, [ref]$days)
        $p = @{ Days = $days; Quiet = $true; ReportPath = $dlg.FileName }
        $p['MinSeverity'] = if ($ctl.WarnChk.IsChecked) { 'Warning' } else { 'Error' }
        Get-WindowsDiagnosticReport @p | Out-Null
        Set-Status "Report saved to $($dlg.FileName)"
        Invoke-Item -LiteralPath $dlg.FileName
    }
    catch { Set-Status "Report failed: $($_.Exception.Message)" }
})

# -- Selection -> details pane ------------------------------------------- #
$ctl.Grid.Add_SelectionChanged({
    $row = $ctl.Grid.SelectedItem
    if (-not $row) { return }
    $f = $row.Finding
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("[$($f.Severity)] $($f.Name)  ($($f.Category))")
    [void]$sb.AppendLine("Rule: $($f.RuleId)   Occurrences: $($f.Count)")
    [void]$sb.AppendLine('')
    if ($f.SampleMessage) { [void]$sb.AppendLine("Example event:"); [void]$sb.AppendLine($f.SampleMessage); [void]$sb.AppendLine('') }
    [void]$sb.AppendLine("Recommendation:"); [void]$sb.AppendLine($f.Rule.Recommendation)
    if ($f.FixApplied -and $f.FixResult) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine("Fix result: $($f.FixResult.Message)")
        if ($f.FixResult.Detail) { [void]$sb.AppendLine($f.FixResult.Detail) }
    }
    $ctl.Detail.Text = $sb.ToString()
})

[void]$win.ShowDialog()
