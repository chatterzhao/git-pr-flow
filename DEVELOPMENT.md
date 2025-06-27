# Git PR Flow 开发文档

> 贡献代码指南 - 技术实现和开发流程

## 快速导航

- 📖 **[项目介绍](README.md)** - 了解项目目标和核心价值
- 🏗️ **[架构设计](ARCHITECTURE.md)** - 系统架构和模块设计
- 📘 **[API文档](API.md)** - 命令行接口参考
- 🎨 **[交互设计](UX.md)** - 用户体验设计

## 开发环境配置

### 技术要求
- Bash 4.0+
- Git 2.20+
- 系统命令: sed, awk, grep, sort, uniq

### 开发原则
1. **零依赖** - 纯 Bash 实现，只依赖 Git
2. **交互优先** - 所有复杂选择都用交互式菜单，不依赖参数记忆
3. **智能推荐** - 基于代码分析提供上下文相关的最佳选择
4. **受控节奏** - 支持策略性PR提交，不强制立即操作
5. **安全第一** - 所有危险操作都需要确认

## 项目结构

```
git-pr-flow/
├── bin/
│   └── git-pr-flow              # 主入口脚本
├── lib/
│   ├── core/
│   │   ├── init.sh              # 初始化功能
│   │   ├── status.sh            # 状态检查
│   │   ├── sync.sh              # 同步逻辑
│   │   └── worktree.sh          # 工作树管理
│   ├── utils/
│   │   ├── git.sh               # Git 工具函数
│   │   ├── ui.sh                # 交互界面
│   │   ├── config.sh            # 配置管理
│   │   └── common.sh            # 通用工具
│   └── commands/
│       ├── init.sh              # init 命令
│       ├── start.sh             # start 命令
│       ├── status.sh            # status 命令
│       ├── sync.sh              # sync 命令
│       ├── clean.sh             # clean 命令
│       └── interactive.sh       # 交互式命令处理
├── tests/
│   ├── unit/                    # 单元测试
│   ├── integration/             # 集成测试
│   └── fixtures/                # 测试数据
├── docs/
│   ├── ARCHITECTURE.md          # 架构设计
│   ├── API.md                   # API 设计
│   ├── UX.md                    # 交互设计
│   └── examples/                # 使用示例
└── config/
    └── templates/               # 配置模板
```

## 开发环境

### 依赖要求
- Bash 4.0+
- Git 2.20+
- 系统命令: sed, awk, grep, sort, uniq

### 开发工具
```bash
# 安装开发环境
make dev-setup

# 运行测试
make test

# 代码检查
make lint

# 生成文档
make docs
```

### 测试框架
使用 `bats` (Bash Automated Testing System) 进行测试：

```bash
# 运行所有测试
bats tests/

# 运行特定测试
bats tests/unit/sync.bats

# 带覆盖率
make test-coverage
```

## 核心模块设计

### 1. 配置系统 (config.sh)
```bash
# 配置文件层次 (按优先级排序)
.git-pr-flow.yaml    # Epic级配置文件 (新增，最高优先级)
.git/pr-config       # 项目配置
~/.gitprconfig       # 全局配置

# Epic配置文件结构 (.git-pr-flow.yaml)
epic_name: auth
description: 用户认证系统
base_branch: develop
architecture: complete
epic_branch: epic/auth
worktree_path: .worktrees/auth
workflow_type: gitflow
created_at: 2024-01-01T10:00:00Z
config_version: "1.0"

# 传统配置结构 (.git/pr-config)
[core]
epic_dir = @epics
temp_dir = @temp

[sync]
default_scope = deps
conflict_mode = prompt

# 配置管理函数
config_file_exists()     # 检查Epic配置文件是否存在
config_file_get()        # 从配置文件读取值
config_file_set()        # 向配置文件写入值
config_file_validate()   # 验证配置文件完整性
config_file_create_epic() # 创建新的Epic配置文件
```

### 2. 工作树管理 (worktree.sh)
```bash
create_epic_worktree() {
  local epic_name="$1"
  local branch_name="$2"
  # 创建 Epic 工作树逻辑
}

cleanup_worktree() {
  local worktree_path="$1"
  # 安全清理工作树
}
```

### 3. 同步引擎 (sync.sh)
```bash
sync_branch_chain() {
  local target_branch="$1"
  local scope="$2"
  # 智能同步依赖链
}

resolve_conflicts() {
  local conflict_files=("$@")
  # 交互式冲突解决
}
```

### 4. 状态检查 (status.sh)
```bash
get_branch_status() {
  local branch="$1"
  # 返回分支状态信息
}

generate_dependency_tree() {
  # 生成依赖关系可视化
}
```

## 交互界面设计

### 颜色系统
```bash
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 状态图标
ICON_SUCCESS="✔"
ICON_WARNING="⚠"
ICON_ERROR="✗"
ICON_INFO="ℹ"
```

### 提示系统
```bash
prompt_choice() {
  local question="$1"
  shift
  local choices=("$@")
  # 显示选择菜单
}

confirm_action() {
  local message="$1"
  local default="${2:-N}"
  # 确认对话框
}
```

## 错误处理

### 错误类别
1. **用户错误** - 输入参数错误，显示帮助信息
2. **环境错误** - Git 状态异常，提供修复建议
3. **系统错误** - 内部错误，记录日志并安全退出

### 错误处理策略
```bash
handle_error() {
  local error_code="$1"
  local error_msg="$2"
  local context="$3"
  
  case "$error_code" in
    "GIT_DIRTY")
      echo "错误: 工作目录有未提交更改"
      echo "建议: git add . && git commit"
      ;;
    "CONFLICT_DETECTED")
      echo "冲突: $error_msg"
      prompt_conflict_resolution "$context"
      ;;
  esac
}
```

## 性能优化

### Git 操作优化
```bash
# 批量 Git 操作
git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads/

# 避免重复检查
cache_branch_status() {
  local cache_file="/tmp/git-pr-status-$$"
  # 缓存分支状态
}
```

### 内存管理
- 避免大文件一次性读取
- 使用流式处理处理大量分支
- 及时清理临时文件

## 扩展机制

### 插件系统
```bash
# 插件目录结构
~/.git-pr/plugins/
├── my-plugin/
│   ├── commands/
│   │   └── my-command.sh
│   └── hooks/
│       └── post-sync.sh

# 插件加载
load_plugins() {
  for plugin in ~/.git-pr/plugins/*/; do
    [[ -f "$plugin/init.sh" ]] && source "$plugin/init.sh"
  done
}
```

### Hook 系统
```bash
# Hook 类型
pre-sync
post-sync
pre-worktree-create
post-worktree-create
pre-conflict-resolve
post-conflict-resolve

# Hook 执行
run_hook() {
  local hook_name="$1"
  shift
  local args=("$@")
  
  for hook in ~/.git-pr/hooks/"$hook_name"*; do
    [[ -x "$hook" ]] && "$hook" "${args[@]}"
  done
}
```

## 发布流程

### 版本管理
- 使用语义化版本 (SemVer)
- 在 `bin/git-pr` 中维护版本号
- 每个发布创建对应的 Git 标签

### 打包发布
```bash
# 创建发布包
make package

# 生成安装脚本
make installer

# 发布到 GitHub Releases
make release
```

### 安装脚本
```bash
#!/bin/bash
# install.sh
curl -fsSL https://github.com/user/git-pr-cli/raw/main/install.sh | bash
```

## 贡献指南

### 代码规范
1. 遵循 [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
2. 函数名使用 `snake_case`
3. 常量使用 `UPPER_CASE`
4. 所有函数都要有注释

### 提交规范
```
<type>(<scope>): <subject>

<body>

<footer>
```

类型：
- feat: 新功能
- fix: 修复
- docs: 文档
- refactor: 重构
- test: 测试

### PR 流程
1. Fork 项目
2. 创建功能分支
3. 编写测试
4. 确保所有测试通过
5. 提交 PR

## 调试指南

### 调试工具
```bash
# 启用调试模式
export GIT_PR_DEBUG=1

# 详细日志
export GIT_PR_VERBOSE=1

# 跟踪执行
bash -x bin/git-pr sync
```

### 常见问题
1. **工作树创建失败** - 检查磁盘空间和权限
2. **同步冲突** - 查看冲突文件和解决建议
3. **依赖检测错误** - 验证分支关系配置

### 日志系统
```bash
log_debug() {
  [[ "$GIT_PR_DEBUG" == "1" ]] && echo "DEBUG: $*" >&2
}

log_info() {
  echo "INFO: $*" >&2
}

log_error() {
  echo "ERROR: $*" >&2
}
```

## 未来规划

### 短期目标 (v1.0)
- [ ] 核心同步功能
- [ ] 工作树管理
- [ ] 基础交互界面
- [ ] 完整测试覆盖

### 中期目标 (v2.0)
- [ ] 插件系统
- [ ] 高级冲突解决
- [ ] 性能优化
- [ ] GUI 界面

### 长期目标 (v3.0)
- [ ] 云端配置同步
- [ ] 团队协作功能
- [ ] AI 辅助冲突解决
- [ ] 与 IDE 集成