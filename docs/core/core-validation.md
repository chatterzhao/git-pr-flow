# GPF 核心公共组件设计 - 状态验证

> 📖 **相关文档**: [主文档](../../README.md) | [架构设计](../ARCHITECTURE.md) | [命令详细](../COMMANDS.md) | [术语表](../术语表.md) | [核心组件索引](../CORE-COMPONENTS.md)

## 设计原则

基于用户的架构哲学："基本方法在 core 文档，并且多个命令是一样的方法，也在core里将多个基本方法组装为高级一点的方法。command文档根据具体命令调用通用或某个命令不一样的调用core 方法扩展加一些自有方法组装为该命令所需方法"

1. **单一职责**：每个组件只负责一个明确的功能域
2. **无副作用**：纯函数设计，输入确定输出确定
3. **错误透明**：清晰的错误传播和处理机制
4. **测试友好**：每个函数都可以独立测试
5. **平台兼容**：跨平台文件系统和路径处理
6. **职责分离**：core提供基础工具，command组合使用
7. **🆕 GitHub集成**：统一的GitHub CLI检查和PR状态管理

---

## 4. validation.sh - 状态验证

### 核心功能
Git状态验证，工作区干净性检查等。

### 基础验证方法

```bash
# 检查工作区是否干净
check_working_tree_clean() {
    local worktree_path="${1:-$(pwd)}"
    
    if git -C "$worktree_path" diff-files --quiet 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 检查暂存区是否干净
check_staging_area_clean() {
    local worktree_path="${1:-$(pwd)}"
    
    if git -C "$worktree_path" diff-index --quiet --cached HEAD 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 检查分支是否已推送
check_branch_pushed() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    if git -C "$worktree_path" rev-parse "origin/$branch_name" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检查分支是否已合并
check_branch_merged() {
    local source_branch="$1"
    local target_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    
    # 检查source_branch的提交是否都在target_branch中
    local unmerged_commits
    unmerged_commits=$(git -C "$worktree_path" rev-list "$source_branch" ^"$target_branch" 2>/dev/null)
    
    [[ -z "$unmerged_commits" ]]
}
```

### 分支安全检查方法（多命令共用）

```bash
# 🛡️ 关键：安全检查机制
check_branch_safety() {
    local branch_name="$1"
    local worktree_path="$2"
    
    # 检查1：未保存修改
    if ! check_working_tree_clean "$worktree_path"; then
        echo "❌ 有未保存的修改"
        return 1
    fi
    
    # 检查2：未提交内容  
    if ! check_staging_area_clean "$worktree_path"; then
        echo "❌ 有未提交的内容"
        return 1
    fi
    
    # 检查3：未合并分支
    local target_branch
    target_branch=$(get_merge_target_branch "$branch_name")
    if ! check_branch_merged "$branch_name" "$target_branch" "$worktree_path"; then
        echo "❌ 分支未合并到 $target_branch"
        return 1
    fi
    
    echo "✅ 安全检查通过"
    return 0
}

# 获取分支的合并目标
get_merge_target_branch() {
    local branch_name="$1"
    
    local suffix
    suffix=$(path_extract_suffix "$branch_name")
    
    case "$suffix" in
        "e")
            # Epic分支 → develop
            echo "develop"
            ;;
        "ef")
            # Feature分支 → Epic分支
            local epic_name
            epic_name=$(extract_epic_from_branch "$branch_name")
            echo "epic-$epic_name-e"
            ;;
        *)
            echo "unknown"
            return 1
            ;;
    esac
}
```

### GitIgnore配置静默处理（gpf start专用）

**功能需求**：
- **触发时机**：用户执行`gpf start`时自动检查
- **处理方式**：静默处理，不需要用户交互
- **核心逻辑**：
  1. 检查项目根目录是否有`.gitignore`文件
  2. 没有则创建，并添加`.worktrees/`忽略规则
  3. 有文件则检查是否包含`.worktrees/`忽略规则  
  4. 没有则添加，并加上注释说明

#### 🏗️ 简化四层架构设计

##### Atomic层 (`lib/core/atomic/file-atomic.sh` - 使用现有方法)
**职责**：基础文件操作（复用现有方法）

```bash
# 现有方法直接使用
file_exists()                        # 检查文件是否存在
file_contains_line()                 # 检查文件是否包含指定行
file_append_safe()                   # 安全追加内容
```

##### Composite层 (`lib/core/composite/validation-composite.sh` - 新增方法)
**职责**：组合atomic方法实现gitignore静默处理

```bash
# 静默检查和修复gitignore配置
gitignore_ensure_worktrees_ignored() {
    local project_root="$1"
    local gitignore_path="$project_root/.gitignore"
    local target_rule=".worktrees/"
    
    # 组合调用atomic方法：
    # 1. file_exists() 检查文件存在
    # 2. file_contains_line() 检查是否已有规则
    # 3. file_append_safe() 添加规则和注释
    
    # 静默处理，无用户输出
    # 返回0/1表示成功/失败
}
```

##### Modules层 (`lib/core/modules/validation-module.sh`)
**职责**：为start命令提供gitignore检查服务

```bash
# 在start命令中静默确保gitignore配置
validation_module_ensure_gitignore_for_start() {
    local project_root="$1"
    
    # 调用composite层方法
    gitignore_ensure_worktrees_ignored "$project_root"
    
    # 静默处理，只返回成功/失败
}

# 集成到现有统一验证接口
validation_module_unified_check() {
    case "$validation_type" in
        "gitignore_for_start")
            validation_module_ensure_gitignore_for_start "$validation_target"
            ;;
        # ... 其他类型
    esac
}
```

##### Commands层 (`lib/commands/start.sh` - 未来实现)
**职责**：在start流程中调用gitignore检查

```bash
# start命令中的静默gitignore检查
gpf_start_command() {
    # 其他start逻辑...
    
    # 静默处理gitignore配置
    validation_module_ensure_gitignore_for_start "$project_root"
    
    # 继续其他start逻辑...
}
```

### 📝 添加的注释内容

```bash
# 在.gitignore中添加的内容格式：
cat >> .gitignore << EOF

# GPF (Git PR Flow) worktree管理
# GPF使用git worktree功能在.worktrees/目录下创建独立的工作区
# 这些工作区不应该被git跟踪，因为：
# 1. worktree是本地开发环境，不应提交到仓库
# 2. 不同开发者的worktree结构可能不同
# 3. 避免.worktrees目录污染git状态
.worktrees/
EOF
```

### 🎯 简化实现计划

1. **epic-core-foundation-e-composite-ef**: 在`validation-composite.sh`中添加`gitignore_ensure_worktrees_ignored()`方法
2. **epic-core-foundation-e-modules-ef**: 在`validation-module.sh`中添加`validation_module_ensure_gitignore_for_start()`方法  
3. **epic-core-foundation-e-commands-ef**: 在`start.sh`中集成静默检查

### ⚡ 核心实现逻辑

```bash
# composite层的核心方法
gitignore_ensure_worktrees_ignored() {
    local project_root="$1"
    local gitignore_path="$project_root/.gitignore"
    
    # 检查.gitignore是否存在
    if ! file_exists "$gitignore_path"; then
        # 创建.gitignore并添加规则
        cat > "$gitignore_path" << 'EOF'
# GPF (Git PR Flow) worktree管理
# GPF使用git worktree功能在.worktrees/目录下创建独立的工作区
# 这些工作区不应该被git跟踪，避免污染git状态
.worktrees/
EOF
        return 0
    fi
    
    # 检查是否已包含.worktrees/规则
    if ! file_contains_line "$gitignore_path" ".worktrees/"; then
        # 添加规则和注释
        cat >> "$gitignore_path" << 'EOF'

# GPF (Git PR Flow) worktree管理
# GPF使用git worktree功能在.worktrees/目录下创建独立的工作区
# 这些工作区不应该被git跟踪，避免污染git状态
.worktrees/
EOF
    fi
    
    return 0
}
```

这样的设计非常简单，静默处理，只做必要的事情，不打扰用户。
```