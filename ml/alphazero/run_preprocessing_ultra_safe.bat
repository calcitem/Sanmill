@echo off
echo 🛡️ Ultra-Safe Perfect Database Preprocessing
echo ================================================================================

cd /d "%~dp0"
echo Current directory: %CD%

echo Setting ultra-safe environment variables...
set AZ_PREFETCH_DB=0
rem Disable prefetch to avoid memory issues

set PYTHONPATH=%CD%\..;%CD%;%CD%\..\perfect;%CD%\..\game;%PYTHONPATH%

echo Environment variables:
echo   AZ_PREFETCH_DB=%AZ_PREFETCH_DB%
echo   PYTHONPATH=%PYTHONPATH%

echo.
echo Testing Python imports...
python -c "import sys; sys.path.insert(0, '..'); import game.Game; print('✅ Game import OK')" 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Game import failed, trying to fix...
    python -c "import sys, os; sys.path.insert(0, os.path.join('..', 'game')); import Game; print('✅ Direct Game import OK')"
    if %ERRORLEVEL% NEQ 0 (
        echo ❌ Cannot import Game modules, aborting
        pause
        exit /b 1
    )
)

echo.
echo 🛡️ Starting ULTRA-SAFE preprocessing with maximum memory protection...
echo   - Workers: 2 (minimum for stability)
echo   - Memory threshold: 64GB (ultra-conservative)
echo   - Resume capability: ENABLED
echo   - Chunk-based processing: ENABLED
echo.

python perfect_db_preprocessor.py ^
    --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" ^
    --output-dir "G:\preprocessed_data" ^
    --max-workers 2 ^
    --memory-threshold 64.0

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ✅ Ultra-safe preprocessing completed!
    echo Viewing statistics...
    python perfect_db_preprocessor.py ^
        --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" ^
        --output-dir "G:\preprocessed_data" ^
        --stats ^
        --memory-threshold 64.0
) else (
    echo.
    echo ❌ Ultra-safe preprocessing failed with error code: %ERRORLEVEL%
    echo.
    echo 🔧 Troubleshooting suggestions:
    echo   1. Check if G: drive has enough free space (Hundreds of GBs required)
    echo   2. Run as Administrator
    echo   3. Close ALL other programs to free maximum memory
    echo   4. Restart computer to clear memory fragments
    echo   5. Consider processing in smaller batches
    echo.
    echo 📊 Memory information:
    python -c "import psutil; mem=psutil.virtual_memory(); print(f'Total: {mem.total/1024**3:.1f}GB, Available: {mem.available/1024**3:.1f}GB, Used: {mem.percent:.1f}%%')" 2>nul
)

echo.
echo Press any key to continue...
pause >nul
