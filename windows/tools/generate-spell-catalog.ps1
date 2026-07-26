param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\..\mac\BG3Assistant\BG3SpellCatalog.generated.swift'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\src\BG3HonorAssistant.Core\Resources\spell-catalog.json')
)

$ErrorActionPreference = 'Stop'
$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$classes = [ordered]@{}
$currentClass = $null

foreach ($line in Get-Content -LiteralPath $resolvedSource) {
    if ($line -match '^\s*"([^"]+)": \[$') {
        $currentClass = $Matches[1]
        $classes[$currentClass] = [ordered]@{}
        continue
    }

    if (
        $null -ne $currentClass -and
        $line -match '^\s*(\d+): \[(.*)\],$'
    ) {
        $rank = $Matches[1]
        $serializedValues = $Matches[2]
        $values = @(
            [regex]::Matches($serializedValues, '"((?:[^"\\]|\\.)*)"') |
                ForEach-Object {
                    ('"' + $_.Groups[1].Value + '"') | ConvertFrom-Json
                }
        )
        $classes[$currentClass][$rank] = $values
    }
}

if ($classes.Count -ne 8) {
    throw "Expected 8 caster-class catalogs, found $($classes.Count)."
}

$payload = [ordered]@{
    source = 'mac/BG3Assistant/BG3SpellCatalog.generated.swift'
    sourceSha256 = (Get-FileHash -LiteralPath $resolvedSource -Algorithm SHA256).Hash
    classes = $classes
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$json = $payload | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText(
    $resolvedOutput,
    $json + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false))

Write-Output $resolvedOutput
