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
                if ($_ -is [System.Management.Automation.PSModuleInfo] -or
                    $_ -is [Microsoft.PackageManagement.Packaging.SoftwareIdentity] -or
                    $_.PSTypeNames[0] -eq 'Microsoft.PowerShell.Commands.PSRepositoryItemInfo') {


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
        [switch]$Unversioned
    )

    begin {
        $Path = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

        try {
            $null = New-Item -Path $CacheDirectory -ItemType Directory
        } catch {
            $pscmdlet.ThrowTerminatingError($_)
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
                { $_ -is [System.Management.Automation.PSModuleInfo] } {
                    Write-Verbose ('Building {0} from PSModuleInfo' -f $InputObject.Name)

                    $dependencies = $InputObject.RequiredModules

                    $null = $psboundparameters.Remove('InputObject')
                    # Package dependencies as well
                    foreach ($dependency in $dependencies) {
                        Get-Module $dependency.Name -ListAvailable |
                            Where-Object Version -EQ $dependency.Version |
                            ConvertTo-ChocoPackage @psboundparameters
                    }

                    if ((Split-Path -Path $InputObject.ModuleBase -Leaf) -eq $InputObject.Version) {
                        $destination = New-Item (Join-Path -Path $toolsPath -ChildPath $InputObject.Name) -ItemType Directory
                    } else {
                        $destination = $toolsPath
                    }

                    $source = $InputObject.ModuleBase
                }
                { $_ -is [Microsoft.PackageManagement.Packaging.SoftwareIdentity] } {
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

                    if ((Split-Path $swidTagText.SoftwareIdentity.Meta.InstalledLocation -Leaf) -eq $InputObject.Version) {
                        $destination = New-Item (Join-Path $toolsPath $InputObject.Name) -ItemType Directory
                    } else {
                        $destination = $toolsPath
                    }

                    $source = $swidTagText.SoftwareIdentity.Meta.InstalledLocation
                }
                { $source -and $destination } {
                    if ($Unversioned) {
                        $source = Join-Path -Path $source -ChildPath '*'
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

                    $null = $psboundparameters.Remove('InputObject')
                    $params = @{
                        Name            = $InputObject.Name
                        RequiredVersion = $InputObject.Version
                        Source          = $InputObject.Repository
                        ProviderName    = 'PowerShellGet'
                        Path            = New-Item (Join-Path $CacheDirectory 'savedPackages') -ItemType Directory -Force
                    }
                    Save-Package @params | ConvertTo-ChocoPackage @psboundparameters

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

                if ($dependencies) {
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

                choco pack $nuspecPath --out=$Path
            }
        } catch {
            Write-Error -ErrorRecord $_
        } finally {
            Remove-Item $packagePath -Recurse -Force
        }
    }

    end {
        Remove-Item $CacheDirectory -Recurse -Force
    }
}
