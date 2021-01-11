param (
    [string[]]$TaskName = ('Clean', 'Build', 'Test')
)

function Clean {
    $path = Join-Path -Path $PSScriptRoot -ChildPath 'build'
    if (Test-Path $path) {
        Remove-Item $path -Recurse
    }
}

function Build {
    Write-Host (Resolve-Path $PSScriptRoot\*\build.psd1)

    Build-Module -Path (Resolve-Path $PSScriptRoot\*\build.psd1)
}

function Test {
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

    if ($env:APPVEYOR_JOB_ID) {
        $path = Join-Path -Path $PSScriptRoot -ChildPath 'build\nunit.xml'

        if (Test-Path $path) {
            $params = @{
                Uri    = 'https://ci.appveyor.com/api/testresults/nunit/{0}' -f $env:APPVEYOR_JOB_ID
                Method = 'POST'
                InFile = $path
            }
            Invoke-WebRequest @params
        }
    }
}

function Publish {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'build\*\*\*.psd1' |
        Get-Item |
        Where-Object { $_.BaseName -eq $_.Directory.Parent.Name }

    Publish-Module -Path $modulePath -NuGetApiKey $env:NuGetApiKey -Repository PSGallery -ErrorAction Stop
}

function InvokeTask {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$TaskName
    )

    begin {
        Write-Host ('Build {0}' -f $PSCommandPath) -ForegroundColor Green
    }

    process {
        $ErrorActionPreference = 'Stop'
        try {
            $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()

            Write-Host ('Task {0}' -f $TaskName) -ForegroundColor Cyan
            & "Script:$TaskName"
            Write-Host ('Done {0} {1}' -f $TaskName, $stopWatch.Elapsed) -ForegroundColor Cyan
        } catch {
            Write-Host ('Failed {0} {1}' -f $TaskName, $stopWatch.Elapsed) -ForegroundColor Red
            Write-Error -ErrorRecord $_ -ErrorAction Continue
            exit 1
        } finally {
            $stopWatch.Stop()
        }
    }
}

$TaskName | InvokeTask
