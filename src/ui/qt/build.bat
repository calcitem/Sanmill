@echo off
setlocal

:: Define which version of Qt to use, possible values are "Qt5" or "Qt6"
set "QtVersion=Qt6"

:: Clean repository
git clean -fdx

:: Set Qt directories and system architecture depending on the chosen Qt version
if "%QtVersion%"=="Qt6" (
    if exist "%ProgramFiles% (Arm)" (
        set "Qt_DIR=C:\Qt\6.7.1\msvc2019_arm64\lib\cmake\Qt6"
        set "arch=ARM64"
    ) else (
        set "Qt_DIR=C:\Qt\6.7.1\msvc2019_64\lib\cmake\Qt6"
        set "arch=X64"
    )
) else if "%QtVersion%"=="Qt5" (
    set "Qt_DIR=C:\Qt\5.15.2\msvc2019_64\lib\cmake\Qt5"
    set "arch=X64"
)

:: Set CMAKE_PREFIX_PATH to Qt_DIR
set "CMAKE_PREFIX_PATH=%Qt_DIR%"

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

:: Generate project files
cmake -G "%vsver%" -A %arch% -DCMAKE_PREFIX_PATH=%CMAKE_PREFIX_PATH% .

:: Build and deploy Debug version
cmake --build . --target mill-pro --config Debug -j
if "%QtVersion%"=="Qt6" (
    C:\Qt\Tools\QtDesignStudio\qt6_design_studio_reduced_version\bin\windeployqt "Debug\mill-pro.exe"
) else (
    C:\Qt\5.15.2\msvc2019_64\bin\windeployqt "Debug\mill-pro.exe"
)

:: Build and deploy Release version
cmake --build . --target mill-pro --config Release -j
if "%QtVersion%"=="Qt6" (
    C:\Qt\Tools\QtDesignStudio\qt6_design_studio_reduced_version\bin\windeployqt "Release\mill-pro.exe"
) else (
    C:\Qt\5.15.2\msvc2019_64\bin\windeployqt "Release\mill-pro.exe"
)
