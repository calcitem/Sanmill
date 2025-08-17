#!/usr/bin/env python3
"""
NNUE Model Cleanup Tool - NNUE 模型清理工具
===========================================

这个工具帮助清理重复和过期的 NNUE 模型文件，维护清洁的模型目录结构。

使用方法:
  python model_cleanup.py --list            # 列出所有模型文件
  python model_cleanup.py --dry-run         # 模拟清理（不实际删除）
  python model_cleanup.py --backup-only     # 仅清理备份文件
  python model_cleanup.py --interactive     # 交互式清理
  python model_cleanup.py --auto            # 自动清理（保留最新的3个模型）
"""

import os
import sys
import time
import argparse
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Tuple

class ModelCleanupTool:
    """NNUE 模型清理工具"""
    
    def __init__(self, project_root=None):
        if project_root is None:
            project_root = Path(__file__).parent
        self.project_root = Path(project_root)
        self.models_dir = self.project_root / "models"
        self.nnue_output_dir = self.project_root / "nnue_output"
        
    def scan_model_files(self) -> Dict[str, List[Path]]:
        """扫描所有模型文件"""
        model_files = {
            'models': [],
            'nnue_output': [],
            'root': [],
            'backups': []
        }
        
        # 扫描 models 目录
        if self.models_dir.exists():
            for pattern in ['*.bin', '*.pth', '*.pytorch', '*.tar']:
                model_files['models'].extend(self.models_dir.glob(pattern))
            
            # 扫描备份文件
            for pattern in ['*.backup_*', '*.bak']:
                model_files['backups'].extend(self.models_dir.glob(pattern))
        
        # 扫描 nnue_output 目录
        if self.nnue_output_dir.exists():
            for pattern in ['*.bin', '*.pth', '*.pytorch', '*.tar']:
                model_files['nnue_output'].extend(self.nnue_output_dir.glob(pattern))
        
        # 扫描项目根目录
        for pattern in ['nnue_model*.bin', 'nnue_model*.pth', 'model*.bin', 'model*.pth']:
            model_files['root'].extend(self.project_root.glob(pattern))
            
        return model_files
    
    def analyze_files(self, model_files: Dict[str, List[Path]]) -> Dict:
        """分析模型文件"""
        analysis = {
            'total_files': 0,
            'total_size_mb': 0,
            'by_category': {},
            'duplicates': [],
            'old_backups': [],
            'large_files': []
        }
        
        all_files = []
        for category, files in model_files.items():
            analysis['by_category'][category] = {
                'count': len(files),
                'size_mb': 0,
                'files': []
            }
            
            for file_path in files:
                if file_path.exists():
                    stat = file_path.stat()
                    size_mb = stat.st_size / (1024 * 1024)
                    mtime = datetime.fromtimestamp(stat.st_mtime)
                    
                    file_info = {
                        'path': file_path,
                        'category': category,
                        'size_mb': size_mb,
                        'mtime': mtime,
                        'age_days': (datetime.now() - mtime).days
                    }
                    
                    analysis['by_category'][category]['files'].append(file_info)
                    analysis['by_category'][category]['size_mb'] += size_mb
                    analysis['total_size_mb'] += size_mb
                    all_files.append(file_info)
        
        analysis['total_files'] = len(all_files)
        
        # 查找可能的重复文件（基于名称和大小）
        self._find_duplicates(all_files, analysis)
        
        # 查找旧备份文件（超过30天）
        analysis['old_backups'] = [
            f for f in all_files 
            if f['category'] == 'backups' and f['age_days'] > 30
        ]
        
        # 查找大文件（超过50MB）
        analysis['large_files'] = [
            f for f in all_files 
            if f['size_mb'] > 50
        ]
        
        return analysis
    
    def _find_duplicates(self, all_files: List[Dict], analysis: Dict):
        """查找重复文件"""
        # 按文件名（不含路径）分组
        by_name = {}
        for file_info in all_files:
            name = file_info['path'].name
            # 忽略备份文件的时间戳
            if '.backup_' in name:
                base_name = name.split('.backup_')[0]
            else:
                base_name = name
                
            if base_name not in by_name:
                by_name[base_name] = []
            by_name[base_name].append(file_info)
        
        # 找到有多个文件的名称组
        for name, files in by_name.items():
            if len(files) > 1:
                # 按修改时间排序，最新的在前
                files.sort(key=lambda f: f['mtime'], reverse=True)
                analysis['duplicates'].append({
                    'name': name,
                    'files': files,
                    'latest': files[0],
                    'duplicates': files[1:]
                })
    
    def print_analysis(self, analysis: Dict):
        """打印分析结果"""
        print("\n📊 NNUE 模型文件分析报告")
        print("=" * 50)
        
        print(f"\n📈 总览:")
        print(f"  文件总数: {analysis['total_files']}")
        print(f"  总大小: {analysis['total_size_mb']:.1f} MB")
        
        print(f"\n📁 按目录分布:")
        for category, info in analysis['by_category'].items():
            if info['count'] > 0:
                category_name = {
                    'models': 'models/ (推荐位置)',
                    'nnue_output': 'nnue_output/ (旧输出)',
                    'root': '项目根目录',
                    'backups': '备份文件'
                }[category]
                
                print(f"  {category_name}: {info['count']} 个文件, {info['size_mb']:.1f} MB")
                
                # 显示最新的几个文件
                if info['files']:
                    sorted_files = sorted(info['files'], key=lambda f: f['mtime'], reverse=True)
                    for file_info in sorted_files[:3]:  # 只显示最新的3个
                        age_str = f"{file_info['age_days']}天前" if file_info['age_days'] > 0 else "今天"
                        print(f"    • {file_info['path'].name} ({file_info['size_mb']:.1f}MB, {age_str})")
                    
                    if len(sorted_files) > 3:
                        print(f"    ... 还有 {len(sorted_files) - 3} 个文件")
        
        if analysis['duplicates']:
            print(f"\n🔄 可能的重复文件 ({len(analysis['duplicates'])} 组):")
            for dup in analysis['duplicates'][:5]:  # 只显示前5组
                print(f"  📄 {dup['name']}:")
                print(f"    ✅ 最新: {dup['latest']['path']} ({dup['latest']['age_days']}天前)")
                for old in dup['duplicates']:
                    print(f"    🗑️  旧版: {old['path']} ({old['age_days']}天前)")
        
        if analysis['old_backups']:
            print(f"\n🗂️ 旧备份文件 ({len(analysis['old_backups'])} 个, 超过30天):")
            for backup in analysis['old_backups'][:5]:
                print(f"  🗑️  {backup['path'].name} ({backup['age_days']}天前, {backup['size_mb']:.1f}MB)")
            if len(analysis['old_backups']) > 5:
                print(f"  ... 还有 {len(analysis['old_backups']) - 5} 个旧备份文件")
        
        if analysis['large_files']:
            print(f"\n📦 大文件 ({len(analysis['large_files'])} 个, 超过50MB):")
            for large in sorted(analysis['large_files'], key=lambda f: f['size_mb'], reverse=True):
                print(f"  📦 {large['path'].name} ({large['size_mb']:.1f}MB)")
    
    def interactive_cleanup(self, analysis: Dict):
        """交互式清理"""
        print("\n🧹 交互式清理模式")
        print("=" * 30)
        
        total_saved = 0
        
        # 处理重复文件
        if analysis['duplicates']:
            print("\n🔄 处理重复文件:")
            for dup in analysis['duplicates']:
                print(f"\n📄 发现重复文件组: {dup['name']}")
                print(f"  ✅ 最新: {dup['latest']['path']} ({dup['latest']['age_days']}天前)")
                
                for i, old in enumerate(dup['duplicates']):
                    print(f"  {i+1}. 🗑️  {old['path']} ({old['age_days']}天前, {old['size_mb']:.1f}MB)")
                
                choice = input("删除旧版本? (y/n/s=跳过): ").lower()
                if choice == 'y':
                    for old in dup['duplicates']:
                        try:
                            os.remove(old['path'])
                            print(f"    ✅ 已删除: {old['path'].name}")
                            total_saved += old['size_mb']
                        except Exception as e:
                            print(f"    ❌ 删除失败: {e}")
                elif choice == 's':
                    continue
        
        # 处理旧备份文件
        if analysis['old_backups']:
            print(f"\n🗂️ 发现 {len(analysis['old_backups'])} 个旧备份文件 (超过30天)")
            choice = input("删除所有旧备份文件? (y/n): ").lower()
            if choice == 'y':
                for backup in analysis['old_backups']:
                    try:
                        os.remove(backup['path'])
                        print(f"  ✅ 已删除备份: {backup['path'].name}")
                        total_saved += backup['size_mb']
                    except Exception as e:
                        print(f"  ❌ 删除失败: {e}")
        
        print(f"\n✅ 清理完成! 释放了 {total_saved:.1f} MB 空间")
    
    def auto_cleanup(self, keep_latest=3, keep_backups_days=7, dry_run=False):
        """自动清理"""
        print(f"\n🤖 自动清理模式 (保留最新 {keep_latest} 个模型, {keep_backups_days} 天内的备份)")
        print("=" * 60)
        
        total_saved = 0
        actions = []
        
        model_files = self.scan_model_files()
        
        # 清理每个目录中的旧模型文件
        for category in ['models', 'nnue_output', 'root']:
            files = model_files[category]
            if not files:
                continue
                
            # 按修改时间排序，最新的在前
            files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
            
            if len(files) > keep_latest:
                old_files = files[keep_latest:]
                print(f"\n📁 {category} 目录:")
                print(f"  保留最新的 {keep_latest} 个文件")
                print(f"  删除 {len(old_files)} 个旧文件:")
                
                for old_file in old_files:
                    size_mb = old_file.stat().st_size / (1024 * 1024)
                    age = (datetime.now() - datetime.fromtimestamp(old_file.stat().st_mtime)).days
                    print(f"    🗑️  {old_file.name} ({size_mb:.1f}MB, {age}天前)")
                    
                    if not dry_run:
                        try:
                            os.remove(old_file)
                            total_saved += size_mb
                            actions.append(f"删除旧模型: {old_file.name}")
                        except Exception as e:
                            print(f"    ❌ 删除失败: {e}")
                    else:
                        total_saved += size_mb
        
        # 清理旧备份文件
        backup_files = model_files['backups']
        if backup_files:
            cutoff_date = datetime.now() - timedelta(days=keep_backups_days)
            old_backups = [
                f for f in backup_files 
                if datetime.fromtimestamp(f.stat().st_mtime) < cutoff_date
            ]
            
            if old_backups:
                print(f"\n🗂️ 清理超过 {keep_backups_days} 天的备份文件:")
                for backup in old_backups:
                    size_mb = backup.stat().st_size / (1024 * 1024)
                    age = (datetime.now() - datetime.fromtimestamp(backup.stat().st_mtime)).days
                    print(f"  🗑️  {backup.name} ({size_mb:.1f}MB, {age}天前)")
                    
                    if not dry_run:
                        try:
                            os.remove(backup)
                            total_saved += size_mb
                            actions.append(f"删除旧备份: {backup.name}")
                        except Exception as e:
                            print(f"    ❌ 删除失败: {e}")
                    else:
                        total_saved += size_mb
        
        mode_str = "预计释放" if dry_run else "实际释放"
        print(f"\n✅ 自动清理完成! {mode_str} {total_saved:.1f} MB 空间")
        
        if actions and not dry_run:
            print(f"\n📝 执行的操作:")
            for action in actions:
                print(f"  • {action}")

def main():
    parser = argparse.ArgumentParser(description='NNUE Model Cleanup Tool')
    parser.add_argument('--list', action='store_true', help='列出所有模型文件')
    parser.add_argument('--dry-run', action='store_true', help='模拟清理（不实际删除）')
    parser.add_argument('--backup-only', action='store_true', help='仅清理备份文件')
    parser.add_argument('--interactive', action='store_true', help='交互式清理')
    parser.add_argument('--auto', action='store_true', help='自动清理')
    parser.add_argument('--keep-latest', type=int, default=3, help='保留最新的几个模型文件 (默认: 3)')
    parser.add_argument('--keep-backups-days', type=int, default=7, help='保留几天内的备份文件 (默认: 7)')
    
    args = parser.parse_args()
    
    # 如果没有指定操作，默认为列出文件
    if not any([args.list, args.dry_run, args.backup_only, args.interactive, args.auto]):
        args.list = True
    
    tool = ModelCleanupTool()
    model_files = tool.scan_model_files()
    analysis = tool.analyze_files(model_files)
    
    if args.list or args.dry_run or args.interactive or args.auto:
        tool.print_analysis(analysis)
    
    if args.interactive:
        tool.interactive_cleanup(analysis)
    elif args.auto:
        tool.auto_cleanup(
            keep_latest=args.keep_latest,
            keep_backups_days=args.keep_backups_days,
            dry_run=args.dry_run
        )
    elif args.backup_only:
        print("\n🗂️ 仅清理备份文件模式")
        if analysis['old_backups']:
            choice = input(f"发现 {len(analysis['old_backups'])} 个旧备份文件，是否删除? (y/n): ")
            if choice.lower() == 'y':
                for backup in analysis['old_backups']:
                    try:
                        if not args.dry_run:
                            os.remove(backup['path'])
                        print(f"  {'✅ 已删除' if not args.dry_run else '🔍 将删除'}: {backup['path'].name}")
                    except Exception as e:
                        print(f"  ❌ 删除失败: {e}")
        else:
            print("  📭 没有发现旧备份文件")

if __name__ == '__main__':
    main()
