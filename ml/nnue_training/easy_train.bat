@echo off
REM NNUE 傻瓜化训练工具 - Windows 启动器
REM ==========================================

echo ==========================================
echo 🎯 Sanmill NNUE 傻瓜化训练工具
echo ==========================================
echo.

REM 检查是否在正确目录
if not exist "easy_train.py" (
    echo ❌ 错误: easy_train.py 未找到！
    echo 请在 ml/nnue_training/ 目录下运行此脚本
    echo.
    pause
    exit /b 1
)

REM 检查 Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ 错误: 未找到 Python！
    echo 请安装 Python 3.7+ 并确保在 PATH 中
    echo 下载地址: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

echo ✅ Python 环境检查通过
echo.

echo 请选择训练模式:
echo   1. 快速训练 (5-10分钟，适合测试)
echo   2. 标准训练 (30-60分钟，推荐)
echo   3. 高质量训练 (2-4小时，最佳效果)
echo   4. 交互式选择
echo.

set /p choice="请输入选择 (1-4): "

if "%choice%"=="1" (
    echo 🚀 启动快速训练...
    python easy_train.py --quick --auto
) else if "%choice%"=="2" (
    echo 🚀 启动标准训练...
    python easy_train.py --auto
) else if "%choice%"=="3" (
    echo 🚀 启动高质量训练...
    python easy_train.py --high-quality --auto
) else if "%choice%"=="4" (
    echo 🚀 启动交互式训练...
    python easy_train.py
) else (
    echo ❌ 无效选择
    goto :menu
)

echo.
echo 训练完成！
pause
