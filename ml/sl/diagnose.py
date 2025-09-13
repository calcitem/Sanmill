#!/usr/bin/env python3
"""
Diagnostic script for Alpha Zero training environment

This script checks if the training environment is configured correctly.
"""

import os
import sys
import importlib.util
from pathlib import Path


def check_python_version():
    """Checks the Python version."""
    print("🐍 Python Environment Check:")
    print(f"  Version: {sys.version}")
    print(f"  Path: {sys.executable}")

    version_info = sys.version_info
    if version_info.major >= 3 and version_info.minor >= 8:
        print("  ✅ Python version is sufficient (>= 3.8)")
        return True
    else:
        print("  ❌ Python version is too old, 3.8 or higher is required")
        return False


def check_required_packages():
    """Checks for necessary Python packages."""
    print("\n📦 Python Package Check:")

    required_packages = [
        'numpy',
        'torch',
        'pathlib',
        'dataclasses',
        'typing',
        'logging',
        'multiprocessing',
        'concurrent.futures',
        'threading'
    ]

    missing_packages = []

    for package in required_packages:
        try:
            if package in ['pathlib', 'dataclasses', 'typing', 'logging', 'multiprocessing', 'concurrent.futures', 'threading']:
                # These are standard libraries
                __import__(package)
            else:
                # Third-party packages
                __import__(package)
            print(f"  ✅ {package}")
        except ImportError:
            print(f"  ❌ {package} (Missing)")
            missing_packages.append(package)

    if missing_packages:
        print(f"\n⚠️ Missing packages: {', '.join(missing_packages)}")
        print(f"Installation command: pip install {' '.join(missing_packages)}")
        return False

    return True


def check_project_structure():
    """Checks the project structure."""
    print("\n📁 Project Structure Check:")

    current_dir = Path(__file__).parent
    parent_dir = current_dir.parent

    print(f"  Current directory: {current_dir}")
    print(f"  Parent directory: {parent_dir}")

    # Check files in the sl directory
    sl_files = [
        'trainer.py',
        'config.py',
        'neural_network.py',
        'mcts.py',
        'easy_train.py',
        'run_training.py'
    ]

    print(f"\n  Alpha Zero Module:")
    missing_az_files = []
    for file in sl_files:
        file_path = current_dir / file
        if file_path.exists():
            print(f"    ✅ {file}")
        else:
            print(f"    ❌ {file} (Missing)")
            missing_az_files.append(file)

    # Check the game directory
    game_dir = parent_dir / 'game'
    print(f"\n  Game Module Directory: {game_dir}")

    if game_dir.exists():
        print("    ✅ game directory exists")

        game_files = ['Game.py', 'GameLogic.py', '__init__.py']
        missing_game_files = []

        for file in game_files:
            file_path = game_dir / file
            if file_path.exists():
                print(f"    ✅ game/{file}")
            else:
                print(f"    ❌ game/{file} (Missing)")
                missing_game_files.append(file)

        if missing_game_files:
            return False
    else:
        print("    ❌ game directory does not exist")
        return False

    return len(missing_az_files) == 0


def check_perfect_database():
    """Checks the Perfect Database configuration."""
    print("\n🗃️ Perfect Database Check:")

    default_path = "E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted"

    print(f"  Default path: {default_path}")

    if os.path.exists(default_path):
        print("  ✅ Default path exists")

        # Check for sec2 files
        sec2_files = list(Path(default_path).glob("std*.sec2"))
        print(f"  Found {len(sec2_files)} std*.sec2 files")

        if len(sec2_files) > 0:
            total_size = sum(f.stat().st_size for f in sec2_files)
            total_size_mb = total_size / (1024 * 1024)
            print(f"  Total size: {total_size_mb:.1f} MB")
            print("  ✅ Perfect Database is available")
            return True
        else:
            print("  ⚠️ No sec2 files found")
            return False
    else:
        print("  ⚠️ Default path does not exist")
        print("  Self-play training can proceed without the Perfect Database")
        return False


def check_import_paths():
    """Checks module import paths."""
    print("\n🔍 Module Import Path Check:")

    current_dir = Path(__file__).parent
    parent_dir = current_dir.parent
    game_dir = parent_dir / 'game'

    print(f"  First 5 items in sys.path:")
    for i, path in enumerate(sys.path[:5]):
        print(f"    {i+1}. {path}")

    # Test imports
    test_imports = [
        ('game.Game', game_dir / 'Game.py'),
        ('trainer', current_dir / 'trainer.py'),
        ('config', current_dir / 'config.py')
    ]

    print(f"\n  Module Import Test:")

    # Temporarily add paths
    for path in [str(current_dir), str(parent_dir), str(game_dir)]:
        if path not in sys.path:
            sys.path.insert(0, path)

    all_imports_ok = True

    for module_name, file_path in test_imports:
        try:
            if '.' in module_name:
                # Handle module names with dots
                parts = module_name.split('.')
                module = __import__(module_name)
                for part in parts[1:]:
                    module = getattr(module, part)
            else:
                __import__(module_name)
            print(f"    ✅ {module_name}")
        except ImportError as e:
            print(f"    ❌ {module_name}: {e}")
            all_imports_ok = False

    return all_imports_ok


def suggest_fixes():
    """Provides suggestions for fixes."""
    print("\n🔧 Suggestions for Fixes:")
    print("  1. Ensure you run the script from the correct directory:")
    print("     cd D:\\Repo\\Sanmill\\ml\\sl")
    print()
    print("  2. Use the simplified startup script:")
    print("     python run_training.py")
    print("     or")
    print("     start_training.bat")
    print()
    print("  3. If Python packages are missing, install them:")
    print("     pip install numpy torch")
    print()
    print("  4. If the Perfect Database is not available:")
    print("     - Training can still proceed, but only in self-play mode.")
    print("     - You can manually specify the database path.")


def main():
    """Main diagnostic function."""
    print("🔍 Alpha Zero Training Environment Diagnostics")
    print("=" * 50)

    checks = [
        ("Python Version", check_python_version),
        ("Python Packages", check_required_packages),
        ("Project Structure", check_project_structure),
        ("Perfect Database", check_perfect_database),
        ("Module Imports", check_import_paths)
    ]

    results = {}

    for name, check_func in checks:
        try:
            results[name] = check_func()
        except Exception as e:
            print(f"  ❌ Error during {name} check: {e}")
            results[name] = False

    # Summary
    print("\n📊 Diagnostic Summary:")
    print("-" * 30)

    all_ok = True
    for name, result in results.items():
        status = "✅ OK" if result else "❌ Problem found"
        print(f"  {name}: {status}")
        if not result:
            all_ok = False

    print()
    if all_ok:
        print("🎉 Environment is configured correctly, you can start training!")
        print("   Recommended command: python run_training.py")
    else:
        print("⚠️ Environment has configuration issues, please refer to the suggestions for fixes.")
        suggest_fixes()

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
