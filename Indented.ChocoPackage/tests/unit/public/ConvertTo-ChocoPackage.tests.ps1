Describe ConvertTo-ChocoPackage -Tag Unit {
    BeforeAll {
        $projectRoot = $PSScriptRoot -replace '\\tests.+' | Split-Path -Parent
        $moduleManifest = $projectRoot |
            Join-Path -ChildPath 'build\*\*\*.psd1' |
            Get-Item |
            Where-Object { $_.BaseName -eq $_.Directory.Parent.Name }
        Import-Module $moduleManifest -Force

        if (-not (Get-Module Configuration -ListAvailable)) {
            Install-Module Configuration
        }
    }

    Context 'Pipeline support' {
        It 'When an imported module is passed from Get-Module, creates a nupkg' {
            Get-Module Pester | ConvertTo-ChocoPackage -Path $TestDrive

            Join-Path -Path $TestDrive -ChildPath 'Pester.*.nupkg' | Should -Exist
        }

        It 'When a module is passed from Get-Module -ListAvailable, creates a nupkg' {
            Get-Module Configuration -ListAvailable | ConvertTo-ChocoPackage -Path $TestDrive

            Join-Path -Path $TestDrive -ChildPath 'Configuration.*.nupkg' | Should -Exist
        }

        It 'When a module is passed from Find-Module, downloads content and creates a nupkg' {
            Find-Module Indented.Net.IP | ConvertTo-ChocoPackage -Path $TestDrive

            Join-Path -Path $TestDrive -ChildPath 'Indented.Net.IP.*.nupkg' | Should -Exist
        }

        It 'When a module is passed from Find-Module, and the module has dependencies, downloads module and dependencies' {
            Find-Module PSModuleDevelopment | ConvertTo-ChocoPackage -Path $TestDrive

            Join-Path -Path $TestDrive -ChildPath 'PSModuleDevelopment.*.nupkg' | Should -Exist
            Join-Path -Path $TestDrive -ChildPath 'PSFramework.*.nupkg' | Should -Exist
        }
    }

    Context 'Package content validation' {
        BeforeAll {
            function Get-ZipFileEntry {
                [CmdletBinding()]
                param (
                    [string]$Path
                )

                try {
                    $stream = [System.IO.File]::OpenRead($Path)
                    $zipArchive = [System.IO.Compression.ZipArchive]::new($stream)
                    $zipArchive.Entries.FullName
                } catch {
                    Write-Warning $_.Exception.Message
                } finally {
                    if ($zipArchive) {
                        $zipArchive.Dispose()
                    }
                    if ($stream) {
                        $stream.Dispose()
                    }
                }
            }

            $modules = @(
                @{ Name = 'VersionedModule';   Path = 'VersionedModule\1.0.0' }
                @{ Name = 'UnversionedModule'; Path = 'UnversionedModule' }
            )
            foreach ($module in $modules) {
                $modulePath = New-Item (Join-Path -Path $TestDrive -ChildPath $module['Path']) -ItemType Directory
                $rootModule = New-Item -Path $modulePath.FullName -Name ('{0}.psm1' -f $module['Name']) -ItemType File
                Set-Content -Path $rootModule.FullName -Value 'function Write-Hello { "hello world" }'

                $manifest = @{
                    Path          = Join-Path -Path $modulePath.FullName -ChildPath ('{0}.psd1' -f $module['Name'])
                    ModuleVersion = '1.0.0'
                    RootModule    = $rootModule.Name
                    Description   = 'Some module'
                }
                New-ModuleManifest @manifest

                Import-Module $manifest['Path'] -Force
            }
        }

        AfterAll {
            Remove-Module VersionedModule, UnversionedModule
        }

        It 'When the source module is versioned, and the packaged module should be versioned' {
            Get-Module 'VersionedModule' | ConvertTo-ChocoPackage -Path $TestDrive
            $entries = Get-ZipFileEntry -Path (Join-Path -Path $TestDrive -ChildPath 'VersionedModule.1.0.0.nupkg')

            $entries | Should -Contain 'tools/chocolateyInstall.ps1'
            $entries | Should -Contain 'tools/chocolateyUninstall.ps1'
            $entries | Should -Contain 'tools/VersionedModule/1.0.0/VersionedModule.psm1'
        }

        It 'When the source module is versioned, and the packaged module should not be versioned' {
            Get-Module 'VersionedModule' | ConvertTo-ChocoPackage -Path $TestDrive -Unversioned
            $entries = Get-ZipFileEntry -Path (Join-Path -Path $TestDrive -ChildPath 'VersionedModule.1.0.0.nupkg')

            $entries | Should -Contain 'tools/chocolateyInstall.ps1'
            $entries | Should -Contain 'tools/chocolateyUninstall.ps1'
            $entries | Should -Contain 'tools/VersionedModule/VersionedModule.psm1'
        }

        It 'When the source module is not versioned, and the packaged module should be versioned' {
            Get-Module 'UnversionedModule' | ConvertTo-ChocoPackage -Path $TestDrive
            $entries = Get-ZipFileEntry -Path (Join-Path -Path $TestDrive -ChildPath 'UnversionedModule.1.0.0.nupkg')

            $entries | Should -Contain 'tools/chocolateyInstall.ps1'
            $entries | Should -Contain 'tools/chocolateyUninstall.ps1'
            $entries | Should -Contain 'tools/UnversionedModule/1.0.0/UnversionedModule.psm1'
        }

        It 'When the source module is not versioned, and the packaged module should not be versioned' {
            Get-Module 'UnversionedModule' | ConvertTo-ChocoPackage -Path $TestDrive -Unversioned
            $entries = Get-ZipFileEntry -Path (Join-Path -Path $TestDrive -ChildPath 'UnversionedModule.1.0.0.nupkg')

            $entries | Should -Contain 'tools/chocolateyInstall.ps1'
            $entries | Should -Contain 'tools/chocolateyUninstall.ps1'
            $entries | Should -Contain 'tools/UnversionedModule/UnversionedModule.psm1'
        }
    }
}
