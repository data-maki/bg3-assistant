param(
    [string]$Configuration = 'Release',
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\publish\win-x64')
)

$ErrorActionPreference = 'Stop'
$dotnet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
$project = Join-Path $PSScriptRoot '..\src\BG3HonorAssistant.App\BG3HonorAssistant.App.csproj'

if (-not (Test-Path -LiteralPath $dotnet)) {
    throw ".NET SDK not found at $dotnet"
}

& $dotnet publish $project `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --no-restore `
    --output $OutputPath `
    -p:PublishTrimmed=false

if ($LASTEXITCODE -ne 0) {
    throw "Self-contained publish failed with exit code $LASTEXITCODE."
}
