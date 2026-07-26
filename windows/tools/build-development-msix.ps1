param(
    [string]$Version = '0.1.0.0',
    [string]$Publisher = 'CN=BG3HonorAssistant Development'
)

$ErrorActionPreference = 'Stop'
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $windowsRoot 'artifacts'
$packageRoot = Join-Path $windowsRoot 'package'
$outputPath = Join-Path $artifactRoot "BG3HonorAssistant_${Version}_x64_unsigned.msix"
$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$temporaryRoot = Join-Path $temporaryBase (
    'BG3HonorAssistant-msix-' + [Guid]::NewGuid().ToString('N'))
$publishRoot = Join-Path $temporaryRoot 'publish'
$temporaryPackage = Join-Path $temporaryRoot 'package.msix'
$buildToolsVersion = '10.0.28000.2270'
$buildToolsRoot = Join-Path $env:USERPROFILE ".nuget\packages\microsoft.windows.sdk.buildtools\$buildToolsVersion"
$makeAppx = Get-ChildItem -LiteralPath $buildToolsRoot -Recurse -Filter 'makeappx.exe' |
    Where-Object { $_.FullName -match '\\x64\\makeappx\.exe$' } |
    Select-Object -First 1

if ($null -eq $makeAppx) {
    throw "MakeAppx.exe was not found. Restore the solution first."
}

$resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
$resolvedPublishRoot = [System.IO.Path]::GetFullPath($publishRoot)
if (
    -not $resolvedTemporaryRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -or
    $resolvedTemporaryRoot -eq $temporaryBase -or
    -not $resolvedPublishRoot.StartsWith($resolvedTemporaryRoot, [StringComparison]::OrdinalIgnoreCase)
) {
    throw 'Temporary package layout escaped the operating-system temporary directory.'
}

New-Item -ItemType Directory -Path $publishRoot -Force | Out-Null
try {
    & (Join-Path $PSScriptRoot 'build-release.ps1') -OutputPath $publishRoot

    New-Item -ItemType Directory -Path (Join-Path $publishRoot 'Assets') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $packageRoot 'Package.appxmanifest') `
        -Destination (Join-Path $publishRoot 'AppxManifest.xml')
    Copy-Item -LiteralPath (Join-Path $windowsRoot '..\Resources\AppIcon.png') `
        -Destination (Join-Path $publishRoot 'Assets\AppIcon.png')

    $manifestPath = Join-Path $publishRoot 'AppxManifest.xml'
    $manifest = [xml](Get-Content -Raw -LiteralPath $manifestPath)
    $manifest.Package.Identity.Version = $Version
    $manifest.Package.Identity.Publisher = $Publisher
    $manifest.Save($manifestPath)

    $debugPayloads = Get-ChildItem -LiteralPath $publishRoot -Recurse -File -Filter '*.pdb'
    foreach ($debugPayload in $debugPayloads) {
        $resolvedDebugPayload = [System.IO.Path]::GetFullPath($debugPayload.FullName)
        if (-not $resolvedDebugPayload.StartsWith($resolvedPublishRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Debug payload escaped the publish layout: $resolvedDebugPayload"
        }
        Remove-Item -LiteralPath $resolvedDebugPayload -Force
    }
    $createdump = Join-Path $publishRoot 'createdump.exe'
    if (Test-Path -LiteralPath $createdump) {
        Remove-Item -LiteralPath $createdump -Force
    }

    $packOutput = & $makeAppx.FullName pack /d $publishRoot /p $temporaryPackage /o 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "MakeAppx failed with exit code $LASTEXITCODE.`n$($packOutput -join [Environment]::NewLine)"
    }
    $packOutput | Select-Object -Last 5
    Copy-Item -LiteralPath $temporaryPackage -Destination $outputPath -Force

    Write-Output $outputPath
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
