@echo off
setlocal enabledelayedexpansion

REM --- Configurable parameters (without quotes) ---
set DB=E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted
set OUT=E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted\std_traps.sec2

REM --- Performance Tuning ---
REM Optional: limit threads to reduce memory (uncomment to use)
set SANMILL_TRAP_THREADS=8
REM Optional: use sub-threads to speed up large sector files (e.g., 2 or 4)
set SANMILL_INTRA_SECTOR_THREADS=4
REM Optional: increase eval cache size per thread (e.g., 10000) if you have ample RAM
set SANMILL_TRAP_CACHE_SIZE=200000

REM --- Derive progress file path ---
set PROG="%OUT%.progress"

REM --- Compute total sectors ---
set TOTAL=0
for %%F in ("%DB%\std_*.sec2") do (
  set /a TOTAL+=1
)
if %TOTAL%==0 (
  echo [trap] No sectors found under "%DB%"
  goto :END
)

echo [trap] Total sectors: %TOTAL%
echo [trap] Starting/resuming trap extraction with auto-retry...

:LOOP
  REM --- Count completed sectors from progress file ---
  set DONE=0
  if exist %PROG% (
    for /f "usebackq delims=" %%L in (%PROG%) do (
      set /a DONE+=1
    )
  )

  REM --- Compute percent ---
  set PCT=0
  if not %TOTAL%==0 (
    set /a PCT=DONE*100/TOTAL
  )

  REM --- We need !DONE! and !PCT! here because they are set inside the LOOP ---
  echo [trap] Progress: !DONE! / %TOTAL% ( !PCT!%% )

  REM --- Run the Python wrapper ---
  python -m ml.perfect.build_trap_sec2 --db "%DB%" --out "%OUT%"
  set RET=%ERRORLEVEL%

  if %RET%==0 (
    echo [trap] Completed successfully.
    goto :END
  ) else (
    echo [trap] Builder exited with code %RET%. Will retry after delay...
    timeout /t 5 /nobreak >nul
    goto :LOOP
  )

:END
endlocal
