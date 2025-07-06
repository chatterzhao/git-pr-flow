# Commands Layer Implementation Roadmap

> **目标**: 为用户提供简化的5个核心命令，每个命令都有智能的支撑逻辑确保操作的安全性和便利性

> **返回**: [项目总路线图](roadmap.md) | [命令用户手册](COMMANDS.md)

## 🎯 Commands Layer设计原则

### 核心理念
- **用户省事原则**: 每个命令自动执行必要的支撑操作，用户无需手动处理
- **安全第一原则**: 所有命令都有预检查和安全验证
- **智能感知原则**: 根据当前环境自动调整命令行为
- **状态透明原则**: 清晰显示当前状态和操作结果

### 架构依赖
Commands层是四层架构的顶层，严格遵循分层调用：
```
Commands Layer (业务编排) ← 我们要实现的层
    ↓ 只能调用
Modules Layer (业务逻辑) ← Commands层的直接依赖 ✅
    ↓ 只能调用
Composite Layer (组合功能)
    ↓ 只能调用
Atomic Layer (原子操作)
```

**重要**：Commands层不能跨层调用，只能调用Modules层的方法！

**架构决策**：删除Operations层，采用经典四层架构以减少复杂性和职责重叠。

## 📋 Commands详细设计

### 1. status命令 - 基础支撑命令

**功能**: 智能状态显示，是其他命令的基础支撑

**支撑逻辑架构**:
```bash
gpf status [epic] [feature]
    ↓
1. 环境检测 (environment_module_get_complete_info)
2. 确定显示范围 (当前环境感知)
3. 收集状态信息 (status_module_get_complete_status)
4. 格式化输出 (JSON → 用户友好格式)
```

**支撑逻辑详细**:
- **环境自动检测**: 检测当前在root/epic/feature环境
- **范围智能确定**: 
  - 在root环境: 显示所有epic状态
  - 在epic环境: 显示当前epic及其features状态
  - 在feature环境: 显示当前feature状态
- **GitHub状态集成**: 自动查询相关PR状态
- **Git状态检查**: 工作区干净性、分支同步状态

**为其他命令提供的支撑**:
- `pr`命令调用status检查PR就绪性
- `clean`命令调用status检查清理安全性
- `sync`命令调用status检查同步需求

### 2. start命令 - 创建环境命令

**功能**: 智能创建Epic/Feature环境，自动处理同步和切换

**支撑逻辑架构**:
```bash
gpf start -e <epic> [base] / gpf start -ef <feature> <epic>
    ↓
1. 参数解析和验证 (path_normalize_user_input)
2. 环境预检查 (environment_module_get_complete_info)
3. 同步基础分支 (sync_module_intelligent_sync) ← 关键支撑
4. 创建/切换环境 (worktree_module_intelligent_switch)
5. 后置验证 (status_module_get_complete_status)
```

**支撑逻辑详细**:
- **预同步逻辑**:
  - 创建Epic前: 确保base分支(通常是develop)是最新的
  - 创建Feature前: 确保Epic分支是最新的，已合并最新的base分支
- **智能存在性检查**:
  - 目标已存在: 切换到目标环境
  - 目标不存在: 创建新的worktree环境
- **Roadmap自动管理**:
  - 创建Epic时: 自动初始化roadmap文件
  - 创建Feature时: 自动在Epic roadmap中添加Feature记录
- **环境验证**:
  - 验证创建结果
  - 检查Git状态
  - 显示环境信息

**关键支撑操作**:
- `sync_module_intelligent_sync`: 确保基础分支最新
- `worktree_module_intelligent_switch`: 智能创建/切换
- `roadmap_module_epic_lifecycle`: 自动管理roadmap

### 3. pr命令 - 核心价值命令

**功能**: 智能PR创建，自动处理GitHub集成和状态验证

**支撑逻辑架构**:
```bash
gpf pr [options]
    ↓
1. 环境强制验证 (必须在epic/feature环境)
2. PR就绪性检查 (status_module_check_pr_ready) ← 关键支撑
3. 同步新鲜度检查 (sync_module_check_sync_needed) ← 关键支撑
4. GitHub环境验证 (github_module_environment_check)
5. 智能PR创建 (github_module_create_pr)
6. 结果验证和显示
```

**支撑逻辑详细**:
- **严格环境验证**:
  - 必须在epic或feature环境执行
  - 拒绝在root环境执行
- **PR就绪性检查**:
  - 工作区必须干净 (无未提交修改)
  - 分支必须已推送到远程
  - 必须有GitHub issue关联 (从分支名或commit message推断)
- **同步新鲜度检查**:
  - 检查目标分支是否有新提交
  - 发现过时时自动提示或执行同步
- **智能方向检测**:
  - Feature环境: Feature分支 → Epic分支
  - Epic环境: Epic分支 → develop分支
- **GitHub CLI集成**:
  - 自动生成PR标题 (从分支名推断)
  - 自动生成PR描述 (从commit历史生成)
  - 自动关联issue

**关键支撑操作**:
- `status_module_check_pr_ready`: PR就绪性检查
- `sync_module_check_sync_needed`: 同步新鲜度检查
- `github_module_create_pr`: GitHub PR创建

### 4. sync命令 - 同步管理命令

**功能**: 智能级联同步，自动处理上游更新

**支撑逻辑架构**:
```bash
gpf sync [scope]
    ↓
1. 环境检测 (environment_module_get_complete_info)
2. 同步范围确定 (根据当前环境和参数)
3. 安全性预检查 (工作区干净性)
4. 级联同步执行 (sync_module_intelligent_sync) ← 核心逻辑
5. 冲突检测和处理
6. 结果验证和报告
```

**支撑逻辑详细**:
- **级联同步策略**:
  - 在root环境: 同步develop → 所有epic → 所有features
  - 在epic环境: 同步develop → 当前epic → 当前epic的所有features
  - 在feature环境: 同步develop → 父epic → 当前feature
- **安全检查**:
  - 所有目标分支工作区必须干净
  - 检测潜在冲突
  - 提供回滚机制
- **Pull策略**:
  - 自动fetch远程更新
  - 智能merge策略选择
  - 冲突时暂停并提供指导
- **进度报告**:
  - 实时显示同步进度
  - 清晰标识成功/失败的操作
  - 提供详细的同步报告

**关键支撑操作**:
- `sync_module_intelligent_sync`: 智能同步逻辑
- `git_operations_fetch_and_merge`: 安全合并操作
- `status_module_check_sync_needed`: 同步需求检测

### 5. clean命令 - 清理管理命令

**功能**: 安全分支清理，自动处理PR状态和依赖检查

**支撑逻辑架构**:
```bash
gpf clean [--preview|--safe|--force]
    ↓
1. 环境检测 (environment_module_get_complete_info)
2. 清理范围确定 (根据当前环境)
3. 安全性分析 (status_module_check_clean_safe) ← 关键支撑
4. 清理建议生成 (🟢安全 🟡警告 🔴危险)
5. 用户确认 (除非--force)
6. 执行清理操作
7. 结果验证和报告
```

**支撑逻辑详细**:
- **安全性分析**:
  - 🟢 **安全清理**: PR已合并，分支已同步，无未推送提交
  - 🟡 **警告清理**: PR已合并但有本地修改，或分支落后
  - 🔴 **危险清理**: PR未合并，有未推送提交，或有未保存工作
- **清理范围智能确定**:
  - 在root环境: 分析所有epic和feature的清理状态
  - 在epic环境: 分析当前epic及其features的清理状态
  - 在feature环境: 分析当前feature的清理状态
- **预览模式** (默认):
  - 显示清理建议
  - 不执行实际清理
  - 提供清理命令建议
- **执行模式**:
  - `--safe`: 只清理🟢安全的分支
  - `--force`: 清理所有分支 (危险操作，需要二次确认)
- **PR状态检查**:
  - 自动查询GitHub PR状态
  - 检查PR合并状态
  - 验证分支保护规则

**关键支撑操作**:
- `status_module_check_clean_safe`: 清理安全性分析
- `github_module_query_pr_status`: PR状态查询
- `worktree_operations_cleanup`: 工作树清理

## 🔄 Commands间的协作模式

### 支撑逻辑调用关系

```
start命令 → sync命令逻辑 (预同步基础分支)
  ↓
pr命令 → status命令逻辑 (PR就绪性检查)
  ↓
pr命令 → sync命令逻辑 (同步新鲜度检查)
  ↓
clean命令 → status命令逻辑 (清理安全性检查)
  ↓
clean命令 → github查询逻辑 (PR状态检查)
```

### 共享支撑模块

所有命令都依赖的核心支撑模块:
- `environment_module`: 环境检测和上下文感知
- `status_module`: 统一状态检查和就绪性验证
- `sync_module`: 同步逻辑和新鲜度检查
- `github_module`: GitHub集成和PR管理
- `worktree_module`: 工作树管理和智能切换

## 📋 Commands实现规范

### 统一命令结构

每个命令文件都应遵循标准结构：

```bash
#!/bin/bash
# lib/commands/[command].sh
# 标准命令实现结构

# 1. 导入依赖Modules（严格遵循四层架构）
source "$(dirname "$0")/../core/modules/status-module.sh"
source "$(dirname "$0")/../core/modules/environment-module.sh"
source "$(dirname "$0")/../core/modules/worktree-module.sh"
source "$(dirname "$0")/../core/modules/github-module.sh"
source "$(dirname "$0")/../core/modules/sync-module.sh"

# 2. 命令参数解析
parse_command_arguments() {
    # 解析和验证命令行参数
    # 设置全局变量存储参数
}

# 3. 环境验证
validate_command_environment() {
    # 检查命令执行的前置条件
    # 验证必要的环境状态
}

# 4. 核心业务逻辑（只调用Modules方法）
execute_command_logic() {
    # 核心命令逻辑实现
    # 只调用modules层的方法
    # Modules层会自动调用下层的composite/atomic
}

# 5. 主入口
main() {
    parse_command_arguments "$@"
    validate_command_environment
    execute_command_logic
}

# 执行主函数
main "$@"
```

### 实现原则

1. **严格分层调用**: Commands层只调用Modules层，绝不跨层调用
2. **功能不足时向下开发**: 发现Modules层功能不足时，回到Epic1相应Feature补充，而不是跨层调用
3. **错误处理**: 每个函数都要有完整的错误处理
4. **用户体验**: 提供清晰的进度反馈和错误提示

## 💡 Epic驱动的分层开发原则

### 核心理念：不跨层，不冗余，逐层完善

当Commands层开发过程中发现下层功能不足时，**绝不允许**：
- ❌ 跨层直接调用Composite或Atomic层
- ❌ 在Commands层重复实现下层功能  
- ❌ 创建临时的workaround方案

**正确做法**：
1. **暂停Commands层开发**
2. **切换到Epic1对应的Feature worktree**
3. **在相应层次补充缺失功能**
4. **测试和验证新功能**
5. **合并到Epic1，再合并到develop**
6. **回到Commands层继续开发**

### 实践示例

```bash
# 场景：开发pr命令时发现github-module缺少某个方法
$ cd .worktrees/epic-commands-layer-e-pr-ef
$ # 发现 github_module_check_issue_association() 方法不存在

# ❌ 错误做法：直接调用composite或atomic层
github_composite_check_issue() { ... }  # 跨层调用

# ✅ 正确做法：回到Epic1补充功能
$ cd /project/root
$ git worktree add .worktrees/epic-core-foundation-e-modules-github-fix \
    -b epic-core-foundation-e-modules-github-fix epic-core-foundation-e

$ cd .worktrees/epic-core-foundation-e-modules-github-fix
$ # 在github-module.sh中添加缺失的方法
$ vim lib/core/modules/github-module.sh
$ # 添加 github_module_check_issue_association() 方法

$ # 测试新功能
$ # 提交和合并
$ git add . && git commit -m "add: github issue association check method"

# 合并流程：Feature → Epic1 → develop → Epic2
$ # 1. PR: epic-core-foundation-e-modules-github-fix → epic-core-foundation-e  
$ # 2. PR: epic-core-foundation-e → develop
$ # 3. 同步: develop → epic-commands-layer-e
$ # 4. 继续Commands层开发
```

### 架构完整性保证

这种做法确保：
- **架构纯净性**: 每层职责清晰，无跨层调用
- **功能完整性**: 下层功能经过充分设计和测试
- **可维护性**: 避免重复代码和临时方案
- **Epic隔离性**: 各Epic功能完整，可独立发布

## 🎯 Commands Layer实现优先级

### Phase 1: 基础支撑 (Week 4)
1. **status命令**: 作为其他命令的基础，必须优先实现
2. **环境检测集成**: 确保所有命令都能正确感知当前环境

### Phase 2: 核心创建 (Week 4-5)
3. **start命令**: 实现智能创建和切换逻辑
4. **同步支撑集成**: 确保start命令的预同步逻辑正确

### Phase 3: 核心价值 (Week 5)
5. **pr命令**: 实现PR创建的完整流程
6. **GitHub集成验证**: 确保PR创建的可靠性

### Phase 4: 管理完善 (Week 5-6)
7. **sync命令**: 实现级联同步逻辑
8. **clean命令**: 实现安全清理逻辑

## 📊 质量标准

### 功能质量
- **智能性**: 所有命令都能根据环境自动调整行为
- **安全性**: 危险操作必须有多重验证和确认
- **一致性**: 所有命令的用户体验保持一致
- **可靠性**: 错误处理覆盖率100%

### 性能质量
- **响应时间**: 命令执行时间<2秒
- **资源使用**: 内存占用<50MB
- **并发安全**: 支持多终端同时使用

### 用户体验质量
- **学习成本**: 新用户5分钟掌握基本用法
- **错误提示**: 100%错误场景提供解决方案
- **进度反馈**: 长时间操作提供进度显示

## 🚀 实施计划

### Epic2: Commands Layer实现
```bash
epic-commands-layer-e                    # Epic分支
├── epic-commands-layer-e-status-ef      # Feature1: status命令
├── epic-commands-layer-e-start-ef       # Feature2: start命令  
├── epic-commands-layer-e-pr-ef          # Feature3: pr命令
├── epic-commands-layer-e-sync-ef        # Feature4: sync命令
└── epic-commands-layer-e-clean-ef       # Feature5: clean命令
```

### 开发顺序
1. 创建Epic2环境: `epic-commands-layer-e`
2. 实现status命令: `epic-commands-layer-e-status-ef`
3. 实现start命令: `epic-commands-layer-e-start-ef`
4. 实现pr命令: `epic-commands-layer-e-pr-ef`
5. 实现sync命令: `epic-commands-layer-e-sync-ef`
6. 实现clean命令: `epic-commands-layer-e-clean-ef`
7. 集成测试和Epic2完成

### 验证标准
- 所有命令通过单元测试
- 所有支撑逻辑通过集成测试
- 完整的用户使用场景测试
- 错误处理和边界情况测试

---

> **总结**: Commands Layer是用户直接交互的界面，通过智能的支撑逻辑确保每个命令都能安全、便捷地完成用户的意图。五个命令相互协作，共同构成了GPF的完整用户体验。