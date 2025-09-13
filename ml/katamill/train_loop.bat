@echo off
REM Katamill iterative training loop script for Windows
REM This script demonstrates a complete training pipeline with resume capability

REM Configuration
set DATA_DIR=data\katamill
set CHECKPOINT_DIR=checkpoints\katamill
set NUM_ITERATIONS=10
set GAMES_PER_ITER=5000
set MCTS_SIMS=400
set EPOCHS_PER_ITER=50
set WORKERS=8
set BATCH_SIZE=32

REM Create directories
if not exist %DATA_DIR% mkdir %DATA_DIR%
if not exist %CHECKPOINT_DIR% mkdir %CHECKPOINT_DIR%

echo Starting Katamill training loop...

REM Iteration 0: Bootstrap with random play
if not exist "%DATA_DIR%\iter_0.npz" (
    echo Iteration 0: Generating bootstrap data with random play...
    python -m ml.katamill.selfplay ^
        --output %DATA_DIR%\iter_0.npz ^
        --games %GAMES_PER_ITER% ^
        --workers %WORKERS% ^
        --mcts-sims 100
)

if not exist "%CHECKPOINT_DIR%\iter_0_final.pth" (
    echo Iteration 0: Training initial model...
    python -m ml.katamill.train ^
        --data %DATA_DIR%\iter_0.npz ^
        --epochs %EPOCHS_PER_ITER% ^
        --batch-size %BATCH_SIZE% ^
        --checkpoint-dir %CHECKPOINT_DIR%\iter_0
    
    REM Copy final model for next iteration
    copy %CHECKPOINT_DIR%\iter_0\katamill_final.pth %CHECKPOINT_DIR%\iter_0_final.pth
)

REM Main training loop
for /L %%i in (1,1,%NUM_ITERATIONS%) do (
    echo ========================================
    echo Iteration %%i/%NUM_ITERATIONS%
    echo ========================================
    
    set /a PREV_ITER=%%i-1
    set PREV_MODEL=%CHECKPOINT_DIR%\iter_!PREV_ITER!_final.pth
    set CURR_DATA=%DATA_DIR%\iter_%%i.npz
    set CURR_CHECKPOINT_DIR=%CHECKPOINT_DIR%\iter_%%i
    set CURR_MODEL=%CHECKPOINT_DIR%\iter_%%i_final.pth
    
    REM Generate self-play data with current best model
    if not exist "!CURR_DATA!" (
        echo Generating self-play data...
        python -m ml.katamill.selfplay ^
            --model !PREV_MODEL! ^
            --output !CURR_DATA! ^
            --games %GAMES_PER_ITER% ^
            --workers %WORKERS% ^
            --mcts-sims %MCTS_SIMS%
    )
    
    REM Split data for validation
    set TRAIN_DATA=%DATA_DIR%\iter_%%i_train.npz
    set VAL_DATA=%DATA_DIR%\iter_%%i_val.npz
    
    if not exist "!TRAIN_DATA!" (
        echo Splitting data for training/validation...
        python -m ml.katamill.data_loader split ^
            -i !CURR_DATA! ^
            -o %DATA_DIR%\iter_%%i
    )
    
    REM Train model (resume from previous iteration)
    if not exist "!CURR_MODEL!" (
        echo Training model...
        
        REM Check if we should resume from a checkpoint
        set RESUME_ARG=
        if exist "!CURR_CHECKPOINT_DIR!\katamill_latest.pth" (
            echo Resuming from latest checkpoint...
            set RESUME_ARG=--resume !CURR_CHECKPOINT_DIR!\katamill_latest.pth
        ) else if exist "!PREV_MODEL!" (
            echo Starting from previous iteration's model...
            set RESUME_ARG=--resume !PREV_MODEL!
        )
        
        python -m ml.katamill.train ^
            --data !TRAIN_DATA! ^
            --val-data !VAL_DATA! ^
            --epochs %EPOCHS_PER_ITER% ^
            --batch-size %BATCH_SIZE% ^
            --checkpoint-dir !CURR_CHECKPOINT_DIR! ^
            !RESUME_ARG!
        
        REM Copy final model for next iteration
        copy !CURR_CHECKPOINT_DIR!\katamill_final.pth !CURR_MODEL!
    )
    
    REM Evaluate model performance
    echo Evaluating model...
    python -m ml.katamill.evaluate ^
        --model !CURR_MODEL! ^
        --command selfplay ^
        --num-games 20
)

echo Training loop completed!
echo Final model: %CHECKPOINT_DIR%\iter_%NUM_ITERATIONS%_final.pth

REM Final evaluation
echo Running final evaluation...
python -m ml.katamill.evaluate ^
    --model %CHECKPOINT_DIR%\iter_%NUM_ITERATIONS%_final.pth ^
    --command selfplay ^
    --num-games 100

REM Create copy as best model
copy %CHECKPOINT_DIR%\iter_%NUM_ITERATIONS%_final.pth %CHECKPOINT_DIR%\katamill_best.pth
echo Best model copied to: %CHECKPOINT_DIR%\katamill_best.pth

pause
