# 九子棋搜索引擎增强功能

本文档总结了参考 Stockfish 实现对 Sanmill 项目搜索引擎所做的改进。

## 主要改进内容

### 1. 置换表 (Transposition Table) 优化

**文件**: `src/tt.h`, `src/tt.cpp`

**改进内容**:
- 改进了 TTEntry 的替换策略，参考 Stockfish 的实现
- 增加了更好的键值验证机制
- 优化了代际管理 (generation management)
- 改进了评分和深度的存储策略

**关键特性**:
```cpp
// 更智能的替换策略
- 空条目总是被替换
- 相同位置的条目总是被替换  
- 精确边界的条目优先保留
- 基于深度、PV状态和年龄计算替换优先级
```

### 2. 空着搜索 (Null Move Search) - 针对九子棋特别适配

**文件**: `src/search.h`, `src/search.cpp`

**特殊考虑**:
九子棋与国际象棋的关键差异：
- **形成 mill 后可以连续行棋** - 这是最重要的考虑点
- 移除对手棋子是强制性动作，不能跳过
- 开局阶段更具战术性

**实现的安全措施**:
```cpp
// 关键限制条件
1. 只在 Action::none (中性状态) 时使用 null move
   - Action::remove: 必须移除对手棋子
   - Action::select: 已选择棋子，必须移动
   - Action::place: 必须完成放置/移动
2. 避免在可能形成 mill 的位置使用
3. 开局前6子时更加保守
4. 使用较少的剪枝深度减少
5. 在简单残局中禁用
```

### 3. 历史启发式 (History Heuristic)

**文件**: `src/history.h` (新增), `src/search.cpp`

**组件**:
- **ButterflyHistory**: 按 [颜色][起始位置][目标位置] 索引的安静走法历史
- **PieceToHistory**: 按 [棋子][目标位置] 索引的历史
- **KillerMoves**: 存储引起 beta 剪枝的好走法
- **CounterMoves**: 反击走法表

**更新机制**:
```cpp
// 历史分数更新 (类似 Stockfish)
bonus = good ? (depth * depth + depth * 32) : -(depth * depth + depth * 32);
entry += bonus - entry * abs(bonus) / MaxValue;
```

### 4. 走法排序 (Move Ordering) 增强

**文件**: `src/movepick.h`, `src/movepick.cpp`

**改进的排序策略**:
1. **置换表走法** (最高优先级)
2. **战术走法** (形成 mill、阻止对手 mill)
3. **杀手走法** (引起剪枝的走法)
4. **历史分数高的走法**
5. **其他安静走法**

### 5. 搜索逻辑改进

**增强的主搜索**:
- 集成了 null move pruning
- 改进的历史更新机制
- 更好的 alpha-beta 边界管理
- 针对九子棋的特殊位置处理

**静态搜索 (Quiescence Search)**:
- 保持了原有的移除走法处理
- 添加了历史分数支持

## 九子棋特定的设计考虑

### 连续行棋处理
```cpp
// 在可能形成 mill 的位置避免 null move
bool nearMill = false;
for (Square sq = SQ_A1; sq <= SQ_C7; ++sq) {
    if (pos->potential_mills_count(sq, pos->sideToMove) > 0) {
        totalMills++;
    }
}
if (totalMills > 3) {
    nearMill = true;  // 避免使用 null move
}
```

### 九子棋的 Action 机制
九子棋中的 Action 状态：
- `Action::none`: 中性状态
- `Action::select`: 玩家已选择棋子（移动阶段）
- `Action::place`: 玩家正在放置/移动棋子  
- `Action::remove`: 玩家必须移除对手棋子

**注意**: 移动 = select + place（两步操作）

### 限制 Null Move 的 Action 状态
```cpp
// 只在中性状态使用 null move
if (pos->get_action() != Action::none) {
    return VALUE_UNKNOWN;  // 所有其他状态都是强制性的
}
```

### 开局保守策略
```cpp
// 开局前6子时避免 null move
if (pos->get_phase() == Phase::placing && 
    pos->piece_on_board_count(WHITE) + pos->piece_on_board_count(BLACK) < 6) {
    return VALUE_UNKNOWN;
}
```

## 性能预期改进

1. **搜索效率**: 通过 null move pruning 减少搜索节点
2. **走法排序**: 历史启发和杀手走法提高剪枝效率  
3. **位置复用**: 改进的置换表提高缓存命中率
4. **战术精度**: 针对九子棋特性的优化提高战术理解

## 使用注意事项

1. **调试信息**: 启动时会显示增强功能已启用
2. **兼容性**: 保持与现有代码的完全兼容
3. **内存使用**: 历史表会增加少量内存使用
4. **线程安全**: 当前实现使用全局历史表，多线程环境下可能需要额外考虑

## 编译要求

确保以下宏定义已启用：
- `TRANSPOSITION_TABLE_ENABLE`: 置换表功能
- `TT_MOVE_ENABLE`: 置换表存储最佳走法
- `TRANSPOSITION_TABLE_FAKE_CLEAN`: 代际管理

这些改进将显著提升 Sanmill 在九子棋对局中的搜索效率和战术理解能力。
