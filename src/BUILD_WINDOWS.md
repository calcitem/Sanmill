# Windows 编译指南

本目录提供了三个批处理文件，用于在 Windows 系统上使用 Visual Studio 编译器编译 Sanmill，无需 make 工具。

## 🛠️ 编译脚本

### 1. `build_simple.bat` - 快速编译
- **用途**: 快速编译基础版本
- **特点**: 
  - 不包含 Perfect 数据库
  - 编译速度最快
  - 适合开发测试
  - **已修复中文乱码问题**
- **输出**: `sanmill_simple.exe`

### 2. `build_complete.bat` - 完整编译 ⭐ **推荐**
- **用途**: 交互式选择编译选项
- **特点**:
  - **已修复中文乱码问题**
  - 使用英文界面，兼容性更好
  - 自动设置 UTF-8 编码
- **选项**:
  1. Standard Edition (标准版 - 不含 Perfect 数据库)
  2. Complete Edition (完整版 - 包含 Perfect 数据库) 
  3. NNUE Specialized Edition (NNUE 专用版 - 优化 NNUE 支持)
- **输出**: 
  - `sanmill_standard.exe`
  - `sanmill_complete.exe` 
  - `sanmill_nnue.exe`

### 3. `build_windows_en.bat` - 详细编译 (英文版)
- **用途**: 显示详细编译过程
- **特点**: 
  - 包含完整的 Perfect 库
  - 英文界面，无乱码问题
- **输出**: `sanmill.exe`

### 4. `build_windows.bat` - 原版本 (保留)
- **注意**: 可能有中文乱码问题，建议使用上面的英文版本

## 🔧 环境要求

### Visual Studio
需要安装 Visual Studio (任一版本):
- Visual Studio 2017 或更高版本
- Visual Studio Community (免费)
- Visual Studio Build Tools

### 环境设置
在以下任一环境中运行脚本:

#### 方法 1: Developer Command Prompt (推荐)
1. 开始菜单搜索 "Developer Command Prompt"
2. 选择对应的 Visual Studio 版本
3. 导航到 `src` 目录
4. 运行批处理文件

#### 方法 2: 普通命令行
```cmd
# 设置 Visual Studio 环境 (根据安装路径调整)
"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64

# 导航到 src 目录
cd D:\Repo\Sanmill\src

# 运行编译脚本
build_complete.bat
```

#### 方法 3: PowerShell
```powershell
# 设置环境
& "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64

# 编译
.\build_complete.bat
```

## 🚀 使用示例

### 快速开始
```cmd
cd D:\Repo\Sanmill\src
build_simple.bat
```

### 完整编译 (推荐)
```cmd
cd D:\Repo\Sanmill\src
build_complete.bat
```
然后选择编译选项:
- 输入 `1` - 标准版 (快速，不含 Perfect)
- 输入 `2` - 完整版 (包含 Perfect 数据库)
- 输入 `3` - NNUE 版 (AI 训练专用)

### NNUE 训练专用
如果您要进行 NNUE 训练，推荐使用选项 3:
```cmd
build_complete.bat
# 选择 3 (NNUE 专用版)
```

## 📁 输出文件

编译成功后，会在 `src` 目录下生成相应的可执行文件:

- `sanmill_simple.exe` - 基础版本
- `sanmill_standard.exe` - 标准版本  
- `sanmill_complete.exe` - 完整版本
- `sanmill_nnue.exe` - NNUE 专用版本

## ⚙️ 编译选项说明

### 基础编译参数
- `/std:c++17` - C++17 标准
- `/O2` - 优化级别 2
- `/EHsc` - 异常处理
- `/MT` - 静态链接运行时库
- `/DNDEBUG` - 发布模式
- `/DIS_64BIT` - 64位支持

### 条件编译定义
- `NO_PERFECT_DB` - 禁用 Perfect 数据库
- `GABOR_MALOM_PERFECT_AI` - 启用 Perfect AI
- `USE_NNUE` - 启用 NNUE 支持
- `WIN32` - Windows 平台
- `_CRT_SECURE_NO_WARNINGS` - 禁用 CRT 安全警告

## 🐛 故障排除

### 中文乱码问题 ✅ **已解决**

#### 问题描述
在 cmd 中运行批处理文件时出现中文乱码。

#### 解决方案
所有批处理文件已添加 `chcp 65001` 命令自动设置 UTF-8 编码：

```batch
@echo off
chcp 65001 >nul
```

#### 如果仍有乱码
1. **手动设置编码**:
   ```cmd
   chcp 65001
   build_complete.bat
   ```

2. **使用英文版本**:
   - `build_complete.bat` (推荐)
   - `build_windows_en.bat`

3. **PowerShell 中运行**:
   ```powershell
   # PowerShell 默认支持 UTF-8
   .\build_complete.bat
   ```

### 常见错误

#### 1. "cl 编译器未找到"
**解决方案**: 
- 在 Visual Studio Developer Command Prompt 中运行
- 或手动设置环境变量

#### 2. 编译错误
**检查项目**:
- 确保在 `src` 目录下运行
- 检查源文件是否完整
- 确认 Visual Studio 版本兼容性

#### 3. 链接错误
**可能原因**:
- Perfect 库文件过大导致内存不足
- 使用 `build_simple.bat` 避免 Perfect 库

#### 4. 运行时错误
**解决方案**:
- 确保所有依赖文件在同一目录
- 检查是否需要 Visual C++ 运行时库

### 性能优化

#### 编译速度
- 使用 `build_simple.bat` 最快
- Perfect 库编译较慢，可选择标准版

#### 运行性能
- 发布模式已启用 `/O2` 优化
- NNUE 版本针对 AI 计算优化

## 🔗 相关文件

### NNUE 训练
编译完成后，可以使用 NNUE 训练工具:
```cmd
cd ..\ml\nnue_training
python easy_train.py
```

### 配置文件
Perfect 数据库路径已配置为:
```
E:\Malom\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted
```

如需修改，请编辑 `ml/nnue_training/configs/` 下的配置文件。

## 📝 注意事项

1. **编译时间**: 完整版编译需要 5-10 分钟
2. **磁盘空间**: 编译过程需要约 500MB 临时空间
3. **内存要求**: 建议至少 4GB 可用内存
4. **Perfect 库**: 如遇链接问题，建议使用标准版

## 💡 提示

- 首次编译建议使用 `build_complete.bat` 并选择标准版
- 确认可以正常编译后，再尝试完整版
- NNUE 训练专用版仅在需要训练时使用
- 编译过程中的中间文件会自动清理
