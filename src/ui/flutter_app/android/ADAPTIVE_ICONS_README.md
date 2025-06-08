# Android 13+ 主题化图标实现

本项目已成功实现Android 13+的主题化/单色应用图标功能。

## 实现的功能

### 1. Adaptive Icons
- 创建了 `mipmap-anydpi-v26/ic_launcher.xml` 和 `mipmap-anydpi-v26/ic_launcher_round.xml`
- 支持Android 8.0 (API 26)及以上版本的自适应图标

### 2. 主题化图标 (Android 13+)
- 创建了 `drawable-v33/ic_launcher_monochrome.xml`
- 支持Android 13 (API 33)及以上版本的主题化图标
- 图标会根据用户的系统主题自动调整颜色

### 3. 图标资源
- **背景**: `drawable/ic_launcher_background.xml` - 白色背景
- **前景**: `drawable/ic_launcher_foreground.xml` - Nine men's morris棋盘设计
- **单色**: `drawable-v33/ic_launcher_monochrome.xml` - 纯黑色版本用于主题化

### 4. AndroidManifest.xml更新
- 添加了 `android:roundIcon="@mipmap/ic_launcher_round"` 支持圆形图标

## 图标设计

### Nine Men's Morris (默认)
默认图标设计基于Nine men's morris游戏的经典棋盘布局：
- 三个嵌套的正方形
- 连接线
- 游戏棋子（圆点）

### Twelve Men's Morris (特定地区)
为以下地区/语言提供Twelve Men's Morris图标：
- 南非 (af, zu)
- 伊朗 (fa) 
- 斯里兰卡 (si)
- 韩国 (ko)
- 印尼 (id)
- 中国 (zh)
- 蒙古 (mn)

Twelve Men's Morris图标特点：
- 三个嵌套的矩形
- 对角线连接（区别于Nine Men's Morris）
- 额外的连接线
- 更多游戏棋子位置

## 兼容性

- **最低支持**: Android 8.0 (API 26) - Adaptive Icons
- **主题化图标**: Android 13 (API 33)及以上
- **目标SDK**: 36 (已配置)

## 测试

要测试主题化图标功能：
1. 在Android 13+设备上安装应用
2. 进入系统设置 > 壁纸和样式 > 主题图标
3. 启用"主题图标"选项
4. 应用图标将自动适应系统主题颜色

## 文件结构

```
android/app/src/main/res/
├── mipmap-anydpi-v26/
│   ├── ic_launcher.xml
│   └── ic_launcher_round.xml
├── drawable/
│   ├── ic_launcher_background.xml
│   ├── ic_launcher_foreground.xml (Nine Men's Morris - 默认)
│   └── ic_launcher_foreground_twelve.xml (Twelve Men's Morris - 备用)
├── drawable-v33/
│   ├── ic_launcher_monochrome.xml (Nine Men's Morris - 默认)
│   └── ic_launcher_monochrome_twelve.xml (Twelve Men's Morris - 备用)
├── drawable-{locale}/ (特定地区的Twelve Men's Morris图标)
│   └── ic_launcher_foreground.xml
└── drawable-{locale}-v33/ (特定地区的Twelve Men's Morris单色图标)
    └── ic_launcher_monochrome.xml

支持的locale: af, zu, fa, si, ko, id, zh, mn
``` 