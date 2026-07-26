param(
    [Parameter(Mandatory)]
    [ValidateSet('arm64', 'x64')]
    [string]$Architecture,
    [string]$Configuration = 'Release',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runtimeIdentifier = "win-$Architecture"
$project = Join-Path $windowsRoot 'src\BG3HonorAssistant.App\BG3HonorAssistant.App.csproj'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $windowsRoot "artifacts\publish\$runtimeIdentifier"
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET SDK was not found on PATH.'
}

Push-Location $windowsRoot
try {
    & dotnet publish $project `
        --configuration $Configuration `
        --runtime $runtimeIdentifier `
        --self-contained true `
        --no-restore `
        --output $OutputPath `
        -p:BG3Architecture=$Architecture `
        -p:PublishTrimmed=false

    if ($LASTEXITCODE -ne 0) {
        throw "Self-contained $runtimeIdentifier publish failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
