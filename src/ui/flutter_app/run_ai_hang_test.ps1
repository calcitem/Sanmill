# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

# AI Thinking Hang Test Runner Script (PowerShell)
# Runs the AI thinking hang detection test on specified platform

param(
    [string]$Device = "windows"
)

Write-Host "==========================================" -ForegroundColor Green
Write-Host "AI Thinking Hang Detection Test Runner" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

Write-Host "Device: $Device" -ForegroundColor Yellow
Write-Host ""

# Check if Flutter is installed
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Flutter is not installed or not in PATH" -ForegroundColor Red
    exit 1
}

# Navigate to the flutter app directory
Set-Location $PSScriptRoot

Write-Host "Running pub get..." -ForegroundColor Yellow
flutter pub get

Write-Host ""
Write-Host "Starting AI hang detection test..." -ForegroundColor Yellow
Write-Host "This may take a while depending on the number of games configured." -ForegroundColor Yellow
Write-Host "The test will stop immediately if a hang is detected." -ForegroundColor Yellow
Write-Host ""

# Run the test
flutter test integration_test/ai_thinking_hang_test.dart -d $Device

$TestResult = $LASTEXITCODE

Write-Host ""
if ($TestResult -eq 0) {
    Write-Host "✓ Test completed successfully - No hangs detected" -ForegroundColor Green
} else {
    Write-Host "✗ Test failed - AI hang detected or test error occurred" -ForegroundColor Red
    Write-Host "Check the output above for detailed hang information" -ForegroundColor Yellow
}

Write-Host "==========================================" -ForegroundColor Green

exit $TestResult
