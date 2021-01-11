Describe PSScriptAnalyzer {
    BeforeDiscovery {
        $rules = Split-Path $PSScriptRoot -Parent |
            Get-ChildItem -File -Recurse -Include *.ps1 -Exclude *.tests.ps1 |
            ForEach-Object {
                Invoke-ScriptAnalyzer -Path $_.FullName
            } | ForEach-Object {
                @{
                    Rule = [PSCustomObject]@{
                        RuleName   = $_.RuleName
                        Message    = $_.Message -replace '(.{50,90}) ', "`n        `$1" -replace '^\n        '
                        ScriptName = $_.ScriptName
                        Line       = $_.Line
                        ScriptPath = $_.ScriptPath
                    }
                }
            }
    }

    It (
        @(
            '<rule.RuleName>'
            '        <rule.Message>'
            '    in <rule.ScriptName> line <rule.Line>'
        ) | Out-String
    ) -TestCases $rules {
        $rule.ScriptPath | Should -BeNullOrEmpty
    }
}
