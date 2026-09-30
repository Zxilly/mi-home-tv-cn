param(
    [Parameter(Mandatory = $true)]
    [string]$InputXapk,

    [string]$OutputDir = (Join-Path $PSScriptRoot '..\dist'),

    [string]$Keystore = (Join-Path $env:USERPROFILE '.android\debug.keystore'),

    [string]$KeystorePassword = 'android',

    [string]$KeyPassword = 'android',

    [string]$AndroidSdk = $(
        if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
        elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME }
        else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    )
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$inputPath = (Resolve-Path -LiteralPath $InputXapk).Path
$keystorePath = (Resolve-Path -LiteralPath $Keystore).Path
$outputPath = [IO.Path]::GetFullPath($OutputDir)
$buildTools = Get-ChildItem (Join-Path $AndroidSdk 'build-tools') -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1

if (-not $buildTools) {
    throw "Android SDK Build Tools not found under $AndroidSdk"
}

foreach ($command in @('7z', 'apktool', 'java', 'python')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $command"
    }
}

$zipalign = Join-Path $buildTools.FullName 'zipalign.exe'
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$apkEditorVersion = '1.4.9'
$apkEditorHash = 'A9CD40DF818845456BE6D696DE6110C89EDF4B0A0580CB83438ED6B25A366E67'
$cacheDir = Join-Path $repoRoot '.cache'
$apkEditor = Join-Path $cacheDir "APKEditor-$apkEditorVersion.jar"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "mi-home-tv-cn-$([guid]::NewGuid())"
$sourceDir = Join-Path $tempRoot 'source'
$decodedDir = Join-Path $tempRoot 'decoded'
$signedDir = Join-Path $tempRoot 'signed'

New-Item -ItemType Directory -Path $outputPath, $cacheDir, $sourceDir, $signedDir -Force | Out-Null

try {
    if (-not (Test-Path -LiteralPath $apkEditor)) {
        $url = "https://github.com/REAndroid/APKEditor/releases/download/V$apkEditorVersion/APKEditor-$apkEditorVersion.jar"
        Invoke-WebRequest -Uri $url -OutFile $apkEditor
    }
    if ((Get-FileHash $apkEditor -Algorithm SHA256).Hash -ne $apkEditorHash) {
        throw 'APKEditor checksum mismatch.'
    }

    & 7z x -y "-o$sourceDir" $inputPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Failed to extract input XAPK.' }

    $baseApk = Join-Path $sourceDir 'com.xiaomi.smarthome.tv.global4.apk'
    if (-not (Test-Path -LiteralPath $baseApk)) {
        throw 'Input XAPK does not contain the expected global4 base APK.'
    }

    & apktool d -f -o $decodedDir $baseApk | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'apktool decode failed.' }

    & python (Join-Path $PSScriptRoot 'patch.py') $decodedDir | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Patch step failed.' }

    $rebuiltBase = Join-Path $tempRoot 'base-unsigned.apk'
    & apktool b $decodedDir -o $rebuiltBase | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'apktool build failed.' }

    $inputs = @(
        [pscustomobject]@{
            Name = 'com.xiaomi.smarthome.tv.global4.apk'
            Path = $rebuiltBase
        }
    )
    Get-ChildItem $sourceDir -Filter 'config.*.apk' | Sort-Object Name | ForEach-Object {
        $inputs += [pscustomobject]@{ Name = $_.Name; Path = $_.FullName }
    }
    if ($inputs.Count -lt 2) { throw 'No split APK files found.' }

    foreach ($item in $inputs) {
        $aligned = Join-Path $tempRoot ("aligned-" + $item.Name)
        $signed = Join-Path $signedDir $item.Name
        & $zipalign -P 16 -f 4 $item.Path $aligned
        if ($LASTEXITCODE -ne 0) { throw "zipalign failed: $($item.Name)" }
        & $apksigner sign `
            --ks $keystorePath `
            --ks-pass "pass:$KeystorePassword" `
            --key-pass "pass:$KeyPassword" `
            --v4-signing-enabled false `
            --out $signed `
            $aligned
        if ($LASTEXITCODE -ne 0) { throw "sign failed: $($item.Name)" }
        & $apksigner verify --verbose $signed | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "signature verify failed: $($item.Name)" }
    }

    Copy-Item -LiteralPath (Join-Path $sourceDir 'icon.png') -Destination $signedDir
    $manifest = Get-Content (Join-Path $sourceDir 'manifest.json') -Raw | ConvertFrom-Json
    $manifest.name = 'Mi Home TV global4 CN test'
    $manifest.version_name = '2.8.0.2-cn1'
    $manifest.total_size = (Get-ChildItem $signedDir -Filter '*.apk' | Measure-Object Length -Sum).Sum
    [IO.File]::WriteAllText(
        (Join-Path $signedDir 'manifest.json'),
        ($manifest | ConvertTo-Json -Depth 20),
        (New-Object Text.UTF8Encoding($false))
    )

    $xapk = Join-Path $outputPath 'MiHome-TV-global4-CN-2.8.0.2-cn1.xapk'
    if (Test-Path -LiteralPath $xapk) { Remove-Item -LiteralPath $xapk -Force }
    Push-Location $signedDir
    try {
        & 7z a -tzip $xapk '.\*.apk' '.\icon.png' '.\manifest.json' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'XAPK packaging failed.' }
    }
    finally {
        Pop-Location
    }

    $mergedUnsigned = Join-Path $tempRoot 'universal-unsigned.apk'
    & java -Xmx2g -jar $apkEditor m -i $xapk -o $mergedUnsigned -clean-meta -f | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'APKEditor merge failed.' }

    $mergedAligned = Join-Path $tempRoot 'universal-aligned.apk'
    $universal = Join-Path $outputPath 'MiHome-TV-global4-CN-2.8.0.2-cn1-universal.apk'
    & $zipalign -P 16 -f 4 $mergedUnsigned $mergedAligned
    if ($LASTEXITCODE -ne 0) { throw 'Universal APK zipalign failed.' }
    & $apksigner sign `
        --ks $keystorePath `
        --ks-pass "pass:$KeystorePassword" `
        --key-pass "pass:$KeyPassword" `
        --v4-signing-enabled false `
        --out $universal `
        $mergedAligned
    if ($LASTEXITCODE -ne 0) { throw 'Universal APK signing failed.' }
    & $apksigner verify --verbose --print-certs $universal | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Universal APK signature verification failed.' }
    & $zipalign -c -P 16 4 $universal
    if ($LASTEXITCODE -ne 0) { throw 'Universal APK alignment verification failed.' }

    $hashes = Get-FileHash $universal, $xapk -Algorithm SHA256
    $checksumFile = Join-Path $outputPath 'SHA256SUMS.txt'
    $hashes | ForEach-Object {
        "$($_.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_.Path))"
    } | Set-Content $checksumFile -Encoding ascii
    $hashes | Format-Table -AutoSize
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
