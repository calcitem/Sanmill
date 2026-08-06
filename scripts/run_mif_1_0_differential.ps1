# SPDX-License-Identifier: AGPL-3.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MifRepository,

    [Parameter(Mandatory = $true)]
    [string]$NmmLlmRepository,

    [string]$Python = 'python',

    [string]$ReferenceSanmillReport = 'target/mif-interop/m4-reference-sanmill-report.json',

    [string]$ThreeProjectReport = 'target/mif-interop/m4-three-project-report.json'
)

$ErrorActionPreference = 'Stop'

$expectedM4Commit = '40718e80d36ec9c060fc17997568d637a74e6d9f'
$expectedWireCommit = '7e45d5a3fa970a535ed6a8a8ff5981aba4b9c978'
$expectedLaunchHash = '560ef369fde248bd96d3468a4336442db1d970ede04f488821509e69925fd48e'
$expectedReferenceBaselineHash = '29d198dbcf8221fa0235af6a72db9d6a82646b45fc653c584071821a9a4bb61b'
$expectedResourceCount = 29

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mifRoot = (Resolve-Path -LiteralPath $MifRepository).Path
$nmmLlmRoot = (Resolve-Path -LiteralPath $NmmLlmRepository).Path
$launch = Join-Path $mifRoot 'interop/differential-candidate-4-v1.json'
$referenceBaseline = Join-Path $mifRoot 'interop/evidence/mif-1.0-candidate-4-m4-reference-baseline.json'
$runner = Join-Path $mifRoot 'tools/run_mif_1_0_differential.py'

$actualCommit = (& git -C $mifRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedM4Commit) {
    throw "MIF M4 commit mismatch: expected $expectedM4Commit, got $actualCommit"
}
& git -C $mifRoot merge-base --is-ancestor $expectedWireCommit $expectedM4Commit
if ($LASTEXITCODE -ne 0) {
    throw 'Candidate-4 wire commit is not an ancestor of the M4 launch commit'
}
$mifStatus = @(& git -C $mifRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to inspect the MIF worktree status'
}
if ($mifStatus.Count -ne 0) {
    throw "MIF worktree must be clean before M4 comparison:`n$($mifStatus -join "`n")"
}

$actualLaunchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $launch).Hash.ToLowerInvariant()
if ($actualLaunchHash -ne $expectedLaunchHash) {
    throw "M4 launch hash mismatch: $actualLaunchHash"
}
$actualReferenceBaselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $referenceBaseline).Hash.ToLowerInvariant()
if ($actualReferenceBaselineHash -ne $expectedReferenceBaselineHash) {
    throw "M4 reference baseline hash mismatch: $actualReferenceBaselineHash"
}
$launchDocument = Get-Content -Raw -LiteralPath $launch | ConvertFrom-Json
$resources = @($launchDocument.resources)
if ($resources.Count -ne $expectedResourceCount) {
    throw "M4 launch resource count mismatch: $($resources.Count)"
}
$resourcePaths = @($resources | ForEach-Object path)
if (@($resourcePaths | Sort-Object -Unique).Count -ne $expectedResourceCount -or
    ($resourcePaths -join "`n") -ne (($resourcePaths | Sort-Object) -join "`n")) {
    throw 'M4 launch resources must be sorted and unique'
}
foreach ($resource in $resources) {
    $path = Join-Path $mifRoot $resource.path
    $actualHash = 'sha256:' + (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actualHash -ne $resource.sha256) {
        throw "M4 launch resource hash mismatch for $($resource.path): $actualHash"
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
$threeProjectConfig = Join-Path $generatedDirectory 'adapters.three-project.m4.generated.json'
$referenceSanmillConfig = Join-Path $generatedDirectory 'adapters.reference-sanmill.m4.generated.json'
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$configJson = $configObject | ConvertTo-Json -Depth 16
[System.IO.File]::WriteAllText($threeProjectConfig, "$configJson`n", $utf8WithoutBom)
$referenceSanmillObject = [ordered]@{
    protocol = $configObject.protocol
    adapters = @($configObject.adapters | Where-Object name -NE 'nmm-llm-python')
}
$referenceSanmillJson = $referenceSanmillObject | ConvertTo-Json -Depth 16
[System.IO.File]::WriteAllText($referenceSanmillConfig, "$referenceSanmillJson`n", $utf8WithoutBom)

function Resolve-ReportPath([string]$Path) {
    $resolved = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $Path))
    }
    $relative = [System.IO.Path]::GetRelativePath($repositoryRoot, $resolved)
    $parentPrefix = "..$([System.IO.Path]::DirectorySeparatorChar)"
    if ([System.IO.Path]::IsPathRooted($relative) -or
        $relative -eq '..' -or
        $relative.StartsWith($parentPrefix, [System.StringComparison]::Ordinal)) {
        throw 'Report path must remain inside the Sanmill repository'
    }
    return $resolved
}

function Invoke-Differential([string]$Config, [string]$Report) {
    $reportPath = Resolve-ReportPath $Report
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $reportPath)) | Out-Null
    # The MIF harness confines report writes to its own root.
    $temporaryReport = Join-Path $mifRoot ".mif-m4-report-$PID-$([System.Guid]::NewGuid().ToString('N')).json"
    $runnerExit = 0
    try {
        & $Python -B $runner --config $Config --launch $launch --report $temporaryReport
        $runnerExit = $LASTEXITCODE
        if (Test-Path -LiteralPath $temporaryReport -PathType Leaf) {
            Copy-Item -LiteralPath $temporaryReport -Destination $reportPath
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryReport -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryReport
        }
    }
    if ($runnerExit -ne 0) {
        throw "M4 differential comparison failed; report saved to $reportPath"
    }
}

Invoke-Differential $referenceSanmillConfig $ReferenceSanmillReport
Invoke-Differential $threeProjectConfig $ThreeProjectReport
