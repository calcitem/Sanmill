@echo off
echo 🧹 Chunk File Cleanup Tool (High-Performance Version)
echo ================================================================================

cd /d "%~dp0"
echo Current directory: %CD%

echo.
echo 🚀 High-performance preview mode - Scanning chunk files with 16 parallel threads...
python cleanup_chunks.py --output-dir "G:\preprocessed_data" --threads 16

echo.
echo If you need to perform the actual cleanup, please run:
echo    python cleanup_chunks.py --output-dir "G:\preprocessed_data" --threads 16 --execute
echo.
echo 💡 Performance Tips:
echo    - Use --threads N to adjust the number of parallel threads (8-16 recommended)
echo    - Use --force to skip the confirmation dialog
echo    - Execution mode is much faster than preview mode
echo.

pause