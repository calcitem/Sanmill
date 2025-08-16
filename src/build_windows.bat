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

REM 设置编译参数
set CXXFLAGS=/std:c++17 /O2 /EHsc /MT /DNDEBUG /DIS_64BIT /DUSE_POPCNT /DUSE_SSE2 /DUSE_SSE41 /DUSE_SSSE3
set INCLUDES=/I..\include /I. /Iperfect
set DEFINES=/DUSE_PTHREADS /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS
set LDFLAGS=/SUBSYSTEM:CONSOLE

REM 创建输出目录
if not exist obj mkdir obj
if not exist obj\perfect mkdir obj\perfect

echo 编译 Perfect 库文件...

REM 编译 Perfect 库
for %%f in (perfect\*.cpp) do (
    echo 编译 %%f...
    cl %CXXFLAGS% %INCLUDES% %DEFINES% /c "%%f" /Fo"obj\%%~nf.obj"
    if errorlevel 1 (
        echo ERROR: 编译 %%f 失败！
        pause
        exit /b 1
    )
)

echo.
echo 编译主程序文件...

REM 编译主程序文件
set MAIN_SOURCES=bitboard.cpp endgame.cpp engine_commands.cpp engine_controller.cpp evaluate.cpp main.cpp mcts.cpp mills.cpp misc.cpp movegen.cpp movepick.cpp opening_book.cpp option.cpp position.cpp rule.cpp search.cpp search_engine.cpp self_play.cpp thread.cpp thread_pool.cpp tt.cpp uci.cpp ucioption.cpp

for %%f in (%MAIN_SOURCES%) do (
    echo 编译 %%f...
    cl %CXXFLAGS% %INCLUDES% %DEFINES% /c "%%f" /Fo"obj\%%~nf.obj"
    if errorlevel 1 (
        echo ERROR: 编译 %%f 失败！
        pause
        exit /b 1
    )
)

REM 编译 NNUE 文件
echo.
echo 编译 NNUE 文件...
if exist nnue\*.cpp (
    for %%f in (nnue\*.cpp) do (
        echo 编译 %%f...
        cl %CXXFLAGS% %INCLUDES% %DEFINES% /Innue /c "%%f" /Fo"obj\%%~nf.obj"
        if errorlevel 1 (
            echo ERROR: 编译 %%f 失败！
            pause
            exit /b 1
        )
    )
)

echo.
echo 链接可执行文件...

REM 收集所有目标文件
set OBJ_FILES=
for %%f in (obj\*.obj) do set OBJ_FILES=!OBJ_FILES! "%%f"

REM 启用延迟变量扩展
setlocal EnableDelayedExpansion

REM 重新收集目标文件
set OBJ_FILES=
for %%f in (obj\*.obj) do (
    set OBJ_FILES=!OBJ_FILES! "%%f"
)

REM 链接
echo 链接中...
link %LDFLAGS% !OBJ_FILES! /OUT:sanmill.exe
if errorlevel 1 (
    echo ERROR: 链接失败！
    pause
    exit /b 1
)

echo.
echo ========================================
echo           编译成功完成！
echo ========================================
echo.
echo 可执行文件: sanmill.exe
echo 大小: 
dir sanmill.exe | findstr "sanmill.exe"
echo.

REM 测试编译的程序
echo 测试编译的程序...
sanmill.exe -h
if errorlevel 1 (
    echo WARNING: 程序可能有问题
) else (
    echo 程序运行正常！
)

echo.
echo 编译完成！按任意键退出...
pause >nul
