param(
    [Parameter(Mandatory)]
    [ValidateSet('arm64', 'x64')]
    [string]$Architecture,
    [string]$Version = '0.1.0.0',
    [string]$Publisher = 'CN=BG3HonorAssistant Development'
)

$ErrorActionPreference = 'Stop'
$runtimeIdentifier = "win-$Architecture"
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $windowsRoot 'artifacts'
$packageRoot = Join-Path $windowsRoot 'package'
$outputPath = Join-Path $artifactRoot "BG3HonorAssistant_${Version}_${Architecture}_unsigned.msix"
$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$temporaryRoot = Join-Path $temporaryBase (
    'BG3HonorAssistant-msix-' + [Guid]::NewGuid().ToString('N'))
$publishRoot = Join-Path $temporaryRoot 'publish'
$temporaryPackage = Join-Path $temporaryRoot 'package.msix'
$inspectionRoot = Join-Path $temporaryRoot 'inspection'
$buildToolsVersion = '10.0.28000.2270'
$buildToolsRoot = Join-Path $env:USERPROFILE ".nuget\packages\microsoft.windows.sdk.buildtools\$buildToolsVersion"
$toolArchitecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    'Arm64' { 'arm64' }
    'X64' { 'x64' }
    default {
        throw "MSIX packaging requires a native ARM64 or x64 Windows SDK tool host."
    }
}
$makeAppx = Get-ChildItem -LiteralPath $buildToolsRoot -Recurse -Filter 'makeappx.exe' |
    Where-Object {
        $_.FullName.EndsWith(
            "\$toolArchitecture\makeappx.exe",
            [StringComparison]::OrdinalIgnoreCase)
    } |
    Select-Object -First 1

if ($null -eq $makeAppx) {
    throw "Native $toolArchitecture MakeAppx.exe was not found. Restore the solution first."
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

function Get-PePayload {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 64) {
            return $null
        }

        $reader = [System.IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            return $null
        }

        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        if ($peOffset -gt ($stream.Length - 24)) {
            throw "Malformed PE header in $Path"
        }

        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            return $null
        }

        $machine = $reader.ReadUInt16()
        $stream.Position = $peOffset + 20
        $optionalHeaderSize = $reader.ReadUInt16()
        $optionalHeaderOffset = $peOffset + 24
        if (
            $optionalHeaderSize -lt 2 -or
            $optionalHeaderOffset + $optionalHeaderSize -gt $stream.Length
        ) {
            throw "Malformed optional PE header in $Path"
        }

        $stream.Position = $optionalHeaderOffset
        $optionalMagic = $reader.ReadUInt16()
        $dataDirectoryOffset = switch ($optionalMagic) {
            0x010B { 96 }
            0x020B { 112 }
            default { 0 }
        }
        $cliDirectoryOffset = $dataDirectoryOffset + (14 * 8)
        $isManaged = $false
        if (
            $dataDirectoryOffset -ne 0 -and
            $optionalHeaderSize -ge ($cliDirectoryOffset + 8)
        ) {
            $stream.Position = $optionalHeaderOffset + $cliDirectoryOffset
            $isManaged = $reader.ReadUInt32() -ne 0
        }

        [pscustomobject]@{
            Path = $Path
            Machine = $machine
            IsManaged = $isManaged
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-PePayloadArchitecture {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('arm64', 'x64')][string]$ExpectedArchitecture
    )

    $expectedMachine = if ($ExpectedArchitecture -eq 'arm64') { 0xAA64 } else { 0x8664 }
    $expectedMachineName = if ($ExpectedArchitecture -eq 'arm64') { 'ARM64' } else { 'AMD64' }
    $expectedPayloads = 0

    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File) {
        $payload = Get-PePayload -Path $file.FullName
        if ($null -eq $payload) {
            continue
        }

        if ($payload.Machine -eq 0xA641) {
            throw "ARM64EC payloads are not allowed: $($file.FullName)"
        }
        if ($payload.Machine -eq $expectedMachine) {
            $expectedPayloads++
            continue
        }
        if ($payload.IsManaged -and $payload.Machine -eq 0x014C) {
            # Architecture-neutral IL is allowed; native payloads never receive this exception.
            continue
        }

        $actualMachine = '0x{0:X4}' -f $payload.Machine
        throw (
            "Cross-architecture PE payload in $ExpectedArchitecture package: " +
            "$($file.FullName) has machine $actualMachine; expected $expectedMachineName.")
    }

    if ($expectedPayloads -eq 0) {
        throw "No $expectedMachineName PE payload was found under $Root."
    }

    $appExecutable = Get-PePayload -Path (Join-Path $Root 'BG3HonorAssistant.exe')
    if (
        $null -eq $appExecutable -or
        $appExecutable.Machine -ne $expectedMachine -or
        $appExecutable.IsManaged
    ) {
        throw "BG3HonorAssistant.exe is not a native $expectedMachineName app host."
    }
}

function Assert-PackageLayout {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('arm64', 'x64')][string]$ExpectedArchitecture
    )

    $manifestPath = Join-Path $Root 'AppxManifest.xml'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Package manifest was not found under $Root."
    }

    $manifest = [xml](Get-Content -Raw -LiteralPath $manifestPath)
    $manifestArchitecture = [string]$manifest.Package.Identity.ProcessorArchitecture
    if ($manifestArchitecture -ne $ExpectedArchitecture) {
        throw (
            "Package manifest architecture '$manifestArchitecture' does not match " +
            "'$ExpectedArchitecture'.")
    }
    if ($manifestArchitecture -in @('neutral', 'AnyCPU', 'MSIL')) {
        throw "Neutral or AnyCPU MSIX identities are not allowed."
    }

    Assert-PePayloadArchitecture -Root $Root -ExpectedArchitecture $ExpectedArchitecture
}

New-Item -ItemType Directory -Path $publishRoot -Force | Out-Null
try {
    & (Join-Path $PSScriptRoot 'build-release.ps1') `
        -Architecture $Architecture `
        -OutputPath $publishRoot

    New-Item -ItemType Directory -Path (Join-Path $publishRoot 'Assets') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $packageRoot 'Package.appxmanifest') `
        -Destination (Join-Path $publishRoot 'AppxManifest.xml')
    Copy-Item -LiteralPath (Join-Path $windowsRoot '..\Resources\AppIcon.png') `
        -Destination (Join-Path $publishRoot 'Assets\AppIcon.png')

    $manifestPath = Join-Path $publishRoot 'AppxManifest.xml'
    $manifest = [xml](Get-Content -Raw -LiteralPath $manifestPath)
    if (
        [string]$manifest.Package.Identity.ProcessorArchitecture -ne
        'ARCHITECTURE_PLACEHOLDER'
    ) {
        throw 'The source package manifest must use the architecture placeholder.'
    }
    $manifest.Package.Identity.Version = $Version
    $manifest.Package.Identity.Publisher = $Publisher
    $manifest.Package.Identity.ProcessorArchitecture = $Architecture
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

    Assert-PackageLayout -Root $publishRoot -ExpectedArchitecture $Architecture

    $packOutput = & $makeAppx.FullName pack /d $publishRoot /p $temporaryPackage /o 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "MakeAppx failed with exit code $LASTEXITCODE.`n$($packOutput -join [Environment]::NewLine)"
    }
    $packOutput | Select-Object -Last 5

    $unpackOutput = & $makeAppx.FullName unpack /p $temporaryPackage /d $inspectionRoot /o 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (
            "MakeAppx validation unpack failed with exit code $LASTEXITCODE.`n" +
            ($unpackOutput -join [Environment]::NewLine))
    }
    Assert-PackageLayout -Root $inspectionRoot -ExpectedArchitecture $Architecture

    Copy-Item -LiteralPath $temporaryPackage -Destination $outputPath -Force

    Write-Output "Validated $Architecture MSIX built from $runtimeIdentifier payloads."
    Write-Output $outputPath
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
