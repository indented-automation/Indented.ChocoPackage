$packageParameters = Get-PackageParameters

$destinations = switch ($true) {
    { $packageParameters.Count -eq 0 -or $packageParameters.ContainsKey('CoreOnly') }    { 'PowerShell\Modules' }
    { $packageParameters.Count -eq 0 -or $packageParameters.ContainsKey('DesktopOnly') } { 'WindowsPowerShell\Modules' }
}

foreach ($destination in $destinations) {
    $psEditionPath = Join-Path -Path $env:PROGRAMFILES -ChildPath $destination
    if (Test-Path -Path $psEditionPath) {
        $modulePath = Join-Path -Path $psEditionPath -ChildPath '%MODULE_NAME%'

        if (Test-Path -Path $modulePath) {
            $source = Join-Path -Path $PSScriptRoot -ChildPath '%MODULE_NAME%\*'
        } else {
            $source = Join-Path -Path $PSScriptRoot -ChildPath '%MODULE_NAME%'
        }
        Copy-Item -Path $source -Destination $modulePath -Recurse -Force

        Join-Path -Path $modulePath -ChildPath '%MODULE_VERSION%\chocolateyInstalled.txt' |
            New-Item -Path { $_ } -ItemType File
    }
}
