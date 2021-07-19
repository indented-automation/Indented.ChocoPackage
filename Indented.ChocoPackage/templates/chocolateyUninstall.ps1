$destinations = @(
    'PowerShell\Modules'
    'WindowsPowerShell\Modules'
)

foreach ($destination in $destinations) {
    $modulePath = Join-Path $env:PROGRAMFILES -ChildPath $destination |
        Join-Path -ChildPath '%MODULE_NAME%'

    $versionedPath = Join-Path -Path $modulePath -ChildPath '%MODULE_VERSION%'
    if (Test-Path $versionedPath) {
        $installMarkerPath = $versionedPath
    } else {
        $installMarkerPath = $modulePath
    }

    if (Join-Path -Path $installMarkerPath -ChildPath 'chocolateyInstalled.txt' | Test-Path) {
        Remove-Item -Path $installMarkerPath -Recurse -Force
    }

    if (-not (Join-Path -Path $modulePath -ChildPath '*' | Test-Path) -and (Test-Path -Path $modulePath)) {
        Remove-Item -Path $modulePath
    }
}
