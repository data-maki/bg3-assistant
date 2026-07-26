param(
    [Parameter(Mandatory)]
    [ValidateSet('arm64', 'x64')]
    [string]$Architecture,
    [Parameter(Mandatory)]
    [string]$PublishPath,
    [string]$PackagePath,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
$expectedMachine = @{
    arm64 = [UInt16]0xAA64
    x64 = [UInt16]0x8664
}[$Architecture]
$expectedRuntimeIdentifier = "win-$Architecture"
$resolvedPublishPath = (Resolve-Path -LiteralPath $PublishPath).Path

function Get-PeMachine {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file: $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Invalid PE signature: $Path"
        }
        return $reader.ReadUInt16()
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Assert-PeMachine {
    param([Parameter(Mandatory)][string]$Path)

    $machine = Get-PeMachine -Path $Path
    if ($machine -ne $expectedMachine) {
        throw (
            "PE architecture mismatch for '$Path': expected 0x{0:X4} ($Architecture), " +
            "found 0x{1:X4}."
        ) -f $expectedMachine, $machine
    }
}

function Assert-PublishLayout {
    param([Parameter(Mandatory)][string]$Root)

    $appHost = Join-Path $Root 'BG3HonorAssistant.exe'
    $depsPath = Join-Path $Root 'BG3HonorAssistant.deps.json'
    if (-not (Test-Path -LiteralPath $appHost)) {
        throw "Published app host is missing: $appHost"
    }
    if (-not (Test-Path -LiteralPath $depsPath)) {
        throw "Published dependency graph is missing: $depsPath"
    }

    Assert-PeMachine -Path $appHost
    $deps = Get-Content -Raw -LiteralPath $depsPath | ConvertFrom-Json
    if ($deps.runtimeTarget.name -notlike "*/$expectedRuntimeIdentifier") {
        throw (
            "Dependency runtime target '$($deps.runtimeTarget.name)' does not identify " +
            "'$expectedRuntimeIdentifier'."
        )
    }

    $nativePayloadNames = @(
        'coreclr.dll',
        'createdump.exe',
        'e_sqlite3.dll',
        'hostfxr.dll',
        'hostpolicy.dll',
        'mscordaccore.dll',
        'mscordbi.dll',
        'mscorrc.dll',
        'PresentationNative_cor3.dll',
        'vcruntime140_cor3.dll',
        'wpfgfx_cor3.dll'
    )
    foreach ($name in $nativePayloadNames) {
        Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $name |
            ForEach-Object { Assert-PeMachine -Path $_.FullName }
    }
}

Assert-PublishLayout -Root $resolvedPublishPath

$resolvedPackagePath = $null
if (-not [string]::IsNullOrWhiteSpace($PackagePath)) {
    $resolvedPackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'BG3HonorAssistant-inspect-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($resolvedPackagePath, $temporaryRoot)
        $manifestPath = Join-Path $temporaryRoot 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            throw "MSIX manifest is missing from '$resolvedPackagePath'."
        }
        $manifest = [xml](Get-Content -Raw -LiteralPath $manifestPath)
        if ($manifest.Package.Identity.ProcessorArchitecture -ne $Architecture) {
            throw (
                "MSIX processor architecture '$($manifest.Package.Identity.ProcessorArchitecture)' " +
                "does not match '$Architecture'."
            )
        }
        Assert-PublishLayout -Root $temporaryRoot
    }
    finally {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

$result = [ordered]@{
    targetArchitecture = $Architecture
    runtimeIdentifier = $expectedRuntimeIdentifier
    expectedPeMachine = ('0x{0:X4}' -f $expectedMachine)
    osArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    processArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    publishPath = $resolvedPublishPath
    packagePath = $resolvedPackagePath
    result = 'pass'
}
$json = $result | ConvertTo-Json
if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) {
    $evidenceDirectory = Split-Path -Parent $EvidencePath
    if (-not [string]::IsNullOrWhiteSpace($evidenceDirectory)) {
        New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    }
    Set-Content -LiteralPath $EvidencePath -Value $json -Encoding utf8
}
$json
