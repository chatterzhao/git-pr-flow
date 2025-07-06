# Epic: Commands Layer Implementation Roadmap

> **Epic目标**: 实现GPF的5个核心用户命令，提供完整的Epic/Feature开发工作流支持

> **Epic基础**: 基于Epic1 (core-foundation) 的三层架构，严格遵循Commands→Modules→Composite→Atomic的四层架构

## 🎯 Epic概述

### 核心价值
Commands Layer是GPF工具的用户接口层，通过5个智能命令为用户提供：
- **简化的Epic/Feature开发流程**
- **智能的环境感知和自动切换**  
- **安全的状态检查和验证**
- **无缝的GitHub PR集成**
- **完整的分支生命周期管理**

### 架构原则
- **严格分层调用**: Commands层只调用Modules层，绝不跨层调用
- **功能不足时向下开发**: 发现Modules功能不足时，回到Epic1补充
- **智能用户体验**: 每个命令都具备环境感知和自动化能力
- **安全第一**: 所有危险操作都有多重验证和确认机制

## 📋 Feature实施计划

### Phase 1: 基础支撑命令 (优先级最高)

#### Feature 1: status命令 (`epic-commands-layer-e-status-ef`)
**目标**: 实现智能状态显示，作为其他命令的基础支撑

**核心功能**:
- 智能环境检测和状态显示
- 为pr、clean、sync命令提供状态检查支撑
- JSON格式状态输出和用户友好格式转换

**依赖的Modules** (来自Epic1):
- `environment_module_get_complete_info` ❓ (可能需要补充)
- `status_module_get_complete_status` ❓ (可能需要补充)  
- `validation_module_*` ✅ (已有)

**支撑逻辑架构**:
```bash
gpf status [epic] [feature]
    ↓
1. 环境检测 (environment_module_get_complete_info)
2. 确定显示范围 (根据当前环境和参数)
3. 收集状态信息 (status_module_get_complete_status)
4. 格式化输出 (JSON → 用户友好格式)
```

**成功标准**:
- [ ] 在root环境显示所有epic状态
- [ ] 在epic环境显示当前epic及其features状态  
- [ ] 在feature环境显示当前feature状态
- [ ] 为其他命令提供status检查接口

### Phase 2: 核心创建命令

#### Feature 2: start命令 (`epic-commands-layer-e-start-ef`)
**目标**: 实现智能Epic/Feature环境创建和切换

**核心功能**:
- 智能创建Epic/Feature worktree环境
- 自动同步基础分支确保最新代码
- 集成gitignore检查 (Epic1已实现✅)
- 自动roadmap管理

**依赖的Modules** (来自Epic1):
- `validation_module_ensure_gitignore_for_start` ✅ (已实现)
- `sync_module_intelligent_sync` ❓ (需要补充)
- `worktree_module_intelligent_switch` ❓ (需要补充)
- `roadmap_module_epic_lifecycle` ❓ (需要补充)

**支撑逻辑架构**:
```bash
gpf start -e <epic> [base] / gpf start -ef <feature> <epic>
    ↓
1. 参数解析和验证 (path_normalize_user_input)
2. 环境预检查 (environment_module_get_complete_info)
3. 同步基础分支 (sync_module_intelligent_sync)
4. 创建/切换环境 (worktree_module_intelligent_switch)
5. gitignore检查 (validation_module_ensure_gitignore_for_start) ✅
6. roadmap管理 (roadmap_module_epic_lifecycle)
7. 后置验证 (status_module_get_complete_status)
```

### Phase 3: 核心价值命令

#### Feature 3: pr命令 (`epic-commands-layer-e-pr-ef`) 
**目标**: 实现智能PR创建和GitHub集成

**核心功能**:
- 智能PR就绪性检查
- 自动GitHub PR创建和issue关联
- 智能分支方向检测 (Feature→Epic, Epic→develop)

**依赖的Modules** (来自Epic1):
- `status_module_check_pr_ready` ❓ (需要补充)
- `sync_module_check_sync_needed` ❓ (需要补充)
- `github_module_create_pr` ❓ (需要补充)

### Phase 4: 管理完善命令

#### Feature 4: sync命令 (`epic-commands-layer-e-sync-ef`)
**目标**: 实现智能级联同步管理

#### Feature 5: clean命令 (`epic-commands-layer-e-clean-ef`)
**目标**: 实现安全分支清理管理

## 🔄 Epic驱动开发流程

### 开发原则
当Commands层开发过程中发现Modules层功能不足时：

1. **暂停Commands层开发**
2. **切换到Epic1对应的Feature worktree**  
3. **在相应Modules层补充缺失功能**
4. **测试和验证新功能**
5. **合并到Epic1，再合并到develop**
6. **回到Commands层继续开发**

### 实践示例
```bash
# 发现 environment_module_get_complete_info() 方法不存在
# ✅ 正确做法：回到Epic1补充功能

$ cd /project/root
$ git worktree add .worktrees/epic-core-foundation-e-modules-env-fix \
    -b epic-core-foundation-e-modules-env-fix epic-core-foundation-e

$ # 在environment-module.sh中添加缺失的方法
$ # 测试、提交、合并
$ # 同步到Commands层继续开发
```

## 📊 质量标准

### 功能质量
- **智能性**: 所有命令根据环境自动调整行为
- **安全性**: 危险操作有多重验证和确认
- **一致性**: 所有命令的用户体验保持一致
- **可靠性**: 错误处理覆盖率100%

### 用户体验质量  
- **学习成本**: 新用户5分钟掌握基本用法
- **错误提示**: 100%错误场景提供解决方案
- **进度反馈**: 长时间操作提供进度显示

## 🎯 Epic成功标准

- [ ] 5个命令全部实现并通过测试
- [ ] 所有Commands严格遵循四层架构，无跨层调用
- [ ] 完整的Epic/Feature工作流可正常运行
- [ ] GitHub PR集成功能正常
- [ ] 所有支撑逻辑通过集成测试
- [ ] 用户文档和示例完整

---

> **总结**: Commands Layer将Epic1的三层架构能力转化为用户可直接使用的智能命令，通过严格的分层架构确保代码质量，通过智能的支撑逻辑提供卓越的用户体验。