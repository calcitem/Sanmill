@echo off
setlocal enabledelayedexpansion

:: Define which version of Qt to use, possible values are "Qt5" or "Qt6"
set "QtVersion=Qt6"

:: Clean repository
::git clean -fdx

:: Set Qt directories and system architecture depending on the chosen Qt version
if "%QtVersion%"=="Qt6" (
    if exist "%ProgramFiles% (Arm)" (
        set "Qt_BASE_DIR=C:\Qt\6.9.0\msvc2022_arm64"
        set "arch=ARM64"
    ) else (
        set "Qt_BASE_DIR=C:\Qt\6.9.0\msvc2022_64"
        set "arch=X64"
    )
) else if "%QtVersion%"=="Qt5" (
    set "Qt_BASE_DIR=C:\Qt\5.15.2\msvc2019_64"
    set "arch=X64"
)

:: Set derived paths after the if block to ensure proper variable expansion
set "Qt_DIR=!Qt_BASE_DIR!"
set "QT_TOOLS_DIR=!Qt_BASE_DIR!\bin"
set "WINDEPLOYQT_PATH=!QT_TOOLS_DIR!\windeployqt.exe"

:: Set CMAKE_PREFIX_PATH to Qt base directory (not cmake subdirectory)
set "CMAKE_PREFIX_PATH=!Qt_DIR!"

:: Add Qt tools to PATH for lrelease and other tools
set "PATH=!QT_TOOLS_DIR!;%PATH%"

echo Building Mill Game with multi-language support...
echo Qt Version: %QtVersion%
echo Qt Base Directory: !Qt_BASE_DIR!
echo Qt Tools Directory: !QT_TOOLS_DIR!
echo CMAKE_PREFIX_PATH: !CMAKE_PREFIX_PATH!
echo Architecture: !arch!

:: Check if Qt installation exists
if not exist "!Qt_DIR!" (
    echo Error: Qt installation not found at !Qt_DIR!
    echo Please check Qt installation path and update the script accordingly.
    pause
    exit /b 1
)

:: Check if lrelease tool is available for translation compilation
where /q lrelease
if %ERRORLEVEL% neq 0 (
    echo Warning: lrelease tool not found in PATH. Translation files may not be compiled.
    echo Please ensure Qt LinguistTools are installed and PATH is configured correctly.
    echo Qt Tools Directory: !QT_TOOLS_DIR!
) else (
    echo lrelease tool found. Translation compilation will be available.
)

:: Compile translation files before building
echo.
echo ======================================
echo Compiling translation files...
echo ======================================
call build_translations.bat
if %ERRORLEVEL% neq 0 (
    echo Warning: Translation compilation failed, but continuing with build...
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
    echo Error: No suitable Visual Studio version found.
    echo Please install Visual Studio 2019 or 2022.
    pause
    exit /b 1
)

echo Visual Studio Generator: !vsver!

:: Clean CMake cache if it exists to avoid configuration conflicts
if exist "CMakeCache.txt" (
    echo Cleaning existing CMake cache...
    del "CMakeCache.txt"
)

:: Generate project files with proper Qt configuration
echo.
echo ======================================
echo Generating CMake project files...
echo ======================================
echo Running: cmake -G "!vsver!" -A !arch! -DCMAKE_PREFIX_PATH="!CMAKE_PREFIX_PATH!" -DQt%QtVersion:~2%_DIR="!Qt_DIR!" .

cmake -G "!vsver!" -A !arch! -DCMAKE_PREFIX_PATH="!CMAKE_PREFIX_PATH!" -DQt%QtVersion:~2%_DIR="!Qt_DIR!" .

if %ERRORLEVEL% neq 0 (
    echo Error: CMake configuration failed.
    echo.
    echo Troubleshooting tips:
    echo 1. Verify Qt installation at: !Qt_DIR!
    echo 2. Check if Qt LinguistTools component is installed
    echo 3. Ensure Visual Studio is properly installed
    echo 4. Try cleaning the build directory and running again
    pause
    exit /b 1
)

:: Build and deploy Debug version
echo.
echo ======================================
echo Building Debug version...
echo ======================================
cmake --build . --target mill-pro --config Debug -j
if %ERRORLEVEL% neq 0 (
    echo Error: Debug build failed.
    pause
    exit /b 1
)

echo Deploying Debug version...
if exist "!WINDEPLOYQT_PATH!" (
    "!WINDEPLOYQT_PATH!" "Debug\mill-pro.exe"
    if %ERRORLEVEL% neq 0 (
        echo Warning: Debug deployment failed.
    )
) else (
    echo Warning: windeployqt not found at !WINDEPLOYQT_PATH!
)

:: Copy translation files to Debug directory if they exist
if exist "translations\*.qm" (
    echo Copying translation files to Debug directory...
    if not exist "Debug\translations" mkdir "Debug\translations"
    copy "translations\*.qm" "Debug\translations\" >nul
    echo Translation files copied to Debug\translations\
)

:: Build and deploy Release version
echo.
echo ======================================
echo Building Release version...
echo ======================================
cmake --build . --target mill-pro --config Release -j
if %ERRORLEVEL% neq 0 (
    echo Error: Release build failed.
    pause
    exit /b 1
)

echo Deploying Release version...
if exist "!WINDEPLOYQT_PATH!" (
    "!WINDEPLOYQT_PATH!" "Release\mill-pro.exe"
    if %ERRORLEVEL% neq 0 (
        echo Warning: Release deployment failed.
    )
) else (
    echo Warning: windeployqt not found at !WINDEPLOYQT_PATH!
)

:: Copy translation files to Release directory if they exist
if exist "translations\*.qm" (
    echo Copying translation files to Release directory...
    if not exist "Release\translations" mkdir "Release\translations"
    copy "translations\*.qm" "Release\translations\" >nul
    echo Translation files copied to Release\translations\
)

echo.
echo ======================================
echo Build completed successfully!
echo ======================================
echo Debug executable: Debug\mill-pro.exe
echo Release executable: Release\mill-pro.exe
echo.
echo Multi-language support:
if exist "translations\*.qm" (
    echo   Translation files available in both Debug and Release builds
    echo   Supported languages: English, German, Hungarian, Simplified Chinese
) else (
    echo   Translation files not found - multi-language features may not work
)

pause
