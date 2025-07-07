# GPF 路径解析问题分析与解决方案

## 问题分析

### 当前路径使用统计
- **总计PROJECT_ROOT使用**: 107次
- **基于PROJECT_ROOT的source**: 42次  
- **相对路径source**: 33次

### 按架构层分析
- **Atomic层**: ✅ 0次PROJECT_ROOT使用，完全使用相对路径
- **Composite层**: ✅ 0次PROJECT_ROOT使用，完全使用相对路径  
- **Modules层**: ❌ 8个文件使用PROJECT_ROOT
- **Commands层**: ❌ 1个文件使用PROJECT_ROOT

### 核心问题
1. **Worktree路径冲突**: Commands层计算`../../../..`在worktree中指向`.worktrees`目录而非项目根
2. **环境感知职责混乱**: 路径计算和环境检测逻辑耦合
3. **路径规范不统一**: 下层用相对路径，上层用绝对路径

## 解决方案设计

### 路径使用原则
1. **代码加载**: 优先使用相对路径
2. **环境检测**: 仅在必要时使用绝对路径
3. **分层职责**: 各层负责自己的路径计算

### 具体规范

#### 1. 模块加载路径 (相对路径)
```bash
# ✅ 推荐：相对路径加载同层或下层模块
source "$(dirname "${BASH_SOURCE[0]}")/same-level-module.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lower-level/module.sh"

# ❌ 避免：基于PROJECT_ROOT的跨层加载
source "$PROJECT_ROOT/lib/core/modules/module.sh"
```

#### 2. 环境检测路径 (绝对路径)
```bash
# ✅ 仅用于环境感知和运行时检测
GPF_RUNTIME_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GPF_WORKTREE_TYPE="$(检测当前是否在worktree中)"
```

#### 3. 分层加载策略
- **Commands层**: 加载common.sh + 直接依赖的modules
- **Modules层**: 不加载common.sh，通过Commands层继承
- **下层**: 完全使用相对路径

### 实施计划

#### Phase 1: 重构Commands层路径计算
- 移除复杂的`../../../..`计算
- 使用相对路径加载依赖

#### Phase 2: 清理Modules层PROJECT_ROOT依赖  
- 移除`environment_get_project_root()`调用
- 依赖Commands层传递环境信息

#### Phase 3: 统一环境检测接口
- 创建专门的环境检测模块
- 分离路径计算和环境感知

#### Phase 4: 验证Worktree兼容性
- 测试在各种环境下的路径解析
- 确保develop和worktree行为一致

## 预期效果

1. **解决Worktree兼容性**: 相对路径在任何环境都正确
2. **简化路径逻辑**: 减少复杂的路径计算
3. **提高可维护性**: 路径逻辑更清晰
4. **增强可移植性**: 项目可在任意位置运行