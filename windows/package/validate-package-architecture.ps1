param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)]
    [ValidateSet('arm64', 'x64')]
    [string]$ExpectedArchitecture
)

$ErrorActionPreference = 'Stop'

function Read-UInt16 {
    param(
        [Parameter(Mandatory)][System.IO.BinaryReader]$Reader,
        [Parameter(Mandatory)][uint64]$Offset,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Offset + 2 -gt [uint64]$Reader.BaseStream.Length) {
        throw "PE field at offset $Offset is out of bounds in $Path."
    }
    $Reader.BaseStream.Position = [long]$Offset
    $Reader.ReadUInt16()
}

function Read-UInt32 {
    param(
        [Parameter(Mandatory)][System.IO.BinaryReader]$Reader,
        [Parameter(Mandatory)][uint64]$Offset,
        [Parameter(Mandatory)][string]$Path
    )

    if ($Offset + 4 -gt [uint64]$Reader.BaseStream.Length) {
        throw "PE field at offset $Offset is out of bounds in $Path."
    }
    $Reader.BaseStream.Position = [long]$Offset
    $Reader.ReadUInt32()
}

function Resolve-Rva {
    param(
        [Parameter(Mandatory)][object[]]$Sections,
        [Parameter(Mandatory)][uint32]$Rva,
        [Parameter(Mandatory)][uint32]$Size,
        [Parameter(Mandatory)][uint64]$FileLength,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$FieldName
    )

    if ($Rva -eq 0 -or $Size -eq 0) {
        throw "$FieldName has an empty or inconsistent RVA/size in $Path."
    }

    $rvaStart = [uint64]$Rva
    $rvaEnd = $rvaStart + [uint64]$Size
    $matches = @()
    foreach ($section in $Sections) {
        $sectionStart = [uint64]$section.VirtualAddress
        $sectionEnd = $sectionStart + [uint64]$section.RawSize
        if ($rvaStart -ge $sectionStart -and $rvaEnd -le $sectionEnd) {
            $fileOffset = [uint64]$section.RawPointer + ($rvaStart - $sectionStart)
            if ($fileOffset + [uint64]$Size -gt $FileLength) {
                throw "$FieldName maps beyond the file in $Path."
            }
            $matches += $fileOffset
        }
    }

    if ($matches.Count -ne 1) {
        throw "$FieldName does not map to exactly one in-bounds PE section in $Path."
    }
    [uint64]$matches[0]
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
        if ((Read-UInt16 -Reader $reader -Offset 0 -Path $Path) -ne 0x5A4D) {
            return $null
        }

        $peOffset = Read-UInt32 -Reader $reader -Offset 0x3C -Path $Path
        if ([uint64]$peOffset + 24 -gt [uint64]$stream.Length) {
            throw "Malformed PE header in $Path."
        }
        if ((Read-UInt32 -Reader $reader -Offset $peOffset -Path $Path) -ne 0x00004550) {
            return $null
        }

        $machine = Read-UInt16 -Reader $reader -Offset ([uint64]$peOffset + 4) -Path $Path
        $sectionCount = Read-UInt16 -Reader $reader -Offset ([uint64]$peOffset + 6) -Path $Path
        $coffCharacteristics =
            Read-UInt16 -Reader $reader -Offset ([uint64]$peOffset + 22) -Path $Path
        $optionalHeaderSize =
            Read-UInt16 -Reader $reader -Offset ([uint64]$peOffset + 20) -Path $Path
        $optionalHeaderOffset = [uint64]$peOffset + 24
        if (
            $optionalHeaderSize -lt 2 -or
            $optionalHeaderOffset + $optionalHeaderSize -gt [uint64]$stream.Length
        ) {
            throw "Malformed optional PE header in $Path."
        }

        $optionalMagic =
            Read-UInt16 -Reader $reader -Offset $optionalHeaderOffset -Path $Path
        $dataDirectoryOffset = switch ($optionalMagic) {
            0x010B { 96 }
            0x020B { 112 }
            default { throw "Unknown PE optional-header format in $Path." }
        }
        $numberOfDirectoriesOffset = if ($optionalMagic -eq 0x010B) { 92 } else { 108 }
        $subsystemOffset = 68
        if ($optionalHeaderSize -lt $dataDirectoryOffset) {
            throw "PE optional header is truncated before NumberOfRvaAndSizes in $Path."
        }
        $addressOfEntryPoint = Read-UInt32 `
            -Reader $reader `
            -Offset ($optionalHeaderOffset + 16) `
            -Path $Path
        $subsystem = Read-UInt16 `
            -Reader $reader `
            -Offset ($optionalHeaderOffset + $subsystemOffset) `
            -Path $Path
        $numberOfDirectories = Read-UInt32 `
            -Reader $reader `
            -Offset ($optionalHeaderOffset + $numberOfDirectoriesOffset) `
            -Path $Path

        $sectionTableOffset = $optionalHeaderOffset + [uint64]$optionalHeaderSize
        if ($sectionCount -eq 0 -or
            $sectionTableOffset + ([uint64]$sectionCount * 40) -gt [uint64]$stream.Length) {
            throw "Malformed PE section table in $Path."
        }
        $sections = @()
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $sectionOffset = $sectionTableOffset + ([uint64]$index * 40)
            $sections += [pscustomobject]@{
                VirtualSize = Read-UInt32 `
                    -Reader $reader -Offset ($sectionOffset + 8) -Path $Path
                VirtualAddress = Read-UInt32 `
                    -Reader $reader -Offset ($sectionOffset + 12) -Path $Path
                RawSize = Read-UInt32 `
                    -Reader $reader -Offset ($sectionOffset + 16) -Path $Path
                RawPointer = Read-UInt32 `
                    -Reader $reader -Offset ($sectionOffset + 20) -Path $Path
                Characteristics = Read-UInt32 `
                    -Reader $reader -Offset ($sectionOffset + 36) -Path $Path
            }
        }

        if ($numberOfDirectories -lt 15) {
            return [pscustomobject]@{
                Path = $Path
                Machine = $machine
                CoffCharacteristics = $coffCharacteristics
                OptionalMagic = $optionalMagic
                AddressOfEntryPoint = $addressOfEntryPoint
                Subsystem = $subsystem
                Sections = $sections
                IsManaged = $false
                IsArchitectureNeutralIl = $false
            }
        }
        if ($optionalHeaderSize -lt ($dataDirectoryOffset + (15 * 8))) {
            throw "PE optional header declares a CLI directory outside its bounds in $Path."
        }

        $cliDirectoryOffset =
            $optionalHeaderOffset + $dataDirectoryOffset + (14 * 8)
        $cliRva = Read-UInt32 -Reader $reader -Offset $cliDirectoryOffset -Path $Path
        $cliSize = Read-UInt32 `
            -Reader $reader -Offset ($cliDirectoryOffset + 4) -Path $Path
        if ($cliRva -eq 0 -and $cliSize -eq 0) {
            return [pscustomobject]@{
                Path = $Path
                Machine = $machine
                CoffCharacteristics = $coffCharacteristics
                OptionalMagic = $optionalMagic
                AddressOfEntryPoint = $addressOfEntryPoint
                Subsystem = $subsystem
                Sections = $sections
                IsManaged = $false
                IsArchitectureNeutralIl = $false
            }
        }
        if ($cliRva -eq 0 -or $cliSize -eq 0) {
            throw "CLI data directory has an inconsistent RVA/size in $Path."
        }
        if ($cliSize -lt 72) {
            throw "CLI header is smaller than IMAGE_COR20_HEADER in $Path."
        }

        $cliOffset = Resolve-Rva `
            -Sections $sections `
            -Rva $cliRva `
            -Size $cliSize `
            -FileLength ([uint64]$stream.Length) `
            -Path $Path `
            -FieldName 'CLI header'
        $cliHeaderSize = Read-UInt32 -Reader $reader -Offset $cliOffset -Path $Path
        if ($cliHeaderSize -lt 72 -or $cliHeaderSize -gt $cliSize) {
            throw "CLI header size is invalid in $Path."
        }

        $metadataRva = Read-UInt32 `
            -Reader $reader -Offset ($cliOffset + 8) -Path $Path
        $metadataSize = Read-UInt32 `
            -Reader $reader -Offset ($cliOffset + 12) -Path $Path
        $metadataOffset = Resolve-Rva `
            -Sections $sections `
            -Rva $metadataRva `
            -Size $metadataSize `
            -FileLength ([uint64]$stream.Length) `
            -Path $Path `
            -FieldName 'CLR metadata'
        if ($metadataSize -lt 16 -or
            (Read-UInt32 -Reader $reader -Offset $metadataOffset -Path $Path) -ne
            0x424A5342) {
            throw "CLR metadata signature or size is invalid in $Path."
        }

        $corFlags = Read-UInt32 -Reader $reader -Offset ($cliOffset + 16) -Path $Path
        $managedNativeRva = Read-UInt32 `
            -Reader $reader -Offset ($cliOffset + 64) -Path $Path
        $managedNativeSize = Read-UInt32 `
            -Reader $reader -Offset ($cliOffset + 68) -Path $Path
        if (($managedNativeRva -eq 0) -ne ($managedNativeSize -eq 0)) {
            throw "Managed native header has an inconsistent RVA/size in $Path."
        }
        if ($managedNativeRva -ne 0) {
            [void](Resolve-Rva `
                -Sections $sections `
                -Rva $managedNativeRva `
                -Size $managedNativeSize `
                -FileLength ([uint64]$stream.Length) `
                -Path $Path `
                -FieldName 'Managed native header')
        }

        $ilOnly = ($corFlags -band 0x00000001) -ne 0
        $requires32Bit = ($corFlags -band 0x00000002) -ne 0
        $nativeEntryPoint = ($corFlags -band 0x00000010) -ne 0
        $prefers32Bit = ($corFlags -band 0x00020000) -ne 0
        $isArchitectureNeutralIl =
            $ilOnly -and
            -not $requires32Bit -and
            -not $nativeEntryPoint -and
            -not $prefers32Bit -and
            $managedNativeRva -eq 0

        [pscustomobject]@{
            Path = $Path
            Machine = $machine
            CoffCharacteristics = $coffCharacteristics
            OptionalMagic = $optionalMagic
            AddressOfEntryPoint = $addressOfEntryPoint
            Subsystem = $subsystem
            Sections = $sections
            IsManaged = $true
            IsArchitectureNeutralIl = $isArchitectureNeutralIl
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-PePayloadArchitecture {
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][ValidateSet('arm64', 'x64')][string]$Architecture
    )

    $expectedMachine = if ($Architecture -eq 'arm64') { 0xAA64 } else { 0x8664 }
    $expectedMachineName = if ($Architecture -eq 'arm64') { 'ARM64' } else { 'AMD64' }
    $expectedPayloads = 0

    foreach ($file in Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File) {
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
        if (
            $payload.Machine -eq 0x014C -and
            $payload.IsManaged -and
            $payload.IsArchitectureNeutralIl
        ) {
            continue
        }

        $actualMachine = '0x{0:X4}' -f $payload.Machine
        throw (
            "Cross-architecture PE payload in $Architecture package: " +
            "$($file.FullName) has machine $actualMachine; expected $expectedMachineName.")
    }

    if ($expectedPayloads -eq 0) {
        throw "No $expectedMachineName PE payload was found under $PayloadRoot."
    }

    $appExecutable = Get-PePayload -Path (Join-Path $PayloadRoot 'BG3HonorAssistant.exe')
    if (
        $null -eq $appExecutable -or
        $appExecutable.Machine -ne $expectedMachine -or
        $appExecutable.IsManaged
    ) {
        throw "BG3HonorAssistant.exe is not a native $expectedMachineName app host."
    }
    if ($appExecutable.OptionalMagic -ne 0x020B) {
        throw "BG3HonorAssistant.exe must use a PE32+ optional header."
    }
    if (
        ($appExecutable.CoffCharacteristics -band 0x0002) -eq 0 -or
        ($appExecutable.CoffCharacteristics -band 0x2000) -ne 0
    ) {
        throw (
            "BG3HonorAssistant.exe must be an executable image and must not " +
            "have the DLL characteristic.")
    }
    if ($appExecutable.Subsystem -notin @(2, 3)) {
        throw "BG3HonorAssistant.exe has no launchable Windows subsystem."
    }
    if ($appExecutable.AddressOfEntryPoint -eq 0) {
        throw "BG3HonorAssistant.exe has no native entry point."
    }
    [void](Resolve-Rva `
        -Sections $appExecutable.Sections `
        -Rva $appExecutable.AddressOfEntryPoint `
        -Size 1 `
        -FileLength ([uint64](Get-Item -LiteralPath $appExecutable.Path).Length) `
        -Path $appExecutable.Path `
        -FieldName 'Application entry point')
    $entryPoint = [uint64]$appExecutable.AddressOfEntryPoint
    $entrySections = @($appExecutable.Sections | Where-Object {
        $sectionStart = [uint64]$_.VirtualAddress
        $sectionEnd = $sectionStart + [uint64]$_.RawSize
        $entryPoint -ge $sectionStart -and $entryPoint -lt $sectionEnd
    })
    if (
        $entrySections.Count -ne 1 -or
        ($entrySections[0].Characteristics -band 0x20000000) -eq 0
    ) {
        throw (
            "BG3HonorAssistant.exe entry point must map to exactly one " +
            "executable, file-backed section.")
    }
}

function Assert-PackageManifest {
    param(
        [Parameter(Mandatory)][xml]$Manifest,
        [Parameter(Mandatory)][ValidateSet('arm64', 'x64')][string]$Architecture
    )

    $namespaceManager =
        [System.Xml.XmlNamespaceManager]::new($Manifest.NameTable)
    $namespaceManager.AddNamespace(
        'foundation',
        'http://schemas.microsoft.com/appx/manifest/foundation/windows10')

    $identities = @($Manifest.SelectNodes(
        '/foundation:Package/foundation:Identity',
        $namespaceManager))
    if ($identities.Count -ne 1) {
        throw "Package manifest must contain exactly one Identity; found $($identities.Count)."
    }
    $manifestArchitecture = [string]$identities[0].ProcessorArchitecture
    if ($manifestArchitecture -ne $Architecture) {
        throw (
            "Package manifest architecture '$manifestArchitecture' does not match " +
            "'$Architecture'.")
    }
    if ($manifestArchitecture -in @('neutral', 'AnyCPU', 'MSIL')) {
        throw "Neutral or AnyCPU MSIX identities are not allowed."
    }

    $applications = @($Manifest.SelectNodes(
        '/foundation:Package/foundation:Applications/foundation:Application',
        $namespaceManager))
    if ($applications.Count -ne 1) {
        throw (
            "Package manifest must contain exactly one namespaced product Application; " +
            "found $($applications.Count).")
    }
    $allApplicationElements = @($Manifest.SelectNodes(
        '//*[local-name() = "Application"]',
        $namespaceManager))
    if ($allApplicationElements.Count -ne $applications.Count) {
        throw "Package manifest contains a deceptive foreign-namespace Application."
    }
    if (
        -not [string]::Equals(
            [string]$applications[0].Executable,
            'BG3HonorAssistant.exe',
            [StringComparison]::Ordinal)
    ) {
        throw "The manifest Application executable must be exactly BG3HonorAssistant.exe."
    }

    $executableNodes = @($Manifest.SelectNodes('//*[@Executable]', $namespaceManager))
    foreach ($node in $executableNodes) {
        if (
            -not [string]::Equals(
                [string]$node.Executable,
                'BG3HonorAssistant.exe',
                [StringComparison]::Ordinal)
        ) {
            throw (
                "Every manifest executable reference must be exactly " +
                "BG3HonorAssistant.exe; found '$([string]$node.Executable)'.")
        }
    }
}

$resolvedRoot = [System.IO.Path]::GetFullPath($Root)
$manifestPath = Join-Path $resolvedRoot 'AppxManifest.xml'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Package manifest was not found under $resolvedRoot."
}

$manifest = [xml](Get-Content -Raw -LiteralPath $manifestPath)
Assert-PackageManifest -Manifest $manifest -Architecture $ExpectedArchitecture
Assert-PePayloadArchitecture `
    -PayloadRoot $resolvedRoot `
    -Architecture $ExpectedArchitecture
