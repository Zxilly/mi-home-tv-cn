# Run with either powershell.exe (Windows PowerShell 5.1) or pwsh.
$ErrorActionPreference = 'Stop'
$buildScript = Join-Path $PSScriptRoot '..\build.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $buildScript, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) { throw ($parseErrors | Out-String) }

# Execute only the production manifest writer, without downloading, rebuilding,
# signing, or installing an APK. AST extraction also checks 5.1 parser support.
$writers = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Static -and $node.Member.Value -eq 'WriteAllText'
}, $true))
if ($writers.Count -ne 1) { throw 'Expected exactly one manifest WriteAllText call.' }
$writeManifest = [scriptblock]::Create($writers[0].Extent.Text)
$signedDir = Join-Path ([IO.Path]::GetTempPath()) ("manifest [test] $([guid]::NewGuid())")
New-Item -ItemType Directory -Path $signedDir | Out-Null

try {
    $manifest = [pscustomobject]@{
        name = "Mi Home $([char]0x4e2d)$([char]0x6587)"
        version_name = '2.8.0.2-cn1'
        total_size = 123
        split_apks = @([pscustomobject]@{ id = 'config'; file = 'config.apk' })
    }
    $path = Join-Path $signedDir 'manifest.json'
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    foreach ($version in @('2.8.0.2-cn1', '1')) {
        $manifest.version_name = $version
        & $writeManifest
        $bytes = [IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
            throw 'The manifest contains a UTF-8 BOM.'
        }
        $json = $strictUtf8.GetString($bytes)
        if ($json -cne ($manifest | ConvertTo-Json -Depth 20)) {
            throw 'The manifest did not preserve the serialized UTF-8 JSON.'
        }
        $decoded = $json | ConvertFrom-Json
        if ($decoded.name -cne $manifest.name -or $decoded.version_name -cne $version -or
            $decoded.split_apks[0].file -cne 'config.apk') {
            throw 'The manifest failed to round-trip.'
        }
    }
    Write-Host "Manifest encoding tests passed on PowerShell $($PSVersionTable.PSVersion)."
}
finally {
    Remove-Item -LiteralPath $signedDir -Recurse -Force
}
