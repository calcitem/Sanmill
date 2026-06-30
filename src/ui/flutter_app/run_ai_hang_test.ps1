# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

# AI hang smoke test runner (PowerShell).

param(
    [string]$Device = "windows"
)

Write-Host "==========================================" -ForegroundColor Green
Write-Host "AI Hang Smoke Test Runner" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Device: $Device" -ForegroundColor Yellow
Write-Host ""

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Flutter is not installed or not in PATH" -ForegroundColor Red
    exit 1
}

Set-Location $PSScriptRoot

$TestFile = "integration_test/ai_hang_smoke_test.dart"
if (-not (Test-Path $TestFile)) {
    Write-Host "Error: $TestFile not found" -ForegroundColor Red
    exit 1
}

flutter pub get
flutter test $TestFile -d $Device --timeout 480s

exit $LASTEXITCODE
