# SPDX-License-Identifier: AGPL-3.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MifRepository,

    [string]$Python = 'python',

    [string]$Capability = 'target/mif-interop/mif-suite-1.0-sanmill-capability.json',

    [string]$DeterministicReport = 'target/mif-interop/mif-suite-1.0-sanmill-deterministic-report.json',

    [string]$DifferentialReport = 'target/mif-interop/mif-suite-1.0-sanmill-differential-report.json'
)

$ErrorActionPreference = 'Stop'

$expectedMifCommit = '3ee7e57c7d4c7208be91f62914f344a587fb0f70'
$expectedWireCommit = '7e45d5a3fa970a535ed6a8a8ff5981aba4b9c978'
$expectedImplementationCommit = '7e86de7e8156a7d7f46a6a6179a8878051699505'
$expectedEvidenceCommit = '9d36d04b4d2a8cd5c660e9582426bedeb888b591'
$expectedSuiteJcs = 'sha256:81a5feabc281bfc4f830addabc2c6846d1f191bbbcf04e548f04b35dd358ae6f'
$expectedSuiteRaw = 'sha256:088ca33234289b06d9276aa4c430758222aa85d61621dee7bef4bfc6dcc069a4'
$expectedArtifactIndexRaw = 'sha256:5acbb714bed77e24eaac72fa5f24d2e54d1e17aaf568a8b60718c840281a6541'
$expectedDeterministicRaw = 'sha256:d11317a090300f8a47f77afed647bdbd236dcdb1996c0147a81c874fa39dfd82'
$expectedDifferentialRaw = 'sha256:560ef369fde248bd96d3468a4336442db1d970ede04f488821509e69925fd48e'
$expectedReleaseManifestRaw = 'sha256:b721cb2bd22e404ef2cac1ff570c7ea4d0b4859c97cbaba94a8acce241a00057'
$expectedRulesets = @(
    'sha256:173caf8189defd1ab7d4a3e8b9e26688a07fd77976bf09d56bff5fe0c273e1a1',
    'sha256:224f7e368e322a4cc8c1225a025fb548d5b41eb096d34b7ae0543182d1aa9393'
)
$expectedClasses = @('identity', 'key', 'position', 'replay', 'ruleset', 'transform')

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mifRoot = (Resolve-Path -LiteralPath $MifRepository).Path
$mifSafeRoot = $mifRoot.Replace('\', '/')
$suitePath = Join-Path $mifRoot 'mif-suite-1.0.json'
$artifactIndex = Join-Path $mifRoot 'artifacts/mif-1.0/index.json'
$deterministicCases = Join-Path $mifRoot 'interop/cases/deterministic-v1.json'
$differentialLaunch = Join-Path $mifRoot 'interop/differential-candidate-4-v1.json'
$releaseManifest = Join-Path $mifRoot 'release/mif-1.0-release-manifest.json'
$evidenceManifest = Join-Path $repositoryRoot 'interop/evidence/mif-suite-1.0-sanmill-adapter-evidence-2026-08-07.json'
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)

function Get-RawDigest([string]$Path) {
    return 'sha256:' + (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-RawDigest([string]$Path, [string]$Expected) {
    $actual = Get-RawDigest $Path
    if ($actual -ne $Expected) {
        throw "Raw SHA-256 mismatch for $Path`: expected $Expected, got $actual"
    }
}

function Resolve-OutputPath([string]$Path) {
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
        throw 'Evidence output must remain inside the Sanmill repository'
    }
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $resolved)) | Out-Null
    return $resolved
}

function Write-JsonLf([object]$Value, [string]$Path) {
    $json = ($Value | ConvertTo-Json -Depth 32) -replace "`r`n?", "`n"
    [System.IO.File]::WriteAllText($Path, "$json`n", $utf8WithoutBom)
}

function Invoke-AdapterCapabilities([string]$Adapter) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Adapter
    $null = $startInfo.ArgumentList.Add('mill')
    $null = $startInfo.ArgumentList.Add('mif-interop')
    $startInfo.WorkingDirectory = $repositoryRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = $utf8WithoutBom
    $startInfo.StandardOutputEncoding = $utf8WithoutBom
    $startInfo.StandardErrorEncoding = $utf8WithoutBom

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = $process.Start()
    if (-not $started) {
        throw 'Failed to start the Sanmill adapter'
    }
    $request = '{"protocol":"MIF-INTEROP/1","kind":"request","requestId":"suite-capabilities","operation":"capabilities","payload":{}}'
    $null = $process.StandardInput.Write("$request`n")
    $null = $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $null = $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Sanmill capability request failed: $stderr"
    }
    if ($stdout.Contains("`r")) {
        throw 'Sanmill capability response must use LF-only framing'
    }
    $lines = @($stdout -split "`n" | Where-Object Length -GT 0)
    if ($lines.Count -ne 1) {
        throw "Expected one capability response, got $($lines.Count)"
    }
    $response = $lines[0] | ConvertFrom-Json -Depth 32
    if ($response.protocol -ne 'MIF-INTEROP/1' -or
        $response.kind -ne 'response' -or
        $response.requestId -ne 'suite-capabilities' -or
        $response.operation -ne 'capabilities' -or
        $response.status -ne 'ok') {
        throw 'Sanmill returned an invalid capability response envelope'
    }
    if ($null -eq $response.result.capabilities) {
        throw 'Sanmill capability response is missing MIFCAP/1.0'
    }
    return [pscustomobject]@{ Capabilities = $response.result.capabilities }
}

function Invoke-Harness([string]$Runner, [string[]]$Arguments, [string]$Output) {
    $outputPath = Resolve-OutputPath $Output
    $temporaryReport = Join-Path $mifRoot ".mif-suite-report-$PID-$([System.Guid]::NewGuid().ToString('N')).json"
    try {
        $runnerOutput = @(& $Python -B $Runner @Arguments --report $temporaryReport)
        if ($LASTEXITCODE -ne 0) {
            throw "MIF harness failed: $Runner"
        }
        foreach ($line in $runnerOutput) {
            Write-Host $line
        }
        Copy-Item -LiteralPath $temporaryReport -Destination $outputPath
    } finally {
        if (Test-Path -LiteralPath $temporaryReport -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryReport
        }
    }
    return $outputPath
}

$actualMifCommit = (& git -c "safe.directory=$mifSafeRoot" -C $mifRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualMifCommit -ne $expectedMifCommit) {
    throw "MIF Suite commit mismatch: expected $expectedMifCommit, got $actualMifCommit"
}
& git -c "safe.directory=$mifSafeRoot" -C $mifRoot merge-base --is-ancestor $expectedWireCommit $expectedMifCommit
if ($LASTEXITCODE -ne 0) {
    throw 'MIF wire commit is not an ancestor of the Suite candidate commit'
}
$mifStatus = @(& git -c "safe.directory=$mifSafeRoot" -C $mifRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $mifStatus.Count -ne 0) {
    throw "MIF Suite worktree must be clean:`n$($mifStatus -join "`n")"
}

Assert-RawDigest $suitePath $expectedSuiteRaw
Assert-RawDigest $artifactIndex $expectedArtifactIndexRaw
Assert-RawDigest $deterministicCases $expectedDeterministicRaw
Assert-RawDigest $differentialLaunch $expectedDifferentialRaw
Assert-RawDigest $releaseManifest $expectedReleaseManifestRaw

$jcsProgram = @'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root))
from reference.jcs import jcs_digest

suite = json.loads((root / "mif-suite-1.0.json").read_text(encoding="utf-8"))
print(jcs_digest(suite))
'@
$actualSuiteJcs = (& $Python -B -c $jcsProgram $mifRoot).Trim()
if ($LASTEXITCODE -ne 0 -or $actualSuiteJcs -ne $expectedSuiteJcs) {
    throw "Suite JCS SHA-256 mismatch: expected $expectedSuiteJcs, got $actualSuiteJcs"
}
$declaredSuiteJcs = (Get-Content -Raw -LiteralPath (Join-Path $mifRoot 'mif-suite-1.0.sha256')).Trim()
if ($declaredSuiteJcs -ne $expectedSuiteJcs) {
    throw "Suite digest declaration mismatch: $declaredSuiteJcs"
}
$suite = Get-Content -Raw -LiteralPath $suitePath | ConvertFrom-Json -Depth 32
if (($suite.rulesets -join ',') -ne ($expectedRulesets -join ',')) {
    throw 'Suite ruleset semantic digests do not match the finalization pin'
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
if (-not (Test-Path -LiteralPath $sanmillAdapter -PathType Leaf)) {
    throw "Sanmill adapter does not exist: $sanmillAdapter"
}

$capabilityResult = @(Invoke-AdapterCapabilities $sanmillAdapter)[-1]
$capabilityDocument = $capabilityResult.Capabilities
if (($capabilityDocument.suites -join ',') -ne $expectedSuiteJcs) {
    throw "MIFCAP suites does not bind the Suite JCS identity: $($capabilityDocument.suites -join ',')"
}
$testedClasses = @($capabilityDocument.classes | Where-Object level -EQ 'tested' | ForEach-Object id)
if (($testedClasses -join ',') -ne ($expectedClasses -join ',')) {
    throw "MIFCAP tested classes mismatch: $($testedClasses -join ',')"
}
$conversion = $capabilityDocument.classes | Where-Object id -EQ 'conversion'
if ($null -eq $conversion -or $conversion.level -ne 'none' -or
    @($capabilityDocument.classes | Where-Object id -EQ 'full').Count -ne 0) {
    throw 'MIFCAP must not claim conversion or full conformance'
}
if ($capabilityDocument.annotations.mifSuiteCommit -ne $expectedMifCommit -or
    $capabilityDocument.annotations.mifSuiteJcs -ne $expectedSuiteJcs -or
    $capabilityDocument.annotations.mifSuiteRaw -ne $expectedSuiteRaw) {
    throw 'MIFCAP Suite annotations do not match the finalization pin'
}
$testedCorpus = @($capabilityDocument.testedCorpora)
if ($testedCorpus.Count -ne 1 -or
    $testedCorpus[0].digest -ne $expectedDeterministicRaw -or
    ($testedCorpus[0].classes -join ',') -ne ($expectedClasses -join ',')) {
    throw 'MIFCAP deterministic corpus evidence does not cover the required classes'
}
$capabilityRulesets = @($capabilityDocument.rulesets | ForEach-Object semanticDigest | Sort-Object)
if (($capabilityRulesets -join ',') -ne (($expectedRulesets | Sort-Object) -join ',')) {
    throw 'MIFCAP ruleset semantic digests do not match the Suite'
}
$capabilityPath = Resolve-OutputPath $Capability
Write-JsonLf $capabilityDocument $capabilityPath

$templatePath = Join-Path $repositoryRoot 'interop/adapters.three-project.mif-1.0.json'
$configObject = Get-Content -Raw -LiteralPath $templatePath | ConvertFrom-Json -Depth 16
$configObject.adapters = @($configObject.adapters | Where-Object name -NE 'nmm-llm-python')
$sanmillConfig = $configObject.adapters | Where-Object name -EQ 'sanmill-rust'
if ($null -eq $sanmillConfig) {
    throw 'Adapter configuration template is missing Sanmill'
}
$sanmillConfig.command = @($sanmillAdapter, 'mill', 'mif-interop')
$generatedDirectory = Join-Path $repositoryRoot 'target/mif-interop'
[System.IO.Directory]::CreateDirectory($generatedDirectory) | Out-Null
$configPath = Join-Path $generatedDirectory 'adapters.reference-sanmill.suite-1.0.generated.json'
Write-JsonLf $configObject $configPath

$deterministicPath = Invoke-Harness `
    (Join-Path $mifRoot 'tools/compare_mif_1_0_adapters.py') `
    @('--config', $configPath, '--cases', $deterministicCases) `
    $DeterministicReport
$deterministic = Get-Content -Raw -LiteralPath $deterministicPath | ConvertFrom-Json -Depth 32
if ($deterministic.protocol -ne 'MIF-INTEROP-REPORT/1' -or
    $deterministic.summary.passed -ne 58 -or
    $deterministic.summary.failed -ne 0) {
    throw 'Deterministic adapter report did not pass 58/58 cases'
}

$differentialPath = Invoke-Harness `
    (Join-Path $mifRoot 'tools/run_mif_1_0_differential.py') `
    @('--config', $configPath, '--launch', $differentialLaunch) `
    $DifferentialReport
$differential = Get-Content -Raw -LiteralPath $differentialPath | ConvertFrom-Json -Depth 32
if ($differential.protocol -ne 'MIF-INTEROP-DIFFERENTIAL-REPORT/1' -or
    $differential.status -ne 'passed' -or
    $differential.suiteConformance -ne $false -or
    $differential.summary.runsPassed -ne 10 -or
    $differential.summary.runsFailed -ne 0 -or
    $differential.summary.negativePassed -ne 5 -or
    $differential.summary.negativeFailed -ne 0) {
    throw 'Differential adapter report did not pass 10/10 runs and 5/5 mutations'
}

$capabilityRawSha256 = Get-RawDigest $capabilityPath
$deterministicReportRawSha256 = Get-RawDigest $deterministicPath
$differentialReportRawSha256 = Get-RawDigest $differentialPath
$publishedEvidence = Get-Content -Raw -LiteralPath $evidenceManifest | ConvertFrom-Json -Depth 32
if ($publishedEvidence.protocol -ne 'MIF-SUITE-ADAPTER-EVIDENCE/1' -or
    $publishedEvidence.implementationCommit -ne $expectedImplementationCommit -or
    $publishedEvidence.evidenceCommit -ne $expectedEvidenceCommit) {
    throw 'Published Suite adapter evidence has stale commit bindings'
}
if ($publishedEvidence.PSObject.Properties.Name -contains 'threeProjectEvidenceCommit') {
    throw 'Published Suite adapter evidence must not retain the legacy M4 commit binding'
}
if ($publishedEvidence.capabilityRawSha256 -ne $capabilityRawSha256 -or
    $publishedEvidence.deterministicReportRawSha256 -ne $deterministicReportRawSha256 -or
    $publishedEvidence.differentialReportRawSha256 -ne $differentialReportRawSha256) {
    throw 'Published Suite adapter evidence does not bind the generated raw artifacts'
}

[pscustomobject]@{
    EvidenceManifestRawSha256 = Get-RawDigest $evidenceManifest
    EvidenceCommit = $publishedEvidence.evidenceCommit
    CapabilityRawSha256 = $capabilityRawSha256
    DeterministicReportRawSha256 = $deterministicReportRawSha256
    DifferentialReportRawSha256 = $differentialReportRawSha256
    DeterministicConfigDigest = $deterministic.configDigest
    DifferentialConfigDigest = $differential.configDigest
    UnexplainedDifferences = 0
} | Format-List
