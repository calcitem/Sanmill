@echo off
setlocal

:: Clean repository
git clean -fdx

:: Detect system architecture and set Qt6_DIR accordingly
if exist "%ProgramFiles%\Arm" (
    set "Qt6_DIR=C:\Qt\6.7.1\msvc2019_arm64\lib\cmake\Qt6"
) else (
    set "Qt6_DIR=C:\Qt\6.7.1\msvc2019_64\lib\cmake\Qt6"
)

:: Detect Visual Studio version
set "vsver="
for /f "tokens=*" %%i in ('dir "C:\Program Files\Microsoft Visual Studio\" /b /ad-h') do (
    if "%%i"=="2019" (
        set "vsver=Visual Studio 16 2019"
    ) else if "%%i"=="2022" (
        set "vsver=Visual Studio 17 2022"
    )
)

if not defined vsver (
    echo "No suitable Visual Studio version found."
    exit /b 1
)

:: Set system architecture based on previous detection
if exist "%ProgramFiles%\Arm" (
    set "arch=ARM64"
) else (
    set "arch=X64"
)

:: Generate project files
cmake -G "%vsver%" -A %arch% .

:: Build and deploy Debug version
cmake --build . --target mill-pro --config Debug
C:\Qt\Tools\QtDesignStudio\qt6_design_studio_reduced_version\bin\windeployqt "Debug\mill-pro.exe"

:: Build and deploy Release version
cmake --build . --target mill-pro --config Release
C:\Qt\Tools\QtDesignStudio\qt6_design_studio_reduced_version\bin\windeployqt "Release\mill-pro.exe"

