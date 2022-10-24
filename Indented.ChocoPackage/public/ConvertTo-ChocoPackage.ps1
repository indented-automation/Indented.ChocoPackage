function ConvertTo-ChocoPackage {
    <#
    .SYNOPSIS
        Convert a PowerShell module into a chocolatey package.

    .DESCRIPTION
        Convert a PowerShell module into a chocolatey package.

    .EXAMPLE
        Find-Module pester | ConvertTo-ChocoPackage

        Find the module pester on a PS repository and convert the module to a chocolatey package.

    .EXAMPLE
        Get-Module SqlServer -ListAvailable | ConvertTo-ChocoPackage

        Get the installed module SqlServer and convert the module to a chocolatey package.

    .EXAMPLE
        Find-Module VMware.PowerCli | ConvertTo-ChocoPackage

        Find the module VMware.PowerCli on a PS repository and convert the module, and all dependencies, to chocolatey packages.
    #>

    [CmdletBinding()]
    param (
        # The module to package.
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateScript(
            {
                $type = $_.GetType().Name
                if ($type -in 'PSModuleInfo', 'SoftwareIdentity' -or $_.PSTypeNames[0] -eq 'Microsoft.PowerShell.Commands.PSRepositoryItemInfo') {
                    $true
                } else {
                    throw 'InputObject must be a PSModuleInfo, SoftwareIdentity, or PSRepositoryItemInfo object.'
                }
            }
        )]
        [object]$InputObject,

        # Write the generated nupkg file to the specified folder.
        [string]$Path = '.',

        # A temporary directory used to stage the choco package content before packing.
        [string]$CacheDirectory = (Join-Path -Path $env:TEMP -ChildPath (New-Guid)),

        # When creating the install package, do not create a versioned directory (supports deployment of JEA role capabilities).
        [switch]$Unversioned,

        # Do not download and package dependencies. Dependencies are still written to the package metadata unless the NoPackageDependencies parameter is also used.
        [switch]$IgnoreDependencies,

        # Do not write dependencies into the package metadata. Any dependent content will need manually installing.
        [switch]$NoPackageDependencies
    )

    begin {
        $Path = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

        try {
            $null = New-Item -Path $CacheDirectory -ItemType Directory
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        $moduleBase = $MyInvocation.MyCommand.Module.ModuleBase
    }

    process {
        try {
            $ErrorActionPreference = 'Stop'

            $packagePath = Join-Path -Path $CacheDirectory -ChildPath $InputObject.Name.ToLower()
            $toolsPath = Join-Path -Path $packagePath -ChildPath 'tools' | New-Item -Path { $_ } -ItemType Directory

            $source = $destination = $null
            switch ($InputObject) {
                { $_.GetType().Name -eq 'PSModuleInfo' } {
                    Write-Verbose ('Building {0} from PSModuleInfo' -f $InputObject.Name)

                    $dependencies = $InputObject.RequiredModules

                    $null = $PSBoundParameters.Remove('InputObject')
                    if (-not $IgnoreDependencies) {
                        # Package dependencies as well
                        foreach ($dependency in $dependencies) {
                            Get-Module $dependency.Name -ListAvailable |
                                Where-Object Version -EQ $dependency.Version |
                                ConvertTo-ChocoPackage @PSBoundParameters
                        }
                    }

                    $installLocation = $InputObject.ModuleBase
                }
                { $_.GetType().Name -eq 'SoftwareIdentity' } {
                    Write-Verbose ('Building {0} from SoftwareIdentity' -f $InputObject.Name)

                    $dependencies = $InputObject.Dependencies | Select-Object -Property @(
                        @{ Name = 'Name'; Expression = { $_ -replace 'powershellget:|/.+$' } }
                        @{ Name = 'Version'; Expression = { $_ -replace '^.+?/|#.+$' } }
                    )

                    [Xml]$swidTagText = $InputObject.SwidTagText

                    $InputObject = [PSCustomObject]@{
                        Name        = $InputObject.Name
                        Version     = $InputObject.Version
                        Author      = $InputObject.Entities.Where{ $_.Role -eq 'author' }.Name
                        Copyright   = $swidTagText.SoftwareIdentity.Meta.copyright
                        Description = $swidTagText.SoftwareIdentity.Meta.summary
                    }

                    $installLocation = $swidTagText.SoftwareIdentity.Meta.InstalledLocation
                }
                { $installLocation } {
                    $source = $installLocation

                    if ((Split-Path $installLocation -Leaf) -eq $InputObject.Version) {
                        $destination = New-Item -Path (Join-Path -Path $toolsPath -ChildPath $InputObject.Name) -ItemType Directory
                        if ($Unversioned) {
                            # Source will be 1.2.3\*, destination will be tools\ModuleName
                            $source = Join-Path -Path $source -ChildPath '*'
                        }
                    } else {
                        if ($Unversioned) {
                            # Source will be ModuleName, destination will be tools
                            $destination = $toolsPath
                        } else {
                            # Source will be ModuleName\*, destination will be tools\ModuleName\1.2.3
                            $source = Join-Path -Path $source -ChildPath '*'
                            $destination = [System.IO.Path]::Combine(
                                $toolsPath,
                                $InputObject.Name,
                                $InputObject.Version
                            ) | New-Item -Path { $_ } -ItemType Directory
                        }
                    }

                    Copy-Item -Path $source -Destination $destination -Recurse

                    break
                }
                { $_.PSTypeNames[0] -eq 'Microsoft.PowerShell.Commands.PSRepositoryItemInfo' } {
                    Write-Verbose ('Building {0} from PSRepositoryItemInfo' -f $InputObject.Name)

                    $dependencies = $InputObject.Dependencies | Select-Object -Property @(
                        @{ Name = 'Name'; Expression = { $_['Name'] } }
                        @{ Name = 'Version'; Expression = { $_['MinimumVersion'] } }
                    )

                    $null = $PSBoundParameters.Remove('InputObject')
                    $params = @{
                        Name            = $InputObject.Name
                        RequiredVersion = $InputObject.Version
                        Source          = $InputObject.Repository
                        ProviderName    = 'PowerShellGet'
                        Path            = New-Item (Join-Path -Path $CacheDirectory -ChildPath 'savedPackages') -ItemType Directory -Force
                        Force           = $true
                    }
                    Save-Package @params | ConvertTo-ChocoPackage @PSBoundParameters

                    # The current module will be last in the chain. Prevent packaging of this iteration.
                    $InputObject = $null

                    break
                }
            }

            if ($InputObject) {
                foreach ($stage in 'Install', 'Uninstall') {
                    $name = 'chocolatey{0}.ps1' -f $stage
                    $content = Join-Path -Path $moduleBase -ChildPath 'templates' |
                        Join-Path -ChildPath $name |
                        Get-Content -Path { $_ } -Raw
                    $content -replace '%MODULE_NAME%', $InputObject.Name -replace '%MODULE_VERSION%', $InputObject.Version |
                        Set-Content -Path (Join-Path -Path $toolsPath -ChildPath $name)
                }

                [xml]$nuspec = Join-Path -Path $moduleBase -ChildPath 'templates\nuspec.xml' |
                    Get-Content -Path { $_ } -Raw
                $metadata = $nuspec.package.metadata
                $metadata.version = $InputObject.Version -as [string]
                $metadata.title = $metadata.id = $InputObject.Name
                $metadata.authors = $InputObject.Author
                $metadata.copyright = $InputObject.Copyright
                $metadata.Description = $InputObject.Description

                if (-not $NoPackageDependencies -and $dependencies) {
                    $fragment = [System.Text.StringBuilder]::new('<dependencies>')

                    $null = foreach ($dependency in $dependencies) {
                        $fragment.AppendFormat('<dependency id="{0}"', $dependency.Name)
                        if ($dependency.Version) {
                            $fragment.AppendFormat(' version="{0}"', $dependency.Version)
                        }
                        $fragment.Append(' />').AppendLine()
                    }

                    $null = $fragment.AppendLine('</dependencies>')

                    $xmlFragment = $nuspec.CreateDocumentFragment()
                    $xmlFragment.InnerXml = $fragment.ToString()

                    $null = $metadata.AppendChild($xmlFragment)
                }

                $nuspecPath = Join-Path -Path $packagePath -ChildPath ('{0}.nuspec' -f $InputObject.Name)
                $nuspec.Save($nuspecPath)

                Write-Verbose ('Building {0} in {1}' -f $nuspecPath, $Path)

                choco pack $nuspecPath --out=$Path
            }
        } catch {
            $PSCmdlet.WriteError($_)
        } finally {
            Remove-Item $packagePath -Recurse -Force
        }
    }

    end {
        Remove-Item $CacheDirectory -Recurse -Force
    }
}
