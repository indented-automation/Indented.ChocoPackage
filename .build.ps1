task default @(
    'Clean'
    'Build'
    'Test'
)

task Clean {
    $path = Join-Path -Path $PSScriptRoot -ChildPath 'build'
    if (Test-Path $path) {
        Remove-Item $path -Recurse
    }
}

task Build {
    Build-Module -Path (Resolve-Path $PSScriptRoot\*\build.psd1)
}

task Test {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'build\*\*\*.psd1' |
        Get-Item |
        Where-Object { $_.BaseName -eq $_.Directory.Parent.Name }
    $rootModule = $modulePath -replace 'd1$', 'm1'

    $stubPath = Join-Path -Path $PSScriptRoot -ChildPath '*\tests\stub\*.psm1'
    if (Test-Path -Path $stubPath) {
        foreach ($module in $stubPath | Resolve-Path) {
            Import-Module -Name $module -Global
        }
    }

    Import-Module -Name $modulePath -Force -Global

    $configuration = @{
        Run          = @{
            Path = Join-Path -Path $PSScriptRoot -ChildPath '*\tests' | Resolve-Path
        }
        CodeCoverage = @{
            Enabled    = $true
            Path       = $rootModule
            OutputPath = Join-Path -Path $PSScriptRoot -ChildPath 'build\codecoverage.xml'
        }
        TestResult   = @{
            Enabled    = $true
            OutputPath = Join-Path -Path $PSScriptRoot -ChildPath 'build\nunit.xml'
        }
        Output       = @{
            Verbosity = 'Detailed'
        }
    }
    Invoke-Pester -Configuration $configuration
}
