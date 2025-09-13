@echo off
echo Perfect Database Complete Preprocessing
echo ================================================================================

cd /d "%~dp0"
echo Current directory: %CD%

echo Setting environment variables...
set AZ_PREFETCH_DB=1
set PYTHONPATH=%CD%;%CD%\..\perfect;%CD%\..\game;%PYTHONPATH%

echo Environment variables:
echo   AZ_PREFETCH_DB=%AZ_PREFETCH_DB%
echo   PYTHONPATH=%PYTHONPATH%

echo.
echo Verifying Python modules...
python -c "import sys; print('Python paths:'); [print(f'  {p}') for p in sys.path[:5]]"

echo.
echo Starting complete preprocessing with memory protection...
python perfect_db_preprocessor.py ^
    --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" ^
    --output-dir "G:\preprocessed_data" ^
    --max-workers 4 ^
    --memory-threshold 32.0

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Preprocessing completed!
    echo Viewing statistics...
    python perfect_db_preprocessor.py ^
        --perfect-db "E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted" ^
        --output-dir "G:\preprocessed_data" ^
        --stats ^
        --memory-threshold 32.0
) else (
    echo.
    echo Preprocessing failed with error code: %ERRORLEVEL%
)

pause
