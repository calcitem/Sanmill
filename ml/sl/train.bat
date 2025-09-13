@echo off
chcp 65001 >nul 2>&1

echo ==========================================
echo   Nine Men's Morris Alpha Zero Trainer
echo ==========================================
echo.

REM Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found
    echo Please install Python 3.8 or higher
    pause
    exit /b 1
)

echo [SUCCESS] Python environment OK

REM Change to script directory
cd /d "%~dp0"

REM Check train.py exists
if not exist "train.py" (
    echo [ERROR] train.py not found
    echo Please ensure you are in the correct directory
    pause
    exit /b 1
)

echo [SUCCESS] Ready to start training
echo.

REM Run training
 python train_with_preprocessed.py --config train_with_preprocessed_high_performance.json --data-dir "G:\preprocessed_data" --chunked-training --chunk-memory 16.0 --memory-threshold 32.0 --no-swap --checkpoint-dir "G:\models_from_npz"

pause
