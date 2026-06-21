#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for the Windows Diagnostic & Problem-Fixer tool.

    These cover the platform-independent logic: rule/fix-catalog integrity, event
    -> finding matching, MinCount thresholds, severity sorting, and HTML report
    generation. They do NOT touch the live event log, so they run on any OS with
    PowerShell + Pester (the actual fixes require Windows and elevation).

    Private functions are exercised through the module object with the call
    operator, e.g.  & $m { param($e) Get-DiagFinding -Event $e -Rule ... } $events
    Fake events are built in normal scope and passed IN as arguments (functions
    defined out here are not visible inside module scope).

    Run:  Invoke-Pester -Path ./tests
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:ModuleRoot 'WindowsDiagnosticTool.psd1') -Force
    $script:m = Get-Module WindowsDiagnosticTool

    # Factory for fake EventLogRecord-like objects (lives in test scope).
    function New-FakeEvent {
        param(
            [string]$LogName = 'System',
            [string]$ProviderName = 'Service Control Manager',
            [int]$Id = 7034,
            [int]$Level = 2,
            [datetime]$TimeCreated = (Get-Date),
            [string]$Message = 'The Example service terminated unexpectedly.',
            [object[]]$Properties = @()
        )
        [pscustomobject]@{
            LogName = $LogName; ProviderName = $ProviderName; Id = $Id; Level = $Level
            TimeCreated = $TimeCreated; Message = $Message; Properties = $Properties
        }
    }
}

Describe 'Fix-action catalog' {
    It 'returns an ordered dictionary with several actions' {
        $info = & $script:m {
            $a = Get-DiagFixAction
            [pscustomobject]@{ IsOrdered = ($a -is [System.Collections.Specialized.OrderedDictionary]); Count = $a.Count }
        }
        $info.IsOrdered | Should -BeTrue
        $info.Count     | Should -BeGreaterThan 5
    }

    It 'every action exposes a runnable script block and required metadata' {
        $badCount = & $script:m {
            $bad = 0
            foreach ($key in (Get-DiagFixAction).Keys) {
                $fix = (Get-DiagFixAction)[$key]
                if ($fix.Id -ne $key -or [string]::IsNullOrEmpty($fix.Name) -or
                    ($fix.Action -isnot [scriptblock]) -or ($fix.RequiresAdmin -isnot [bool])) { $bad++ }
            }
            $bad
        }
        $badCount | Should -Be 0
    }
}

Describe 'Rule catalog integrity' {
    It 'has unique rule IDs' {
        $dupes = & $script:m {
            $rules = Get-DiagRule
            $rules.Count - ($rules.Id | Sort-Object -Unique).Count
        }
        $dupes | Should -Be 0
    }

    It 'every rule FixId maps to a real fix action' {
        $unresolved = & $script:m {
            $a = Get-DiagFixAction
            @(Get-DiagRule | Where-Object FixId | Where-Object { -not $a.Contains($_.FixId) }).Count
        }
        $unresolved | Should -Be 0
    }

    It 'every rule has a valid severity and a category' {
        $invalid = & $script:m {
            @(Get-DiagRule | Where-Object {
                $_.Severity -notin @('Critical', 'Error', 'Warning') -or [string]::IsNullOrEmpty($_.Category)
            }).Count
        }
        $invalid | Should -Be 0
    }
}

Describe 'Event-to-finding matching' {
    It 'creates a finding when events match a rule' {
        $events   = @( (New-FakeEvent -Id 7034), (New-FakeEvent -Id 7031) )
        $findings = @(& $script:m { param($e) Get-DiagFinding -Event $e -Rule (Get-DiagRule | Where-Object Id -eq 'SYS-SERVICE-CRASH') } $events)
        $findings.Count     | Should -Be 1
        $findings[0].RuleId | Should -Be 'SYS-SERVICE-CRASH'
        $findings[0].Count  | Should -Be 2
        $findings[0].HasFix | Should -BeTrue
        $findings[0].FixId  | Should -Be 'restart-service'
    }

    It 'ignores events from a different log or provider' {
        $events   = @( (New-FakeEvent -LogName 'Application' -Id 7034), (New-FakeEvent -ProviderName 'Some Other Source' -Id 7034) )
        $findings = @(& $script:m { param($e) Get-DiagFinding -Event $e -Rule (Get-DiagRule | Where-Object Id -eq 'SYS-SERVICE-CRASH') } $events)
        $findings.Count | Should -Be 0
    }

    It 'respects the MinCount threshold' {
        $two   = @(1..2 | ForEach-Object { New-FakeEvent -ProviderName 'Microsoft-Windows-DistributedCOM' -Id 10016 -Level 3 })
        $three = @(1..3 | ForEach-Object { New-FakeEvent -ProviderName 'Microsoft-Windows-DistributedCOM' -Id 10016 -Level 3 })
        $below = @(& $script:m { param($e) Get-DiagFinding -Event $e -Rule (Get-DiagRule | Where-Object Id -eq 'SYS-DCOM-10016') } $two)
        $met   = @(& $script:m { param($e) Get-DiagFinding -Event $e -Rule (Get-DiagRule | Where-Object Id -eq 'SYS-DCOM-10016') } $three)
        $below.Count | Should -Be 0
        $met.Count   | Should -Be 1
    }

    It 'sorts findings by severity (most severe first)' {
        $events = @(
            (New-FakeEvent -ProviderName 'Microsoft-Windows-DistributedCOM' -Id 10016 -Level 3)
            (New-FakeEvent -ProviderName 'Microsoft-Windows-DistributedCOM' -Id 10016 -Level 3)
            (New-FakeEvent -ProviderName 'Microsoft-Windows-DistributedCOM' -Id 10016 -Level 3)
            (New-FakeEvent -ProviderName 'disk' -Id 51 -Level 2)
        )
        $findings = @(& $script:m { param($e) Get-DiagFinding -Event $e -Rule (Get-DiagRule) } $events)
        $findings[0].Severity | Should -Be 'Critical'
    }
}

Describe 'HTML report generation' {
    It 'writes a self-contained HTML file with the findings' {
        $sys = [pscustomobject]@{
            ComputerName = 'TESTPC'; UserName = 'tester'; OSName = 'Windows Test'
            OSVersion = '10.0'; OSBuild = '99999'; Architecture = '64-bit'
            Manufacturer = 'x'; Model = 'y'; LastBoot = (Get-Date); UptimeText = '1d 2h 3m'
            IsAdmin = $false; PSVersion = '5.1'; ScanTime = (Get-Date)
        }
        $events   = @(New-FakeEvent -Id 7034)
        $findings = @(& $script:m { param($e) Get-DiagFinding -Event $e -Rule (Get-DiagRule | Where-Object Id -eq 'SYS-SERVICE-CRASH') } $events)

        $out = Join-Path ([System.IO.Path]::GetTempPath()) ("wdt_test_{0}.html" -f ([guid]::NewGuid()))
        try {
            $path = & $script:m { param($s, $f, $e, $p) Out-DiagHtmlReport -SystemInfo $s -Finding $f -Event $e -LogEntry @() -Path $p } $sys $findings $events $out
            Test-Path $path | Should -BeTrue
            $html = Get-Content $path -Raw
            $html | Should -Match 'Windows Diagnostic Report'
            $html | Should -Match 'Service crashed or failed to start'
            $html | Should -Match 'TESTPC'
        }
        finally {
            if (Test-Path $out) { Remove-Item $out -Force }
        }
    }
}

Describe 'Repair-WindowsProblem behaviour' {
    It 'reports an unknown -ApplyFix id without throwing' {
        { Repair-WindowsProblem -ApplyFix 'no-such-fix' -NoRestorePoint -Confirm:$false -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'does not apply a fix when -WhatIf is used' {
        # clean-temp does not require admin; -WhatIf must still prevent any action.
        { Repair-WindowsProblem -ApplyFix 'clean-temp' -WhatIf -NoRestorePoint } | Should -Not -Throw
    }

    It 'every fixable rule resolves to a real action (including new rules)' {
        $unresolved = & $script:m {
            $a = Get-DiagFixAction
            @(Get-DiagRule | Where-Object FixId | Where-Object { -not $a.Contains($_.FixId) }).Count
        }
        $unresolved | Should -Be 0
    }

    It 'maps the Group Policy rule to the gpupdate fix' {
        (Get-WindowsDiagnosticRule | Where-Object Id -eq 'SYS-GROUPPOLICY').FixId | Should -Be 'refresh-grouppolicy'
    }
}

Describe 'Public surface' {
    It 'exports the four public commands' {
        $cmds = (Get-Command -Module WindowsDiagnosticTool).Name
        $cmds | Should -Contain 'Invoke-WindowsDiagnostic'
        $cmds | Should -Contain 'Get-WindowsDiagnosticReport'
        $cmds | Should -Contain 'Repair-WindowsProblem'
        $cmds | Should -Contain 'Get-WindowsDiagnosticRule'
    }

    It 'Get-WindowsDiagnosticRule returns a fix name for fixable rules' {
        $rule = Get-WindowsDiagnosticRule | Where-Object HasFix | Select-Object -First 1
        $rule.FixName | Should -Not -BeNullOrEmpty
    }
}
