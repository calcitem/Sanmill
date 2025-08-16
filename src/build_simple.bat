@echo off
chcp 65001 >nul
REM Simplified Windows Build Script
REM Excludes Perfect library to avoid linking issues

echo ========================================
echo    Sanmill Simple Build Script
echo ========================================
echo.

REM Check compiler
where cl >nul 2>&1
if errorlevel 1 (
    echo ERROR: Please run in Visual Studio Developer Command Prompt
    pause
    exit /b 1
)

echo Using compiler: 
cl 2>&1 | findstr "Version"
echo.

REM Compilation parameters
set CXXFLAGS=/std:c++17 /O2 /EHsc /MT /DNDEBUG /DIS_64BIT
set INCLUDES=/I..\include /I.
set DEFINES=/DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS /DNO_PERFECT_DB
set SOURCES=bitboard.cpp endgame.cpp engine_commands.cpp engine_controller.cpp evaluate.cpp main.cpp mcts.cpp mills.cpp misc.cpp movegen.cpp movepick.cpp opening_book.cpp option.cpp position.cpp rule.cpp search.cpp search_engine.cpp self_play.cpp thread.cpp thread_pool.cpp tt.cpp uci.cpp ucioption.cpp

echo Compiling main program...
cl %CXXFLAGS% %INCLUDES% %DEFINES% %SOURCES% /Fe:sanmill_simple.exe /link /SUBSYSTEM:CONSOLE

if errorlevel 1 (
    echo ERROR: Compilation failed!
    pause
    exit /b 1
)

echo.
echo Compilation successful! Generated file: sanmill_simple.exe
echo.

REM Test program
echo Testing program...
sanmill_simple.exe -h

echo.
echo Done! Press any key to exit...
pause >nul
