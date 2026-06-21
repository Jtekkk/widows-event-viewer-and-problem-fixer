@{
    RootModule           = 'WindowsDiagnosticTool.psm1'
    ModuleVersion        = '1.1.0'
    GUID                 = 'a7d4e8c2-3b15-4f9a-9c2d-6e8b1f0a5d73'
    Author               = 'Windows Diagnostic Tool contributors'
    CompanyName          = 'Community'
    Copyright            = '(c) Windows Diagnostic Tool contributors. MIT License.'
    Description          = 'Scans Windows event logs and live system state for known problems and applies safe, automatic fixes (SFC/DISM, chkdsk, service recovery, Windows Update reset, DNS/DHCP, network reset, time resync, cleanup).'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'Invoke-WindowsDiagnostic',
        'Get-WindowsDiagnosticReport',
        'Repair-WindowsProblem',
        'Get-WindowsDiagnosticRule',
        'Show-DiagnosticGui'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Windows', 'EventLog', 'EventViewer', 'Diagnostics', 'Troubleshooting', 'Repair', 'SysAdmin')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ReleaseNotes = 'v1.1: more rules (drivers, VSS, MSI, Group Policy, profiles, lockouts), direct -ApplyFix, JSON/CSV export, level-agnostic detection, scan progress, and CI. See CHANGELOG.md.'
        }
    }
}
