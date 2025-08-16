@echo off
chcp 65001 >nul
REM Windows batch script for compiling Sanmill
REM Uses Visual Studio cl compiler
REM Must be run in Visual Studio Developer Command Prompt

echo ========================================
echo    Sanmill Windows Build Script
echo ========================================
echo.

REM Check if in VS Developer Command Prompt
where cl >nul 2>&1
if errorlevel 1 (
    echo ERROR: cl compiler not found!
    echo Please run this script in Visual Studio Developer Command Prompt
    echo or run "vcvarsall.bat x64" to set up environment
    pause
    exit /b 1
)

echo Detected Visual Studio compiler environment
cl 2>&1 | findstr "Version"
echo.

REM Set compilation parameters
set CXXFLAGS=/std:c++17 /O2 /EHsc /MT /DNDEBUG /DIS_64BIT /DUSE_POPCNT /DUSE_SSE2 /DUSE_SSE41 /DUSE_SSSE3
set INCLUDES=/I..\include /I. /Iperfect
set DEFINES=/DUSE_PTHREADS /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS
set LDFLAGS=/SUBSYSTEM:CONSOLE

REM Create output directory
if not exist obj mkdir obj
if not exist obj\perfect mkdir obj\perfect

echo Compiling Perfect library files...

REM Compile Perfect library
for %%f in (perfect\*.cpp) do (
    echo Compiling %%f...
    cl %CXXFLAGS% %INCLUDES% %DEFINES% /c "%%f" /Fo"obj\%%~nf.obj"
    if errorlevel 1 (
        echo ERROR: Failed to compile %%f!
        pause
        exit /b 1
    )
)

echo.
echo Compiling main program files...

REM Compile main program files
set MAIN_SOURCES=bitboard.cpp endgame.cpp engine_commands.cpp engine_controller.cpp evaluate.cpp main.cpp mcts.cpp mills.cpp misc.cpp movegen.cpp movepick.cpp opening_book.cpp option.cpp position.cpp rule.cpp search.cpp search_engine.cpp self_play.cpp thread.cpp thread_pool.cpp tt.cpp uci.cpp ucioption.cpp

for %%f in (%MAIN_SOURCES%) do (
    echo Compiling %%f...
    cl %CXXFLAGS% %INCLUDES% %DEFINES% /c "%%f" /Fo"obj\%%~nf.obj"
    if errorlevel 1 (
        echo ERROR: Failed to compile %%f!
        pause
        exit /b 1
    )
)

REM Compile NNUE files
echo.
echo Compiling NNUE files...
if exist nnue\*.cpp (
    for %%f in (nnue\*.cpp) do (
        echo Compiling %%f...
        cl %CXXFLAGS% %INCLUDES% %DEFINES% /Innue /c "%%f" /Fo"obj\%%~nf.obj"
        if errorlevel 1 (
            echo ERROR: Failed to compile %%f!
            pause
            exit /b 1
        )
    )
)

echo.
echo Linking executable...

REM Collect all object files
setlocal EnableDelayedExpansion
set OBJ_FILES=
for %%f in (obj\*.obj) do (
    set OBJ_FILES=!OBJ_FILES! "%%f"
)

REM Link
echo Linking...
link %LDFLAGS% !OBJ_FILES! /OUT:sanmill.exe
if errorlevel 1 (
    echo ERROR: Linking failed!
    pause
    exit /b 1
)

echo.
echo ========================================
echo        Build Completed Successfully!
echo ========================================
echo.
echo Executable file: sanmill.exe
echo Size: 
dir sanmill.exe | findstr "sanmill.exe"
echo.

REM Test the compiled program
echo Testing the compiled program...
sanmill.exe -h
if errorlevel 1 (
    echo WARNING: Program may have issues
) else (
    echo Program runs correctly!
)

echo.
echo Build completed! Press any key to exit...
pause >nul
