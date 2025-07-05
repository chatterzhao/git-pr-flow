# GPF 新版本架构设计

> 📖 **相关文档**: [主文档](../newgpf-README.md) | [命令详细](newgpf-COMMANDS.md) | [核心组件](newgpf-CORE-COMPONENTS.md) | [术语表](newgpf-术语表.md)

基于 [newgpf-README.md](../newgpf-README.md) 的设计理念，GPF采用明确的参数格式、统一的 **epic- 前缀标识系统** 和 **智能切换功能**。

> 术语说明：参考 [术语表](newgpf-术语表.md) 了解标准定义。

## 总体架构

```
gpf (新版本)
├── bin/git-pr-flow          # 主入口脚本
├── lib/
│   ├── core/                # 按四层架构重新组织
│   │   ├── atomic/         # 底层原子方法 - 单一功能，无业务逻辑
│   │   │   ├── git-atomic.sh
│   │   │   ├── gh-atomic.sh
│   │   │   ├── path-atomic.sh
│   │   │   ├── worktree-query.sh
│   │   │   ├── github-pr-query.sh
│   │   │   ├── environment-atomic.sh
│   │   │   ├── roadmap-template.sh
│   │   │   └── epic-validation.sh
│   │   ├── composite/      # 中层组合方法 - 组合原子方法
│   │   │   ├── git-composite.sh
│   │   │   ├── gh-composite.sh
│   │   │   ├── path-composite.sh
│   │   │   ├── worktree-composite.sh
│   │   │   ├── github-pr-composite.sh
│   │   │   └── roadmap-composite.sh
│   │   ├── modules/        # 模块层聚拢方法 - 完整功能模块
│   │   │   ├── status-module.sh
│   │   │   ├── github-module.sh
│   │   │   ├── worktree-module.sh
│   │   │   ├── environment-module.sh
│   │   │   └── roadmap-module.sh
│   │   └── operations/     # 操作层原子方法 - 仅执行操作
│   │       ├── worktree-operations.sh
│   │       ├── github-pr-operations.sh
│   │       └── git-operations.sh
│   └── commands/           # 命令编排层 - 只调用模块方法
│       ├── start.sh        # 只调用 worktree-module + environment-module + roadmap-module
│       ├── pr.sh          # 只调用 status-module + github-module
│       ├── clean.sh       # 只调用 status-module + worktree-module
│       ├── status.sh      # 只调用 status-module
│       └── sync.sh        # 只调用 worktree-module + environment-module
└── docs/                   # 文档
```

## 核心设计原则

### 1. 分层架构原则
按照"底层最散，上层聚拢"的理念：
- **底层原子方法**：单一功能，最散布，无业务逻辑
- **中层组合方法**：组合多个原子方法，形成功能单元
- **模块层聚拢方法**：完整功能模块，供命令直接调用
- **命令层编排**：只做业务编排，调用模块方法

### 2. 模块复用原则
- 命令需要完整功能时：直接调用模块方法（如status模块）
- 命令需要部分功能时：调用中层组合方法
- 命令有特殊需求时：自有方法+底层原子方法组合
- 避免命令间直接调用，改为调用共同的模块方法

### 3. 单一职责原则
- 每个命令只负责一个核心功能
- 公共组件职责清晰，不互相依赖
- 修改任何组件不影响其他命令

### 4. 环境驱动
所有操作基于当前环境自动推断：

```bash
# 环境检测结果
Environment = {
  type: "root" | "epic" | "feature" | "unknown"
  epic_name: string | null
  feature_name: string | null  
  current_path: string
  git_branch: string
}
```

### 5. 路径抽象
统一的路径管理，跨平台兼容：

```bash
# 路径工具函数
get_project_root()                    # 项目根目录
get_epic_worktree_path(epic_name)     # Epic工作树路径
get_feature_worktree_path(epic, feat) # 功能工作树路径
to_git_branch_name(path_name)         # 路径名转Git分支名
to_worktree_name(git_branch)          # Git分支名转工作树名

# 🚀 智能切换工具函数（新设计）
switch_to_target_environment(type, identifier, fallback)  # 统一的智能切换接口
switch_to_worktree(branch, fallback)         # worktree切换
switch_to_root(branch)                       # 根目录切换
smart_switch_to_target(target, fallback)       # 智能选择目标环境

# 🆕 智能切换工具函数（保留兼容）
find_worktree_by_branch(branch_name)  # 根据分支名查找worktree路径
create_and_switch_worktree(branch, base) # 创建并切换worktree
```

## 命令设计

### `gpf start` 

**参数模式：**
- `gpf start` - 交互模式，引导用户选择
- `gpf start -e <epic-name> <base-branch>` - 创建Epic
- `gpf start -ef <feature-name> <epic-name>` - 创建 Epic 的子 Feature

**🆕 智能切换+同步执行流程：**
1. 参数解析和验证（-e/-ef标志）
2. 统一前缀处理（移除用户输入前缀，添加标准epic-前缀）
3. **Worktree检测**：扫描已存在的worktree
4. **智能切换判断**：
   - 存在 → 自动切换到对应worktree
   - 不存在 → 继续创建流程
5. **🆕 同步检查**（仅-ef命令）：检查Epic是否需要从develop同步
6. **🆕 Epic环境准备**（仅-ef命令）：自动切换到Epic环境作为基础分支
7. 环境检测
8. 路径计算
9. Git操作执行
10. 工作树创建（仅在不存在时）
11. 切换到目标环境

### `gpf pr`

> 详细命令说明参考 [命令详细文档](newgpf-COMMANDS.md#gpf-pr---创建github-pull-request)。

**🔧 GitHub CLI 集成核心：**
- **环境强制验证**：必须在Epic或Feature的worktree环境中执行
- **GitHub CLI检查**：自动验证gh工具安装、认证和仓库支持
- **智能切换**：支持目标参数，自动切换到对应worktree
- **状态完整验证**：调用统一的`status_module_get_complete_status`进行本地和GitHub状态检查
- **Issue关联强制**：PR必须关联GitHub issue（最佳实践要求）
- **直接创建PR**：调用`gh pr create`在GitHub创建真实PR
- **结果展示**：自动执行`gh pr view`显示创建结果

**依赖和集成：**
- **GitHub CLI依赖**：完全依赖gh工具，提供完整错误处理和解决方案
- **Status组件集成**：复用统一的状态检查接口
- **Worktree智能切换**：利用现有的智能切换功能
- **前缀处理复用**：使用统一的分支名称处理机制

### `gpf clean`

> 详细清理策略参考 [清理命令设计](newgpf-COMMANDS.md#gpf-clean---清理分支)。

**🆕 环境感知的智能清理：**
- 基于当前执行环境智能确定清理范围
- 支持可选目标参数精确指定清理对象
- 🆕 集成状态分析，提供详细的安全级别报告

**安全模式：**
- `gpf clean [target]` 预览模式（默认）
- `gpf clean --safe [target]` 安全清理
- `gpf clean --force [target]` 强制清理

**清理范围：**
- 根目录：所有GPF管理的worktree分支
- Epic环境：该Epic的所有 Epic 的子 Feature 分支
- Feature环境：仅当前 Epic 的子 Feature 分支
- 指定目标：Epic或 Epic 的子 Feature 的精确清理

### `gpf status`

**🆕 环境感知的状态显示：**
- 基于当前执行环境智能确定显示范围
- 支持指定目标参数查看特定Epic或Feature状态
- 提供完整的开发进度和状态可视化

**显示模式：**
- `gpf status` 根据当前环境智能显示
- `gpf status <epic>` 显示Epic及所有子features
- `gpf status <epic> <feature>` 显示特定feature详细状态

**状态信息：**
- 未保存修改数量、未提交内容数量、未推送提交数量
- 分支合并状态、开发进度估算
- 依赖关系和同步状态

### `gpf sync`

**🆕 智能级联同步：**
- 基于当前执行环境智能确定同步范围
- 支持指定目标参数同步特定Epic或Feature
- 自动执行上往下的级联同步（develop→epic→features）

**同步模式：**
- `gpf sync` 根据当前环境智能同步
- `gpf sync <epic>` 同步指定Epic及所有子features

**同步流程：**
- Pull最新远程代码、检查同步安全性
- 执行级联同步、推送同步结果
- 提供详细的同步报告和冲突处理

## 组件分层设计

### 分层架构实现

按照"底层最散，上层聚拢"原则，组件分为四层：

```
lib/core/
├── atomic/             # 底层原子方法 - 最散布，单一功能，无业务逻辑
│   ├── git-atomic.sh           # Git原子操作
│   │   ├── git_get_current_branch()
│   │   ├── git_check_working_tree_clean()
│   │   └── git_check_branch_pushed()
│   ├── gh-atomic.sh            # GitHub CLI原子操作
│   │   ├── gh_check_installation()
│   │   ├── gh_check_auth()
│   │   └── gh_get_pr_basic_info()
│   ├── path-atomic.sh          # 路径原子操作
│   │   ├── path_extract_suffix()
│   │   ├── path_strip_prefix()
│   │   └── path_validate_format()
│   ├── roadmap-template.sh     # Roadmap模板原子操作
│   │   ├── roadmap_generate_template()
│   │   ├── roadmap_get_epic_info()
│   │   └── roadmap_validate_path()
│   └── epic-validation.sh      # Epic分支验证原子操作
│       ├── epic_check_roadmap_only()
│       ├── epic_validate_commit_files()
│       └── epic_get_modified_files()
│
├── composite/          # 中层组合方法 - 组合多个原子方法，形成功能单元
│   ├── git-composite.sh       # Git组合操作
│   │   ├── git_validate_branch_state()     # = git_check_working_tree_clean + git_check_branch_pushed
│   │   └── git_ensure_safe_state()         # = multiple git checks
│   ├── gh-composite.sh         # GitHub组合操作
│   │   ├── gh_validate_environment()       # = gh_check_installation + gh_check_auth
│   │   └── gh_get_pr_complete_info()       # = gh_get_pr_basic_info + formatting
│   ├── path-composite.sh       # 路径组合操作
│   │   ├── path_normalize_user_input()     # = extract + strip + validate
│   │   └── path_generate_standard_names()  # = multiple path generations
│   └── roadmap-composite.sh     # Roadmap组合操作
│       ├── roadmap_initialize_epic()       # = generate_template + validate_path + create_file
│       └── roadmap_validate_epic_commit()  # = check_roadmap_only + validate_commit_files
│
├── modules/            # 模块层聚拢方法 - 完整功能模块，供命令直接调用
│   ├── status-module.sh        # 状态检查模块
│   │   └── status_module_get_complete_status()
│   ├── github-module.sh        # GitHub管理模块
│   │   └── github_module_manage_pr_lifecycle()
│   ├── worktree-module.sh      # 工作树管理模块
│   │   └── worktree_module_manage_lifecycle()
│   ├── environment-module.sh   # 环境管理模块
│   │   └── environment_module_detect_and_switch()
│   └── roadmap-module.sh        # Roadmap管理模块
│       ├── roadmap_module_manage_epic_lifecycle()
│       └── roadmap_module_validate_epic_operations()
│
└── commands/           # 命令编排层 - 只做业务编排，调用模块方法
    ├── start.sh       # 只调用 worktree_module + environment_module + roadmap_module
    ├── pr.sh         # 只调用 status_module + github_module
    ├── clean.sh      # 只调用 status_module + worktree_module
    ├── status.sh     # 只调用 status_module
    └── sync.sh       # 只调用 worktree_module + environment_module
```

### 调用关系规范

```bash
# ✅ 正确的四层调用关系
命令层 (commands/): pr_command()
  ↓ 只调用模块层方法
模块层 (modules/): github_module_manage_pr_lifecycle()
  ↓ 调用中层组合方法
中层 (composite/): gh_validate_environment() + git_validate_branch_state()
  ↓ 调用底层原子方法
底层 (atomic/): gh_check_installation() + git_check_working_tree_clean()

# ❌ 错误的调用关系
命令层 → 命令层     # 禁止：命令间直接调用
命令层 → 底层原子    # 禁止：跨层调用
中层 → 模块层      # 禁止：反向调用
```

### 层级职责说明

| 层级 | 职责 | 特点 | 示例 |
|------|------|------|------|
| **原子层** | 单一功能，无业务逻辑 | 纯函数，可独立测试 | `git_get_current_branch()` |
| **组合层** | 组合原子方法，形成功能单元 | 有简单逻辑，可复用 | `git_validate_branch_state()` |
| **模块层** | 完整功能模块，供命令调用 | 包含业务逻辑，高内聚 | `status_module_get_complete_status()` |
| **命令层** | 业务编排，用户交互 | 组织流程，处理参数 | `pr_command()` |

## 公共组件设计

### context.sh - 环境检测

```bash
detect_environment() {
  # 返回标准化的环境对象
  # 所有命令都使用相同的环境信息
}

is_in_epic()     # 是否在Epic环境
is_in_feature()  # 是否在功能环境  
is_in_root()     # 是否在项目根目录环境
```

### paths.sh - 路径管理

```bash
# 统一前缀处理（核心功能）
strip_epic_prefix_from_input()     # 清除用户输入的epic-前缀
add_epic_prefix()        # 统一添加epic-前缀
process_feature_name()   # 处理Epic子功能名称

# 路径转换
get_epic_worktree_path()    # auth -> .worktrees/epic-auth-e
get_feature_worktree_path() # auth login -> .worktrees/epic-auth-e-login-ef

# Git分支转换（分支名与worktree目录名一致）
epic_to_git_branch()    # auth -> epic-auth-e
feature_to_git_branch() # auth login -> epic-auth-e-login-ef
git_branch_to_epic()    # epic-auth-e -> auth
git_branch_to_feature() # epic-auth-e-login-ef -> auth login
```

### 🆕 worktree组件 - 职责分离设计

按照新架构的单一职责原则，worktree功能分离为查询和操作两个组件：

```bash
# worktree-query.sh - 仅查询职责（原子层）
worktree_list_all()            # 列出所有现有worktree
worktree_find_by_branch()      # 根据分支名查找worktree路径
worktree_exists()              # 检查worktree是否存在
worktree_get_current()         # 获取当前worktree信息

# worktree-operations.sh - 仅操作职责（原子层）
worktree_create()              # 创建worktree
worktree_delete()              # 删除worktree
worktree_switch_to()           # 切换到worktree

# worktree-composite.sh - 组合操作（组合层）
worktree_find_or_create()      # 查找存在的或创建新的
worktree_safe_delete()         # 安全删除（包含检查）

# worktree-module.sh - 完整管理（模块层）
worktree_module_manage_lifecycle()  # 供命令层调用的完整管理
```

### validation.sh - 状态验证

```bash
check_working_tree_clean()  # 工作区是否干净
check_staging_area_clean()  # 暂存区是否干净
check_branch_pushed()       # 分支是否已推送
check_branch_merged()       # 分支是否已合并
```

### git-ops.sh - Git操作

```bash
create_worktree()     # 创建工作树
create_branch()       # 创建分支
push_branch()         # 推送分支
merge_branch()        # 合并分支
delete_worktree()     # 删除工作树
delete_branch()       # 删除分支
```

### 🆕 github-check.sh - GitHub CLI工具检查

```bash
# 通用的GitHub CLI环境检查（供所有命令使用）
github_check_environment() {
    # 检查gh工具安装
    # 验证GitHub认证状态
    # 确认仓库支持GitHub操作
    # 提供详细的错误信息和解决方案
}

# 网络连接和GitHub可访问性检查
check_github_connectivity()

# GitHub CLI版本兼容性检查
check_gh_version_compatibility()
```

### 🆕 github-pr组件 - 职责分离设计

按照新架构的单一职责原则，GitHub PR功能分离为查询和操作两个组件：

```bash
# github-pr-query.sh - 仅查询职责（原子层）
github_pr_exists()             # 检查PR是否存在
github_pr_get_status()         # 获取PR状态信息
github_pr_get_review_status()  # 获取审核状态
github_pr_get_merge_status()   # 获取合并状态

# github-pr-operations.sh - 仅操作职责（原子层）
github_pr_create()             # 创建PR
github_pr_update()             # 更新PR
github_pr_close()              # 关闭PR

# github-pr-composite.sh - 组合操作（组合层）
github_pr_get_complete_info()  # 获取完整PR信息
github_pr_verify_safe_to_clean() # 验证可安全清理

# github-pr-module.sh - 完整管理（模块层）
github_module_manage_pr_lifecycle()  # 供命令层调用的完整PR管理
```

### 🆕 issue-handler.sh - Issue关联处理

```bash
# Issue关联检查和处理
handle_issue_association() {
    # 命令参数优先级处理
    # 分支名自动解析
    # 交互式输入（AI友好）
    # 返回标准化的issue信息
}

# 从分支名解析issue号
extract_issue_from_branch_name() {
    # 解析如 epic-auth-123-e 的格式
    # 返回issue号码
}

# 验证issue号码格式
validate_issue_numbers() {
    # 检查issue格式正确性
    # 支持多个issue的验证
}
```

### ui.sh - 用户界面

```bash
# 输出函数（重新设计，避免耦合）
ui_info()      # 信息输出
ui_success()   # 成功信息
ui_error()     # 错误信息（包含解决方案）
ui_warning()   # 警告信息

# 交互函数（AI友好）
ui_confirm()   # 确认操作
ui_select()    # 选择菜单（输出隔离）
```

## 错误处理设计

### 统一错误格式

```bash
# 错误信息结构
Error = {
  code: string           # 错误代码
  message: string        # 错误描述  
  context: object        # 当前环境
  solutions: array       # 解决方案列表
}
```

### 示例错误输出

```
❌ 错误：工作区不干净

📍 当前位置：feature分支 user-auth/login
📁 工作目录：.worktrees/epic--user-auth--login

🔍 检测到的问题：
  - 2个未保存的文件修改
  - 1个未暂存的新文件

💡 解决方案：
  1. 保存修改：git add . && git commit -m "保存当前进度" 
  2. 丢弃修改：git checkout . && git clean -fd --force
  3. 暂存修改：git stash push -m "临时保存"

🤖 AI友好命令：
  gpf pr --force  # 强制创建PR（危险）
```

## 测试策略

### 单元测试
- 每个公共组件独立测试
- 路径转换函数测试
- 环境检测测试
- Git操作测试
- 🆕 智能切换功能测试

### 集成测试  
- 命令端到端测试
- 跨平台兼容性测试
- 错误场景测试

### 回归测试
- 旧版本功能对照测试
- 性能基准测试

## 向前兼容

保留旧版本的核心工作流，但简化命令：

```bash
# 旧版本 -> 新版本映射
gpf init <epic> <base>     -> gpf start -e <epic> <base>
gpf start <epic>/<feature> -> gpf start -ef <feature> <epic>
gpf ready <target>         -> gpf pr --status
gpf status                 -> gpf pr --status  
gpf clean <target>         -> gpf clean --all
```

## 🚀 智能切换架构特性

### 核心优势
1. **零心智负担**：用户无需关心当前在哪个目录
2. **自动检测**：智能扫描现有worktree，避免重复创建
3. **无缝切换**：存在则切换，不存在则创建
4. **友好反馈**：明确提示操作结果
5. **🆕 策略化设计**：统一接口支持多种切换策略

### 技术实现
```bash
# 🎯 统一切换流程
用户输入 → 目标解析 → 策略选择 → 环境切换
    ↓
switch_to_target_environment(type, target, fallback)
    ↓
worktree优先 → 根目录fallback → 错误处理
```

### 🎯 三命令的正确目录策略

| 命令 | 目录策略 | 管理范围 | 关键要求 |
|------|----------|----------|----------|
| **start** | worktree优先，根目录+基础分支创建 | 仅管理`.worktrees/`下的Epic/Feature | 创建时必须在根目录+正确基础分支 |
| **pr** | 必须在正确worktree中 | 仅管理Epic→develop，Feature→Epic的PR | 不管理根目录分支的PR |
| **clean** | 基于当前环境确定清理范围 | 仅清理GPF管理的worktree分支 | 根据环境智能确定清理范围 |

### 🛡️ GPF管理边界

| ✅ GPF管理 | ❌ GPF不管理 |
|------------|--------------|
| `.worktrees/epic-*-e` | 根目录分支操作 |
| `.worktrees/epic-*-e-*-ef` | `develop → main` PR |
| `epic-*-e` Git分支 | 根目录分支清理 |
| `epic-*-e-*-ef` Git分支 | 传统Git工作流 |

### 架构优势
- **🧩 模块化设计**：directory.sh统一管理所有目录切换逻辑
- **🔄 统一接口**：所有命令使用相同的切换API，避免重复代码
- **🛡️ 错误处理**：统一的错误检测和用户引导
- **🎯 策略灵活**：支持worktree、根目录、自动选择等多种策略
- **🔧 易扩展**：新增命令可直接复用现有切换组件

## 与旧版本的改进

> 完整的重构计划参考 [重构路线图](newgpf-roadmap.md)。

1. **命令简化**：从8个命令精简到5个核心命令，覆盖完整工作流
2. **参数明确**：使用-e/-ef参数明确区分操作类型
3. **前缀统一**：Git分支名与worktree目录名完全一致
4. **输入灵活**：支持多种输入格式，系统智能补全
5. **职责清晰**：每个命令职责单一，不互相影响
6. **公共组件抽象**：路径、环境、状态检查、同步等完全解耦
7. **错误处理统一**：一致的错误格式和解决方案引导
8. **测试友好**：每个组件可独立测试，修改影响范围可控
9. **🆕 智能切换**：自动目录检测和切换，提升用户体验
10. **🆕 自动同步**：集成级联同步，确保代码同步性
11. **🆕 状态透明**：完整的状态可视化和进度跟踪