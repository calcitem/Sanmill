# NNUE 训练安全机制

## 🛡️ 保护功能概述

为了防止训练过程中意外清空已有的训练成果，NNUE 傻瓜化训练工具内置了完善的保护机制。

## 🔍 自动检测现有模型

### 检测范围
训练开始前会自动扫描以下位置的现有模型：
- `nnue_model*.bin` - 当前目录下的二进制模型
- `nnue_model*.pth` - 当前目录下的 PyTorch 模型  
- `models/nnue_model*.bin` - models 目录下的二进制模型
- `models/nnue_model*.pth` - models 目录下的 PyTorch 模型

### 显示信息
对于每个发现的模型，会显示：
- 📁 文件路径和名称
- 📏 文件大小（KB）
- 📅 最后修改时间

```
🔍 检查现有训练成果...
  发现 2 个现有模型:
    📁 nnue_model_quick_20231216_143022.bin (14.8 KB, 2023-12-16 14:30:22)
    📁 models/nnue_model_standard_20231215_210115.pth (32.2 KB, 2023-12-15 21:01:15)
```

## 📋 保护选项

### 交互式选择
当发现现有模型时，会提供三个选项：

```
⚠️  继续训练将可能覆盖现有模型！
   建议选择:
   1. 备份现有模型 (推荐)
   2. 继续训练 (可能覆盖)
   3. 取消训练
```

#### 选项 1: 备份现有模型 ✅ **推荐**
- 自动创建时间戳备份目录
- 复制所有现有模型到备份目录
- 生成恢复脚本
- 然后继续新的训练

#### 选项 2: 继续训练 ⚠️ **谨慎**
- 直接开始训练
- 可能会覆盖同名模型文件
- 适合确认要替换旧模型的情况

#### 选项 3: 取消训练 ✅ **安全**
- 立即停止训练流程
- 保护现有模型不被修改
- 给用户时间考虑或手动备份

## 💾 自动备份机制

### 备份目录结构
```
model_backups/
  20231216_143500/           # 时间戳目录
    nnue_model_quick.bin     # 备份的模型文件
    nnue_model_standard.pth
    restore_models.py        # 自动生成的恢复脚本
```

### 恢复脚本
自动生成的恢复脚本包含：
- 📜 完整的文件映射关系
- 🔄 自动恢复功能
- ✅ 错误处理和进度显示

```bash
# 恢复备份的模型
python model_backups/20231216_143500/restore_models.py
```

## 🔄 断点恢复功能

### 检查点检测
训练前会自动扫描检查点文件：
- `checkpoint*.pth` - 检查点文件
- `*.checkpoint` - 其他格式检查点
- `models/checkpoint*.pth` - models 目录下的检查点

### 恢复选项
```
🔄 检查训练恢复选项...
  发现 1 个检查点文件:
    🔄 checkpoint_standard_20231216_120000.pth (156.4 KB, 2023-12-16 12:00:00)

  是否从检查点恢复训练？
    y - 恢复训练 (继续之前的进度)
    n - 重新开始 (将创建新的训练)
```

### 检查点备份
如果选择重新开始训练，会自动备份现有检查点：
```
  💾 备份 1 个检查点文件...
    ✅ checkpoint_standard_20231216_120000.pth -> checkpoint_backups/20231216_143500/
```

## 🚀 命令行控制

### 自动备份模式
```bash
python easy_train.py --backup-existing
```
- 发现现有模型时自动备份
- 无需用户交互
- 适合自动化脚本

### 强制模式 ⚠️
```bash
python easy_train.py --force
```
- 跳过所有保护检查
- 直接开始训练
- **谨慎使用**，可能覆盖现有文件

### 组合使用
```bash
# 自动备份 + GPU + 快速训练
python easy_train.py --quick --gpu --backup-existing --auto

# 强制高质量训练（跳过检查）
python easy_train.py --high-quality --force --auto
```

## 🔒 防覆盖机制

### 唯一文件名
新训练的模型使用时间戳命名：
```
nnue_model_quick_20231216_143500.bin
nnue_model_standard_20231216_143500.pth
checkpoint_quick_20231216_143500.pth
```

### 目录隔离
不同类型的文件存储在不同目录：
- `models/` - 训练的模型文件
- `model_backups/` - 模型备份
- `checkpoint_backups/` - 检查点备份
- `plots/` - 训练图表

## 📊 安全使用建议

### 开发环境
1. ✅ 使用默认保护机制
2. ✅ 选择备份现有模型
3. ✅ 定期清理备份目录
4. ✅ 检查恢复脚本功能

```bash
# 推荐的开发流程
python easy_train.py --quick           # 快速实验
python easy_train.py                   # 标准训练
python easy_train.py --high-quality    # 高质量模型
```

### 生产环境
1. ✅ 使用自动备份模式
2. ✅ 配置外部备份策略
3. ✅ 监控磁盘空间
4. ⚠️ 谨慎使用强制模式

```bash
# 推荐的生产流程
python easy_train.py --backup-existing --auto
```

### 自动化脚本
1. ✅ 明确指定备份策略
2. ✅ 处理磁盘空间不足
3. ✅ 记录训练日志
4. ⚠️ 避免使用交互模式

```bash
# 自动化脚本示例
#!/bin/bash
# 清理旧备份
find model_backups/ -mtime +7 -type d -exec rm -rf {} \;

# 自动训练
python easy_train.py --high-quality --backup-existing --auto --no-gui
```

## 🚨 故障恢复

### 训练中断
```bash
# 检查是否有检查点
ls checkpoint*.pth

# 恢复训练
python easy_train.py  # 会自动询问是否恢复
```

### 模型丢失
```bash
# 查看备份
ls model_backups/

# 恢复最新备份
python model_backups/latest_timestamp/restore_models.py
```

### 空间不足
```bash
# 清理旧备份（保留最近3个）
ls -t model_backups/ | tail -n +4 | xargs rm -rf

# 清理临时文件
rm easy_train_*_config.json
rm training_data_*.txt
```

## 💡 最佳实践

### 1. 训练前准备
- ✅ 检查磁盘空间（至少1GB可用）
- ✅ 备份重要模型到其他位置
- ✅ 了解训练时间预估

### 2. 训练中监控
- ✅ 观察损失曲线
- ✅ 监控内存和GPU使用
- ✅ 注意检查点保存

### 3. 训练后验证
- ✅ 验证新模型功能
- ✅ 对比新旧模型性能
- ✅ 清理不需要的备份

### 4. 版本管理
- ✅ 为重要模型添加版本标签
- ✅ 记录训练参数和数据集
- ✅ 建立模型性能基准

## 🎯 常见问题

### Q: 如何知道哪个模型是最新的？
**A**: 文件名包含时间戳，按修改时间排序即可：
```bash
ls -lt nnue_model*.bin
```

### Q: 备份会占用多少空间？
**A**: 通常每个模型15-50KB，100个备份约5MB，可定期清理。

### Q: 如何禁用保护机制？
**A**: 使用 `--force` 参数，但需要谨慎：
```bash
python easy_train.py --force --auto  # 跳过所有检查
```

### Q: 恢复脚本失败怎么办？
**A**: 手动复制备份文件：
```bash
cp model_backups/20231216_143500/*.bin ./
cp model_backups/20231216_143500/*.pth ./
```

### Q: 如何清理所有备份？
**A**: 删除备份目录：
```bash
rm -rf model_backups/
rm -rf checkpoint_backups/
```

---

## 📞 获取帮助

如果遇到问题：
1. 查看训练日志了解具体错误
2. 检查磁盘空间和权限
3. 尝试使用 `--force` 模式（谨慎）
4. 手动备份重要文件后重试

保护机制的目标是让训练更安全，但不应该成为使用障碍。合理配置这些选项可以在安全性和便利性之间找到平衡。
