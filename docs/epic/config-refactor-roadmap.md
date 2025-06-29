# Epic: Config Refactor - 配置文件重构路线图

> 移除 Epic/Feature 分支的 YAML 配置文件依赖，改用 Git 上下文智能推导

## 🎯 Epic 目标

**核心愿景**: 简化配置管理，减少文件系统污染，提升工具响应速度和可维护性

### 问题背景

当前 git-pr-flow 在每个 Epic 和 Feature 分支创建时都会生成 `.git-pr-flow.yaml` 配置文件，这带来了几个问题：

1. **文件系统污染**: 每个 worktree 目录都有配置文件，增加了项目复杂度
2. **配置冗余**: 大部分信息可以从 Git 上下文推导得出
3. **维护负担**: 配置文件需要同步更新，容易出现不一致
4. **性能影响**: 频繁的文件读写操作影响命令响应速度

### 重构目标

- ✅ **零配置文件**: Epic/Feature 分支不再创建 YAML 文件
- ✅ **智能推导**: 通过 Git 分支名、目录结构、worktree 信息推导配置
- ✅ **向后兼容**: 保证现有用户的工作流不受影响
- ✅ **集中配置**: 项目级配置统一管理在 `.gpf/` 目录
- ✅ **性能提升**: 减少文件 I/O，提升命令执行速度

## 🔍 现状分析

### YAML 配置文件当前用途

基于代码分析，YAML 文件主要存储以下信息：

#### Epic 配置文件内容
```yaml
epic_name: "config-refactor"
epic_branch: "epic/config-refactor"  
description: "config-refactor Epic功能开发"
base_branch: "develop"
worktree_path: ".worktrees/epic--config-refactor"
config_version: "1.0"
created_at: "2025-06-29T09:06:58Z"
last_updated: "2025-06-29T09:06:58Z"

# 自动化设置
auto_switch_branch: true
auto_sync: false
auto_cleanup: false

# 工作流设置
workflow_type: "gitflow"
pr_strategy: "progressive"
```

#### Feature 配置文件内容
```yaml
feature_name: "config-refactor/yaml-removal"
epic_name: "config-refactor"
epic_branch: "epic/config-refactor"
description: "移除 YAML 配置文件依赖"
base_branch: "epic/config-refactor"
worktree_path: ".worktrees/epic--config-refactor--yaml-removal"
config_version: "1.0"
created_at: "2025-06-29T10:00:00Z"
last_updated: "2025-06-29T10:00:00Z"
branch_type: "feature"

# Feature 设置
auto_switch_branch: true
auto_sync: false
auto_cleanup: false

# 工作流设置
workflow_type: "gitflow"
pr_strategy: "feature_to_epic"
```

### 信息推导可行性分析

| YAML 字段 | Git 上下文推导方式 | 实现难度 | 准确度 |
|-----------|-------------------|----------|-------|
| `epic_name` | 从目录名 `epic--<name>` 或分支名 `epic/<name>` 提取 | **简单** | **100%** |
| `epic_branch` | 从 epic_name 构造：`epic/<epic_name>` | **简单** | **100%** |
| `feature_name` | 从分支名 `<epic>/<feature>` 解析 | **简单** | **100%** |
| `base_branch` | Git 配置或约定优先级：`develop` > `main` > `master` | **中等** | **90%** |
| `worktree_path` | 从目录结构推导：当前 worktree 路径 | **简单** | **100%** |
| `branch_type` | 从分支名模式判断：`epic/*` vs `<epic>/<feature>` | **简单** | **100%** |
| `created_at` | Git 分支创建时间：`git log --reverse --format=%ct` | **简单** | **95%** |
| `description` | Git 配置或交互式输入 | **中等** | **用户输入** |
| `auto_*` 设置 | 项目级配置或用户偏好 | **中等** | **100%** |
| `workflow_type` | 项目级配置，默认 `gitflow` | **简单** | **100%** |
| `pr_strategy` | 从分支类型推导 | **简单** | **95%** |

### 核心重构策略

#### 1. Git 上下文推导引擎
```bash
# 示例：从当前上下文推导配置信息
detect_context_from_current_location() {
    local current_dir=$(pwd)
    local git_branch=$(git branch --show-current 2>/dev/null)
    
    # 从目录名推导
    if [[ "$current_dir" =~ \.worktrees/epic--([^/]+)$ ]]; then
        epic_name="${BASH_REMATCH[1]}"
        epic_branch="epic/$epic_name"
        branch_type="epic"
    elif [[ "$current_dir" =~ \.worktrees/epic--([^-]+)--(.+)$ ]]; then
        epic_name="${BASH_REMATCH[1]}"
        feature_name="${BASH_REMATCH[2]}"
        epic_branch="epic/$epic_name"
        feature_branch="$epic_name/$feature_name"
        branch_type="feature"
    fi
    
    # 从 Git 分支名推导
    if [[ "$git_branch" =~ ^epic/(.+)$ ]]; then
        epic_name="${BASH_REMATCH[1]}"
        branch_type="epic"
    elif [[ "$git_branch" =~ ^([^/]+)/(.+)$ ]]; then
        epic_name="${BASH_REMATCH[1]}"
        feature_name="${BASH_REMATCH[2]}"
        branch_type="feature"
    fi
}
```

#### 2. 项目级配置管理
```bash
# .gpf/config.yaml - 项目级配置文件
project_name: "git-pr-flow"
base_branch: "develop"
workflow_type: "gitflow"

# 用户偏好设置
user_preferences:
  auto_switch_branch: true
  auto_sync: false
  auto_cleanup: false
  
# PR 策略配置
pr_strategies:
  epic_to_base: "progressive"
  feature_to_epic: "feature_to_epic"
```

#### 3. 智能初始化逻辑
```bash
# gpf init 时的逻辑
gpf_init_with_context() {
    local epic_name="$1"
    local base_branch="${2:-$(detect_default_base_branch)}"
    
    # 检查或创建项目配置
    if [[ ! -f ".gpf/config.yaml" ]]; then
        create_project_config "$base_branch"
    fi
    
    # 不再创建 Epic 级别的 YAML 文件
    # 所有信息通过上下文推导
}
```

## 📋 开发计划

### Story 1: 上下文推导引擎 (优先级: 高)
**目标**: 实现基于 Git 上下文的配置信息推导

#### 子任务:
- [ ] **实现 `detect_epic_context()` 函数**
  - 从目录路径推导 Epic 信息
  - 从 Git 分支名推导 Epic 信息
  - 处理边界情况和错误场景

- [ ] **实现 `detect_feature_context()` 函数**
  - 从目录路径推导 Feature 信息
  - 从 Git 分支名推导 Feature 信息
  - 解析 Epic/Feature 关系

- [ ] **实现 `detect_base_branch()` 函数**
  - 智能检测项目默认分支
  - 支持多种分支命名约定
  - 优先级：develop > main > master
  - **关键**: 区分 Epic 的 base_branch (develop) 和 Feature 的 base_branch (epic/xxx)

- [ ] **创建上下文推导测试套件**
  - 覆盖各种目录结构场景
  - 覆盖各种分支命名场景
  - 性能基准测试

**交付标准**: 
- 上下文推导准确率 ≥ 95%
- 性能优于当前 YAML 读取方式
- 完整的单元测试覆盖

---

### Story 2: 项目级配置系统 (优先级: 高)
**目标**: 建立 `.gpf/` 目录下的项目级配置管理

#### 子任务:
- [ ] **设计项目配置文件结构**
  - `.gpf/config.yaml` 主配置文件
  - `.gpf/user-preferences.yaml` 用户偏好
  - 配置文件版本管理机制

- [ ] **实现配置文件操作函数**
  - `create_project_config()` - 创建项目配置
  - `read_project_config()` - 读取项目配置
  - `update_project_config()` - 更新项目配置

- [ ] **实现 `gpf init` 配置检查逻辑**
  - 检测 `.gpf/` 目录是否存在
  - 缺失时创建默认配置
  - 存在时读取并验证配置

- [ ] **配置迁移工具**
  - 从现有 YAML 文件迁移配置
  - 向后兼容性支持
  - 迁移进度提示

**交付标准**:
- `.gpf/` 配置系统完全替代分散的 YAML 文件
- 支持配置继承和覆盖
- 提供配置迁移向导

---

### Story 3: 重构 Epic/Feature 创建流程 (优先级: 高)
**目标**: 移除 Epic/Feature 创建过程中的 YAML 文件生成

#### 子任务:
- [ ] **重构 `config_epic_create()` 函数**
  - 移除 YAML 文件创建逻辑
  - 改用上下文推导验证 Epic 信息
  - 更新函数接口和调用方式

- [ ] **重构 `config_feature_create()` 函数**
  - 移除 YAML 文件创建逻辑
  - 改用上下文推导验证 Feature 信息
  - 保持与现有调用接口兼容

- [ ] **更新 `init.sh` 命令逻辑**
  - 移除配置文件创建调用
  - 集成项目级配置检查
  - 保持用户体验一致性

- [ ] **更新 `start.sh` 命令逻辑**
  - 移除配置文件创建调用
  - 使用上下文推导获取 Epic 信息
  - 优化分支创建流程
  - **修复功能分支基础分支逻辑**: 功能分支应该基于 Epic 分支（如 `epic/config-refactor`）创建，而不是基于 develop

**交付标准**:
- Epic/Feature 创建过程不再生成 YAML 文件
- 功能保持完全一致
- 命令执行速度提升 ≥ 30%

---

### Story 4: 重构配置读取逻辑 (优先级: 中)
**目标**: 将所有 YAML 读取操作替换为上下文推导

#### 子任务:
- [ ] **重构 `config_epic_get()` 函数**
  - 替换 YAML 读取为上下文推导
  - 支持向后兼容模式
  - 保持函数接口不变

- [ ] **重构 `config_feature_get()` 函数**
  - 替换 YAML 读取为上下文推导
  - 保持返回数据格式一致
  - 添加性能优化

- [ ] **重构 `detect_current_epic()` 函数**
  - 完全基于上下文推导
  - 移除文件系统依赖
  - 提升检测准确性

- [ ] **更新所有配置读取调用点**
  - 审计代码中所有配置读取位置
  - 确保功能一致性
  - 添加错误处理

**交付标准**:
- 所有配置读取操作不再依赖 YAML 文件
- 向后兼容现有工作流
- 性能提升 ≥ 50%

---

### Story 5: 向后兼容和迁移支持 (优先级: 中)
**目标**: 确保现有用户平滑迁移到新配置系统

#### 子任务:
- [ ] **实现 YAML 文件兼容模式**
  - 检测现有 YAML 文件
  - 优雅降级到文件读取模式
  - 提供迁移建议

- [ ] **创建配置迁移命令**
  - `gpf migrate-config` 命令
  - 批量清理旧 YAML 文件
  - 迁移报告和确认

- [ ] **添加迁移向导**
  - 交互式迁移流程
  - 数据备份和恢复
  - 迁移前后对比验证

- [ ] **更新用户文档**
  - 迁移指南文档
  - 新配置系统说明
  - 常见问题解答

**交付标准**:
- 100% 向后兼容现有工作流
- 提供自动化迁移工具
- 完整的迁移文档

---

### Story 6: 性能优化和测试完善 (优先级: 低)
**目标**: 验证重构效果，确保系统稳定性

#### 子任务:
- [ ] **性能基准测试**
  - 对比重构前后性能指标
  - 大型项目压力测试
  - 内存使用优化

- [ ] **集成测试套件**
  - 端到端工作流测试
  - 边界条件测试
  - 错误恢复测试

- [ ] **用户体验验证**
  - Alpha 用户测试反馈
  - 命令响应时间统计
  - 错误率监控

- [ ] **文档和示例更新**
  - 更新 API 文档
  - 更新使用示例
  - 性能改进说明

**交付标准**:
- 整体性能提升 ≥ 40%
- 测试覆盖率 ≥ 90%
- 零功能回归

## 🎯 成功标准

### 功能指标
- ✅ **零 YAML 污染**: Epic/Feature 分支不再产生配置文件
- ✅ **功能完整性**: 100% 保持现有功能
- ✅ **向后兼容**: 现有用户工作流零中断
- ✅ **配置集中**: 项目配置统一在 `.gpf/` 目录管理

### 性能指标
- ✅ **命令响应**: 平均响应时间提升 ≥ 40%
- ✅ **内存使用**: 内存占用减少 ≥ 30%
- ✅ **文件 I/O**: 配置读取操作减少 ≥ 80%
- ✅ **冷启动**: 首次命令执行时间提升 ≥ 50%

### 用户体验指标
- ✅ **学习成本**: 用户无需学习新概念
- ✅ **迁移成本**: 自动化迁移，用户零手动操作
- ✅ **错误率**: 配置相关错误减少 ≥ 60%
- ✅ **维护负担**: 配置维护工作量减少 ≥ 70%

## 🚀 实施时间线

### 第 1-2 周：基础设施
- **Week 1**: Story 1 (上下文推导引擎) + Story 2 (项目级配置)
- **Week 2**: Story 3 (重构创建流程) + 集成测试

### 第 3-4 周：核心重构
- **Week 3**: Story 4 (重构读取逻辑) + 性能优化
- **Week 4**: Story 5 (向后兼容) + 全面测试

### 第 5-6 周：优化完善
- **Week 5**: Story 6 (性能优化) + 文档更新
- **Week 6**: Alpha 测试 + 用户反馈收集

## 🔄 验证和测试策略

### 单元测试
- 上下文推导函数 100% 覆盖
- 配置操作函数完整测试
- 边界条件和错误场景测试

### 集成测试
- 完整工作流端到端测试
- 多种项目结构兼容性测试
- 性能回归测试

### 用户测试
- 内部 Dogfooding 验证
- Alpha 用户迁移测试
- 真实项目场景验证

## 🎉 预期收益

### 开发体验提升
- **更快响应**: 命令执行更迅速
- **更少文件**: 项目目录更清洁
- **更好维护**: 配置管理更简单

### 系统架构优化
- **代码简化**: 移除大量文件操作代码
- **性能提升**: 减少 I/O 依赖
- **可维护性**: 集中化配置管理

### 用户价值
- **零学习成本**: 工作流保持不变
- **更好性能**: 工具响应更快
- **更少错误**: 配置冲突减少

这个重构将显著提升 git-pr-flow 的性能和可维护性，同时保持完全的向后兼容性，为用户提供更优秀的开发体验。