$destinations = @(
    'PowerShell\Modules'
    'WindowsPowerShell\Modules'
)

foreach ($destination in $destinations) {
    $modulePath = Join-Path $env:PROGRAMFILES -ChildPath $destination |
        Join-Path -ChildPath '%MODULE_NAME%'
    $versionedPath = Join-Path -Path $modulePath -ChildPath '%MODULE_VERSION%'

    if (Join-Path -Path $versionedPath -ChildPath 'chocolateyInstalled.txt' | Test-Path) {
        Remove-Item -Path $versionedPath -Recurse -Force
    }

    if (-not (Join-Path -Path $modulePath -ChildPath '*' | Test-Path)) {
        Remove-Item -Path $modulePath
    }
}
