# SPDX-License-Identifier: AGPL-3.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MifRepository,

    [Parameter(Mandatory = $true)]
    [string]$NmmLlmRepository,

    [string]$Cases = 'interop/cases/smoke-v1.json',

    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'

$expectedCommit = 'f37ddfeb5fb8479991fa38eeb03c797bef8ae408'
$expectedFiles = [ordered]@{
    'mif-1.0.md' = '330e65145ceb26fe582e58b89405d87bd73e8be200b476aef82c0ee27731d995'
    'docs/zh-CN/mif-1.0.md' = '9cc06abb57425e2bc2e26432b6da53abe503e9b5415ea0b4f854f19f68722cc1'
    'artifacts/mif-1.0/index.json' = '3849a70897829d6d994c790b64e63484469483a940887fe828a1a0d421d78e90'
    'artifacts/mif-1.0/corpus/executable/reference-cases.json' = 'a48c50352caebce30deb1de11f8f73dbc4540ee538651c3a139d9bcb166ba983'
    'interop/adapter-protocol-v1.md' = 'a59e5e5af3e948f6c7cac6a39a490c6eae6338151741b6c7fcdde5c88d991e2d'
    'interop/cases/smoke-v1.json' = 'a6d292f4d19381172fbc19f89d3ee42145a6d5533d6d81fd719394e25342bb53'
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mifRoot = (Resolve-Path -LiteralPath $MifRepository).Path
$nmmLlmRoot = (Resolve-Path -LiteralPath $NmmLlmRepository).Path
$actualCommit = (& git -C $mifRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) {
    throw "MIF commit mismatch: expected $expectedCommit, got $actualCommit"
}

$mifStatus = @(& git -C $mifRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to inspect the MIF worktree status'
}
if ($mifStatus.Count -ne 0) {
    throw "MIF worktree must be clean before baseline comparison:`n$($mifStatus -join "`n")"
}

foreach ($entry in $expectedFiles.GetEnumerator()) {
    $path = Join-Path $mifRoot $entry.Key
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actualHash -ne $entry.Value) {
        throw "MIF artifact hash mismatch for $($entry.Key): $actualHash"
    }
}

& cargo build --manifest-path (Join-Path $repositoryRoot 'Cargo.toml') -p tgf-cli
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to build the Sanmill MIF adapter'
}

$metadata = (& cargo metadata --format-version 1 --no-deps --manifest-path (Join-Path $repositoryRoot 'Cargo.toml') | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to locate the Cargo target directory'
}
$executableName = if ($env:OS -eq 'Windows_NT') { 'tgf.exe' } else { 'tgf' }
$sanmillAdapter = Join-Path $metadata.target_directory (Join-Path 'debug' $executableName)
$nmmLlmAdapter = Join-Path $nmmLlmRoot 'tools/nmm_llm_mif_adapter.py'
foreach ($adapterPath in @($sanmillAdapter, $nmmLlmAdapter)) {
    if (-not (Test-Path -LiteralPath $adapterPath -PathType Leaf)) {
        throw "Adapter executable does not exist: $adapterPath"
    }
}

$templatePath = Join-Path $repositoryRoot 'interop/adapters.three-project.mif-1.0.json'
$configObject = Get-Content -Raw -LiteralPath $templatePath | ConvertFrom-Json
$sanmillConfig = $configObject.adapters | Where-Object name -EQ 'sanmill-rust'
$nmmLlmConfig = $configObject.adapters | Where-Object name -EQ 'nmm-llm-python'
if ($null -eq $sanmillConfig -or $null -eq $nmmLlmConfig) {
    throw 'Adapter configuration template is missing a project entry'
}
$sanmillConfig.command = @($sanmillAdapter, 'mill', 'mif-interop')
$nmmLlmConfig.command = @('{python}', '-B', $nmmLlmAdapter)

$generatedDirectory = Join-Path $repositoryRoot 'target/mif-interop'
[System.IO.Directory]::CreateDirectory($generatedDirectory) | Out-Null
$config = Join-Path $generatedDirectory 'adapters.three-project.mif-1.0.generated.json'
$configJson = $configObject | ConvertTo-Json -Depth 16
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($config, "$configJson`n", $utf8WithoutBom)

$comparator = Join-Path $mifRoot 'tools/compare_mif_1_0_adapters.py'
& $Python -B $comparator --config $config --cases (Join-Path $mifRoot $Cases)
if ($LASTEXITCODE -ne 0) {
    throw 'MIF three-project comparison failed'
}
