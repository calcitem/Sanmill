@echo off
REM Easy Katamill Training Script for Windows
REM This script provides a simple way to train Katamill models

echo ========================================
echo    Katamill Easy Training Script
echo ========================================
echo.

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo Error: Python not found. Please install Python 3.8+ and try again.
    pause
    exit /b 1
)

REM Check if PyTorch is available
python -c "import torch" >nul 2>&1
if errorlevel 1 (
    echo Error: PyTorch not found. Please install PyTorch:
    echo pip install torch
    pause
    exit /b 1
)

echo Python and PyTorch found. Starting training...
echo.

REM Prompt user for training mode
echo Choose training mode:
echo 1. Quick test (1-2 hours, testing model)
echo 2. Standard training (6-10 hours, strong model with early stopping)
echo 3. Strong training (12-20 hours, tournament model - max_moves=280, temp=0.6)
echo 4. Custom config (specify your own config file)
echo.

set /p choice="Enter your choice (1-4): "

if "%choice%"=="1" (
    echo Starting quick training...
    python easy_train.py --quick --max-moves 250 --temperature 0.8
) else if "%choice%"=="2" (
    echo Starting standard training...
    python easy_train.py --max-moves 250 --temperature 0.8
) else if "%choice%"=="3" (
    echo Starting strong training...
    echo This will take 12-20 hours for tournament-strength AI
    python easy_train.py --fresh-start --max-moves 280 --temperature 0.6 --workers 12
) else if "%choice%"=="4" (
    set /p config_file="Enter config file path: "
    if exist "%config_file%" (
        echo Starting training with config: %config_file%
        python easy_train.py --config "%config_file%"
    ) else (
        echo Config file not found: %config_file%
        echo Creating sample config...
        python easy_train.py --create-config sample_config.json
        echo Sample config created: sample_config.json
        echo Please edit it and run this script again.
        pause
        exit /b 1
    )
) else (
    echo Invalid choice. Please run the script again.
    pause
    exit /b 1
)

echo.
if errorlevel 1 (
    echo Training failed. Check the error messages above.
    pause
    exit /b 1
) else (
    echo ========================================
    echo    Training completed successfully!
    echo ========================================
    echo.
    echo Your trained model is ready. You can now:
    echo 1. Play against it: python pit.py --model output/katamill/best_model.pth --first human
    echo 2. Evaluate it: python evaluate.py --model output/katamill/best_model.pth --command selfplay
    echo.
    echo Check the training report: output/katamill/training_report.json
    echo.
)

pause
