param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)]
    [ValidateSet('arm64', 'x64')]
    [string]$ExpectedArchitecture
)

$ErrorActionPreference = 'Stop'

function Test-MzPayload {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 2) {
            return $false
        }

        return $stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A
    }
    finally {
        $stream.Dispose()
    }
}

$resolvedRoot = [System.IO.Path]::GetFullPath($Root)
$rootPrefix = $resolvedRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar
if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
    throw "Delivered payload root was not found: $resolvedRoot"
}

$requiredPaths = @(
    'AppxManifest.xml',
    'Assets/AppIcon.png',
    'BG3HonorAssistant.exe',
    'BG3HonorAssistant.dll',
    'BG3HonorAssistant.deps.json',
    'BG3HonorAssistant.runtimeconfig.json',
    'Resources/Data/guide-bundle.json',
    'Resources/THIRD_PARTY_NOTICES.md'
)
foreach ($relativePath in $requiredPaths) {
    $nativeRelativePath = $relativePath.Replace(
        '/',
        [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot $nativeRelativePath) -PathType Leaf)) {
        throw "Required delivered payload is missing: $relativePath"
    }
}

$dependencyPath = Join-Path $resolvedRoot 'BG3HonorAssistant.deps.json'
try {
    $dependencyDocument =
        Get-Content -Raw -LiteralPath $dependencyPath |
        ConvertFrom-Json
}
catch {
    throw "BG3HonorAssistant.deps.json is not valid JSON."
}

$runtimeTargetName = [string]$dependencyDocument.runtimeTarget.name
$expectedRuntimeSuffix = "/win-$ExpectedArchitecture"
if (-not $runtimeTargetName.EndsWith(
        $expectedRuntimeSuffix,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw (
        "Dependency runtime target '$runtimeTargetName' does not match " +
        "win-$ExpectedArchitecture.")
}

$targetProperties = @(
    $dependencyDocument.targets.PSObject.Properties |
    Where-Object {
        [string]::Equals(
            $_.Name,
            $runtimeTargetName,
            [StringComparison]::Ordinal)
    })
if ($targetProperties.Count -ne 1) {
    throw "Dependency manifest must contain exactly one selected runtime target."
}

$allowedRootDlls =
    [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
$selectedTarget = $targetProperties[0].Value
foreach ($library in $selectedTarget.PSObject.Properties) {
    foreach ($groupName in @('runtime', 'native', 'runtimeTargets')) {
        $group = $library.Value.$groupName
        if ($null -eq $group) {
            continue
        }

        foreach ($asset in $group.PSObject.Properties) {
            $assetName = [string]$asset.Name
            $leafName = [System.IO.Path]::GetFileName(
                $assetName.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            if ([System.IO.Path]::GetExtension($leafName) -eq '.dll') {
                [void]$allowedRootDlls.Add($leafName)
            }
        }
    }
}

foreach ($productAssembly in @(
        'BG3HonorAssistant.dll',
        'BG3HonorAssistant.Core.dll',
        'BG3HonorAssistant.Infrastructure.dll',
        'BG3HonorAssistant.Windows.dll')) {
    if (-not $allowedRootDlls.Contains($productAssembly)) {
        throw "Dependency manifest does not provenance-list $productAssembly."
    }
}

$allowedRootFiles =
    [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
foreach ($rootFile in @(
        'AppxBlockMap.xml',
        'AppxManifest.xml',
        'AppxSignature.p7x',
        'BG3HonorAssistant.deps.json',
        'BG3HonorAssistant.exe',
        'BG3HonorAssistant.runtimeconfig.json',
        '[Content_Types].xml')) {
    [void]$allowedRootFiles.Add($rootFile)
}

$allowedCultures =
    [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
foreach ($culture in @(
        'cs', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pl', 'pt-BR',
        'ru', 'tr', 'zh-Hans', 'zh-Hant')) {
    [void]$allowedCultures.Add($culture)
}

$allowedCultureAssemblies =
    [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
foreach ($assembly in @(
        'Microsoft.VisualBasic.Forms.resources.dll',
        'PresentationCore.resources.dll',
        'PresentationFramework.resources.dll',
        'PresentationUI.resources.dll',
        'ReachFramework.resources.dll',
        'System.Windows.Controls.Ribbon.resources.dll',
        'System.Windows.Forms.Design.resources.dll',
        'System.Windows.Forms.Primitives.resources.dll',
        'System.Windows.Forms.resources.dll',
        'System.Windows.Input.Manipulations.resources.dll',
        'System.Xaml.resources.dll',
        'UIAutomationClient.resources.dll',
        'UIAutomationClientSideProviders.resources.dll',
        'UIAutomationProvider.resources.dll',
        'UIAutomationTypes.resources.dll',
        'WindowsBase.resources.dll',
        'WindowsFormsIntegration.resources.dll')) {
    [void]$allowedCultureAssemblies.Add($assembly)
}

$items = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force
foreach ($item in $items) {
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed in the delivered payload: $($item.FullName)"
    }
}

foreach ($file in $items | Where-Object { -not $_.PSIsContainer }) {
    $fullPath = [System.IO.Path]::GetFullPath($file.FullName)
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Delivered payload escaped its validated root: $fullPath"
    }

    $relativePath = $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
    $segments = $relativePath.Split('/')
    $allowed = $false

    if ($segments.Count -eq 1) {
        if ($allowedRootFiles.Contains($segments[0])) {
            $allowed = $true
        }
        elseif ($file.Extension -eq '.dll' -and $allowedRootDlls.Contains($segments[0])) {
            $allowed = $true
        }
    }
    elseif (
        $segments.Count -eq 2 -and
        $segments[0] -eq 'Assets' -and
        $segments[1] -eq 'AppIcon.png'
    ) {
        $allowed = $true
    }
    elseif (
        $segments.Count -eq 2 -and
        $segments[0] -eq 'AppxMetadata' -and
        $segments[1] -eq 'CodeIntegrity.cat'
    ) {
        $allowed = $true
    }
    elseif (
        $segments.Count -eq 2 -and
        $allowedCultures.Contains($segments[0]) -and
        $allowedCultureAssemblies.Contains($segments[1])
    ) {
        $allowed = $true
    }
    elseif ($segments[0] -eq 'Resources') {
        $resourceExtension = $file.Extension.ToLowerInvariant()
        $allowed =
            $resourceExtension -in @('.png', '.webp') -or
            $relativePath -in @(
                'Resources/BuildOptionIcons/manifest.json',
                'Resources/Data/guide-bundle.json',
                'Resources/THIRD_PARTY_NOTICES.md')
        if ($allowed -and (Test-MzPayload -Path $fullPath)) {
            throw "Executable content is not allowed under Resources: $relativePath"
        }
    }

    if (-not $allowed) {
        throw (
            "Payload is not present in the delivered dependency/resource allowlist: " +
            $relativePath)
    }
}
