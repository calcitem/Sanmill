# AI Thinking Hang Test - First Move Only
# Tests only the first 2 moves (human move 1, AI move 2)
# This is the most common scenario where AI hangs occur

param(
    [string]$Device = "windows"
)

Write-Host "========================================" -ForegroundColor Blue
Write-Host "AI First Move Hang Detection Test" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""
Write-Host "Test Focus: " -NoNewline -ForegroundColor Yellow
Write-Host "AI's first response (move 2)"
Write-Host "Games: " -NoNewline -ForegroundColor Yellow
Write-Host "500 iterations"
Write-Host "Moves per game: " -NoNewline -ForegroundColor Yellow
Write-Host "Only 2 moves"
Write-Host "Expected time: " -NoNewline -ForegroundColor Yellow
Write-Host "~5-10 minutes"
Write-Host "Platform: " -NoNewline -ForegroundColor Yellow
Write-Host $Device
Write-Host ""
Write-Host "Starting test..." -ForegroundColor Green
Write-Host ""

# Run the test
flutter test integration_test/ai_thinking_hang_first_move_test.dart -d $Device

$ExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
if ($ExitCode -eq 0) {
    Write-Host "✓ Test completed" -ForegroundColor Green
} else {
    Write-Host "✗ Test failed with exit code $ExitCode" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Blue

exit $ExitCode


