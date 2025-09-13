@echo off
REM SPSA Parameter Tuning Batch Script for Sanmill (Windows)
REM This script provides an easy way to run SPSA parameter tuning with common configurations

setlocal enabledelayedexpansion

REM Default values
set ITERATIONS=1000
set GAMES=100
set THREADS=8
set CONFIG_FILE=
set PARAMS_FILE=
set OUTPUT_FILE=tuned_parameters.txt
set LOG_FILE=spsa_tuning.log
set RESUME_FILE=
set INTERACTIVE=false
set QUICK_MODE=false

REM Parse command line arguments
:parse_args
if "%~1"=="" goto end_parse
if "%~1"=="-h" goto show_usage
if "%~1"=="--help" goto show_usage
if "%~1"=="-i" (
    set ITERATIONS=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--iterations" (
    set ITERATIONS=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="-g" (
    set GAMES=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--games" (
    set GAMES=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="-t" (
    set THREADS=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--threads" (
    set THREADS=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="-c" (
    set CONFIG_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--config" (
    set CONFIG_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="-p" (
    set PARAMS_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--params" (
    set PARAMS_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="-o" (
    set OUTPUT_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--output" (
    set OUTPUT_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="-r" (
    set RESUME_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="--resume" (
    set RESUME_FILE=%~2
    shift
    shift
    goto parse_args
)
if "%~1"=="-I" (
    set INTERACTIVE=true
    shift
    goto parse_args
)
if "%~1"=="--interactive" (
    set INTERACTIVE=true
    shift
    goto parse_args
)
if "%~1"=="--fast" (
    set ITERATIONS=200
    set GAMES=50
    echo [INFO] Using fast configuration
    shift
    goto parse_args
)
if "%~1"=="--standard" (
    set ITERATIONS=1000
    set GAMES=100
    echo [INFO] Using standard configuration
    shift
    goto parse_args
)
if "%~1"=="--thorough" (
    set ITERATIONS=2000
    set GAMES=200
    echo [INFO] Using thorough configuration
    shift
    goto parse_args
)
if "%~1"=="--ultra" (
    set ITERATIONS=5000
    set GAMES=500
    echo [INFO] Using ultra thorough configuration
    shift
    goto parse_args
)
if "%~1"=="--clean" (
    goto clean_results
)
echo [ERROR] Unknown option: %~1
goto show_usage

:end_parse

REM Main execution
echo ========================================
echo SPSA Parameter Tuning for Sanmill
echo ========================================

REM Check if tuner exists
if not exist "spsa_tuner.exe" (
    echo [INFO] SPSA tuner not found, attempting to compile...
    if exist "spsa_tuner_makefile" (
        make -f spsa_tuner_makefile
        if !errorlevel! neq 0 (
            echo [ERROR] Failed to compile SPSA tuner
            exit /b 1
        )
        echo [SUCCESS] Successfully compiled SPSA tuner
    ) else (
        echo [ERROR] Makefile not found. Please compile manually.
        exit /b 1
    )
)

REM Show configuration
echo.
echo [INFO] Configuration Summary:
echo   Iterations: !ITERATIONS!
echo   Games per evaluation: !GAMES!
echo   Threads: !THREADS!
echo   Output file: !OUTPUT_FILE!
echo   Log file: !LOG_FILE!
if not "!CONFIG_FILE!"=="" echo   Config file: !CONFIG_FILE!
if not "!PARAMS_FILE!"=="" echo   Initial parameters: !PARAMS_FILE!
if not "!RESUME_FILE!"=="" echo   Resume from: !RESUME_FILE!
echo.

REM Build command line arguments
set CMD_ARGS=--iterations !ITERATIONS! --games !GAMES! --threads !THREADS! --output "!OUTPUT_FILE!" --log "!LOG_FILE!"

if not "!CONFIG_FILE!"=="" set CMD_ARGS=!CMD_ARGS! --config "!CONFIG_FILE!"
if not "!PARAMS_FILE!"=="" set CMD_ARGS=!CMD_ARGS! --params "!PARAMS_FILE!"
if not "!RESUME_FILE!"=="" set CMD_ARGS=!CMD_ARGS! --resume "!RESUME_FILE!"
if "!INTERACTIVE!"=="true" set CMD_ARGS=!CMD_ARGS! --interactive

REM Ask for confirmation unless in quick mode
if not "!QUICK_MODE!"=="true" if not "!INTERACTIVE!"=="true" (
    echo.
    set /p "CONFIRM=Continue with tuning? (y/N): "
    if /i not "!CONFIRM!"=="y" if /i not "!CONFIRM!"=="yes" (
        echo [INFO] Tuning cancelled
        exit /b 0
    )
)

REM Start tuning
echo [INFO] Starting SPSA parameter tuning...
echo [INFO] Command: spsa_tuner.exe !CMD_ARGS!

spsa_tuner.exe !CMD_ARGS!

if !errorlevel! equ 0 (
    echo [SUCCESS] Tuning completed successfully!
    if exist "!OUTPUT_FILE!" (
        echo [SUCCESS] Best parameters saved to: !OUTPUT_FILE!
    )
    if exist "!LOG_FILE!" (
        echo [INFO] Detailed log available in: !LOG_FILE!
    )
) else (
    echo [ERROR] Tuning failed or was interrupted
    if exist "spsa_checkpoint.txt" (
        echo [INFO] You can resume with: %~nx0 --resume spsa_checkpoint.txt
    )
    exit /b 1
)

goto :eof

:show_usage
echo SPSA Parameter Tuning Script for Sanmill
echo.
echo Usage: %~nx0 [options]
echo.
echo Options:
echo   -h, --help              Show this help message
echo   -i, --iterations N      Number of iterations (default: 1000)
echo   -g, --games N           Games per evaluation (default: 100)
echo   -t, --threads N         Number of threads (default: 8)
echo   -c, --config FILE       Configuration file
echo   -p, --params FILE       Initial parameters file
echo   -o, --output FILE       Output file for best parameters (default: tuned_parameters.txt)
echo   -r, --resume FILE       Resume from checkpoint file
echo   -I, --interactive       Run in interactive mode
echo   --clean                 Clean previous results and start fresh
echo.
echo Predefined configurations:
echo   --fast                  Fast tuning (200 iterations, 50 games)
echo   --standard              Standard tuning (1000 iterations, 100 games)
echo   --thorough              Thorough tuning (2000 iterations, 200 games)
echo   --ultra                 Ultra thorough (5000 iterations, 500 games)
echo.
echo Examples:
echo   %~nx0 --fast                           # Quick tuning session
echo   %~nx0 --standard --threads 16          # Standard tuning with 16 threads
echo   %~nx0 --config my_config.txt           # Use custom configuration
echo   %~nx0 --resume checkpoint.txt          # Resume previous session
echo   %~nx0 --interactive                    # Interactive mode
exit /b 0

:clean_results
echo [INFO] Cleaning previous results...
if exist "spsa_checkpoint.txt" (
    set timestamp=%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
    set timestamp=!timestamp: =0!
    copy "spsa_checkpoint.txt" "spsa_checkpoint.txt.backup.!timestamp!" >nul
    echo [INFO] Backed up spsa_checkpoint.txt to spsa_checkpoint.txt.backup.!timestamp!
    del "spsa_checkpoint.txt"
)
if exist "!LOG_FILE!" (
    set timestamp=%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
    set timestamp=!timestamp: =0!
    copy "!LOG_FILE!" "!LOG_FILE!.backup.!timestamp!" >nul
    echo [INFO] Backed up !LOG_FILE! to !LOG_FILE!.backup.!timestamp!
    del "!LOG_FILE!"
)
if exist "best_parameters.txt" del "best_parameters.txt"
if exist "final_parameters.txt" del "final_parameters.txt"
if exist "final_checkpoint.txt" del "final_checkpoint.txt"
echo [SUCCESS] Cleaned previous results
exit /b 0
