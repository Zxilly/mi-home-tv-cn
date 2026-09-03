param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [string]$Serial,

    [switch]$TclPackageInstallerWorkaround
)

$ErrorActionPreference = 'Stop'
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$adbArgs = @()
if ($Serial) { $adbArgs += @('-s', $Serial) }

try {
    if ($TclPackageInstallerWorkaround) {
        & adb @adbArgs shell pm disable-user --user 0 com.android.packageinstaller
    }

    $output = (& adb @adbArgs install -r $apk 2>&1 | Out-String)
    $output
    if ($LASTEXITCODE -ne 0 -or -not $output.Contains('Success')) {
        throw 'Installation failed. If the official global4 build is installed, uninstall it first.'
    }
}
finally {
    if ($TclPackageInstallerWorkaround) {
        & adb @adbArgs shell pm default-state --user 0 com.android.packageinstaller
    }
}

& adb @adbArgs shell am start -n `
    com.xiaomi.smarthome.tv.global4/com.xiaomi.smarthome.tv.ui.MainActivity
