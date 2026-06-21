function Show-DiagnosticGui {
    <#
    .SYNOPSIS
        Launches the graphical front-end for the Windows Diagnostic &
        Problem-Fixer tool.

    .DESCRIPTION
        A polished WPF dashboard: scan the event logs, filter/search the detected
        problems, review details, and apply automatic fixes to the ones you select
        (or all safe fixes at once). Run elevated to enable repairs and the
        Security log.

    .PARAMETER RelaunchPath
        Internal: the script path to relaunch when the user clicks "Run as admin"
        (used by the .ps1 launcher). When omitted, the current executable is
        relaunched (used by the compiled .exe).

    .EXAMPLE
        Show-DiagnosticGui
    #>
    [CmdletBinding()]
    param([string]$RelaunchPath)

    if ($env:OS -ne 'Windows_NT') { Write-Error 'The GUI requires Windows (WPF).'; return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    $isAdmin = Test-DiagAdministrator

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Diagnostic &amp; Problem Fixer" Height="740" Width="1160"
        WindowStartupLocation="CenterScreen" Background="#0B1220" FontFamily="Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="Panel" Color="#111A2E"/>
    <SolidColorBrush x:Key="Panel2" Color="#0F1830"/>
    <SolidColorBrush x:Key="Ink" Color="#E6EDF7"/>
    <SolidColorBrush x:Key="Muted" Color="#8A98B8"/>
    <SolidColorBrush x:Key="Accent" Color="#3B82F6"/>
    <SolidColorBrush x:Key="Good" Color="#22C55E"/>
    <SolidColorBrush x:Key="Crit" Color="#F43F5E"/>
    <SolidColorBrush x:Key="Err" Color="#F97316"/>
    <SolidColorBrush x:Key="Warn" Color="#EAB308"/>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="{StaticResource Accent}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="8" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#1E293B"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Panel}"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="16"/>
      <Setter Property="Margin" Value="0,0,12,0"/>
    </Style>

    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="{StaticResource Panel}"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="RowBackground" Value="{StaticResource Panel}"/>
      <Setter Property="AlternatingRowBackground" Value="{StaticResource Panel2}"/>
      <Setter Property="GridLinesVisibility" Value="None"/>
      <Setter Property="RowHeight" Value="30"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#0C1426"/>
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
  </Window.Resources>

  <DockPanel Margin="16">
    <!-- Header -->
    <Border DockPanel.Dock="Top" CornerRadius="14" Padding="20,16" Margin="0,0,0,14">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#1D4ED8" Offset="0"/><GradientStop Color="#0EA5E9" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Grid>
        <StackPanel>
          <TextBlock Text="Windows Diagnostic &amp; Problem Fixer" Foreground="White" FontSize="22" FontWeight="Bold"/>
          <TextBlock Name="SubText" Foreground="#DBEAFE" FontSize="12" Margin="0,2,0,0"
                     Text="Scan the Windows event logs for problems, then fix the ones you choose."/>
        </StackPanel>
        <Button Name="ElevateBtn" Style="{StaticResource Ghost}" Content="Run as admin"
                HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <!-- Toolbar -->
    <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Margin="0,0,0,14">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="Days" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="0,0,6,0"/>
        <TextBox Name="DaysBox" Text="7" Width="46" VerticalContentAlignment="Center" Padding="6,4"/>
        <TextBlock Text="Show" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="14,0,6,0"/>
        <ComboBox Name="SevBox" Width="150" SelectedIndex="0" VerticalContentAlignment="Center">
          <ComboBoxItem Content="Warning and above"/>
          <ComboBoxItem Content="Error and above"/>
          <ComboBoxItem Content="Critical only"/>
        </ComboBox>
        <TextBox Name="SearchBox" Width="200" Margin="14,0,0,0" Padding="6,4" VerticalContentAlignment="Center"
                 ToolTip="Filter by text"/>
        <Button Name="ScanBtn" Style="{StaticResource Btn}" Content="Scan" Margin="16,0,8,0"/>
        <Button Name="FixSelBtn" Style="{StaticResource Btn}" Content="Fix Selected" Background="{StaticResource Good}" IsEnabled="False"/>
        <Button Name="FixAllBtn" Style="{StaticResource Ghost}" Content="Fix All Safe" IsEnabled="False"/>
        <Button Name="ExportBtn" Style="{StaticResource Ghost}" Content="Export / Report" IsEnabled="False"/>
      </StackPanel>
    </Border>

    <!-- Dashboard cards -->
    <Grid DockPanel.Dock="Top" Margin="0,0,0,14">
      <Grid.ColumnDefinitions>
        <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/>
      </Grid.ColumnDefinitions>
      <Border Grid.Column="0" Style="{StaticResource Card}">
        <StackPanel><TextBlock Name="CritNum" Text="0" Foreground="{StaticResource Crit}" FontSize="30" FontWeight="Bold"/><TextBlock Text="CRITICAL" Foreground="{StaticResource Muted}" FontSize="11"/></StackPanel>
      </Border>
      <Border Grid.Column="1" Style="{StaticResource Card}">
        <StackPanel><TextBlock Name="ErrNum" Text="0" Foreground="{StaticResource Err}" FontSize="30" FontWeight="Bold"/><TextBlock Text="ERRORS" Foreground="{StaticResource Muted}" FontSize="11"/></StackPanel>
      </Border>
      <Border Grid.Column="2" Style="{StaticResource Card}">
        <StackPanel><TextBlock Name="WarnNum" Text="0" Foreground="{StaticResource Warn}" FontSize="30" FontWeight="Bold"/><TextBlock Text="WARNINGS" Foreground="{StaticResource Muted}" FontSize="11"/></StackPanel>
      </Border>
      <Border Grid.Column="3" Style="{StaticResource Card}" Margin="0">
        <StackPanel><TextBlock Name="FixNum" Text="0" Foreground="{StaticResource Accent}" FontSize="30" FontWeight="Bold"/><TextBlock Text="AUTO-FIXABLE" Foreground="{StaticResource Muted}" FontSize="11"/></StackPanel>
      </Border>
    </Grid>

    <!-- Status bar -->
    <Border DockPanel.Dock="Bottom" Style="{StaticResource Card}" Margin="0,14,0,0" Padding="12,10">
      <Grid>
        <TextBlock Name="StatusText" Text="Ready. Click Scan to begin." Foreground="{StaticResource Muted}" VerticalAlignment="Center"/>
        <ProgressBar Name="Progress" Width="180" Height="6" HorizontalAlignment="Right" IsIndeterminate="False" Visibility="Hidden"
                     Background="#0C1426" Foreground="{StaticResource Accent}" BorderThickness="0"/>
      </Grid>
    </Border>

    <!-- Main: grid + details -->
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="2*"/><RowDefinition Height="Auto"/><RowDefinition Height="1*"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0" Style="{StaticResource Card}" Margin="0" Padding="0">
        <DataGrid Name="Grid" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Extended" SelectionUnit="FullRow">
          <DataGrid.Columns>
            <DataGridTextColumn Header="SEVERITY" Binding="{Binding Severity}" Width="90">
              <DataGridTextColumn.ElementStyle>
                <Style TargetType="TextBlock">
                  <Setter Property="FontWeight" Value="Bold"/>
                  <Setter Property="Padding" Value="10,0"/>
                  <Style.Triggers>
                    <DataTrigger Binding="{Binding Severity}" Value="Critical"><Setter Property="Foreground" Value="#F43F5E"/></DataTrigger>
                    <DataTrigger Binding="{Binding Severity}" Value="Error"><Setter Property="Foreground" Value="#F97316"/></DataTrigger>
                    <DataTrigger Binding="{Binding Severity}" Value="Warning"><Setter Property="Foreground" Value="#EAB308"/></DataTrigger>
                  </Style.Triggers>
                </Style>
              </DataGridTextColumn.ElementStyle>
            </DataGridTextColumn>
            <DataGridTextColumn Header="CATEGORY" Binding="{Binding Category}" Width="100"/>
            <DataGridTextColumn Header="PROBLEM" Binding="{Binding Name}" Width="*"/>
            <DataGridTextColumn Header="COUNT" Binding="{Binding Count}" Width="60"/>
            <DataGridTextColumn Header="LAST SEEN" Binding="{Binding LastSeen}" Width="130"/>
            <DataGridTextColumn Header="AUTO-FIX" Binding="{Binding FixName}" Width="190"/>
            <DataGridTextColumn Header="STATUS" Binding="{Binding Status}" Width="150"/>
          </DataGrid.Columns>
        </DataGrid>
      </Border>

      <GridSplitter Grid.Row="1" Height="6" HorizontalAlignment="Stretch" Background="#0C1426"/>

      <Border Grid.Row="2" Style="{StaticResource Card}" Margin="0,8,0,0">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <TextBlock Name="Detail" Foreground="{StaticResource Ink}" TextWrapping="Wrap" FontFamily="Cascadia Mono, Consolas" FontSize="12"
                     Text="Select a problem to see details and the recommended action."/>
        </ScrollViewer>
      </Border>
    </Grid>
  </DockPanel>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $win = [Windows.Markup.XamlReader]::Load($reader)

    $ctl = @{}
    foreach ($n in 'SubText','DaysBox','SevBox','SearchBox','ScanBtn','FixSelBtn','FixAllBtn','ExportBtn','ElevateBtn',
                   'CritNum','ErrNum','WarnNum','FixNum','StatusText','Progress','Grid','Detail') {
        $ctl[$n] = $win.FindName($n)
    }

    $state = [pscustomobject]@{ Findings = @(); Rows = @() }
    $fixNames = @{}
    foreach ($r in (Get-WindowsDiagnosticRule)) { $fixNames[$r.Id] = $r.FixName }

    function Set-Status([string]$t) { $ctl.StatusText.Text = $t }
    function Pump { $win.Dispatcher.Invoke([action] {}, [Windows.Threading.DispatcherPriority]::Background) }

    if (-not $isAdmin) {
        $ctl.SubText.Text = 'Not elevated - repairs and the Security log are disabled. Click "Run as admin" to enable them.'
    } else {
        $ctl.ElevateBtn.Visibility = 'Collapsed'
    }

    $MinSeverityFromBox = {
        switch ($ctl.SevBox.SelectedIndex) { 1 { 'Error' } 2 { 'Critical' } default { 'Warning' } }
    }

    function Build-Rows($findings) {
        @($findings | ForEach-Object {
            [pscustomobject]@{
                Severity = $_.Severity
                Category = $_.Category
                Name     = $_.Name
                Count    = $_.Count
                LastSeen = if ($_.LastSeen) { '{0:yyyy-MM-dd HH:mm}' -f $_.LastSeen } else { 'n/a' }
                FixName  = if ($_.HasFix) { $fixNames[$_.RuleId] } else { '(manual)' }
                Status   = if ($_.FixApplied -and $_.FixResult) { $_.FixResult.Message } else { '' }
                Finding  = $_
            }
        })
    }

    function Apply-Filter {
        $q = $ctl.SearchBox.Text
        $rows = $state.Rows
        if ($q) { $rows = @($rows | Where-Object { $_.Name -match [regex]::Escape($q) -or $_.Category -match [regex]::Escape($q) }) }
        $ctl.Grid.ItemsSource = $rows
    }

    function Update-Cards {
        $f = $state.Findings
        $ctl.CritNum.Text = [string]@($f | Where-Object Severity -eq 'Critical').Count
        $ctl.ErrNum.Text  = [string]@($f | Where-Object Severity -eq 'Error').Count
        $ctl.WarnNum.Text = [string]@($f | Where-Object Severity -eq 'Warning').Count
        $ctl.FixNum.Text  = [string]@($f | Where-Object HasFix).Count
    }

    # ---- Scan ---------------------------------------------------------- #
    $ctl.ScanBtn.Add_Click({
        try {
            $ctl.ScanBtn.IsEnabled = $false
            $ctl.Progress.Visibility = 'Visible'; $ctl.Progress.IsIndeterminate = $true
            Set-Status 'Scanning event logs, please wait...'; Pump
            $days = 7; [void][int]::TryParse($ctl.DaysBox.Text, [ref]$days); if ($days -lt 1) { $days = 7 }
            $state.Findings = @(Get-WindowsDiagnosticReport -Days $days -MinSeverity (& $MinSeverityFromBox) -Quiet -NoHtmlReport)
            $state.Rows = Build-Rows $state.Findings
            Apply-Filter; Update-Cards
            $fixable = @($state.Findings | Where-Object HasFix).Count
            Set-Status ("Found {0} problem(s); {1} auto-fixable. Select rows then 'Fix Selected', or 'Fix All Safe'." -f $state.Findings.Count, $fixable)
            $ctl.FixSelBtn.IsEnabled = ($fixable -gt 0 -and $isAdmin)
            $ctl.FixAllBtn.IsEnabled = ($fixable -gt 0 -and $isAdmin)
            $ctl.ExportBtn.IsEnabled = $true
        }
        catch { Set-Status "Scan failed: $($_.Exception.Message)" }
        finally { $ctl.ScanBtn.IsEnabled = $true; $ctl.Progress.IsIndeterminate = $false; $ctl.Progress.Visibility = 'Hidden' }
    })

    $applyFixes = {
        param($targets, $label)
        if (-not $targets.Count) { Set-Status 'Nothing to fix in that selection.'; return }
        $answer = [System.Windows.MessageBox]::Show(
            "Apply automatic fixes to $($targets.Count) problem(s)? A System Restore point is created first.",
            'Confirm fixes', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { return }
        try {
            $ctl.FixSelBtn.IsEnabled = $false; $ctl.FixAllBtn.IsEnabled = $false
            $ctl.Progress.Visibility = 'Visible'; $ctl.Progress.IsIndeterminate = $true
            Set-Status "Applying $label fixes..."; Pump
            $targets | Repair-WindowsProblem -Confirm:$false | Out-Null
            $state.Rows = Build-Rows $state.Findings
            Apply-Filter
            Set-Status 'Fixes applied. Review the Status column (a reboot may be needed for some).'
        }
        catch { Set-Status "Fix failed: $($_.Exception.Message)" }
        finally { $ctl.FixSelBtn.IsEnabled = $isAdmin; $ctl.FixAllBtn.IsEnabled = $isAdmin; $ctl.Progress.IsIndeterminate = $false; $ctl.Progress.Visibility = 'Hidden' }
    }

    $ctl.FixSelBtn.Add_Click({
        $targets = @($ctl.Grid.SelectedItems | ForEach-Object { $_.Finding } | Where-Object { $_.HasFix })
        & $applyFixes $targets 'selected'
    })
    $ctl.FixAllBtn.Add_Click({
        $targets = @($state.Findings | Where-Object HasFix)
        & $applyFixes $targets 'all safe'
    })

    # ---- Export / report ---------------------------------------------- #
    $ctl.ExportBtn.Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = 'HTML report (*.html)|*.html|JSON (*.json)|*.json|CSV (*.csv)|*.csv'
        $dlg.FileName = "WindowsDiagnostic_{0:yyyyMMdd_HHmmss}" -f (Get-Date)
        if ($dlg.ShowDialog() -ne 'OK') { return }
        try {
            $days = 7; [void][int]::TryParse($ctl.DaysBox.Text, [ref]$days)
            $p = @{ Days = $days; Quiet = $true; MinSeverity = (& $MinSeverityFromBox) }
            switch ([System.IO.Path]::GetExtension($dlg.FileName).ToLower()) {
                '.json' { $p['NoHtmlReport'] = $true; $p['JsonPath'] = $dlg.FileName }
                '.csv'  { $p['NoHtmlReport'] = $true; $p['CsvPath'] = $dlg.FileName }
                default { $p['ReportPath'] = $dlg.FileName }
            }
            Set-Status 'Generating...'; Pump
            Get-WindowsDiagnosticReport @p | Out-Null
            Set-Status "Saved to $($dlg.FileName)"
            Invoke-Item -LiteralPath $dlg.FileName
        }
        catch { Set-Status "Export failed: $($_.Exception.Message)" }
    })

    # ---- Filters ------------------------------------------------------- #
    $ctl.SearchBox.Add_TextChanged({ Apply-Filter })
    $ctl.SevBox.Add_SelectionChanged({ if ($state.Findings.Count) { Set-Status 'Severity filter changed - click Scan to refresh results.' } })

    # ---- Selection -> details ----------------------------------------- #
    $ctl.Grid.Add_SelectionChanged({
        $row = $ctl.Grid.SelectedItem
        if (-not $row) { return }
        $f = $row.Finding
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("[$($f.Severity)] $($f.Name)   ($($f.Category))")
        [void]$sb.AppendLine("Rule: $($f.RuleId)    Occurrences: $($f.Count)")
        if ($f.Breakdown) { [void]$sb.AppendLine("Events: $($f.Breakdown)") }
        [void]$sb.AppendLine('')
        if ($f.SampleMessage) { [void]$sb.AppendLine('Example event:'); [void]$sb.AppendLine($f.SampleMessage); [void]$sb.AppendLine('') }
        [void]$sb.AppendLine('Recommendation:'); [void]$sb.AppendLine($f.Rule.Recommendation)
        if ($f.FixApplied -and $f.FixResult) {
            [void]$sb.AppendLine(''); [void]$sb.AppendLine("Fix result: $($f.FixResult.Message)")
            if ($f.FixResult.Detail) { [void]$sb.AppendLine($f.FixResult.Detail) }
        }
        $ctl.Detail.Text = $sb.ToString()
    })

    # ---- Elevate ------------------------------------------------------- #
    $ctl.ElevateBtn.Add_Click({
        try {
            $proc = (Get-Process -Id $PID).Path
            if ($RelaunchPath) {
                Start-Process -FilePath $proc -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$RelaunchPath`""
            } else {
                Start-Process -FilePath $proc -Verb RunAs
            }
            $win.Close()
        }
        catch { Set-Status "Could not elevate: $($_.Exception.Message)" }
    })

    [void]$win.ShowDialog()
}
