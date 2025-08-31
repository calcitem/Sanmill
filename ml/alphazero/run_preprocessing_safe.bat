@echo off
echo 🚀 Perfect Database Safe Preprocessing
echo ================================================================================

cd /d "%~dp0"
echo Current directory: %CD%

echo Setting environment variables...
set AZ_PREFETCH_DB=0
rem Disable prefetch to avoid memory issues

set PYTHONPATH=%CD%\..;%CD%;%CD%\..\perfect;%CD%\..\game;%PYTHONPATH%
rem Add ml root directory to the path

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
echo Starting SAFE preprocessing with reduced settings...
echo   - Workers: 4 (reduced from 24)
echo   - Prefetch: DISABLED
echo   - Sample mode: 10000 positions per sector
echo.

python perfect_db_preprocessor.py ^
    --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" ^
    --output-dir "G:\preprocessed_data" ^
    --max-workers 4 ^
    --max-positions 10000

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ✅ Safe preprocessing completed!
    echo Viewing statistics...
    python perfect_db_preprocessor.py ^
        --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" ^
        --output-dir "G:\preprocessed_data" ^
        --stats
) else (
    echo.
    echo ❌ Safe preprocessing failed with error code: %ERRORLEVEL%
    echo.
    echo 🔧 Troubleshooting suggestions:
    echo   1. Check if G: drive has enough free space
    echo   2. Run as Administrator
    echo   3. Close other programs to free memory
    echo   4. Try with even fewer workers: --max-workers 1
)

pause


