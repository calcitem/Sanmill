@echo off
echo Fast Cleanup Tool for Orphaned Chunks
echo ================================================================================

cd /d "%~dp0"
echo Current directory: %CD%

echo.
echo Ultra-fast preview mode - specialized for cleaning orphaned chunks...
echo This tool is 10-100x faster than full validation!
echo.

python cleanup_orphaned_chunks.py --output-dir "G:\preprocessed_data"

echo.
echo To execute fast deletion, run:
echo   python cleanup_orphaned_chunks.py --output-dir "G:\preprocessed_data" --execute
echo.
echo Ultra-fast cleanup tips:
echo   - This tool only deletes orphaned chunks from completed sectors, very safe
echo   - No detailed validation, extremely fast
echo   - For full validation, use cleanup_chunks.bat
echo.

pause
