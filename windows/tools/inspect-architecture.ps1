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

function Get-PeClassification {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64) {
            throw "Truncated PE file: $Path"
        }
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file: $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        if ($peOffset -gt $stream.Length - 24) {
            throw "PE header is outside '$Path'."
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Invalid PE signature: $Path"
        }
        $machine = $reader.ReadUInt16()
        $sectionCount = $reader.ReadUInt16()
        $stream.Position = $peOffset + 20
        $optionalHeaderSize = $reader.ReadUInt16()
        $optionalHeaderOffset = $peOffset + 24
        if ($optionalHeaderSize -lt 96 -or
            $optionalHeaderOffset + $optionalHeaderSize -gt $stream.Length) {
            throw "Invalid optional PE header in '$Path'."
        }

        $stream.Position = $optionalHeaderOffset
        $optionalMagic = $reader.ReadUInt16()
        $dataDirectoryOffset = switch ($optionalMagic) {
            0x010B { 96 }
            0x020B { 112 }
            default { throw "Unknown optional PE magic 0x{0:X4} in '$Path'." -f $optionalMagic }
        }
        $numberOfDirectoriesOffset = $dataDirectoryOffset - 4
        if ($optionalHeaderSize -lt $dataDirectoryOffset) {
            throw "Truncated PE data directories in '$Path'."
        }
        $stream.Position = $optionalHeaderOffset + $numberOfDirectoriesOffset
        $numberOfDirectories = $reader.ReadUInt32()
        $cliRva = [UInt32]0
        if ($numberOfDirectories -gt 14 -and
            $optionalHeaderSize -ge $dataDirectoryOffset + (15 * 8)) {
            $stream.Position = $optionalHeaderOffset + $dataDirectoryOffset + (14 * 8)
            $cliRva = $reader.ReadUInt32()
            $cliSize = $reader.ReadUInt32()
            if (($cliRva -eq 0) -ne ($cliSize -eq 0)) {
                throw "Malformed CLI data directory in '$Path'."
            }
        }

        $corFlags = [UInt32]0
        $hasManagedMetadata = $false
        if ($cliRva -ne 0) {
            $sectionTableOffset = $optionalHeaderOffset + $optionalHeaderSize
            if ($sectionTableOffset + ($sectionCount * 40) -gt $stream.Length) {
                throw "Truncated PE section table in '$Path'."
            }
            $cliFileOffset = $null
            for ($section = 0; $section -lt $sectionCount; $section++) {
                $stream.Position = $sectionTableOffset + ($section * 40) + 8
                $virtualSize = $reader.ReadUInt32()
                $virtualAddress = $reader.ReadUInt32()
                $rawSize = $reader.ReadUInt32()
                $rawPointer = $reader.ReadUInt32()
                $mappedSize = [Math]::Max($virtualSize, $rawSize)
                if ($cliRva -ge $virtualAddress -and
                    $cliRva -lt $virtualAddress + $mappedSize) {
                    $cliFileOffset = $rawPointer + ($cliRva - $virtualAddress)
                    break
                }
            }
            if ($null -eq $cliFileOffset -or $cliFileOffset + 20 -gt $stream.Length) {
                throw "CLI header is outside PE sections in '$Path'."
            }
            $stream.Position = $cliFileOffset
            $cliHeaderSize = $reader.ReadUInt32()
            if ($cliHeaderSize -lt 0x48) {
                throw "Truncated CLI header in '$Path'."
            }
            $stream.Position = $cliFileOffset + 8
            $metadataRva = $reader.ReadUInt32()
            $metadataSize = $reader.ReadUInt32()
            $corFlags = $reader.ReadUInt32()
            $hasManagedMetadata = $metadataRva -ne 0 -and $metadataSize -ne 0
            if (-not $hasManagedMetadata) {
                throw "CLI image lacks managed metadata in '$Path'."
            }
        }

        return [pscustomobject]@{
            Machine = $machine
            HasManagedMetadata = $hasManagedMetadata
            CorFlags = $corFlags
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Assert-PeArchitecture {
    param([Parameter(Mandatory)][string]$Path)

    $pe = Get-PeClassification -Path $Path
    if ($pe.Machine -eq $expectedMachine) {
        return 'target'
    }

    $i386Machine = [UInt16]0x014C
    $ilOnly = 0x00000001
    $requires32Bit = 0x00000002
    $prefers32Bit = 0x00020000
    if ($pe.Machine -eq $i386Machine -and
        $pe.HasManagedMetadata -and
        ($pe.CorFlags -band $ilOnly) -ne 0 -and
        ($pe.CorFlags -band ($requires32Bit -bor $prefers32Bit)) -eq 0) {
        return 'neutral-managed'
    }

    if ($pe.Machine -eq $i386Machine) {
        throw (
            "32-bit or native x86 PE is forbidden in '$Path': machine=0x{0:X4}, " +
            "managed={1}, CorFlags=0x{2:X8}."
        ) -f $pe.Machine, $pe.HasManagedMetadata, $pe.CorFlags
    }

    throw (
        "PE architecture mismatch for '$Path': expected 0x{0:X4} ($Architecture) " +
        "or verifiable neutral managed IL, found 0x{1:X4}."
    ) -f $expectedMachine, $pe.Machine
}

function Assert-PublishLayout {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$AllowMissingCreatedump
    )

    $appHost = Join-Path $Root 'BG3HonorAssistant.exe'
    $depsPath = Join-Path $Root 'BG3HonorAssistant.deps.json'
    if (-not (Test-Path -LiteralPath $appHost)) {
        throw "Published app host is missing: $appHost"
    }
    if (-not (Test-Path -LiteralPath $depsPath)) {
        throw "Published dependency graph is missing: $depsPath"
    }
    if ((Assert-PeArchitecture -Path $appHost) -ne 'target') {
        throw "Published app host must be a native $Architecture PE: $appHost"
    }

    $deps = Get-Content -Raw -LiteralPath $depsPath | ConvertFrom-Json
    $expectedDepsTarget = "$($deps.runtimeTarget.name -replace '/[^/]+$', '')/$expectedRuntimeIdentifier"
    if ($deps.runtimeTarget.name -ne $expectedDepsTarget) {
        throw (
            "Dependency runtime target '$($deps.runtimeTarget.name)' does not exactly " +
            "identify '$expectedRuntimeIdentifier'."
        )
    }

    $allFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File)
    $filesByName = @{}
    $targetPeCount = 0
    $neutralManagedPeCount = 0
    foreach ($file in $allFiles) {
        $filesByName[$file.Name.ToLowerInvariant()] = $true
        $relativePath = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        if ($relativePath -match '(?i)(^|[\\/])win-(?<arch>arm64|x64|x86)([\\/]|$)' -and
            $Matches.arch -ne $Architecture) {
            throw "Opposite or unsupported RID path '$relativePath' is present in $Architecture output."
        }

        $stream = [System.IO.File]::OpenRead($file.FullName)
        try {
            $first = $stream.ReadByte()
            $second = $stream.ReadByte()
        }
        finally {
            $stream.Dispose()
        }
        $hasMzSignature = $first -eq 0x4D -and $second -eq 0x5A
        $peExtension = $file.Extension -in @('.dll', '.exe')
        if (-not $hasMzSignature) {
            if ($peExtension) {
                throw "Executable/library payload is not a valid PE: $($file.FullName)"
            }
            continue
        }

        $classification = Assert-PeArchitecture -Path $file.FullName
        if ($classification -eq 'target') {
            $targetPeCount++
        }
        else {
            $neutralManagedPeCount++
        }
    }
    if ($targetPeCount -eq 0) {
        throw "No target-architecture PE files were found under '$Root'."
    }

    $depsTarget = $deps.targets.PSObject.Properties[$deps.runtimeTarget.name].Value
    if ($null -eq $depsTarget) {
        throw "Dependency graph lacks selected target '$($deps.runtimeTarget.name)'."
    }
    $foundSqlite = $false
    foreach ($library in $depsTarget.PSObject.Properties) {
        foreach ($nativeAsset in $library.Value.native.PSObject.Properties) {
            $assetPath = $nativeAsset.Name
            if ($assetPath -match '(?i)(^|/)runtimes/win-(?<arch>[^/]+)/native/' -and
                $Matches.arch -ne $Architecture) {
                throw "Dependency native asset '$assetPath' conflicts with $expectedRuntimeIdentifier."
            }
            $assetName = [System.IO.Path]::GetFileName($assetPath)
            if ($assetName -eq 'e_sqlite3.dll') {
                $foundSqlite = $true
            }
            if (-not $filesByName.ContainsKey($assetName.ToLowerInvariant()) -and
                -not ($AllowMissingCreatedump -and $assetName -eq 'createdump.exe')) {
                throw "Dependency native asset '$assetPath' is missing from '$Root'."
            }
        }
        foreach ($runtimeAsset in $library.Value.runtimeTargets.PSObject.Properties) {
            $assetRid = [string]$runtimeAsset.Value.rid
            if ($assetRid -like 'win-*' -and $assetRid -ne $expectedRuntimeIdentifier) {
                throw "Dependency runtime asset '$($runtimeAsset.Name)' targets '$assetRid'."
            }
        }
    }
    if (-not $foundSqlite -or -not $filesByName.ContainsKey('e_sqlite3.dll')) {
        throw "Architecture-specific e_sqlite3.dll is missing from the dependency graph or output."
    }

    return [pscustomobject]@{
        TargetPeCount = $targetPeCount
        NeutralManagedPeCount = $neutralManagedPeCount
        TotalPeCount = $targetPeCount + $neutralManagedPeCount
    }
}

$publishInspection = Assert-PublishLayout -Root $resolvedPublishPath

$resolvedPackagePath = $null
if (-not [string]::IsNullOrWhiteSpace($PackagePath)) {
    $resolvedPackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'BG3HonorAssistant-inspect-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
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
        $packageInspection = Assert-PublishLayout `
            -Root $temporaryRoot `
            -AllowMissingCreatedump
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
    publishPeCount = $publishInspection.TotalPeCount
    publishTargetPeCount = $publishInspection.TargetPeCount
    publishNeutralManagedPeCount = $publishInspection.NeutralManagedPeCount
    packagePeCount = if ($null -eq $packageInspection) { $null } else { $packageInspection.TotalPeCount }
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
