#Requires -RunAsAdministrator

Describe ConvertTo-ChocoPackage -Tag Integration {
    BeforeAll {
        $projectRoot = $PSScriptRoot -replace '\\tests.+' | Split-Path -Parent
        $moduleManifest = $projectRoot |
            Join-Path -ChildPath 'build\*\*\*.psd1' |
            Get-Item |
            Where-Object { $_.BaseName -eq $_.Directory.Parent.Name }
        Import-Module $moduleManifest -Force

        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 'Tls12'
            Invoke-WebRequest 'https://chocolatey.org/install.ps1' | Invoke-Expression
        }

        $desktopPath = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules\Indented.ChocoPackage\*'
        $corePath = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\Modules\Indented.ChocoPackage\*'

        Get-Module Indented.ChocoPackage | ConvertTo-ChocoPackage -Path $TestDrive
    }

    Context 'All PS versions' {
        It 'Installs a module in both Program Files\PowerShell and Program Files\WindowsPowerShell' {
            choco install Indented.ChocoPackage --source $TestDrive -y

            Join-Path -Path $desktopPath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeTrue
            Join-Path -Path $desktopPath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeTrue

            Join-Path -Path $corePath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeTrue
            Join-Path -Path $corePath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeTrue
        }

        It 'Uninstalls a module from both Program Files\PowerShell and Program Files\WindowsPowerShell' {
            choco uninstall Indented.ChocoPackage  -y

            Join-Path -Path $desktopPath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeFalse
            Join-Path -Path $desktopPath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeFalse

            Join-Path -Path $corePath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeFalse
            Join-Path -Path $corePath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeFalse
        }
    }

    Context 'Windows PowerShell only' {
        It 'Installs a module in Program Files\WindowsPowerShell' {
            choco install Indented.ChocoPackage --source $TestDrive -y --params "'/DesktopOnly'"

            Join-Path -Path $desktopPath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeTrue
            Join-Path -Path $desktopPath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeTrue

            Join-Path -Path $corePath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeFalse
            Join-Path -Path $corePath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeFalse
        }

        It 'Uninstalls a module from Program Files\WindowsPowerShell' {
            choco uninstall Indented.ChocoPackage -y

            Join-Path -Path $desktopPath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeFalse
            Join-Path -Path $desktopPath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeFalse

            Join-Path -Path $corePath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeFalse
            Join-Path -Path $corePath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeFalse
        }
    }

    Context 'PowerShell core only' {
        It 'Installs a module in Program Files\PowerShell' {
            choco install Indented.ChocoPackage --source $TestDrive  -y --params "'/CoreOnly'"

            Join-Path -Path $desktopPath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeFalse
            Join-Path -Path $desktopPath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeFalse

            Join-Path -Path $corePath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeTrue
            Join-Path -Path $corePath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeTrue
        }

        It 'Uninstalls a module from both Program Files\PowerShell' {
            choco uninstall Indented.ChocoPackage -y

            Join-Path -Path $desktopPath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeFalse
            Join-Path -Path $desktopPath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeFalse

            Join-Path -Path $corePath -ChildPath Indented.ChocoPackage.psd1 | Test-Path | Should -BeFalse
            Join-Path -Path $corePath -ChildPath chocolateyInstalled.txt | Test-Path | Should -BeFalse
        }
    }
}
