@echo off
REM NNUE GUI Quick Start Script for Windows
REM This script helps users quickly start the NNUE GUI without typing long commands

echo ====================================
echo Sanmill NNUE GUI Launcher
echo ====================================
echo.

REM Check if we're in the right directory
if not exist "nnue_pit.py" (
    echo Error: nnue_pit.py not found!
    echo Please run this script from the ml/nnue_training/ directory
    echo.
    pause
    exit /b 1
)

REM Check for Python
python --version >nul 2>&1
if errorlevel 1 (
    echo Error: Python not found!
    echo Please install Python 3.7+ and ensure it's in your PATH
    echo.
    pause
    exit /b 1
)

echo Searching for NNUE model files...
python start_nnue_gui.py --list-models

echo.
echo Starting NNUE GUI...
echo Press Ctrl+C to stop
echo.

REM Start the GUI
python start_nnue_gui.py

echo.
echo NNUE GUI has exited.
pause
