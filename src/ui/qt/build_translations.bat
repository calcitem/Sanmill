@echo off
echo Building translation files...

REM Set Qt tools path (adjust this path according to your Qt installation)
set QT_TOOLS_PATH=C:\Qt\Tools\mingw1120_64\bin
set PATH=%QT_TOOLS_PATH%;%PATH%

REM Create translations directory if it doesn't exist
if not exist "translations" mkdir translations

REM Compile .ts files to .qm files using lrelease
echo Compiling English translation...
lrelease translations\mill-pro_en.ts -qm translations\mill-pro_en.qm

echo Compiling German translation...
lrelease translations\mill-pro_de.ts -qm translations\mill-pro_de.qm

echo Compiling Hungarian translation...
lrelease translations\mill-pro_hu.ts -qm translations\mill-pro_hu.qm

echo Compiling Chinese translation...
lrelease translations\mill-pro_zh_CN.ts -qm translations\mill-pro_zh_CN.qm

echo Translation files built successfully!
pause 