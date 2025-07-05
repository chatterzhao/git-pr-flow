# NewGPF 核心公共组件设计 - Worktree管理

> 📖 **相关文档**: [主文档](../../newgpf-README.md) | [架构设计](../newgpf-ARCHITECTURE.md) | [命令详细](../newgpf-COMMANDS.md) | [术语表](../newgpf-术语表.md) | [核心组件索引](../newgpf-CORE-COMPONENTS.md)

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

## 3. worktree.sh - Worktree管理

### 核心功能
Worktree创建、检测、切换和清理的统一管理。

### Worktree信息获取（基础方法）

```bash
# 列出所有现有的worktree
list_all_worktrees() {
    git worktree list --porcelain | \
    awk '/^worktree/ {path=$2} /^branch/ {branch=$2} /^$/ {if(branch && path) print branch":"path; branch=""; path=""}'
}

# 根据分支名查找worktree路径
find_worktree_by_branch() {
    local target_branch="$1"
    
    list_all_worktrees | while IFS=: read -r branch path; do
        if [[ "$branch" == "$target_branch" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# 检查worktree是否存在
worktree_exists() {
    local branch_name="$1"
    
    find_worktree_by_branch "$branch_name" >/dev/null 2>&1
}

# 获取worktree所在的分支名
get_worktree_branch() {
    local worktree_path="$1"
    
    if [[ -d "$worktree_path" ]]; then
        git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null
    else
        return 1
    fi
}
```

### 🚀 统一目录切换公共组件（多命令共用）

```bash
# 🎯 核心方法：智能切换到目标环境
# 支持：worktree目录、项目根目录+分支checkout
switch_to_target_environment() {
    local target_type="$1"        # "worktree" | "root" | "auto"
    local target_identifier="$2"  # 分支名 | "develop" | worktree路径
    local fallback_strategy="${3:-fail}"  # "fail" | "create" | "root"
    
    case "$target_type" in
        "worktree")
            switch_to_worktree_environment "$target_identifier" "$fallback_strategy"
            ;;
        "root")
            switch_to_root_environment "$target_identifier"
            ;;
        "auto")
            smart_switch_to_best_environment "$target_identifier" "$fallback_strategy"
            ;;
        *)
            echo "❌ 无效的目标类型: $target_type" >&2
            return 1
            ;;
    esac
}

# 切换到worktree
switch_to_worktree_environment() {
    local target_branch="$1"
    local fallback_strategy="${2:-fail}"
    
    local worktree_path
    worktree_path=$(find_worktree_by_branch "$target_branch")
    
    if [[ -n "$worktree_path" ]]; then
        # Worktree存在，使用cd切换（worktree最佳实践）
        cd "$worktree_path" || return 1
        echo "✅ 已切换到目标环境 $target_branch ($worktree_path)"
        return 0
    else
        # Worktree不存在，根据fallback策略处理
        case "$fallback_strategy" in
            "create")
                echo "💡 Worktree不存在，需要调用方创建: $target_branch" >&2
                return 2  # 特殊返回码表示需要创建
                ;;
            "root")
                echo "💡 Worktree不存在，降级到根目录+checkout" >&2
                switch_to_root_environment "$target_branch"
                ;;
            "fail"|*)
                echo "❌ Worktree 不存在: $target_branch" >&2
                return 1
                ;;
        esac
    fi
}

# 切换到项目根目录（必要时checkout分支）
switch_to_root_environment() {
    local target_branch="${1:-}"  # 可选的目标分支
    
    local project_root
    project_root=$(find_project_root) || return 1
    
    cd "$project_root" || return 1
    
    if [[ -n "$target_branch" ]]; then
        # 需要切换到特定分支
        if git checkout "$target_branch" 2>/dev/null; then
            echo "✅ 已切换到根目录环境，分支: $target_branch"
            return 0
        else
            echo "❌ 无法切换到分支: $target_branch" >&2
            return 1
        fi
    else
        # 只切换到根目录，保持当前分支
        echo "✅ 已切换到根目录环境"
        return 0
    fi
}

# 智能选择最佳环境（worktree优先，根目录作为fallback）
smart_switch_to_best_environment() {
    local target_identifier="$1"
    local fallback_strategy="${2:-root}"
    
    # 首先尝试worktree
    if switch_to_worktree_environment "$target_identifier" "root" 2>/dev/null; then
        return 0
    fi
    
    # worktree不可用，根据策略降级
    case "$fallback_strategy" in
        "root")
            switch_to_root_environment "$target_identifier"
            ;;
        "fail")
            echo "❌ 无法找到合适的环境: $target_identifier" >&2
            return 1
            ;;
        *)
            echo "❌ 无效的fallback策略: $fallback_strategy" >&2
            return 1
            ;;
    esac
}

# 创建worktree并切换
create_and_switch_worktree() {
    local branch_name="$1"
    local base_branch="$2"
    local project_root="${3:-$(find_project_root)}"
    
    local worktree_path="$project_root/.worktrees/$branch_name"
    
    # 检查目标目录是否已存在
    if [[ -d "$worktree_path" ]]; then
        echo "❌ 目录已存在: $worktree_path" >&2
        return 1
    fi
    
    # 创建worktree
    if git -C "$project_root" worktree add -b "$branch_name" "$worktree_path" "$base_branch" 2>/dev/null; then
        cd "$worktree_path" || return 1
        echo "✅ 已创建并切换到目标环境 $branch_name ($worktree_path)"
        return 0
    else
        echo "❌ 创建 worktree 失败: $branch_name" >&2
        return 1
    fi
}
```

### 智能匹配方法（多命令共用）

```bash
# 智能匹配目标分支（通用匹配）
find_target_branch() {
    local user_input="$1"
    local match_type="$2"  # "epic" | "feature" | "any"
    
    case "$match_type" in
        "epic")
            # 只匹配Epic
            local normalized_epic
            normalized_epic=$(transform_input_to_epic_branch "$user_input") 2>/dev/null
            if [[ -n "$normalized_epic" ]] && worktree_exists "$normalized_epic"; then
                echo "$normalized_epic"
                return 0
            fi
            ;;
        "feature")
            # 匹配Feature（需要当前Epic环境）
            local current_epic
            current_epic=$(extract_current_epic_name) 2>/dev/null
            if [[ -n "$current_epic" ]]; then
                local normalized_feature
                normalized_feature=$(transform_input_to_feature_branch "$user_input" "$current_epic") 2>/dev/null
                if [[ -n "$normalized_feature" ]] && worktree_exists "$normalized_feature"; then
                    echo "$normalized_feature"
                    return 0
                fi
            fi
            ;;
        "any")
            # 先尝试Epic，再尝试Feature
            if find_target_branch "$user_input" "epic" >/dev/null 2>&1; then
                find_target_branch "$user_input" "epic"
                return 0
            elif find_target_branch "$user_input" "feature" >/dev/null 2>&1; then
                find_target_branch "$user_input" "feature"
                return 0
            fi
            ;;
    esac
    
    return 1
}

# 获取当前Epic名称（从当前环境推断）
extract_current_epic_name() {
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
    
    local branch_suffix
    branch_suffix=$(path_extract_suffix "$current_branch")
    
    case "$branch_suffix" in
        "e")
            # 当前在Epic分支，直接返回
            strip_suffix_from_input "$(strip_epic_prefix_from_input "$current_branch")"
            ;;
        "ef")
            # 当前在Feature分支，提取Epic部分
            local clean_name
            clean_name=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$current_branch")")
            # epic-auth-e-login-ef -> auth-login -> auth
            echo "${clean_name%-*}"
            ;;
        *)
            return 1
            ;;
    esac
}
```