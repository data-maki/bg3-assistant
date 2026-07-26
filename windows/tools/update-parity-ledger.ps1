param(
    [string]$FeatureParityPath = (Join-Path $PSScriptRoot '..\research\feature-parity.md'),
    [string]$LedgerPath = (Join-Path $PSScriptRoot '..\evidence\parity-ledger.md')
)

$ErrorActionPreference = 'Stop'
$gateByPrefix = @{
    O = 'G2'
    R = 'G2'
    P = 'G3'
    A = 'G4'
    S = 'G2/G4'
    I = 'G1/G5'
}

$ids = foreach ($line in Get-Content -LiteralPath $FeatureParityPath) {
    if ($line -match '^\| (?<id>[ORPASI]-\d{2}) \|') {
        $Matches.id
    }
}

$rows = foreach ($id in $ids) {
    $prefix = $id.Substring(0, 1)
    "| $id | $($gateByPrefix[$prefix]) | Pending | - |"
}

$content = @(
    '# Windows parity evidence ledger'
    ''
    '> Generated from `research/feature-parity.md`. Update Status and Evidence as tests are completed;'
    '> rerunning this generator intentionally resets rows to Pending.'
    ''
    '| Row | Gate | Status | Evidence |'
    '|---|---|---|---|'
    $rows
    ''
    'Allowed statuses: `Pending`, `Automated pass`, `Manual pass`, `Approved exclusion`, `Data gap`, `Blocked`.'
)

$directory = Split-Path -Parent $LedgerPath
New-Item -ItemType Directory -Path $directory -Force | Out-Null
[System.IO.File]::WriteAllLines($LedgerPath, $content)
