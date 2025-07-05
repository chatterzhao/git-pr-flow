# GPF 核心公共组件设计

> 📖 **相关文档**: [主文档](../README.md) | [架构设计](ARCHITECTURE.md) | [命令详细](COMMANDS.md) | [术语表](术语表.md)

## 文档说明

本文档已拆分为多个专门的组件文档，以便更好地维护和阅读。请根据需要查阅相应的组件文档。

## 设计原则

基于用户的架构哲学："基本方法在 core 文档，并且多个命令是一样的方法，也在core里将多个基本方法组装为高级一点的方法。command文档根据具体命令调用通用或某个命令不一样的调用core 方法扩展加一些自有方法组装为该命令所需方法"

1. **单一职责**：每个组件只负责一个明确的功能域
2. **无副作用**：纯函数设计，输入确定输出确定
3. **错误透明**：清晰的错误传播和处理机制
4. **测试友好**：每个函数都可以独立测试
5. **平台兼容**：跨平台文件系统和路径处理
6. **职责分离**：core提供基础工具，command组合使用
7. **🆕 GitHub集成**：统一的GitHub CLI检查和PR状态管理

## 核心组件文档索引

### 🏗️ 基础组件
- **[环境检测](core/core-context.md)** - 检测当前执行环境，为所有命令提供统一的环境信息
- **[路径管理](core/core-paths.md)** - 统一的路径计算和转换，处理所有与文件系统路径相关的操作
- **[Worktree管理](core/core-worktree.md)** - Worktree创建、检测、切换和清理的统一管理

### 🔧 核心工具
- **[状态验证](core/core-validation.md)** - Git状态验证，工作区干净性检查等
- **[Git操作](core/core-git-ops.md)** - Git操作的统一封装，提供一致的接口
- **[用户界面](core/core-ui.md)** - 统一的用户界面输出，避免耦合

### 📋 业务组件
- **[Epic Roadmap管理](core/core-roadmap.md)** - 管理Epic的roadmap文件生成、验证和Epic分支保护机制
- **[同步管理](core/core-sync.md)** - 智能的级联同步管理，支持上往下的分支同步、自动pull远程更新、安全检查和冲突处理
- **[状态检查](core/core-status.md)** - 统一状态检查架构，供所有命令使用的状态检查和分析功能

### 🚀 高级组件
- **[工作流方法](core/core-workflows.md)** - 多命令共用的中级组合方法和命令级别的高级工作流方法
- **[GitHub集成](core/core-github.md)** - GitHub CLI环境检查、PR状态检查和操作、Issue关联处理

## 组件分层架构

### Layer 1 - 基础方法（原子操作）
- `path_extract_suffix()`, `strip_epic_prefix_from_input()`, `validate_name_format()`
- 专注单一功能，无副作用，可独立测试

### Layer 2 - 验证方法（输入检查）  
- `validate_input_suffix_matches_expected()`, `validate_epic_prefix_format()`, `check_branch_safety()`
- 组合基础方法进行验证，返回明确结果

### Layer 3 - 处理方法（转换规范）
- `ensure_suffix_present()`, `transform_input_to_epic_branch()`, `build_standard_branch_name()`
- 组合基础和验证方法，进行数据转换

### Layer 4 - 多命令共用组合（中级工作流）
- `intelligent_parse_user_intent()`, `intelligent_navigate_to_target()`, `execute_epic_workflow()`
- **关键层**：被start/pr/clean多个命令共同使用

### Layer 5 - 命令专用工作流（高级组合）
- `start_epic_creation_workflow()`, `auto_detect_pr_direction_workflow()`, `environment_aware_cleanup_workflow()`
- **专门为特定命令定制**，但仍调用Layer 4的共用方法

## 使用原则

命令文件应该：
- 调用core提供的基础和组合方法
- 实现命令特定的逻辑和工作流
- 避免重复实现core已有的功能
- 保持轻量，专注于命令编排

## 维护说明

- 修改基础功能只需更新对应的core组件文档
- 新增命令可以直接复用现有的core工具
- 每个组件文档都可以独立维护和测试
- 所有组件都遵循统一的设计原则和接口规范