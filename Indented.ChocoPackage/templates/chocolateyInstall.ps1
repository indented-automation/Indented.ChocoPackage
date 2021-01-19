$packageParameters = Get-PackageParameters

$destinations = switch ($true) {
    { $packageParameters.Count -eq 0 -or $packageParameters.ContainsKey('CoreOnly') }    { 'PowerShell\Modules' }
    { $packageParameters.Count -eq 0 -or $packageParameters.ContainsKey('DesktopOnly') } { 'WindowsPowerShell\Modules' }
}

foreach ($destination in $destinations) {
    $psEditionPath = Join-Path -Path $env:PROGRAMFILES -ChildPath $destination

    if (-not (Test-Path $psEditionPath)) {
        New-Item -Path $psEditionPath -ItemType Directory
    }

    $modulePath = Join-Path -Path $psEditionPath -ChildPath '%MODULE_NAME%'

    if ($packageParameters.ContainsKey('Replace') -and (Test-Path $modulePath)) {
        Remove-Item -Path $modulePath -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -Path $modulePath) {
        $source = Join-Path -Path $PSScriptRoot -ChildPath '%MODULE_NAME%\*'
    } else {
        $source = Join-Path -Path $PSScriptRoot -ChildPath '%MODULE_NAME%'
    }
    Copy-Item -Path $source -Destination $modulePath -Recurse -Force

    Join-Path -Path $modulePath -ChildPath '%MODULE_VERSION%\chocolateyInstalled.txt' |
        New-Item -Path { $_ } -ItemType File
}
