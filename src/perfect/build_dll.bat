@echo off
setlocal

:: Find Visual Studio installation
for /f "usebackq delims=" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "VS_PATH=%%i"
)

if not defined VS_PATH (
    echo Visual Studio with C++ tools not found!
    exit /b 1
)

:: Setup build environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"

:: Change to perfect directory
cd /d "%~dp0"

echo Building perfect_db.dll...

:: Compile all source files and link into DLL
cl /nologo /LD /O2 /EHsc /MD /std:c++17 ^
   perfect_c_api.cpp ^
   perfect_api.cpp ^
   perfect_adaptor.cpp ^
   perfect_common.cpp ^
   perfect_debug.cpp ^
   perfect_errors.cpp ^
   perfect_eval_elem.cpp ^
   perfect_game_state.cpp ^
   perfect_game.cpp ^
   perfect_hash.cpp ^
   perfect_log.cpp ^
   perfect_move.cpp ^
   perfect_player.cpp ^
   perfect_rules.cpp ^
   perfect_sec_val.cpp ^
   perfect_sector_graph.cpp ^
   perfect_sector.cpp ^
   perfect_symmetries.cpp ^
   perfect_symmetries_slow.cpp ^
   perfect_wrappers.cpp ^
   ..\option.cpp ^
   ..\rule.cpp ^
   /I .. /I ..\..\include ^
   /Fe:perfect_db.dll

if %ERRORLEVEL% EQU 0 (
    echo Success! perfect_db.dll created.
    echo DLL location:
    dir perfect_db.dll
    echo.
) else (
    echo Build failed with error %ERRORLEVEL%
)

pause
