# NewGPF 命令详细设计

> 📖 **相关文档**: [主文档](../newgpf-README.md) | [架构设计](newgpf-ARCHITECTURE.md) | [核心组件](newgpf-CORE-COMPONENTS.md) | [术语表](newgpf-术语表.md)

根据 [newgpf-README.md](../newgpf-README.md) 的设计理念，GPF提供5个核心命令，支持明确的参数格式、智能的 **epic- 前缀处理**、**自动目录切换功能**、**级联同步管理** 和 **完整状态可视化**。

> 有关技术实现细节参考 [核心组件设计](newgpf-CORE-COMPONENTS.md)。

## 设计理念

### 核心原则
- **命令明确性**：使用 `-e` 和 `-ef` 参数明确区分操作类型
- **前缀统一性**：Git分支名与worktree目录名完全一致，统一使用 `epic-` 前缀
- **输入灵活性**：支持多种输入格式，系统智能补全
- **AI友好性**：参数化设计，AI容易理解和操作
- **🆕 智能切换**：智能检测现有worktree，存在则自动切换，不存在则创建

### 智能切换特性
```bash
# 核心特性：不管用户在哪个目录执行命令，都能智能处理
gpf start -e auth develop     # 如果 epic-auth-e 已存在 → 自动切换
                              # 如果不存在 → 创建并切换

gpf start -ef login auth      # 如果 epic-auth-login-ef 已存在 → 自动切换  
                              # 如果不存在 → 创建并切换

gpf pr auth                   # 自动切换到Epic环境并创建PR到develop
gpf pr                        # 根据当前环境智能判断PR方向
```

### 命名规范
```bash
# 用户输入 → 系统处理 → 最终结果
auth → epic-auth-e → Git分支: epic-auth-e, Worktree: .worktrees/epic-auth-e
login + auth → auth-login → epic-auth-login-ef → Git分支: epic-auth-login-ef, Worktree: .worktrees/epic-auth-login-ef
```

## 1. `gpf start` - 开始开发

### 命令格式

```bash
# 无参数：交互模式
gpf start

# 创建Epic：-e 参数
gpf start -e <epic-name> <base-branch>

# 创建Epic 的子 Feature：-ef 参数
gpf start -ef <feature-name> <epic-name>
```

### 参数说明

| 参数 | 说明 | 示例 | 必需 |
|------|------|------|------|
| `-e` | 创建Epic分支 | `-e auth develop` | - |
| `-ef` | 创建Epic 的子 Feature分支 | `-ef login auth` | - |
| `<epic-name>` | Epic名称（可省略epic-前缀） | `auth`, `epic-auth-e` | ✅ |
| `<feature-name>` | Epic 的子 Feature 名称（可省略Epic前缀） | `login`, `auth-login`, `epic-auth-login-ef` | ✅ |
| `<base-branch>` | 基础分支名 | `develop`, `main` | ✅ |

### 🆕 智能切换逻辑

#### Epic创建/切换流程 (`gpf start -e`)
1. **输入验证和补全**
   - 使用 `validate_start_input(user_input, "e")` 验证后缀
   - 用户输入 `auth` → 自动补全为 `auth-e`
   - 用户输入 `auth-e` → 验证匹配通过
   - 用户输入 `auth-ef` → 报错：后缀不匹配

2. **Worktree检测和切换**
   - 使用 `smart_switch_to_worktree(epic_name, "start-e")` 检测现有worktree
   - 如果 `epic-auth-e` 的worktree已存在 → 自动切换并提示
   - 如果不存在 → 继续创建流程

3. **创建新Worktree（仅在不存在时）**
   - 使用 `transform_input_to_epic_branch()` 生成标准分支名
   - 使用 `create_and_switch_worktree()` 创建并切换
   - 生成最终分支名：`epic-<clean_name>-e`

4. **执行示例**
   ```bash
   # 场景1：Worktree已存在
   $ gpf start -e auth develop
   ✅ Epic auth 已存在，已自动切换到Epic环境 (.worktrees/epic-auth-e)
   
   # 场景2：Worktree不存在  
   $ gpf start -e payment develop
   ✅ 已创建并切换到Epic环境 epic-payment-e (.worktrees/epic-payment-e)
   ```

#### Epic子功能创建/切换流程 (`gpf start -ef`) - 内部必须步骤

**核心设计**：每个步骤都是内部自动执行的必须步骤，确保基于最新代码创建Feature

1. **输入验证和补全**
   - 使用 `validate_start_input(feature_input, "ef")` 验证后缀
   - 使用 `validate_start_input(epic_input, "e")` 验证Epic后缀
   - 智能补全：`login` + `auth` → `epic-auth-login-ef`

2. **Worktree检测和切换**
   - 使用 `smart_switch_to_worktree(feature_name, "start-ef", epic_name)` 检测
   - 如果 `epic-auth-login-ef` 的worktree已存在 → 自动切换并提示
   - 如果不存在 → 继续创建流程

3. **🔄 内部Epic同步检查（必须步骤）**
   - **自动检测**：使用 `check_sync_requirements_remote("epic-auth-e", "develop")` 检查Epic是否落后
   - **自动同步**：如果落后 → 强制执行 `ensure_epic_is_synced_before_feature_creation()`
   - **失败处理**：同步失败 → 终止创建流程，提示用户手动处理
   - **目的**：确保新Feature基于最新的Epic代码，避免过时的基础

4. **🆕 Epic环境准备（创建子功能前必须步骤）**
   - 验证Epic分支 `epic-auth-e` 是否存在
   - **自动切换到Epic环境**: 自动切换到 .worktrees/epic-auth-e 目录
   - 确保基于正确的Epic分支创建子功能分支

5. **创建新Worktree（仅在不存在时）**
   - 使用 `transform_input_to_feature_branch()` 生成标准分支名
   - 基于Epic分支创建Feature分支和worktree
   - **自动切换到新创建的Feature环境**

6. **内部执行示例**
   ```bash
   # 场景1：Feature已存在
   $ gpf start -ef login auth
   ✅ Epic子功能 login 已存在，已自动切换到Feature环境 (.worktrees/epic-auth-login-ef)
   
   # 场景2：Feature不存在，需要创建（包含自动同步）
   $ gpf start -ef register auth
   
   🔄 步骤1: 输入验证和补全
   ✅ 补全为: epic-auth-register-ef
   
   🔄 步骤2: Worktree检测
   📍 Feature不存在，需要创建
   
   🔄 步骤3: Epic同步检查（必须步骤）
   🔍 检查Epic是否基于最新develop...
   🟡 检测到Epic落后develop 3个提交
   🚀 自动同步Epic: develop → epic-auth-e
   ✅ Epic同步完成
   
   🔄 步骤4: Epic环境准备
   📍 切换到Epic环境 (.worktrees/epic-auth-e)
   
   🔄 步骤5: 创建Feature
   ✅ 已创建并切换到Feature环境 epic-auth-register-ef (.worktrees/epic-auth-register-ef)
   ```

### 交互式模式详细流程

#### 创建Epic交互流程
```bash
$ gpf start
欢迎使用 gpf 工具
由于没有带参数您已经切换到交互模式

请选择要创建 Epic 还是创建 Epic 的子 Feature
1. Epic，2. Epic 的子 Feature，3. 退出
请输入你的选择：1

下方名称开头的`epic-`前缀，手工输入时可省略，会自动补全；输入 `q:` 退出
请输入 Epic 名称：auth
请输入 git Base 分支：develop

✅ Epic auth 已存在，已自动切换到Epic环境
工作目录：.worktrees/epic-auth-e
分支名称：epic-auth-e
分支状态：未推送
分支状态：未合并
```

## 2. `gpf pr` - 创建GitHub Pull Request

### 🎯 PR友好工具的核心理念

**重要**：GPF不替代GitHub PR，而是让GitHub PR工作流更简单高效

**GPF pr命令的作用**：
1. **强制环境检查**：必须在Epic或Feature环境中执行
2. **状态完整验证**：调用`status_module_get_complete_status()`进行本地Git和GitHub PR状态检查
3. **Issue关联强制**：确保PR遵循最佳实践，必须关联GitHub issue
4. **直接创建PR**：调用`gh pr create`直接在GitHub创建PR
5. **结果展示**：自动执行`gh pr view`显示创建结果

### 🛡️ 强制环境要求

GPF PR命令**必须在正确环境中执行**，不支持在项目根目录执行：

```bash
# ✅ 正确的执行环境
cd .worktrees/epic-auth-e         # Epic环境
cd .worktrees/epic-auth-login-ef  # Feature环境

# ❌ 错误的执行环境  
cd /project/root                  # 项目根目录 - 直接报错
```

### 命令格式

```bash
# 自动模式（在当前环境创建PR）
gpf pr

# 指定目标模式（切换到目标环境后创建PR）
gpf pr <target>

# 指定关联issue
gpf pr --issue 123,456

# 帮助信息
gpf pr --help
gpf pr -h
```

### 🔧 GitHub CLI 工具依赖

GPF PR命令完全依赖GitHub CLI工具，执行前会自动检查：

```bash
# 自动检查项目
1. gh工具是否安装
2. GitHub认证是否配置 (gh auth status)
3. 当前仓库是否为GitHub仓库
4. 网络连接和GitHub可访问性
```

如检查失败，会提供具体的解决方案指导。

### 🔄 完整执行流程

#### GPF PR 执行步骤

**核心设计**：直接创建GitHub PR，而不是仅提供辅助信息

1. **环境强制验证**
   - 检查当前是否在正确环境中（Epic或Feature环境）
   - 如在项目根目录，直接报错并引导用户切换
   - 列出可用的worktree目录供用户选择

2. **GitHub CLI 工具检查**
   - 验证gh工具安装状态
   - 检查GitHub认证配置
   - 确认当前仓库支持GitHub操作
   - 失败时提供具体解决方案

3. **智能目标切换（可选）**
   - 无参数：在当前环境执行
   - 有参数：智能解析目标并切换到对应环境
   ```bash
   # 目标解析示例
   gpf pr auth     → 切换到 .worktrees/epic-auth-e
   gpf pr login    → 切换到Feature环境 (.worktrees/epic-auth-login-ef)
   ```

4. **状态完整检查**
   - 调用 `status_module_get_complete_status()` 获取完整状态信息
   - 本地Git状态：工作区、暂存区、推送状态
   - GitHub PR状态：是否已有PR、PR审核状态
   - 分支同步状态：是否基于最新上游代码
   - 任何阻断性问题都会终止PR创建

5. **强制Issue关联**
   - 命令参数优先：`--issue 123,456`
   - 分支名解析：`epic-auth-123-e` 自动提取issue号
   - 交互式输入：非交互式环境必须通过参数指定
   - 无issue关联时强制要求用户输入

6. **直接创建GitHub PR**
   - 调用 `gh pr create` 创建真实的GitHub PR
   - 自动设置正确的base和head分支
   - 添加issue关联到PR描述中
   - 支持PR模板和自动填充

7. **结果展示和后续操作**
   - 创建成功后自动执行 `gh pr view`
   - 显示PR链接、状态、和后续操作建议
   - 提供直接的GitHub网页链接

### 📋 执行示例

#### Feature分支创建PR示例

```bash
$ cd .worktrees/epic-auth-login-ef
$ gpf pr

🔄 环境检测: Feature环境 (epic-auth-login-ef)
🎯 PR方向: epic-auth-login-ef → epic-auth-e

🔧 GitHub CLI检查: ✅ 工具已安装并认证

📊 状态检查 (调用 status_module_get_complete_status):
  ✅ 工作区干净 (0个未保存修改)
  ✅ 暂存区为空 (0个未提交内容)
  ✅ 已推送GitHub (0个未推送提交)
  ✅ 基于最新Epic分支
  🔗 GitHub PR状态: 未创建

🔗 Issue关联检查:
  📝 从分支名检测到issue: #123
  ✅ 将关联issue #123

🚀 创建GitHub PR:
  gh pr create --base epic-auth-e --head epic-auth-login-ef --body "Closes #123"
  
✅ PR创建成功! #45

📋 PR详情:
  PR #45: Add login functionality
  状态: Open
  审核: 等待review
  链接: https://github.com/owner/repo/pull/45
```

#### 指定目标切换示例

```bash
$ gpf pr auth

🔄 目标解析: auth → epic-auth-e
📍 切换到Epic环境: .worktrees/epic-auth-e
🎯 PR方向: epic-auth-e → develop

🔧 GitHub CLI检查: ✅

📊 状态检查:
  ✅ 所有检查通过

🔗 Issue关联: 
  📝 请输入相关issue编号: 456,789
  ✅ 将关联issues #456, #789

🚀 创建GitHub PR:
  gh pr create --base develop --head epic-auth-e --body "Closes #456, #789"
  
✅ Epic PR创建成功! #46
```

#### 错误处理示例

```bash
# 在项目根目录执行
$ cd /project/root
$ gpf pr
❌ gpf pr 必须在 Epic 或 Feature 的 worktree 目录中执行

💡 请切换到正确的环境：
   Epic目录: cd .worktrees/epic-xxx-e
   Feature目录: cd .worktrees/epic-xxx-yyy-ef

📋 可用的 worktree 目录：
   .worktrees/epic-auth-e
   .worktrees/epic-auth-login-ef
   .worktrees/epic-auth-register-ef

# 状态检查失败
$ cd .worktrees/epic-auth-login-ef
$ gpf pr
❌ 状态检查失败

🔍 检测到的问题:
  - 工作区有2个未保存修改
  - 分支未推送到GitHub

💡 解决方案:
  1. 保存修改: git add . && git commit -m "fix: 准备创建PR"
  2. 推送分支: git push origin epic-auth-login-ef
  3. 重新创建PR: gpf pr
```

### 执行前检查

#### 必要检查（阻断性）
- **工作区干净**：`git diff-files --quiet`
- **暂存区为空**：`git diff-index --quiet --cached HEAD`
- **分支已推送**：`git rev-parse origin/<branch-name>`

#### 建议检查（警告性）
- **有新提交**：相比目标分支是否有新内容
- **测试状态**：基本检查提醒

### 🔧 统一状态检查接口

**设计理念**：PR命令不再重复实现状态检查逻辑，而是调用统一的status组件接口。

#### 实现方式

```bash
# 在PR命令中的调用方式
pr_command_implementation() {
    local branch_name="$1"
    local target_branch="$2"
    
    # 🎯 调用模块层状态检查接口（符合分层架构）
    if ! status_module_get_complete_status "$branch_name" "$target_branch" "pr"; then
        echo "❌ PR状态检查失败，请处理问题后重试"
        return 1
    fi
    
    # 继续PR创建逻辑...
    create_pull_request "$branch_name" "$target_branch"
}
```

#### PR辅助执行示例（分支类型感知检查）

```bash
# Feature分支的PR辅助示例
$ cd .worktrees/epic-auth-login-ef
$ gpf pr

🔄 步骤1: 环境检测
📍 检测到Feature环境: epic-auth-login-ef → epic-auth-e

🔄 步骤2: 智能级联同步检查
🔍 检查Feature分支同步状态...
🟡 检测到Epic需要先同步develop（其他Epic已合并）
🚀 自动执行Epic同步: develop → epic-auth-e
✅ Epic同步完成，获取2个来自develop的更新

🔍 检查Feature与Epic的同步状态...
🟡 检测到Feature落后Epic 4个提交（包含develop更新）
🚀 自动执行Feature同步: epic-auth-e → epic-auth-login-ef
✅ Feature同步完成，现在基于最新Epic+develop

🔄 步骤3: PR就绪性状态验证
🔍 PR就绪性检查: epic-auth-login-ef (ef分支)
📦 Feature分支检查标准:
  ✅ 工作区干净
  ✅ 暂存区为空
  ✅ 已推送到GitHub
  ✅ 相对于Epic有新提交 (3个新提交)
  ✅ 基于最新Epic分支
  ✅ 对应Epic分支可访问

🔄 步骤4: PR准备和辅助
🎯 PR目标识别: epic-auth-login-ef → epic-auth-e
📋 PR信息:
  源分支: epic-auth-login-ef
  目标分支: epic-auth-e  
  变更数量: 3个提交, 15个文件修改

💡 下一步操作:
  方式1: 在GitHub网页创建PR
    → https://github.com/your-repo/compare/epic-auth-e...epic-auth-login-ef
  
  方式2: 使用gh命令创建PR
    → gh pr create --base epic-auth-e --head epic-auth-login-ef --title "Add login functionality"
  
  方式3: 使用GPF集成创建 (如果已安装gh)
    → gpf pr --create-gh

---

# Epic分支的PR辅助示例
$ cd .worktrees/epic-auth-e  
$ gpf pr

🔄 步骤1: 环境检测
📍 检测到Epic环境: epic-auth-e → develop

🔄 步骤2: Epic智能同步检查
🔍 分析epic-auth-e与develop的关系...
📊 检测结果: Epic领先develop 5个提交，develop领先Epic 2个提交
🎯 同步策略: develop有其他Epic的更新，需要合并到当前Epic
🚀 自动执行同步: develop → epic-auth-e
✅ 同步完成，Epic保持领先但包含develop最新更新

🔄 步骤3: PR就绪性状态验证
🔍 PR就绪性检查: epic-auth-e (e分支)
🎯 Epic分支检查标准:
  ✅ 工作区干净
  ✅ 暂存区为空
  ✅ 已推送到GitHub
  ✅ 基于最新develop分支
  ✅ 包含有效提交内容

🔄 步骤4: PR准备和辅助
🎯 PR目标识别: epic-auth-e → develop
📋 PR信息:
  源分支: epic-auth-e
  目标分支: develop
  Epic里程碑: 用户认证功能完成

💡 下一步操作:
  方式1: 在GitHub网页创建PR
    → https://github.com/your-repo/compare/develop...epic-auth-e
  
  方式2: 使用gh命令创建PR
    → gh pr create --base develop --head epic-auth-e --title "Epic: User Authentication"
  
  方式3: 使用GPF集成创建 (如果已安装gh)
    → gpf pr --create-gh
```

## 3. `gpf clean` - 清理分支（基于status的智能清理）

### 🎯 与status命令的关系重新设计

**核心设计理念**：`gpf clean` 无参数 = `status_module_get_complete_status()` + 合并状态检查 + 清理建议

```bash
# clean命令实际上是status命令的扩展应用
gpf clean      # = status_module_get_complete_status + 检查哪些已合并 + 提供清理建议
gpf clean --safe  # = 内部status模块检查 + 自动清理已合并且安全的分支
```

### 🎯 基于环境的智能清理

GPF Clean命令基于**当前执行环境**智能确定清理范围，只管理GPF创建的worktree分支。

### 命令格式

```bash
# 分析模式（= status + 合并检查 + 清理建议）
gpf clean                    # 基于当前环境显示状态和清理建议
gpf clean <target>           # 分析指定目标的状态和清理建议

# 安全清理（内部自动检查 + 只清理已合并且安全的分支）
gpf clean --safe             # 基于当前环境安全清理  
gpf clean --safe <target>    # 安全清理指定目标

# 强制清理（清理所有分支，危险操作，将丢失数据）
gpf clean --force            # 基于当前环境强制清理
gpf clean --force <target>   # 强制清理指定目标
```

### 目标参数说明

| 目标参数 | 解析结果 | 清理范围 |
|---------|---------|---------|
| `auth` | Epic | `epic-auth-e` + 该Epic的所有子功能分支 |
| `auth-login` | Feature | 仅 `epic-auth-login-ef` 分支 |
| 无参数 | 环境自动检测 | 根据当前执行位置智能确定范围 |

### 🛡️ 环境感知的清理范围

| 执行环境 | 清理范围 | 示例 |
|---------|---------|------|
| **根目录** | 所有GPF管理的worktree | 清理所有 `epic-*-e` 和 `epic-*-*-ef` |
| **Epic worktree** | 该Epic的所有子功能 | 在 `epic-auth-e` → 清理 `epic-auth-*-ef` |
| **Feature worktree** | 仅当前Feature分支 | 在 `epic-auth-login-ef` → 仅清理该分支 |

### 🚨 统一安全检查接口

**设计理念**：Clean命令不再重复实现安全检查逻辑，而是调用统一的status组件接口。

#### 实现方式

```bash
# 在Clean命令中的调用方式
clean_command_implementation() {
    local branch_name="$1"
    local target_branch="$2"
    
    # 🎯 调用统一的清理安全检查接口（无目录切换）
    local safety_result exit_code
    safety_result=$(status_module_get_complete_status "$branch_name" "$target_branch" "clean")
    exit_code=$?
    
    case $exit_code in
        0) echo "🟢 安全：可以清理" ;;
        1) echo "🟡 警告：有风险" ;;
        2) echo "🔴 危险：需要--force" ;;
        *) echo "❌ 检查失败" && return 1 ;;
    esac
    
    echo "$safety_result"
}
```

**🔒 安全清理的阻断性检查**（必须通过才能清理）：
1. **未保存修改**：工作区必须干净
2. **未提交内容**：暂存区必须为空  
3. **🆕 GitHub PR+Review验证**：使用GitHub CLI检查完整状态
   - **依赖**: GitHub CLI (`gh`) - 随GPF自动安装
   - **检查**: PR存在、Review完成、已Merge到目标分支
   - **认证**: 需要`gh auth login`完成GitHub认证
4. **🆕 完整分支清理**：本地worktree目录、本地分支、远程分支的统一清理

**核心安全理念**：依赖GitHub CLI提供完整的PR工作流状态检查，确保不误删正在Review的分支

> 📋 **安装说明**: GitHub CLI会在GPF安装时自动安装，详见 [安装指南](newgpf-INSTALL.md)

### 🔧 Clean --safe 内部执行逻辑

**设计理念**：`gpf clean --safe` 内部自动执行完整的状态检查和合并验证，只清理确认安全的分支

#### 内部执行步骤

```bash
clean_safe_implementation() {
    local target_branches=()
    
    # 🔄 步骤1: 基于环境发现待清理分支
    discover_cleanup_targets_by_environment
    
    # 🔄 步骤2: 对每个分支执行完整检查
    for branch in "${target_branches[@]}"; do
        # 📊 调用统一状态检查
        local status_result
        status_result=$(status_module_get_complete_status "$branch" "$target_branch" "clean")
        
        # 🔍 GitHub PR+Review验证（clean命令专用）
        local pr_check_result
        pr_check_result=$(github_pr_get_status "$branch" "$target_branch" "clean_safety")
        
        if [[ "$pr_check_result" != "safe_to_clean" ]]; then
            mark_as_unsafe "$branch" "$pr_check_result"
            continue
        fi
        
        # ✅ 通过所有检查，标记为可清理
        mark_as_safe_to_clean "$branch"
    done
    
    # 🔄 步骤3: 执行安全清理
    execute_safe_cleanup_for_marked_branches
}
```

#### 关键检查逻辑

1. **📊 复用status检查**：调用 `status_module_get_complete_status()` 获得统一的安全等级
2. **🔍 GitHub PR+Review检查**：使用`gh pr status`和`gh pr view`验证完整的PR流程
   - PR是否存在并已创建
   - Review是否已完成（approved状态）
   - 分支是否已merge到目标分支
3. **🛡️ 双重验证**：status安全 + GitHub CLI验证 = 真正可清理
4. **🗑️ 完整清理**：本地worktree + 本地分支 + 远程分支的统一清理
5. **📋 清理报告**：提供详细的清理结果和跳过原因

### 执行流程

#### Clean --safe 执行示例

```bash
$ gpf clean --safe

🔄 步骤1: 环境检测和分支发现
🔍 环境检测：Epic环境 (epic-auth-e)
📋 发现4个待检查分支: epic-auth-login-ef, epic-auth-register-ef, epic-auth-forgot-ef, epic-auth-profile-ef

🔄 步骤2: 逐个分支安全检查

📦 检查: epic-auth-login-ef
  📊 状态检查: 🟢 安全 (已保存+已提交+已推送)
  🔍 GitHub PR+Review检查: ✅ 已完成review并merge到 epic-auth-e
  ✅ 标记为可清理

📦 检查: epic-auth-register-ef  
  📊 状态检查: 🟡 警告 (有未推送提交)
  🔍 GitHub PR+Review检查: ✅ 已完成review并merge到 epic-auth-e
  ⚠️ 跳过清理 (有未推送提交，可能丢失)

📦 检查: epic-auth-forgot-ef
  📊 状态检查: 🟢 安全 (已保存+已提交+已推送)  
  🔍 GitHub PR+Review检查: ❌ PR尚未完成review或未merge到 epic-auth-e
  ❌ 跳过清理 (未完成GitHub review流程，会丢失代码)

📦 检查: epic-auth-profile-ef
  📊 状态检查: 🔴 危险 (有未保存修改)
  ❌ 跳过清理 (状态不安全)

🔄 步骤3: 执行安全清理

🗑️ 完整清理: epic-auth-login-ef
  ✅ 删除本地worktree: .worktrees/epic-auth-login-ef
  ✅ 删除本地Git分支: epic-auth-login-ef
  ✅ 删除远程分支: origin/epic-auth-login-ef
  ✅ 完整清理完成

📋 清理报告:
  ✅ 成功清理: 1个分支（本地worktree + 本地分支 + 远程分支）
  ⚠️ 跳过清理: 3个分支
    - epic-auth-register-ef: 有未推送提交
    - epic-auth-forgot-ef: 未完成GitHub review流程
    - epic-auth-profile-ef: 工作区不干净
```

## 4. `gpf status` - 查看状态（统一状态检查核心）

### 🎯 双重角色设计

GPF Status命令承担两个重要角色：

1. **👤 用户界面**：为用户提供完整的状态可视化和进度跟踪
2. **🔧 内核服务**：为其他命令（pr、clean、sync）提供统一的状态检查接口

### 🏗️ 作为统一状态检查核心

```bash
# Status模块为其他命令提供的统一接口（符合分层架构）
pr命令 → status_module_get_complete_status(branch, target, "pr") → 统一PR就绪性检查
clean命令 → status_module_get_complete_status(branch, target, "clean") → 统一清理安全检查  
sync命令 → status_module_get_complete_status(branch, target, "sync") → 统一同步就绪检查

# 所有检查都基于相同的原子级状态检查方法
# 确保跨命令的状态检查一致性和准确性
```

### 🔗 GitHub CLI 集成

GPF Status 集成GitHub CLI功能，提供完整的本地和远程状态检查：

```bash
# 自动检查GitHub CLI工具状态
# 如工具可用，显示GitHub PR状态
# 如工具不可用，仅显示本地Git状态
```

### 命令格式

```bash
# 环境感知的状态显示（本地 + GitHub）
gpf status                   # 根据当前环境智能显示完整状态
gpf status --pr             # 仅显示GitHub PR状态
gpf status <epic>            # 显示指定Epic及其所有子features状态
gpf status <epic> --pr       # 显示指定Epic的GitHub PR状态
```

### 🛡️ 状态检查维度

**本地Git状态：**
- 🔍 **未保存修改**：工作区修改文件数量
- 📝 **未提交内容**：暂存区文件数量  
- 📤 **未推送提交**：本地领先GitHub的提交数量
- 🔄 **分支同步**：相对于上游分支的ahead/behind状态

**🔗 GitHub PR状态（需要gh工具）：**
- 📋 **PR存在性**：是否已创建PR
- 👥 **审核状态**：待审核/已审核/需修改
- ✅ **合并状态**：已合并/待合并/已关闭
- 🔄 **CI状态**：持续集成检查结果

**🎯 操作权限状态：**
基于当前状态确定各个命令的执行权限

| 状态 | gpf pr | gpf clean | gpf sync | 说明 |
|------|---------|-----------|----------|------|
| **未保存修改** | ❌ 阻止 | ❌ 阻止 | ⚠️ 警告 | 必须先保存 |
| **未提交内容** | ❌ 阻止 | ❌ 阻止 | ⚠️ 警告 | 必须先提交 |
| **未推送提交** | ❌ 阻止 | ❌ 阻止 | ✅ 允许 | PR需要推送 |
| **未创建PR** | ✅ 允许 | ❌ 阻止 | ✅ 允许 | clean需要PR完整 |
| **PR待审核** | ❌ 阻止 | ❌ 阻止 | ⚠️ 警告 | 避免重复PR |
| **PR已合并** | ❌ 阻止 | ✅ 允许 | ✅ 允许 | 可安全清理 |

### Status状态显示示例

#### 完整状态显示（本地 + GitHub）

```bash
# Feature分支的完整状态显示
$ cd .worktrees/epic-auth-login-ef
$ gpf status

📍 当前环境: Feature分支 (epic-auth-login-ef)
🎯 PR方向: epic-auth-login-ef → epic-auth-e

📊 本地Git状态:
  ✅ 工作区干净 (0个未保存修改)
  ✅ 暂存区为空 (0个未提交内容)
  ✅ 已推送GitHub (0个未推送提交)
  🔄 分支同步: 基于最新Epic分支

🔗 GitHub PR状态:
  📋 PR #123: 待审核 - "Add login functionality"
  👥 审核状态: 等待review
  🔄 CI状态: 通过
  
🎯 操作权限:
  ❌ gpf pr: 已有PR存在，无需重复创建
  ❌ gpf clean: 等待PR审核完成并合并
  ✅ gpf sync: 可执行同步操作

💡 建议操作:
  - 等待代码审核完成
  - 查看PR详情: gh pr view 123
```

#### 仅GitHub PR状态显示

```bash
$ cd .worktrees/epic-auth-e
$ gpf status --pr

🔗 GitHub PR状态检查:
  🔧 GitHub CLI: ✅ 已配置
  📍 当前分支: epic-auth-e
  🎯 PR方向: epic-auth-e → develop
  
  📋 PR状态: 未创建
  💡 建议: 运行 gpf pr 创建PR
  
  🎯 操作权限:
    ✅ gpf pr: 可以创建新PR
```

#### GitHub CLI 不可用时的状态

```bash
$ gpf status

📍 当前环境: Feature分支 (epic-auth-login-ef)

📊 本地Git状态:
  ✅ 工作区干净
  ✅ 暂存区为空
  ✅ 已推送GitHub
  
🔗 GitHub PR状态:
  ⚠️ 无法检查（GitHub CLI未配置）
  💡 安装并配置: gh auth login
  
🎯 基于本地状态的操作权限:
  ✅ gpf pr: 本地状态允许（需要GitHub CLI支持）
  ❌ gpf clean: 无法验证PR状态，不建议清理
  ✅ gpf sync: 可执行本地同步
```

## 5. `gpf sync` - 上到下同步（本地merge）

### 🎯 Sync的核心理念

**重要**：sync是GPF中唯一的本地merge操作，实现上到下的pull->merge流程

```bash
# ✅ 允许的sync方向（上到下 pull->merge）
pull -> Develop -> Epic -> merge -> Epic-Feature -> merge

# ❌ 不允许的方向（下到上，只能通过GitHub PR+Review）
epic-features ❌→ epic        # 只能: push -> pr -> review -> 可清理
epic ❌→ develop              # 只能: push -> pr -> review -> 可清理
```

### 🔄 Sync的触发时机

**自动触发场景**：
1. **start -ef命令**：创建Feature前确保Epic同步
2. **pr命令**：创建PR前确保分支同步

**手动触发场景**：
1. **其他Feature合并后**：`epic-feature-1` 在GitHub PR合并到epic后，其他features需要同步
2. **Epic合并后**：`epic` 在GitHub PR合并到develop后，所有epics和features需要同步

### 命令格式

```bash
# 环境感知的智能同步（上到下）
gpf sync                     # 根据当前环境智能同步
gpf sync <epic>              # 同步指定Epic及其所有子features
```

### 🔄 Sync执行逻辑

```bash
# 根据当前环境确定sync策略

# 在根目录：同步所有Epic从develop
$ cd /project/root
$ gpf sync
→ pull develop → sync to all epics → sync to all features

# 在Epic环境：智能Epic同步策略
$ cd .worktrees/epic-auth-e  
$ gpf sync
→ 检测Epic与develop关系 → 智能同步Epic → sync to all epic-auth-*-ef

# 在Feature环境：级联同步策略
$ cd .worktrees/epic-auth-login-ef
$ gpf sync  
→ Epic先同步develop → pull epic-auth-e → sync to epic-auth-login-ef
```

### 🧠 智能同步策略详解

**核心问题**：Epic可能领先develop（Epic在开发中，还没到合并里程碑），但Feature开发时既要获取Epic的最新代码，也要确保Epic包含develop的其他Epic更新。

#### Epic同步策略（处理复杂场景）

```bash
# Epic智能同步检测逻辑
$ cd .worktrees/epic-auth-e
$ gpf sync

🔄 步骤1: 检测Epic与develop的关系
🔍 分析epic-auth-e与develop的提交关系...

# 场景1: Epic领先develop（正常开发状态）
📊 检测结果: Epic领先develop 3个提交，develop领先Epic 0个提交
🎯 同步策略: Epic处于开发状态，无需从develop pull
✅ Epic同步完成，继续同步Feature分支

# 场景2: develop领先Epic（其他Epic已合并）
📊 检测结果: Epic领先develop 2个提交，develop领先Epic 5个提交  
🎯 同步策略: develop有新更新，需要merge到Epic
🔀 正在合并 develop → epic-auth-e
✅ 合并成功，Epic现在包含develop的最新更新

# 场景3: 双向都有新提交（最复杂情况）
📊 检测结果: Epic领先develop 3个提交，develop领先Epic 2个提交
🎯 同步策略: 需要将develop的更新merge到Epic
🔀 正在合并 develop → epic-auth-e  
✅ 合并成功，Epic保持领先状态但包含develop更新
```

#### Feature级联同步策略

```bash
# Feature同步：确保基于最新Epic+develop
$ cd .worktrees/epic-auth-login-ef
$ gpf sync

🔄 步骤1: 预检查Epic同步状态
🔍 检查epic-auth-e是否包含develop最新更新...
🟡 检测到Epic需要先同步develop
🚀 自动执行Epic同步: develop → epic-auth-e
✅ Epic同步完成

🔄 步骤2: Feature同步
📡 正在拉取最新epic-auth-e代码...
✅ 发现3个新提交（包含develop更新）

🔄 步骤3: 执行Feature同步
🔀 正在合并 epic-auth-e → epic-auth-login-ef
✅ 合并成功，Feature现在基于最新Epic+develop

📊 同步统计:
  - Epic更新: 2个来自develop
  - Epic更新: 1个来自Epic开发
  - 修改文件: 8个
  - 新增文件: 2个

💡 建议下一步: 
  git push  # 推送同步后的代码到GitHub
```
