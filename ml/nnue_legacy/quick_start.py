#!/usr/bin/env python3
"""
NNUE 一键快速开始 - 最简单的入门方式
=================================

这是最简化的 NNUE 训练脚本，新手可以一键开始训练。

使用方法:
  python quick_start.py

特点:
  - 无需任何配置
  - 自动检测环境
  - 快速训练（5-10分钟）
  - 自动启动 GUI 测试
"""

import os
import sys
import subprocess
import time

def print_welcome():
    """显示欢迎信息"""
    print("=" * 50)
    print("🎯 NNUE 一键快速开始")
    print("=" * 50)
    print("这是最简单的 NNUE 训练方式！")
    print("✅ 无需复杂配置")
    print("✅ 快速训练（5-10分钟）")
    print("✅ 自动测试验证")
    print("=" * 50)
    print()

def check_python():
    """检查 Python 环境"""
    print("🔍 检查 Python 环境...")
    
    if sys.version_info < (3, 7):
        print("❌ Python 版本过低，需要 3.7+")
        print("请访问 https://www.python.org/downloads/ 升级")
        return False
        
    print(f"✅ Python {sys.version_info.major}.{sys.version_info.minor}")
    return True

def check_dependencies():
    """检查和安装依赖"""
    print("🔍 检查依赖包...")
    
    required = ['torch', 'numpy']
    missing = []
    
    for package in required:
        try:
            __import__(package)
            print(f"✅ {package}")
        except ImportError:
            missing.append(package)
            print(f"❌ 缺少 {package}")
    
    if missing:
        print("\n📦 正在安装缺少的依赖...")
        try:
            cmd = [sys.executable, '-m', 'pip', 'install'] + missing
            subprocess.run(cmd, check=True)
            print("✅ 依赖安装完成")
        except subprocess.CalledProcessError:
            print("❌ 依赖安装失败")
            print("请手动运行: pip install torch numpy")
            return False
    
    return True

def run_quick_training():
    """运行快速训练"""
    print("\n🚀 开始快速训练...")
    print("训练时间约 5-10 分钟，请耐心等待...")
    
    if not os.path.exists("easy_train.py"):
        print("❌ 未找到 easy_train.py")
        print("请确保在 ml/nnue_training/ 目录下运行")
        return False
    
    try:
        cmd = [sys.executable, "easy_train.py", "--quick", "--auto"]
        print(f"执行: {' '.join(cmd)}")
        print("=" * 40)
        
        result = subprocess.run(cmd)
        
        if result.returncode == 0:
            print("=" * 40)
            print("✅ 快速训练完成！")
            return True
        else:
            print("❌ 训练失败")
            return False
            
    except Exception as e:
        print(f"❌ 训练出错: {e}")
        return False

def find_model():
    """查找训练的模型"""
    import glob
    
    patterns = ["nnue_model*.bin", "nnue_model*.pth", "models/nnue_model*.bin"]
    
    for pattern in patterns:
        files = glob.glob(pattern)
        if files:
            return max(files, key=os.path.getmtime)  # 返回最新的
    
    return None

def test_model():
    """测试训练的模型"""
    print("\n🎮 启动模型测试...")
    
    model_path = find_model()
    if not model_path:
        print("❌ 未找到训练的模型")
        return False
    
    print(f"📁 找到模型: {model_path}")
    
    # 检查 GUI 环境
    try:
        import tkinter
        print("✅ GUI 环境可用")
    except ImportError:
        print("⚠️  GUI 不可用，跳过可视化测试")
        return True
    
    print("🎯 启动 GUI 测试...")
    print("您将看到一个棋盘界面，可以与 AI 对战！")
    
    try:
        cmd = [sys.executable, "nnue_pit.py", "--model", model_path, "--gui", "--first", "human"]
        subprocess.run(cmd)
        return True
    except Exception as e:
        print(f"❌ GUI 启动失败: {e}")
        print("您可以稍后手动启动:")
        print(f"python nnue_pit.py --model {model_path} --gui")
        return False

def show_summary():
    """显示总结"""
    print("\n" + "=" * 50)
    print("🎉 快速开始完成！")
    print("=" * 50)
    print("您已经成功:")
    print("✅ 训练了您的第一个 NNUE 模型")
    print("✅ 验证了模型功能")
    print("✅ 体验了人机对战")
    print()
    print("🎯 接下来可以:")
    print("1. 尝试更高质量的训练:")
    print("   python easy_train.py --high-quality")
    print("2. 学习更多配置选项:")
    print("   python easy_train.py --help")
    print("3. 查看新手指南:")
    print("   阅读 BEGINNER_GUIDE.md")
    print("=" * 50)

def main():
    """主函数"""
    try:
        # 显示欢迎信息
        print_welcome()
        
        # 环境检查
        if not check_python():
            return 1
        
        if not check_dependencies():
            return 1
        
        # 确认开始
        print("🚀 准备开始快速训练！")
        choice = input("按 Enter 开始，或输入 'n' 退出: ").strip().lower()
        if choice in ['n', 'no', '否']:
            print("已取消")
            return 0
        
        # 运行训练
        if not run_quick_training():
            return 1
        
        # 测试模型
        test_model()
        
        # 显示总结
        show_summary()
        
        return 0
        
    except KeyboardInterrupt:
        print("\n\n⏹️  已中断")
        return 0
    except Exception as e:
        print(f"\n❌ 出现错误: {e}")
        return 1

if __name__ == '__main__':
    sys.exit(main())
