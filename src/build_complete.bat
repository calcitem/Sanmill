@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

REM Complete Windows Build Script
REM Support choosing whether to include Perfect library

echo ========================================
echo    Sanmill Complete Build Script
echo ========================================
echo.
echo Choose build mode:
echo 1. Standard Edition (No Perfect Database)
echo 2. Complete Edition (Include Perfect Database)
echo 3. NNUE Specialized Edition (Optimized NNUE Support)
echo.
set /p CHOICE="Please enter your choice (1-3): "

REM Check compiler
where cl >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: cl compiler not found!
    echo Please run in one of the following environments:
    echo 1. Visual Studio Developer Command Prompt
    echo 2. Run vcvarsall.bat x64
    echo 3. Open terminal in Visual Studio
    pause
    exit /b 1
)

echo.
echo Detected compiler environment:
cl 2>&1 | findstr "Version"
echo.

REM Set base compilation parameters
set BASE_CXXFLAGS=/std:c++17 /O2 /EHsc /MT /DNDEBUG /DIS_64BIT /DUSE_POPCNT
set BASE_INCLUDES=/I..\include /I.
set BASE_DEFINES=/DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS

REM Main program source files
set MAIN_SOURCES=bitboard.cpp endgame.cpp engine_commands.cpp engine_controller.cpp evaluate.cpp main.cpp mcts.cpp mills.cpp misc.cpp movegen.cpp movepick.cpp opening_book.cpp option.cpp position.cpp rule.cpp search.cpp search_engine.cpp self_play.cpp thread.cpp thread_pool.cpp tt.cpp uci.cpp ucioption.cpp

REM Set compilation parameters based on user choice
if "%CHOICE%"=="1" (
    echo Building Standard Edition...
    set CXXFLAGS=%BASE_CXXFLAGS%
    set INCLUDES=%BASE_INCLUDES%
    set DEFINES=%BASE_DEFINES% /DNO_PERFECT_DB
    set SOURCES=%MAIN_SOURCES%
    set OUTPUT=sanmill_standard.exe
    set BUILD_PERFECT=0
) else if "%CHOICE%"=="2" (
    echo Building Complete Edition...
    set CXXFLAGS=%BASE_CXXFLAGS%
    set INCLUDES=%BASE_INCLUDES% /Iperfect
    set DEFINES=%BASE_DEFINES% /DGABOR_MALOM_PERFECT_AI
    set SOURCES=%MAIN_SOURCES%
    set OUTPUT=sanmill_complete.exe
    set BUILD_PERFECT=1
) else if "%CHOICE%"=="3" (
    echo Building NNUE Specialized Edition...
    set CXXFLAGS=%BASE_CXXFLAGS% /DUSE_NNUE
    set INCLUDES=%BASE_INCLUDES% /Innue /Iperfect
    set DEFINES=%BASE_DEFINES% /DGABOR_MALOM_PERFECT_AI /DUSE_NNUE
    set SOURCES=%MAIN_SOURCES%
    set OUTPUT=sanmill_nnue.exe
    set BUILD_PERFECT=1
) else (
    echo Invalid choice, using Standard Edition
    set CXXFLAGS=%BASE_CXXFLAGS%
    set INCLUDES=%BASE_INCLUDES%
    set DEFINES=%BASE_DEFINES% /DNO_PERFECT_DB
    set SOURCES=%MAIN_SOURCES%
    set OUTPUT=sanmill_standard.exe
    set BUILD_PERFECT=0
)

echo.
echo Build Parameters:
echo   Output File: %OUTPUT%
echo   Include Perfect: %BUILD_PERFECT%
echo.

REM Create directories
if not exist obj mkdir obj
if not exist obj\perfect mkdir obj\perfect
if not exist obj\nnue mkdir obj\nnue

REM Compile Perfect library (if needed)
if "%BUILD_PERFECT%"=="1" (
    echo Compiling Perfect library files...
    set PERFECT_OBJ=
    for %%f in (perfect\*.cpp) do (
        echo   Compiling %%f...
        cl !CXXFLAGS! !INCLUDES! !DEFINES! /c "%%f" /Fo"obj\perfect\%%~nf.obj" >nul
        if errorlevel 1 (
            echo ERROR: Failed to compile %%f!
            pause
            exit /b 1
        )
        set PERFECT_OBJ=!PERFECT_OBJ! "obj\perfect\%%~nf.obj"
    )
    echo   Perfect library compilation completed
    echo.
) else (
    set PERFECT_OBJ=
)

REM Compile NNUE files (if exist and needed)
if "%CHOICE%"=="3" (
    if exist nnue\*.cpp (
        echo Compiling NNUE files...
        set NNUE_OBJ=
        for %%f in (nnue\*.cpp) do (
            echo   Compiling %%f...
            cl !CXXFLAGS! !INCLUDES! !DEFINES! /c "%%f" /Fo"obj\nnue\%%~nf.obj" >nul
            if errorlevel 1 (
                echo ERROR: Failed to compile %%f!
                pause
                exit /b 1
            )
            set NNUE_OBJ=!NNUE_OBJ! "obj\nnue\%%~nf.obj"
        )
        echo   NNUE files compilation completed
        echo.
    ) else (
        set NNUE_OBJ=
    )
) else (
    set NNUE_OBJ=
)

REM Compile main program
echo Compiling main program files...
set MAIN_OBJ=
for %%f in (%MAIN_SOURCES%) do (
    echo   Compiling %%f...
    cl !CXXFLAGS! !INCLUDES! !DEFINES! /c "%%f" /Fo"obj\%%~nf.obj" >nul
    if errorlevel 1 (
        echo ERROR: Failed to compile %%f!
        pause
        exit /b 1
    )
    set MAIN_OBJ=!MAIN_OBJ! "obj\%%~nf.obj"
)

echo   Main program compilation completed
echo.

REM Link
echo Linking executable...
link /SUBSYSTEM:CONSOLE !MAIN_OBJ! !PERFECT_OBJ! !NNUE_OBJ! /OUT:!OUTPUT! >nul
if errorlevel 1 (
    echo ERROR: Linking failed!
    echo Trying to show detailed error information...
    link /SUBSYSTEM:CONSOLE !MAIN_OBJ! !PERFECT_OBJ! !NNUE_OBJ! /OUT:!OUTPUT!
    pause
    exit /b 1
)

echo.
echo ========================================
echo        Build Completed Successfully!
echo ========================================
echo.
echo Generated file: !OUTPUT!
if exist !OUTPUT! (
    echo File size: 
    for %%f in (!OUTPUT!) do echo   %%~zf bytes
    echo.
    
    echo Testing program...
    !OUTPUT! -h >nul 2>&1
    if errorlevel 1 (
        echo WARNING: Program test failed, may have runtime issues
    ) else (
        echo Program test passed!
    )
) else (
    echo ERROR: Output file not generated
)

echo.
echo Cleaning intermediate files...
if exist obj rmdir /s /q obj
if exist *.pdb del *.pdb >nul 2>&1

echo.
echo Build completed! Press any key to exit...
pause >nul
