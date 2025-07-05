# NewGPF 核心公共组件设计

> 📖 **相关文档**: [主文档](../newgpf-README.md) | [架构设计](newgpf-ARCHITECTURE.md) | [命令详细](newgpf-COMMANDS.md) | [术语表](newgpf-术语表.md)

## 设计原则

基于用户的架构哲学："基本方法在 core 文档，并且多个命令是一样的方法，也在core里将多个基本方法组装为高级一点的方法。command文档根据具体命令调用通用或某个命令不一样的调用core 方法扩展加一些自有方法组装为该命令所需方法"

1. **单一职责**：每个组件只负责一个明确的功能域
2. **无副作用**：纯函数设计，输入确定输出确定
3. **错误透明**：清晰的错误传播和处理机制
4. **测试友好**：每个函数都可以独立测试
5. **平台兼容**：跨平台文件系统和路径处理
6. **职责分离**：core提供基础工具，command组合使用
7. **🆕 GitHub集成**：统一的GitHub CLI检查和PR状态管理

## 1. context.sh - 环境检测

### 核心功能
检测当前执行环境，为所有命令提供统一的环境信息。

### 数据结构

```bash
# 环境对象
Environment = {
    type: "root" | "epic" | "feature" | "unknown"
    project_root: "/absolute/path/to/project"
    current_path: "/current/working/directory" 
    epic_name: "auth" | null      # Epic 名称  
    feature_name: "login" | null  # Epic 的子 Feature 名称
    git_branch: "epic-auth-e" | "epic-auth-login-ef" | "develop"  # 分支名
    worktree_path: "/absolute/path/to/worktree" | null  # Worktree 路径
}
```

### 基础检测方法

```bash
# 项目根目录检测
find_project_root() {
    local current_dir=$(pwd)
    
    # 从当前目录向上查找
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/.git/config" ]] || [[ -d "$current_dir/.git" ]]; then
            if [[ -f "$current_dir/bin/git-pr-flow" ]]; then
                echo "$current_dir"
                return 0
            fi
        fi
        current_dir=$(dirname "$current_dir")
    done
    
    return 1
}

# 环境类型判断
determine_environment_type() {
    local current_path="$1"
    local project_root="$2"
    
    # 检查是否在工作树中
    if [[ "$current_path" == "$project_root/.worktrees/"* ]]; then
        local worktree_name
        worktree_name=$(extract_worktree_name "$current_path" "$project_root")
        
        if [[ "$worktree_name" =~ -ef$ ]]; then
            echo "feature"
        elif [[ "$worktree_name" =~ -e$ ]]; then
            echo "epic"  
        else
            echo "unknown"
        fi
    elif [[ "$current_path" == "$project_root" ]]; then
        echo "root"
    else
        echo "unknown"
    fi
}

# 统一的环境检测函数（多命令共用）
# 原：get_current_environment() + detect_environment() → 新：environment_detect_complete()
environment_detect_complete() {
    local environment_json
    
    # 检测项目根目录
    local project_root
    project_root=$(find_project_root) || return 1
    
    # 检测当前位置类型
    local current_path=$(pwd)
    local environment_type=$(determine_environment_type "$current_path" "$project_root")
    
    # 根据类型提取详细信息
    case "$environment_type" in
        "epic")
            extract_epic_environment "$current_path" "$project_root"
            ;;
        "feature")  
            extract_feature_environment "$current_path" "$project_root"
            ;;
        "root")
            extract_root_environment "$current_path" "$project_root"
            ;;
        *)
            extract_unknown_environment "$current_path" "$project_root"
            ;;
    esac
}
```

## 2. paths.sh - 路径管理

### 核心功能
统一的路径计算和转换，处理所有与文件系统路径相关的操作。

### 🎯 精细化的后缀检测和处理（基础方法）

```bash
# 提取输入中的后缀标识符（原子方法）
# 原：extract_suffix() + path_extract_suffix() → 新：path_extract_suffix()
path_extract_suffix() {
    local input="$1"
    
    if [[ "$input" =~ -e$ ]]; then
        echo "e"
    elif [[ "$input" =~ -ef$ ]]; then
        echo "ef"  
    else
        echo "none"
    fi
}

# 清除输入中的后缀标识符（基础原子方法）
strip_suffix_from_input() {
    local input="$1"
    local suffix
    suffix=$(path_extract_suffix "$input")
    
    case "$suffix" in
        "e")
            echo "${input%-e}"
            ;;
        "ef")
            echo "${input%-ef}"
            ;;
        *)
            echo "$input"
            ;;
    esac
}

# 验证输入后缀与期望类型匹配（验证层方法）
validate_input_suffix_matches_expected() {
    local input="$1"
    local expected_suffix="$2"  # "e" 或 "ef"
    
    local current_suffix
    current_suffix=$(path_extract_suffix "$input")
    
    case "$current_suffix" in
        "none")
            # 没有后缀，符合期望（可以自动补全）
            return 0
            ;;
        "$expected_suffix")
            # 后缀匹配期望
            return 0
            ;;
        *)
            # 后缀不匹配期望
            echo "错误：输入后缀 -$current_suffix 与期望后缀 -$expected_suffix 不匹配" >&2
            return 1
            ;;
    esac
}

# 为输入补全缺失的后缀标识符（处理层方法）
ensure_suffix_present() {
    local input="$1"
    local required_suffix="$2"  # "e" 或 "ef"
    
    local current_suffix
    current_suffix=$(path_extract_suffix "$input")
    
    if [[ "$current_suffix" == "none" ]]; then
        # 没有后缀，添加所需后缀
        echo "$input-$required_suffix"
    else
        # 已有后缀，直接返回（假设已通过验证）
        echo "$input"
    fi
}

# 强制替换输入的后缀标识符（处理层方法）
replace_suffix_forcefully() {
    local input="$1"
    local required_suffix="$2"  # "e" 或 "ef"
    
    local clean_name
    clean_name=$(strip_suffix_from_input "$input")
    echo "$clean_name-$required_suffix"
}
```

### 🎯 精细化的前缀检测和处理（基础方法）

```bash
# 提取输入中的前缀标识符（基础原子方法）
extract_prefix_from_input() {
    local input="$1"
    
    if [[ "$input" =~ ^epic-(.+)$ ]]; then
        echo "epic-"
    elif [[ "$input" =~ ^epic_(.+)$ ]]; then
        echo "epic_"
    elif [[ "$input" =~ ^epic/(.+)$ ]]; then
        echo "epic/"
    else
        echo "none"
    fi
}

# 清除输入中的epic前缀（基础原子方法）
strip_epic_prefix_from_input() {
    local input="$1"
    local prefix
    prefix=$(extract_prefix_from_input "$input")
    
    case "$prefix" in
        "epic-")
            echo "${input#epic-}"
            ;;
        "epic_")
            echo "${input#epic_}"
            ;;
        "epic/")
            echo "${input#epic/}"
            ;;
        *)
            echo "$input"
            ;;
    esac
}

# 验证epic前缀格式合法性（验证层方法）
validate_epic_prefix_format() {
    local input="$1"
    local prefix
    prefix=$(extract_prefix_from_input "$input")
    
    case "$prefix" in
        "none"|"epic-")
            # 没有前缀或标准前缀，都是合法的
            return 0
            ;;
        "epic_"|"epic/")
            # 非标准前缀，给出警告但不阻断
            echo "警告：建议使用标准前缀 epic- 而不是 $prefix" >&2
            return 0
            ;;
        *)
            # 其他情况
            return 1
            ;;
    esac
}

# 添加标准前缀（如果没有的话）（处理方法）
add_epic_prefix_if_missing() {
    local input="$1"
    local prefix
    prefix=$(extract_prefix_from_input "$input")
    
    if [[ "$prefix" == "none" ]]; then
        echo "epic-$input"
    else
        # 有前缀，先移除再添加标准前缀（避免重复）
        local clean_name
        clean_name=$(strip_epic_prefix_from_input "$input")
        echo "epic-$clean_name"
    fi
}

# 强制设置标准前缀（替换现有前缀）（处理方法）
force_set_epic_prefix() {
    local input="$1"
    local clean_name
    clean_name=$(strip_epic_prefix_from_input "$input")
    echo "epic-$clean_name"
}
```

### 🎯 通用高级组合方法（多命令共用）

```bash
# 将用户输入转化为标准epic分支名（处理层组合）
transform_input_to_epic_branch() {
    local user_input="$1"
    
    # 1. 验证前缀
    validate_epic_prefix_format "$user_input" || return 1
    
    # 2. 提取纯净名称
    local clean_name
    clean_name=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$user_input")")
    
    # 3. 验证名称合法性
    validate_name_format "$clean_name" || return 1
    
    # 4. 生成最终规范名称
    echo "epic-$clean_name-e"
}

# 将用户输入转化为标准feature分支名（处理层组合）
transform_input_to_feature_branch() {
    local feature_input="$1"
    local epic_input="$2"
    
    # 1. 处理Epic和Feature名称
    local clean_epic
    clean_epic=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$epic_input")")
    
    local clean_feature
    clean_feature=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$feature_input")")
    
    # 2. 验证名称合法性
    validate_name_format "$clean_feature" || return 1
    
    # 3. 智能构建Feature名称
    if [[ "$clean_feature" == "$clean_epic-"* ]]; then
        # Feature已包含Epic前缀：auth-login
        echo "epic-$clean_feature-ef"
    else
        # Feature不包含Epic前缀：login
        echo "epic-$clean_epic-$clean_feature-ef"
    fi
}

# 全面验证并处理用户输入（多命令共用组合）
process_and_validate_user_input() {
    local user_input="$1"
    local expected_suffix="$2"      # "e" | "ef"
    local current_environment="${3:-}"  # 当前环境（可选）
    
    # 1. 基础验证
    validate_epic_prefix_format "$user_input" || return 1
    validate_input_suffix_matches_expected "$user_input" "$expected_suffix" || return 1
    
    # 2. 环境验证（如果提供）
    if [[ -n "$current_environment" ]]; then
        validate_input_environment_match "$user_input" "$current_environment" || return 1
    fi
    
    # 3. 处理并返回规范名称
    local clean_name
    clean_name=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$user_input")")
    echo "epic-$clean_name-$expected_suffix"
}

# 环境验证：检查用户输入是否与当前环境匹配（多命令共用）
validate_input_environment_match() {
    local user_input="$1"
    local current_environment="$2"  # "epic" | "feature" | "root"
    
    local input_suffix
    input_suffix=$(path_extract_suffix "$user_input")
    
    # 如果用户没有输入后缀，则不需要验证（可以自动补全）
    if [[ "$input_suffix" == "none" ]]; then
        return 0
    fi
    
    # 验证输入后缀与环境是否匹配
    case "$current_environment" in
        "epic")
            if [[ "$input_suffix" != "e" ]]; then
                echo "❌ 错误：在Epic环境中，但输入了 -$input_suffix 后缀" >&2
                echo "💡 建议：在Epic环境中应使用 -e 后缀或省略后缀" >&2
                return 1
            fi
            ;;
        "feature")
            if [[ "$input_suffix" != "ef" ]]; then
                echo "❌ 错误：在Feature环境中，但输入了 -$input_suffix 后缀" >&2
                echo "💡 建议：在Feature环境中应使用 -ef 后缀或省略后缀" >&2
                return 1
            fi
            ;;
        "root")
            # 在根目录环境中，不强制要求特定后缀
            return 0
            ;;
        *)
            echo "❌ 错误：未知的环境: $current_environment" >&2
            return 1
            ;;
    esac
    
    return 0
}
```

### 辅助工具方法（多命令共用）

```bash
# 名称格式验证（通用验证）
validate_name_format() {
    local name="$1"
    
    # 长度检查
    if [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        echo "❌ 错误：名称长度必须在2-50字符之间" >&2
        return 1
    fi
    
    # 格式检查：允许小写字母、数字、连字符、下划线
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        echo "❌ 错误：名称只能包含小写字母、数字、连字符、下划线" >&2
        return 1
    fi
    
    # 不能以连字符或下划线开头或结尾
    if [[ "$name" =~ ^[-_] ]] || [[ "$name" =~ [-_]$ ]]; then
        echo "❌ 错误：名称不能以连字符或下划线开头或结尾" >&2
        return 1
    fi
    
    return 0
}

# 从分支名提取Epic名称（通用工具）
extract_epic_from_branch() {
    local branch_name="$1"
    
    local suffix
    suffix=$(path_extract_suffix "$branch_name")
    
    case "$suffix" in
        "e")
            # Epic分支：epic-auth-e -> auth
            strip_suffix_from_input "$(strip_epic_prefix_from_input "$branch_name")"
            ;;
        "ef")
            # Feature分支：epic-auth-login-ef -> auth
            local clean_name
            clean_name=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$branch_name")")
            echo "${clean_name%-*}"  # 移除最后一个-及之后的内容
            ;;
        *)
            echo "❌ 错误：无法从分支名提取Epic: $branch_name" >&2
            return 1
            ;;
    esac
}
```

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
            # epic-auth-login-ef -> auth-login -> auth
            echo "${clean_name%-*}"
            ;;
        *)
            return 1
            ;;
    esac
}
```

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

## 5. git-ops.sh - Git操作

### 核心功能
Git操作的统一封装，提供一致的接口。

### 基础Git操作

```bash
# 创建Git分支
create_git_branch() {
    local branch_name="$1"
    local base_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    
    if git -C "$worktree_path" checkout -b "$branch_name" "$base_branch" 2>/dev/null; then
        echo "✅ 已创建分支: $branch_name"
        return 0
    else
        echo "❌ 创建分支失败: $branch_name" >&2
        return 1
    fi
}

# 推送分支
push_git_branch() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    if git -C "$worktree_path" push -u origin "$branch_name" 2>/dev/null; then
        echo "✅ 已推送分支: $branch_name"
        return 0
    else
        echo "❌ 推送分支失败: $branch_name" >&2
        return 1
    fi
}

# 删除Git分支
delete_git_branch() {
    local branch_name="$1"
    local force="${2:-false}"
    local worktree_path="${3:-$(pwd)}"
    
    local delete_flag="-d"
    if [[ "$force" == "true" ]]; then
        delete_flag="-D"
    fi
    
    if git -C "$worktree_path" branch "$delete_flag" "$branch_name" 2>/dev/null; then
        echo "✅ 已删除分支: $branch_name"
        return 0
    else
        echo "❌ 删除分支失败: $branch_name" >&2
        return 1
    fi
}
```

## 6. ui.sh - 用户界面

### 核心功能
统一的用户界面输出，避免耦合。

### 基础输出方法

```bash
# 信息输出
ui_info() {
    local message="$1"
    echo "ℹ️ $message"
}

# 成功信息
ui_success() {
    local message="$1"
    echo "✅ $message"
}

# 错误信息（包含解决方案）
ui_error() {
    local message="$1"
    local solution="${2:-}"
    
    echo "❌ 错误：$message" >&2
    if [[ -n "$solution" ]]; then
        echo "💡 建议：$solution" >&2
    fi
}

# 警告信息
ui_warning() {
    local message="$1"
    echo "⚠️ 警告：$message" >&2
}

# 确认操作
ui_confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        echo -n "$message (Y/n): "
    else
        echo -n "$message (y/N): "
    fi
    
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        [nN]|[nN][oO])
            return 1
            ;;
        "")
            [[ "$default" == "y" ]]
            ;;
        *)
            return 1
            ;;
    esac
}
```

## 7. 多命令共用的中级组合方法

### 🎯 输入处理组合方法（所有命令都需要）

这些方法处理用户输入的通用逻辑，被start/pr/clean所有命令使用：

```bash
# 智能解析用户输入的意图（多命令共用核心）
intelligent_parse_user_intent() {
    local user_input="$1"
    local environment_hint="${2:-}"  # "epic", "feature", "auto"
    
    # 1. 基础清理：移除多余的前缀和后缀
    local clean_input
    clean_input=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$user_input")")
    
    # 2. 检测用户输入的意图
    local input_type
    input_type=$(detect_input_type "$user_input" "$environment_hint")
    
    # 3. 返回解析结果
    echo "$input_type:$clean_input"
}

# 推断用户输入的目标类型（epic/feature）
infer_target_type_from_input() {
    local user_input="$1" 
    local environment_hint="${2:-}"
    
    # 1. 优先检查明确的后缀
    local suffix
    suffix=$(path_extract_suffix "$user_input")
    
    case "$suffix" in
        "e")
            echo "epic"
            return 0
            ;;
        "ef")
            echo "feature"
            return 0
            ;;
    esac
    
    # 2. 没有明确后缀，根据环境提示判断
    case "$environment_hint" in
        "epic")
            echo "epic"
            ;;
        "feature")
            echo "feature"
            ;;
        "auto"|"")
            # 3. 自动判断：根据名称特征
            if [[ "$user_input" =~ - ]]; then
                # 包含连字符，可能是feature（如auth-login）
                echo "feature"
            else
                # 简单名称，可能是epic（如auth）
                echo "epic"
            fi
            ;;
        *)
            echo "unknown"
            return 1
            ;;
    esac
}

# 根据类型生成标准分支名称（多命令共用工具）
build_standard_branch_name() {
    local input_type="$1"
    local clean_name="$2"
    local epic_environment="${3:-}"  # 对于feature类型，需要epic环境
    
    case "$input_type" in
        "epic")
            echo "epic-$clean_name-e"
            ;;
        "feature")
            if [[ -z "$epic_environment" ]]; then
                # 尝试从当前环境获取epic环境
                local current_epic
                current_epic=$(extract_current_epic_name) || {
                    echo "❌ 错误：创建Feature需要Epic环境" >&2
                    return 1
                }
                epic_environment="$current_epic"
            fi
            
            # 智能构建feature名称
            if [[ "$clean_name" == "$epic_environment-"* ]]; then
                # 已包含epic前缀：auth-login
                echo "epic-$clean_name-ef"
            else
                # 不包含epic前缀：login
                echo "epic-$epic_environment-$clean_name-ef"
            fi
            ;;
        *)
            echo "❌ 错误：未知的输入类型: $input_type" >&2
            return 1
            ;;
    esac
}

# 验证用户输入与当前环境的匹配性（所有命令共用）
check_input_environment_compatibility() {
    local user_input="$1"
    local current_environment="$2"  # 当前环境
    local expected_type="${3:-}"  # 期望的类型（可选）
    
    # 1. 解析用户输入
    local parse_result
    parse_result=$(intelligent_parse_user_intent "$user_input" "$expected_type") || return 1
    
    local input_type="${parse_result%:*}"
    local clean_name="${parse_result#*:}"
    
    # 2. 验证与当前环境的匹配
    case "$current_environment" in
        "epic")
            if [[ "$input_type" == "feature" && -z "$expected_type" ]]; then
                # 在epic环境中，如果没有明确指定，不应该默认为feature
                echo "⚠️ 警告：在Epic环境中输入了可能是Feature的名称" >&2
                echo "💡 提示：如果要创建Feature，请明确指定" >&2
            fi
            ;;
        "feature")
            if [[ "$input_type" == "epic" && -z "$expected_type" ]]; then
                echo "⚠️ 警告：在Feature环境中输入了可能是Epic的名称" >&2
            fi
            ;;
    esac
    
    # 3. 返回验证结果
    echo "$input_type:$clean_name"
}
```

### 🧭 环境感知组合方法（所有命令都需要）

这些方法处理环境检测和目录切换，被所有命令使用：

```bash
# 检测当前工作环境的完整信息（多命令共用核心）
detect_current_work_environment() {
    # 1. 检测基础环境
    local base_environment
    base_environment=$(environment_detect_complete) || return 1
    
    # 2. 获取详细信息
    local current_branch current_epic current_feature
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || current_branch="unknown"
    
    case "$base_environment" in
        "epic")
            current_epic=$(extract_epic_from_branch "$current_branch")
            echo "epic:$current_epic:$current_branch"
            ;;
        "feature")
            current_epic=$(extract_epic_from_branch "$current_branch")
            current_feature=$(extract_feature_name_from_branch "$current_branch")
            echo "feature:$current_epic:$current_feature:$current_branch"
            ;;
        "root")
            echo "root::$current_branch"
            ;;
        *)
            echo "unknown::$current_branch"
            ;;
    esac
}

# 智能导航到目标工作环境（多命令共用核心）
intelligent_navigate_to_target() {
    local target_input="$1"
    local operation_type="$2"  # "start", "pr", "clean"
    local force_type="${3:-}"  # 可选：强制指定类型
    
    # 1. 解析目标
    local parse_result
    parse_result=$(intelligent_parse_user_intent "$target_input" "$force_type") || return 1
    
    local target_type="${parse_result%:*}"
    local clean_name="${parse_result#*:}"
    
    # 2. 生成标准目标名称
    local target_branch
    case "$target_type" in
        "epic")
            target_branch="epic-$clean_name-e"
            ;;
        "feature")
            # 需要当前epic环境来构建完整feature名称
            local current_epic
            current_epic=$(extract_current_epic_name) || {
                echo "❌ 错误：无法确定Epic环境来构建Feature目标" >&2
                return 1
            }
            target_branch=$(build_standard_branch_name "feature" "$clean_name" "$current_epic")
            ;;
    esac
    
    # 3. 检查目标是否存在
    if worktree_exists "$target_branch"; then
        # 存在，切换到目标环境
        switch_to_worktree_environment "$target_branch" "fail" || return 1
        echo "✅ 已切换到 $target_branch"
        return 0
    else
        # 不存在，根据操作类型决定行为
        case "$operation_type" in
            "start")
                # start命令：返回特殊码，由命令决定是否创建
                echo "💡 目标不存在，需要创建: $target_branch" >&2
                echo "$target_branch"  # 返回标准名称供创建使用
                return 2  # 特殊返回码：需要创建
                ;;
            "pr"|"clean")
                # pr和clean命令：目标必须存在
                echo "❌ 错误：目标不存在: $target_branch" >&2
                return 1
                ;;
            *)
                echo "❌ 错误：未知的操作类型: $operation_type" >&2
                return 1
                ;;
        esac
    fi
}

# 从分支名提取功能名称（新增工具方法）
extract_feature_name_from_branch() {
    local branch_name="$1"
    
    # epic-auth-login-ef -> login
    local clean_name
    clean_name=$(strip_suffix_from_input "$(strip_epic_prefix_from_input "$branch_name")")
    
    # auth-login -> login (移除epic部分)
    echo "${clean_name#*-}"
}
```

### 🔄 工作流程组合方法（多命令共用）

这些方法组合完整的业务流程，被多个命令使用：

```bash
# 统一的Epic处理流程（start和pr命令使用）
execute_epic_workflow() {
    local user_input="$1"
    local operation="$2"     # "create", "switch", "pr"
    local base_branch="${3:-}"  # 仅创建时需要
    
    # 1. 解析和验证输入
    local current_environment
    current_environment=$(detect_current_work_environment) || return 1
    
    local validated_input
    validated_input=$(check_input_environment_compatibility "$user_input" "${current_environment%%:*}" "epic") || return 1
    
    local clean_name="${validated_input#*:}"
    local epic_branch="epic-$clean_name-e"
    
    # 2. 根据操作类型执行
    case "$operation" in
        "create")
            if worktree_exists "$epic_branch"; then
                echo "✅ Epic已存在，切换到环境"
                switch_to_worktree_environment "$epic_branch" "fail"
            else
                echo "🚀 创建新Epic环境"
                switch_to_root_environment "$base_branch" || return 1
                create_and_switch_worktree "$epic_branch" "$base_branch"
            fi
            ;;
        "switch")
            if worktree_exists "$epic_branch"; then
                switch_to_worktree_environment "$epic_branch" "fail"
            else
                echo "❌ Epic不存在: $epic_branch" >&2
                return 1
            fi
            ;;
        "pr")
            # PR特定的Epic处理逻辑
            if ! worktree_exists "$epic_branch"; then
                echo "❌ Epic不存在: $epic_branch" >&2
                return 1
            fi
            switch_to_worktree_environment "$epic_branch" "fail"
            echo "$epic_branch:develop"  # 返回PR方向
            ;;
    esac
}

# 统一的Feature处理流程（start和pr命令使用）
process_feature_operation() {
    local feature_input="$1"
    local epic_input="$2"
    local operation="$3"     # "create", "switch", "pr"
    
    # 1. 解析Epic和Feature
    local epic_result
    epic_result=$(check_input_environment_compatibility "$epic_input" "unknown" "epic") || return 1
    local epic_clean="${epic_result#*:}"
    local epic_branch="epic-$epic_clean-e"
    
    local feature_result
    feature_result=$(check_input_environment_compatibility "$feature_input" "unknown" "feature") || return 1
    local feature_clean="${feature_result#*:}"
    
    # 2. 生成Feature分支名
    local feature_branch
    feature_branch=$(build_standard_branch_name "feature" "$feature_clean" "$epic_clean") || return 1
    
    # 3. 根据操作类型执行
    case "$operation" in
        "create")
            if worktree_exists "$feature_branch"; then
                echo "✅ Feature已存在，切换到环境"
                switch_to_worktree_environment "$feature_branch" "fail"
            else
                echo "🚀 创建新Feature环境"
                # 确保Epic存在
                if ! worktree_exists "$epic_branch"; then
                    echo "❌ Epic不存在: $epic_branch" >&2
                    return 1
                fi
                # 切换到Epic环境作为基础
                switch_to_worktree_environment "$epic_branch" "fail" || return 1
                echo "📍 切换到Epic环境 (.worktrees/$epic_branch)"
                # 创建Feature
                create_and_switch_worktree "$feature_branch" "$epic_branch"
            fi
            ;;
        "switch")
            if worktree_exists "$feature_branch"; then
                switch_to_worktree_environment "$feature_branch" "fail"
            else
                echo "❌ Feature不存在: $feature_branch" >&2
                return 1
            fi
            ;;
        "pr")
            # PR特定的Feature处理逻辑
            if ! worktree_exists "$feature_branch"; then
                echo "❌ Feature不存在: $feature_branch" >&2
                return 1
            fi
            switch_to_worktree_environment "$feature_branch" "fail"
            echo "$feature_branch:$epic_branch"  # 返回PR方向
            ;;
    esac
}
```

## 8. 命令级别的高级工作流方法

### 🚀 最终工作流组合（命令直接调用）

这些方法是最高级的组合，专门为特定命令提供完整的业务流程：

```bash
# start命令专用：Epic创建或切换流程
start_epic_creation_workflow() {
    local user_input="$1"
    local base_branch="$2"
    
    # 直接调用通用的Epic处理流程
    execute_epic_workflow "$user_input" "create" "$base_branch"
}

# start命令专用：Feature创建或切换流程  
start_feature_creation_workflow() {
    local feature_input="$1"
    local epic_input="$2"
    
    # 直接调用通用的Feature处理流程
    execute_feature_workflow "$feature_input" "$epic_input" "create"
}

# pr命令专用：自动检测PR方向并创建
auto_detect_pr_direction_workflow() {
    # 1. 获取当前执行环境
    local execution_environment
    execution_environment=$(detect_current_work_environment) || return 1
    
    local environment_type="${execution_environment%%:*}"
    
    # 2. 根据环境自动确定PR方向
    case "$environment_type" in
        "epic")
            local current_branch="${execution_environment##*:}"
            echo "$current_branch:develop"  # Epic → develop
            ;;
        "feature")
            local current_branch="${execution_environment##*:}"
            local epic_name
            epic_name=$(extract_epic_from_branch "$current_branch")
            echo "$current_branch:epic-$epic_name-e"  # Feature → Epic
            ;;
        *)
            echo "❌ 错误：当前不在Epic或Feature环境中" >&2
            echo "💡 提示：请切换到正确目录或指定目标分支" >&2
            return 1
            ;;
    esac
}

# pr命令专用：指定目标的PR创建
target_pr_creation_workflow() {
    local target_input="$1"
    
    # 1. 智能切换到目标环境
    local switch_result
    switch_result=$(intelligent_navigate_to_target "$target_input" "pr") || return 1
    
    # 2. 切换成功后，调用自动PR流程
    auto_detect_pr_direction_workflow
}

# pr命令专用：PR状态检查和创建
pr_safety_check_and_creation() {
    local source_branch="$1"
    local target_branch="$2"
    
    # 1. 必要的状态检查
    local current_path=$(pwd)
    if ! check_branch_safety "$source_branch" "$current_path"; then
        echo "❌ 分支状态检查失败" >&2
        echo "💡 建议：处理未保存的修改后重试" >&2
        return 1
    fi
    
    # 2. 推送分支（如果需要）
    if ! check_branch_pushed "$source_branch" "$current_path"; then
        echo "📤 推送分支到远程..."
        push_git_branch "$source_branch" "$current_path" || return 1
    fi
    
    # 3. 状态确认
    ui_success "🔍 PR状态检查：工作区干净 ✅ 暂存区为空 ✅ 分支已推送 ✅"
    ui_success "🚀 准备创建PR：$source_branch → $target_branch"
    
    # 4. 返回PR创建信息（具体的PR创建由命令特定代码处理）
    echo "$source_branch:$target_branch"
}

# clean命令专用：环境感知清理流程
environment_aware_cleanup_workflow() {
    local cleanup_mode="$1"     # "preview", "safe", "force"
    local target_input="${2:-}" # 可选的目标参数
    
    # 1. 确定清理范围
    local cleanup_scope
    if [[ -n "$target_input" ]]; then
        # 有指定目标，解析目标范围
        cleanup_scope=$(analyze_cleanup_target "$target_input") || return 1
    else
        # 无目标，根据当前环境确定范围
        local current_environment
        current_environment=$(detect_current_work_environment) || return 1
        cleanup_scope=$(calculate_cleanup_scope_for_environment "${current_environment%%:*}") || return 1
    fi
    
    # 2. 根据模式执行清理
    case "$cleanup_mode" in
        "preview")
            analyze_cleanup_scope "$cleanup_scope"
            ;;
        "safe")
            execute_safe_cleanup_workflow "$cleanup_scope"
            ;;
        "force")
            execute_force_cleanup_workflow "$cleanup_scope"
            ;;
        *)
            echo "❌ 错误：无效的清理模式: $cleanup_mode" >&2
            return 1
            ;;
    esac
}

# clean命令专用：解析清理目标
analyze_cleanup_target() {
    local target_input="$1"
    
    # 1. 解析用户输入
    local parse_result
    parse_result=$(intelligent_parse_user_intent "$target_input" "auto") || return 1
    
    local target_type="${parse_result%:*}"
    local clean_name="${parse_result#*:}"
    
    # 2. 根据类型确定清理范围
    case "$target_type" in
        "epic")
            echo "epic_target:$clean_name"
            ;;
        "feature")
            # Feature清理需要完整的分支名
            local current_epic
            current_epic=$(extract_current_epic_name) || {
                echo "❌ 错误：清理Feature需要Epic环境" >&2
                return 1
            }
            local feature_branch
            feature_branch=$(build_standard_branch_name "feature" "$clean_name" "$current_epic")
            echo "feature_target:$feature_branch"
            ;;
        *)
            echo "❌ 错误：无法识别清理目标类型: $target_input" >&2
            return 1
            ;;
    esac
}

# clean命令专用：根据环境确定清理范围
calculate_cleanup_scope_for_environment() {
    local current_environment="$1"
    
    case "$current_environment" in
        "root")
            echo "all_gpf_worktrees"
            ;;
        "epic")
            local current_epic
            current_epic=$(extract_current_epic_name) || return 1
            echo "epic_scope:$current_epic"
            ;;
        "feature")
            local current_branch
            current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
            echo "feature_scope:$current_branch"
            ;;
        *)
            echo "❌ 错误：无法确定清理范围，当前环境: $current_environment" >&2
            return 1
            ;;
    esac
}
```

### 🎯 完善的分层架构总结

经过重新设计，现在的方法分层完全符合您的架构理念：

**Layer 1 - 基础方法（原子操作）**
- `path_extract_suffix()`, `strip_epic_prefix_from_input()`, `validate_name_format()`
- 专注单一功能，无副作用，可独立测试

**Layer 2 - 验证方法（输入检查）**  
- `validate_input_suffix_matches_expected()`, `validate_epic_prefix_format()`, `check_branch_safety()`
- 组合基础方法进行验证，返回明确结果

**Layer 3 - 处理方法（转换规范）**
- `ensure_suffix_present()`, `transform_input_to_epic_branch()`, `build_standard_branch_name()`
- 组合基础和验证方法，进行数据转换

**🆕 Layer 4 - 多命令共用组合（中级工作流）**
- `intelligent_parse_user_intent()`, `intelligent_navigate_to_target()`, `execute_epic_workflow()`
- **这是关键层**：被start/pr/clean多个命令共同使用

**🆕 Layer 5 - 命令专用工作流（高级组合）**
- `start_epic_creation_workflow()`, `auto_detect_pr_direction_workflow()`, `environment_aware_cleanup_workflow()`
- **专门为特定命令定制**，但仍调用Layer 4的共用方法

### 🎯 核心设计理念

这样的分层组件设计确保了：

1. **完美的职责分离**：core提供基础工具和多命令共用方法，command文件负责命令特定逻辑
2. **自由灵活组合**：基础方法可以自由组合为高级方法，高级方法可以被命令调用
3. **易于扩展维护**：新增命令可以直接复用现有的core工具
4. **测试友好设计**：每个基础方法都可以独立测试
5. **维护成本极低**：修改基础功能只需更新core，不影响命令逻辑

### 💡 使用原则

命令文件应该：
- 调用core提供的基础和组合方法
- 实现命令特定的逻辑和工作流
- 避免重复实现core已有的功能
- 保持轻量，专注于命令编排

现在的架构完全实现了您的设想：**"底层要改，上层不用改，或者上层需要组合某个底层就实现良好的上层方法"**！

## 8. sync.sh - 同步管理

### 核心功能
智能的级联同步管理，支持上往下的分支同步、自动pull远程更新、安全检查和冲突处理。

### 基础同步检查方法

```bash
# 检查分支是否需要同步
check_sync_requirements() {
    local source_branch="$1"    # epic-auth-e
    local target_branch="$2"    # develop
    
    # 获取分支的最新commit
    local source_commit=$(git rev-parse "$source_branch" 2>/dev/null) || return 1
    local target_commit=$(git rev-parse "$target_branch" 2>/dev/null) || return 1
    
    # 检查source_branch是否基于最新的target_branch
    local merge_base=$(git merge-base "$source_branch" "$target_branch" 2>/dev/null) || return 1
    
    if [[ "$merge_base" != "$target_commit" ]]; then
        # 需要同步
        return 0
    else
        # 无需同步
        return 1
    fi
}

# 检查同步的安全性
check_sync_safety() {
    local branch_name="$1"
    local worktree_path="$2"
    
    # 1. 工作区必须干净
    if ! check_working_tree_clean "$worktree_path"; then
        echo "❌ 工作区有未保存修改，无法安全同步"
        return 1
    fi
    
    # 2. 暂存区必须为空
    if ! check_staging_area_clean "$worktree_path"; then
        echo "❌ 暂存区有未提交内容，无法安全同步"
        return 1
    fi
    
    # 3. 检查远程连接
    if ! git ls-remote --exit-code origin >/dev/null 2>&1; then
        echo "❌ 无法连接到远程仓库"
        return 1
    fi
    
    return 0
}

# Pull最新远程代码
pull_latest_remote_changes() {
    local branch_name="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 1. Fetch 所有远程更新
    if ! git -C "$worktree_path" fetch origin; then
        echo "❌ Fetch 远程更新失败"
        return 1
    fi
    
    # 2. 如果分支已推送到远程，则pull最新
    if check_branch_pushed "$branch_name" "$worktree_path"; then
        if ! git -C "$worktree_path" pull origin "$branch_name"; then
            echo "❌ Pull $branch_name 失败"
            return 1
        fi
        echo "✅ Pull $branch_name: 成功"
    else
        echo "ℹ️ $branch_name 未推送到远程，跳过pull"
    fi
    
    return 0
}
```

### 核心同步执行方法

```bash
# 执行单个分支的上游同步
execute_upstream_sync() {
    local target_branch="$1"    # epic-auth-e
    local source_branch="$2"    # develop
    local force="${3:-false}"   # 是否强制同步
    
    local worktree_path
    worktree_path=$(find_worktree_by_branch "$target_branch") || {
        echo "❌ 未找到分支 $target_branch 的worktree"
        return 1
    }
    
    echo "📦 同步 $source_branch → $target_branch"
    
    # 1. 安全检查
    if [[ "$force" != "true" ]]; then
        check_sync_safety "$target_branch" "$worktree_path" || return 1
    fi
    
    # 2. Pull最新远程代码
    pull_latest_remote_changes "$source_branch" || return 1
    pull_latest_remote_changes "$target_branch" "$worktree_path" || return 1
    
    # 3. 执行合并
    echo "🔗 合并 $source_branch → $target_branch"
    if git -C "$worktree_path" merge "$source_branch" --no-edit; then
        echo "✅ 合并成功"
    else
        echo "❌ 合并失败，存在冲突"
        echo "💡 请手动解决冲突后重试"
        return 1
    fi
    
    # 4. 推送更新到远程
    if git -C "$worktree_path" push origin "$target_branch"; then
        echo "✅ 推送成功"
    else
        echo "⚠️ 推送失败，但本地同步已完成"
        return 1
    fi
    
    return 0
}

# 执行级联同步（Epic → 所有Features）
execute_cascade_sync() {
    local epic_branch="$1"      # epic-auth-e
    local source_branch="${2:-develop}"  # develop
    
    echo "🔄 执行级联同步: $source_branch → $epic_branch → features"
    
    # 1. 同步Epic
    if check_sync_requirements "$epic_branch" "$source_branch"; then
        echo "📦 Phase 1: 主同步 ($source_branch → $epic_branch)"
        execute_upstream_sync "$epic_branch" "$source_branch" || return 1
    else
        echo "✅ $epic_branch 已是最新，无需同步"
    fi
    
    # 2. 获取所有相关的Feature分支
    local epic_name
    epic_name=$(extract_epic_from_branch "$epic_branch") || return 1
    
    local feature_branches
    feature_branches=$(list_all_worktrees | grep "^epic-$epic_name-.*-ef:")
    
    if [[ -z "$feature_branches" ]]; then
        echo "ℹ️ 没有发现相关的Feature分支"
        return 0
    fi
    
    # 3. 级联同步所有Feature
    echo "📦 Phase 2: 级联同步 ($epic_branch → features)"
    local sync_count=0
    local skip_count=0
    
    while IFS=: read -r feature_branch feature_path; do
        echo "🔄 同步 $feature_branch"
        
        if check_sync_requirements "$feature_branch" "$epic_branch"; then
            if execute_upstream_sync "$feature_branch" "$epic_branch"; then
                ((sync_count++))
                echo "✅ $feature_branch 同步成功"
            else
                echo "❌ $feature_branch 同步失败"
                ((skip_count++))
            fi
        else
            echo "✅ $feature_branch 已是最新，跳过"
            ((skip_count++))
        fi
    done <<< "$feature_branches"
    
    echo "📊 级联同步完成: 成功 $sync_count 个，跳过 $skip_count 个"
    return 0
}
```

### 多命令共用的同步方法

```bash
# start命令专用：确保Epic在创建Feature前是同步的
ensure_epic_is_synced_before_feature_creation() {
    local epic_branch="$1"      # epic-auth-e
    local base_branch="${2:-develop}"    # develop
    
    echo "🔍 检查Epic同步状态..."
    
    if check_sync_requirements "$epic_branch" "$base_branch"; then
        echo "🔄 检测到Epic需要从 $base_branch 同步"
        echo "❓ 是否先同步Epic再创建Feature? [Y/n]:"
        
        if ui_confirm "继续同步" "y"; then
            execute_upstream_sync "$epic_branch" "$base_branch" || {
                echo "❌ Epic同步失败，无法创建Feature"
                return 1
            }
            echo "✅ Epic同步完成，继续创建Feature"
        else
            echo "⚠️ 用户选择跳过同步，继续创建Feature"
        fi
    else
        echo "✅ Epic已是最新，继续创建Feature"
    fi
    
    return 0
}

# pr命令专用：检查PR前的同步新鲜度
check_pr_sync_requirements() {
    local source_branch="$1"    # epic-auth-login-ef
    local target_branch="$2"    # epic-auth-e
    
    echo "🔍 检查分支同步新鲜度..."
    
    if check_sync_requirements "$source_branch" "$target_branch"; then
        echo "⚠️ 当前分支不是基于最新的 $target_branch"
        echo "❓ 是否先同步再创建PR? [Y/n]:"
        
        if ui_confirm "继续同步" "y"; then
            execute_upstream_sync "$source_branch" "$target_branch" || {
                echo "❌ 同步失败，无法创建PR"
                return 1
            }
            echo "✅ 同步完成，继续创建PR"
        else
            echo "⚠️ 用户选择跳过同步，继续创建PR"
        fi
    else
        echo "✅ 分支已是最新，继续创建PR"
    fi
    
    return 0
}

# 根据环境智能确定同步范围
determine_sync_scope() {
    local current_environment="$1"
    local target_input="${2:-}"
    
    if [[ -n "$target_input" ]]; then
        # 有指定目标，解析目标类型
        local parse_result
        parse_result=$(intelligent_parse_user_intent "$target_input" "auto") || return 1
        
        local target_type="${parse_result%:*}"
        local clean_name="${parse_result#*:}"
        
        case "$target_type" in
            "epic")
                echo "epic_target:$clean_name"
                ;;
            "feature")
                echo "feature_target:$clean_name"
                ;;
        esac
    else
        # 无目标，根据当前环境确定
        case "$current_environment" in
            "root")
                echo "all_epics"
                ;;
            "epic")
                local current_epic
                current_epic=$(extract_current_epic_name) || return 1
                echo "epic_cascade:$current_epic"
                ;;
            "feature")
                local current_branch
                current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
                echo "feature_sync:$current_branch"
                ;;
            *)
                echo "❌ 无法确定同步范围，当前环境: $current_environment" >&2
                return 1
                ;;
        esac
    fi
}
```

## 9. status.sh - 统一状态检查架构

### 🎯 核心设计理念
**统一状态检查，消除重复逻辑**：将所有命令中的状态检查逻辑整合到这个组件中，其他命令通过调用这里的方法而不是重复实现。

**无目录切换设计**：所有状态检查方法不执行目录切换，通过显式路径参数进行远程分析，避免干扰调用命令的工作流。

**分层状态检查**：原子级检查 → 组合级检查 → 应用级检查，支持不同命令的不同需求。

### 🏗️ 三层状态检查架构

#### 第一层：原子级状态检查（远程无切换）

```bash
# 基础工作区状态检查（无目录切换）
check_working_tree_clean_remote() {
    local worktree_path="$1"
    [[ -d "$worktree_path" ]] || return 1
    git -C "$worktree_path" diff --quiet 2>/dev/null
}

check_staging_area_clean_remote() {
    local worktree_path="$1"
    [[ -d "$worktree_path" ]] || return 1
    git -C "$worktree_path" diff --cached --quiet 2>/dev/null
}

check_branch_pushed_remote() {
    local branch_name="$1"
    local worktree_path="$2"
    [[ -d "$worktree_path" ]] || return 1
    git -C "$worktree_path" rev-parse "origin/$branch_name" >/dev/null 2>&1
}

check_branch_merged_remote() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="$3"
    [[ -d "$worktree_path" ]] || return 1
    
    local merge_base commit_count
    merge_base=$(git -C "$worktree_path" merge-base "$branch_name" "$target_branch" 2>/dev/null)
    commit_count=$(git -C "$worktree_path" rev-list --count "$merge_base..$branch_name" 2>/dev/null || echo "1")
    [[ "$commit_count" -eq 0 ]]
}

# 🆕 同步状态检查（远程）
check_sync_requirements_remote() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="$3"
    [[ -d "$worktree_path" ]] || return 1
    
    # 检查分支是否基于最新的目标分支
    local target_latest_commit source_base_commit
    target_latest_commit=$(git -C "$worktree_path" rev-parse "origin/$target_branch" 2>/dev/null)
    source_base_commit=$(git -C "$worktree_path" merge-base "$branch_name" "origin/$target_branch" 2>/dev/null)
    
    [[ "$target_latest_commit" != "$source_base_commit" ]]
}

# 🆕 非worktree分支状态检查（完整覆盖）
check_root_branch_status() {
    local branch_name="$1"
    local project_root="$2"
    
    # 检查根目录分支状态
    git -C "$project_root" rev-parse --verify "$branch_name" >/dev/null 2>&1 || return 1
    
    # 返回状态信息
    local current_branch
    current_branch=$(git -C "$project_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$current_branch" == "$branch_name" ]]; then
        # 当前在此分支，检查工作区状态
        check_working_tree_clean_remote "$project_root" && 
        check_staging_area_clean_remote "$project_root"
    else
        # 不在此分支，只检查分支存在性
        return 0
    fi
}

# 🌐 远程分支状态检查（扩展覆盖）
check_remote_branch_status() {
    local branch_name="$1"
    local worktree_path="$2"
    local remote_name="${3:-origin}"
    
    [[ -d "$worktree_path" ]] || return 1
    
    # 检查远程分支是否存在
    git -C "$worktree_path" rev-parse --verify "$remote_name/$branch_name" >/dev/null 2>&1 || return 1
    
    # 获取本地和远程的最新提交
    local local_commit remote_commit
    local_commit=$(git -C "$worktree_path" rev-parse "$branch_name" 2>/dev/null)
    remote_commit=$(git -C "$worktree_path" rev-parse "$remote_name/$branch_name" 2>/dev/null)
    
    # 计算领先和落后的提交数量
    local ahead_count behind_count
    ahead_count=$(git -C "$worktree_path" rev-list --count "$remote_name/$branch_name..$branch_name" 2>/dev/null || echo "0")
    behind_count=$(git -C "$worktree_path" rev-list --count "$branch_name..$remote_name/$branch_name" 2>/dev/null || echo "0")
    
    # 返回同步状态信息
    if [[ "$local_commit" == "$remote_commit" ]]; then
        echo "synced:0:0"  # 同步:领先0:落后0
    else
        echo "diverged:$ahead_count:$behind_count"  # 分叉:领先数:落后数
    fi
}

# 🔍 全覆盖分支发现（包括非GPF管理的分支）
discover_all_branches() {
    local project_root="$1"
    local include_non_gpf="${2:-false}"  # 是否包括非GPF管理的分支
    
    local all_branches=()
    
    # 🎯 发现GPF管理的worktree分支
    local worktree_branches
    worktree_branches=$(list_all_worktrees "$project_root" | awk '{print $2}' | grep -E '-(e|ef)$')
    while IFS= read -r branch; do
        [[ -n "$branch" ]] && all_branches+=("$branch:worktree")
    done <<< "$worktree_branches"
    
    # 🌐 发现根目录可能的分支（如果启用）
    if [[ "$include_non_gpf" == "true" ]]; then
        local current_branch
        current_branch=$(git -C "$project_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
        
        # 检查当前根目录分支（通常是develop或main）
        if [[ -n "$current_branch" ]] && [[ "$current_branch" != "HEAD" ]]; then
            # 排除GPF管理的分支，只包含真正的根目录分支
            if ! [[ "$current_branch" =~ -(e|ef)$ ]]; then
                all_branches+=("$current_branch:root")
            fi
        fi
        
        # 发现其他本地非GPF分支
        local other_branches
        other_branches=$(git -C "$project_root" branch --format='%(refname:short)' | grep -v -E '-(e|ef)$')
        while IFS= read -r branch; do
            if [[ -n "$branch" ]] && [[ "$branch" != "$current_branch" ]]; then
                all_branches+=("$branch:local")
            fi
        done <<< "$other_branches"
    fi
    
    # 输出发现的分支
    printf '%s\n' "${all_branches[@]}"
}

# 📊 综合状态分析（扩展覆盖所有分支）
analyze_comprehensive_project_status() {
    local target_identifier="${1:-}"    
    local include_non_gpf="${2:-false}"  # 是否包括非GPF分支
    local detail_level="${3:-summary}"   
    
    local project_root
    project_root=$(find_project_root) || {
        echo "❌ 不在GPF项目中" >&2
        return 1
    }
    
    echo "🌍 完整项目状态分析 (包括非GPF分支: $include_non_gpf)"
    echo "📁 项目路径: $project_root"
    
    # 🔍 发现所有分支
    local all_discovered_branches
    all_discovered_branches=$(discover_all_branches "$project_root" "$include_non_gpf")
    
    # 📊 分类统计
    local worktree_count=0 root_count=0 local_count=0
    while IFS=':' read -r branch_name branch_type; do
        case "$branch_type" in
            "worktree") ((worktree_count++)) ;;
            "root") ((root_count++)) ;;
            "local") ((local_count++)) ;;
        esac
    done <<< "$all_discovered_branches"
    
    echo ""
    echo "📊 分支统计:"
    echo "  🎯 GPF Worktree分支: $worktree_count 个"
    [[ "$include_non_gpf" == "true" ]] && {
        echo "  🏠 根目录分支: $root_count 个"
        echo "  📱 其他本地分支: $local_count 个"
    }
    
    # 🎯 分析每个分支的状态
    while IFS=':' read -r branch_name branch_type; do
        [[ -n "$branch_name" ]] || continue
        
        case "$branch_type" in
            "worktree")
                # GPF管理的worktree分支，使用完整分析
                analyze_single_branch_comprehensive "$branch_name" "$detail_level" "human"
                ;;
            "root"|"local")
                # 非GPF分支，使用基础分析
                [[ "$include_non_gpf" == "true" ]] && analyze_non_gpf_branch "$branch_name" "$branch_type" "$project_root"
                ;;
        esac
    done <<< "$all_discovered_branches"
}

# 📱 非GPF分支状态分析
analyze_non_gpf_branch() {
    local branch_name="$1"
    local branch_type="$2"  # root|local
    local project_root="$3"
    
    echo ""
    case "$branch_type" in
        "root") echo "🏠 根目录分支: $branch_name" ;;
        "local") echo "📱 本地分支: $branch_name" ;;
    esac
    
    # 检查当前是否在此分支
    local current_branch
    current_branch=$(git -C "$project_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    if [[ "$current_branch" == "$branch_name" ]]; then
        echo "📍 状态: 🔴 当前活跃分支"
        
        # 检查工作区状态
        local modified_count staged_count
        modified_count=$(git -C "$project_root" diff --name-only | wc -l | tr -d ' ')
        staged_count=$(git -C "$project_root" diff --cached --name-only | wc -l | tr -d ' ')
        
        local status_indicators=()
        [[ "$modified_count" -eq 0 ]] && status_indicators+=("💾") || status_indicators+=("📝")
        [[ "$staged_count" -eq 0 ]] && status_indicators+=("✅") || status_indicators+=("📋")
        
        echo "🏷️ 状态: $(IFS=' '; echo "${status_indicators[*]}")"
        echo "   修改文件: $modified_count | 暂存文件: $staged_count"
    else
        echo "📍 状态: ⚪ 非活跃分支"
        
        # 检查与远程的同步状态
        if git -C "$project_root" rev-parse --verify "origin/$branch_name" >/dev/null 2>&1; then
            local sync_info
            sync_info=$(check_remote_branch_status "$branch_name" "$project_root")
            local sync_status ahead_count behind_count
            IFS=':' read -r sync_status ahead_count behind_count <<< "$sync_info"
            
            case "$sync_status" in
                "synced") echo "🔄 同步状态: 🟢 与远程同步" ;;
                "diverged") echo "🔄 同步状态: 🟡 领先${ahead_count}个，落后${behind_count}个提交" ;;
            esac
        else
            echo "🔄 同步状态: ⚪ 无远程分支"
        fi
    fi
}
```

#### 第二层：分层状态检查（根据分支类型应用不同标准）

```bash
# 🎯 分支类型感知的PR就绪性检查
check_pr_readiness_unified() {
    local branch_name="$1"
    local worktree_path="${2:-}"
    local skip_output="${3:-false}"
    
    # 🔍 自动解析worktree路径
    if [[ -z "$worktree_path" ]]; then
        worktree_path=$(find_worktree_by_branch "$branch_name")
        [[ -n "$worktree_path" ]] || {
            [[ "$skip_output" != "true" ]] && echo "❌ 找不到分支对应的worktree: $branch_name" >&2
            return 1
        }
    fi
    
    # 🏷️ 识别分支类型
    local branch_type
    branch_type=$(path_extract_suffix "$branch_name")
    
    [[ "$skip_output" != "true" ]] && echo "🔍 PR就绪性检查: $branch_name ($branch_type分支)"
    
    local issues=()
    
    # 🎯 通用检查（所有分支都需要）
    check_working_tree_clean_remote "$worktree_path" || issues+=("工作区有未保存修改")
    check_staging_area_clean_remote "$worktree_path" || issues+=("暂存区有未提交内容")
    
    # 🎯 分支类型特定检查
    case "$branch_type" in
        "e")
            # Epic分支：需要推送到GitHub，PR到develop
            check_epic_pr_readiness "$branch_name" "$worktree_path" issues
            ;;
        "ef")
            # Feature分支：不需要推送GitHub，只需合并到Epic
            check_feature_pr_readiness "$branch_name" "$worktree_path" issues
            ;;
        *)
            issues+=("未知分支类型: $branch_type")
            ;;
    esac
    
    # 返回结果
    if [[ ${#issues[@]} -eq 0 ]]; then
        [[ "$skip_output" != "true" ]] && echo "✅ PR就绪性检查通过"
        return 0
    else
        if [[ "$skip_output" != "true" ]]; then
            echo "❌ 发现 ${#issues[@]} 个问题："
            for issue in "${issues[@]}"; do
                echo "  - $issue"
            done
        fi
        return 1
    fi
}

# 🎯 Epic分支的PR就绪性检查
check_epic_pr_readiness() {
    local branch_name="$1"
    local worktree_path="$2"
    local -n issues_ref="$3"
    
    # Epic分支必须推送到GitHub
    check_branch_pushed_remote "$branch_name" "$worktree_path" || 
        issues_ref+=("Epic分支未推送到GitHub")
    
    # Epic分支必须基于最新的develop
    check_sync_requirements_remote "$branch_name" "develop" "$worktree_path" && 
        issues_ref+=("Epic分支不基于最新的develop，需要同步")
    
    # Epic分支必须有提交内容（不能是空分支）
    local commit_count
    commit_count=$(git -C "$worktree_path" rev-list --count HEAD 2>/dev/null || echo "0")
    [[ "$commit_count" -eq 0 ]] && issues_ref+=("Epic分支没有任何提交")
}

# 📦 Feature分支的PR就绪性检查  
check_feature_pr_readiness() {
    local branch_name="$1"
    local worktree_path="$2"
    local -n issues_ref="$3"
    
    # 🔧 修正：Feature分支也必须推送到GitHub
    # GPF是PR友好工具，所有分支都要推送后在GitHub创建PR
    check_branch_pushed_remote "$branch_name" "$worktree_path" || 
        issues_ref+=("Feature分支未推送到GitHub")
    
    # Feature分支需要检查是否有相对于Epic的新提交
    local commit_count target_epic
    target_epic=$(extract_parent_epic_from_feature "$branch_name")
    commit_count=$(git -C "$worktree_path" rev-list --count "epic-$target_epic-e..HEAD" 2>/dev/null || echo "0")
    [[ "$commit_count" -eq 0 ]] && issues_ref+=("Feature分支相对于Epic没有新的提交")
    
    # Feature分支必须基于最新的Epic
    check_sync_requirements_remote "$branch_name" "epic-$target_epic-e" "$worktree_path" && 
        issues_ref+=("Feature分支不基于最新的Epic，需要同步")
    
    # 检查Epic分支是否存在且可访问
    local epic_worktree
    epic_worktree=$(find_worktree_by_branch "epic-$target_epic-e")
    [[ -z "$epic_worktree" ]] && issues_ref+=("对应的Epic分支不存在或不可访问: epic-$target_epic-e")
}

# 🧹 分支类型感知的清理安全性检查
check_clean_safety_unified() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="${3:-}"
    local skip_output="${4:-false}"
    
    # 🔍 自动解析worktree路径
    if [[ -z "$worktree_path" ]]; then
        worktree_path=$(find_worktree_by_branch "$branch_name")
        [[ -n "$worktree_path" ]] || {
            [[ "$skip_output" != "true" ]] && echo "❌ 找不到分支对应的worktree: $branch_name" >&2
            return 1
        }
    fi
    
    # 🏷️ 识别分支类型
    local branch_type
    branch_type=$(path_extract_suffix "$branch_name")
    
    [[ "$skip_output" != "true" ]] && echo "🧹 清理安全性检查: $branch_name ($branch_type分支)"
    
    local safety_level="safe"
    local issues=()
    
    # 🎯 通用安全检查（所有分支都需要）
    check_working_tree_clean_remote "$worktree_path" || {
        safety_level="dangerous"
        issues+=("工作区有未保存修改")
    }
    
    check_staging_area_clean_remote "$worktree_path" || {
        safety_level="dangerous" 
        issues+=("暂存区有未提交内容")
    }
    
    # 🎯 分支类型特定的安全检查
    case "$branch_type" in
        "e")
            # Epic分支的清理检查
            check_epic_clean_safety "$branch_name" "$worktree_path" safety_level issues
            ;;
        "ef")
            # Feature分支的清理检查
            check_feature_clean_safety "$branch_name" "$target_branch" "$worktree_path" safety_level issues
            ;;
        *)
            safety_level="dangerous"
            issues+=("未知分支类型: $branch_type")
            ;;
    esac
    
    # 返回结果格式：safety_level:issue1,issue2,issue3
    echo "$safety_level:$(IFS=','; echo "${issues[*]}")"
}

# 🎯 Epic分支的清理安全检查
check_epic_clean_safety() {
    local branch_name="$1"
    local worktree_path="$2"
    local -n safety_level_ref="$3"
    local -n issues_ref="$4"
    
    # Epic分支必须已合并到develop
    check_branch_merged_remote "$branch_name" "develop" "$worktree_path" || {
        safety_level_ref="dangerous"
        issues_ref+=("Epic分支未合并到develop")
    }
    
    # Epic分支的推送检查：必须已推送到GitHub
    if check_branch_pushed_remote "$branch_name" "$worktree_path"; then
        local unpushed_count
        unpushed_count=$(git -C "$worktree_path" rev-list --count "origin/$branch_name..HEAD" 2>/dev/null || echo "0")
        if [[ "$unpushed_count" -gt 0 ]]; then
            [[ "$safety_level_ref" == "safe" ]] && safety_level_ref="warning"
            issues_ref+=("有 $unpushed_count 个未推送提交")
        fi
    else
        safety_level_ref="dangerous"
        issues_ref+=("Epic分支未推送到GitHub")
    fi
}

# 📦 Feature分支的清理安全检查
check_feature_clean_safety() {
    local branch_name="$1"
    local target_branch="$2"  # 通常是对应的Epic分支
    local worktree_path="$3"
    local -n safety_level_ref="$4"
    local -n issues_ref="$5"
    
    # 🔧 修正：Feature分支必须已在GitHub PR合并到Epic
    # 检查是否已通过GitHub PR合并（而不是本地merge）
    if ! check_github_pr_merged "$branch_name" "$target_branch"; then
        safety_level_ref="dangerous"
        issues_ref+=("Feature分支未在GitHub PR合并到 $target_branch")
    fi
    
    # Feature分支的推送检查：必须已推送到GitHub
    if check_branch_pushed_remote "$branch_name" "$worktree_path"; then
        local unpushed_count
        unpushed_count=$(git -C "$worktree_path" rev-list --count "origin/$branch_name..HEAD" 2>/dev/null || echo "0")
        if [[ "$unpushed_count" -gt 0 ]]; then
            [[ "$safety_level_ref" == "safe" ]] && safety_level_ref="warning"
            issues_ref+=("有 $unpushed_count 个未推送提交")
        fi
    else
        safety_level_ref="dangerous"
        issues_ref+=("Feature分支未推送到GitHub")
    fi
}

# 🔍 检查GitHub PR是否已合并（需要gh命令或API调用）
check_github_pr_merged() {
    local source_branch="$1"
    local target_branch="$2"
    
    # 方法1：使用gh命令检查（如果可用）
    if command -v gh >/dev/null 2>&1; then
        gh pr list --state merged --head "$source_branch" --base "$target_branch" --json number >/dev/null 2>&1
        return $?
    fi
    
    # 方法2：使用git检查本地是否已合并（fallback）
    # 注意：这不能保证是通过PR合并的，只能检查是否已合并
    local worktree_path
    worktree_path=$(find_worktree_by_branch "$target_branch")
    if [[ -n "$worktree_path" ]]; then
        check_branch_merged_remote "$source_branch" "$target_branch" "$worktree_path"
    else
        return 1
    fi
}

# 🔄 Sync前的就绪性检查（供sync命令调用）
check_sync_readiness_unified() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="${3:-}"
    local skip_output="${4:-false}"
    
    # 🔍 自动解析worktree路径
    if [[ -z "$worktree_path" ]]; then
        worktree_path=$(find_worktree_by_branch "$branch_name")
        [[ -n "$worktree_path" ]] || {
            [[ "$skip_output" != "true" ]] && echo "❌ 找不到分支对应的worktree: $branch_name" >&2
            return 1
        }
    fi
    
    [[ "$skip_output" != "true" ]] && echo "🔄 同步就绪性检查: $branch_name"
    
    local issues=()
    
    # 基本安全检查
    check_working_tree_clean_remote "$worktree_path" || issues+=("工作区有未保存修改")
    check_staging_area_clean_remote "$worktree_path" || issues+=("暂存区有未提交内容")
    
    # 检查是否真的需要同步
    if ! check_sync_requirements_remote "$branch_name" "$target_branch" "$worktree_path"; then
        [[ "$skip_output" != "true" ]] && echo "ℹ️ 分支已是最新，无需同步"
        return 2  # 特殊返回码：无需同步
    fi
    
    # 返回结果
    if [[ ${#issues[@]} -eq 0 ]]; then
        [[ "$skip_output" != "true" ]] && echo "✅ 同步就绪性检查通过"
        return 0
    else
        if [[ "$skip_output" != "true" ]]; then
            echo "❌ 发现 ${#issues[@]} 个阻塞问题："
            for issue in "${issues[@]}"; do
                echo "  - $issue"
            done
        fi
        return 1
    fi
}
```

#### 第三层：全局状态分析（供status命令和概览使用）

```bash
# 🌍 完整项目状态分析（status命令核心）
analyze_project_status_global() {
    local target_identifier="${1:-}"    # Epic名称或Feature名称，空则全局
    local detail_level="${2:-summary}"  # summary|detailed|full
    local output_format="${3:-human}"   # human|json|csv
    
    local project_root
    project_root=$(find_project_root) || {
        echo "❌ 不在GPF项目中" >&2
        return 1
    }
    
    echo "🌍 项目状态分析 ($(date '+%Y-%m-%d %H:%M:%S'))"
    echo "📁 项目路径: $project_root"
    
    # 🔍 扫描所有GPF管理的分支
    local all_worktrees epic_branches feature_branches
    all_worktrees=$(list_all_worktrees "$project_root")
    epic_branches=()
    feature_branches=()
    
    while IFS= read -r worktree_info; do
        [[ -n "$worktree_info" ]] || continue
        local branch_name
        branch_name=$(echo "$worktree_info" | awk '{print $2}')
        
        if [[ "$branch_name" =~ -e$ ]]; then
            epic_branches+=("$branch_name")
        elif [[ "$branch_name" =~ -ef$ ]]; then
            feature_branches+=("$branch_name")
        fi
    done <<< "$all_worktrees"
    
    # 🎯 根据目标过滤显示范围
    local display_epics=() display_features=()
    if [[ -n "$target_identifier" ]]; then
        # 指定了目标，确定是Epic还是Feature
        local target_epic_branch target_feature_branch
        target_epic_branch=$(transform_input_to_epic_branch "$target_identifier" 2>/dev/null)
        
        if [[ -n "$target_epic_branch" ]] && printf '%s\n' "${epic_branches[@]}" | grep -q "^$target_epic_branch$"; then
            # 目标是Epic，显示该Epic及其所有Features
            display_epics=("$target_epic_branch")
            local epic_name
            epic_name=$(extract_epic_name_from_branch "$target_epic_branch")
            for feature_branch in "${feature_branches[@]}"; do
                if [[ "$feature_branch" =~ ^epic-${epic_name}- ]]; then
                    display_features+=("$feature_branch")
                fi
            done
        else
            # 尝试作为Feature处理
            for feature_branch in "${feature_branches[@]}"; do
                if [[ "$feature_branch" =~ $target_identifier ]]; then
                    display_features+=("$feature_branch")
                    # 同时显示对应的Epic
                    local parent_epic
                    parent_epic=$(extract_parent_epic_from_feature "$feature_branch")
                    if [[ -n "$parent_epic" ]]; then
                        display_epics+=("$parent_epic")
                    fi
                    break
                fi
            done
        fi
    else
        # 无目标，显示所有
        display_epics=("${epic_branches[@]}")
        display_features=("${feature_branches[@]}")
    fi
    
    # 📊 状态统计
    echo ""
    echo "📊 状态概览:"
    echo "  🎯 Epic分支: ${#display_epics[@]} 个"
    echo "  📦 Feature分支: ${#display_features[@]} 个"
    
    # 🎯 分析每个Epic的状态
    for epic_branch in "${display_epics[@]}"; do
        analyze_single_branch_comprehensive "$epic_branch" "$detail_level" "$output_format"
    done
    
    # 📦 分析每个Feature的状态
    for feature_branch in "${display_features[@]}"; do
        analyze_single_branch_comprehensive "$feature_branch" "$detail_level" "$output_format"
    done
}

# 📦 单分支综合状态分析（支持Epic和Feature）
analyze_single_branch_comprehensive() {
    local branch_name="$1"
    local detail_level="${2:-summary}"  # summary|detailed|full  
    local output_format="${3:-human}"   # human|json|csv
    
    local worktree_path
    worktree_path=$(find_worktree_by_branch "$branch_name")
    [[ -n "$worktree_path" ]] || {
        echo "❌ 找不到分支对应的worktree: $branch_name" >&2
        return 1
    }
    
    # 🏷️ 分支基本信息
    local branch_type epic_name feature_name target_branch
    branch_type=$(path_extract_suffix "$branch_name")
    
    if [[ "$branch_type" == "e" ]]; then
        epic_name=$(extract_epic_name_from_branch "$branch_name")
        target_branch="develop"
        echo ""
        echo "🎯 Epic: $epic_name ($branch_name)"
    elif [[ "$branch_type" == "ef" ]]; then
        feature_name=$(extract_feature_name_from_branch "$branch_name")
        epic_name=$(extract_parent_epic_from_feature "$branch_name")
        target_branch="epic-$epic_name-e"
        echo ""
        echo "📦 Feature: $feature_name (Epic: $epic_name)"
    else
        echo "❓ 未知分支类型: $branch_name"
        return 1
    fi
    
    echo "📍 路径: $worktree_path"
    
    # 🔍 快速状态检查
    local modified_count staged_count unpushed_count
    modified_count=$(git -C "$worktree_path" diff --name-only | wc -l | tr -d ' ')
    staged_count=$(git -C "$worktree_path" diff --cached --name-only | wc -l | tr -d ' ')
    
    if check_branch_pushed_remote "$branch_name" "$worktree_path"; then
        unpushed_count=$(git -C "$worktree_path" rev-list --count "origin/$branch_name..HEAD" 2>/dev/null || echo "0")
    else
        local total_commits
        total_commits=$(git -C "$worktree_path" rev-list --count HEAD 2>/dev/null || echo "0")
        unpushed_count="$total_commits"
    fi
    
    # 📊 状态指示器
    local status_indicators=()
    [[ "$modified_count" -eq 0 ]] && status_indicators+=("💾") || status_indicators+=("📝")
    [[ "$staged_count" -eq 0 ]] && status_indicators+=("✅") || status_indicators+=("📋")
    [[ "$unpushed_count" -eq 0 ]] && status_indicators+=("☁️") || status_indicators+=("📤")
    
    # 🔄 同步状态检查
    local sync_status="🟢"
    if check_sync_requirements_remote "$branch_name" "$target_branch" "$worktree_path"; then
        sync_status="🟡"
    fi
    status_indicators+=("$sync_status")
    
    echo "🏷️ 状态: $(IFS=' '; echo "${status_indicators[*]}")"
    
    # 📈 详细信息（根据detail_level显示）
    if [[ "$detail_level" != "summary" ]]; then
        echo "   修改文件: $modified_count | 暂存文件: $staged_count | 未推送: $unpushed_count"
        
        # 🔄 PR就绪性快速检查
        if check_pr_readiness_unified "$branch_name" "$worktree_path" "true" >/dev/null 2>&1; then
            echo "   PR状态: ✅ 可创建PR"
        else
            echo "   PR状态: ❌ 需要处理问题"
        fi
        
        # 🧹 清理安全等级
        if [[ "$detail_level" == "full" ]]; then
            local safety_result
            safety_result=$(check_clean_safety_unified "$branch_name" "$target_branch" "$worktree_path" "true")
            local safety_level
            safety_level=$(echo "$safety_result" | cut -d: -f1)
            case "$safety_level" in
                "safe") echo "   清理安全级别: 🟢 安全" ;;
                "warning") echo "   清理安全级别: 🟡 警告" ;;
                "dangerous") echo "   清理安全级别: 🔴 危险" ;;
            esac
        fi
    fi
}
```

### 🔧 命令集成接口（消除重复代码）

```bash
# ✅ 供其他命令直接调用的统一接口
# 这些方法专门设计为无目录切换，可安全地在其他命令中调用

# 原：pr_command_status_check() + clean_command_safety_check() + sync_command_readiness_check()
# 新：统一的状态检查模块接口
status_module_get_complete_status() {
    local branch_name="$1"
    local target_branch="$2"
    local purpose="${3:-status}"  # pr|clean|sync|status
    
    case "$purpose" in
        "pr")
            # PR就绪性检查
            check_pr_readiness_unified "$branch_name" "$target_branch" "false"
            ;;
        "clean")
            # 清理安全性检查
            local safety_result
            safety_result=$(check_clean_safety_unified "$branch_name" "$target_branch" "" "true")
            
            local safety_level
            safety_level=$(echo "$safety_result" | cut -d: -f1)
            
            case "$safety_level" in
                "safe") return 0 ;;
                "warning") return 1 ;;
                "dangerous") return 2 ;;
                *) return 3 ;;
            esac
            ;;
        "sync")
            # 同步就绪性检查
            check_sync_readiness_unified "$branch_name" "$target_branch"
            ;;
        "status"|*)
            # 完整状态显示
            get_complete_status_display "$branch_name" "$target_branch"
            ;;
    esac
}

# 原方法保持向后兼容（标记为废弃）
sync_command_readiness_check() {
    local branch_name="$1"
    local target_branch="$2"
    local worktree_path="${3:-}"
    
    # 调用统一的同步就绪性检查
    check_sync_readiness_unified "$branch_name" "$target_branch" "$worktree_path" "false"
}
```

## 🆕 10. github-check.sh - GitHub CLI 环境检查（通用组件）

### 核心功能
提供统一的GitHub CLI工具检查，供所有需要GitHub集成的命令使用。

### 通用检查方法

```bash
# 🔧 通用的GitHub CLI环境检查（供所有命令使用）
github_check_environment() {
    # 1. 检查gh工具安装
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI (gh) 未安装"
        echo "💡 解决方案:"
        echo "   macOS: brew install gh"
        echo "   Ubuntu: sudo apt install gh"
        echo "   Windows: winget install GitHub.CLI"
        echo "   或访问: https://cli.github.com/"
        return 1
    fi
    
    # 2. 检查GitHub认证状态
    if ! gh auth status &> /dev/null; then
        echo "❌ GitHub CLI 未认证"
        echo "💡 解决方案: 运行 gh auth login"
        echo "   选择 GitHub.com"
        echo "   选择 HTTPS 协议"
        echo "   按提示完成认证"
        return 1
    fi
    
    # 3. 检查当前仓库支持
    if ! gh repo view &> /dev/null; then
        echo "❌ 当前目录不是GitHub仓库或无权限访问"
        echo "💡 可能原因:"
        echo "   1. 不是Git仓库"
        echo "   2. 远程仓库不是GitHub"
        echo "   3. 认证账户无仓库权限"
        return 1
    fi
    
    # 4. 检查网络连接
    if ! gh api user &> /dev/null; then
        echo "❌ GitHub网络连接失败"
        echo "💡 可能原因:"
        echo "   1. 网络连接问题"
        echo "   2. GitHub服务不可用"
        echo "   3. 企业防火墙限制"
        return 1
    fi
    
    return 0
}

# 静默检查（供其他组件调用）
github_check_environment_silent() {
    command -v gh &> /dev/null && 
    gh auth status &> /dev/null && 
    gh repo view &> /dev/null && 
    gh api user &> /dev/null
}

# GitHub CLI版本兼容性检查
check_gh_version() {
    local version
    version=$(gh --version | head -1 | awk '{print $3}')
    echo "GitHub CLI版本: $version"
    
    # 检查最低版本要求（2.0.0+）
    if version_compare "$version" "2.0.0" "<"; then
        echo "⚠️ GitHub CLI版本较低，建议升级到 2.0.0+"
        echo "💡 升级命令: gh extension upgrade gh"
    fi
}
```

## 🆕 11. github-pr.sh - GitHub PR 状态检查和操作

### 核心功能
GitHub PR的状态查询、合并检查和创建操作，供pr、status、clean命令使用。

### PR状态查询方法

```bash
# 检查分支是否已有PR
github_pr_get_status() {
    local branch="$1"
    local target_branch="$2"
    
    # 调用通用环境检查
    if ! github_check_environment_silent; then
        return 1
    fi
    
    # 查找PR
    local pr_number
    pr_number=$(gh pr list --head "$branch" --base "$target_branch" --json number --jq '.[0].number' 2>/dev/null)
    
    if [[ -n "$pr_number" && "$pr_number" != "null" ]]; then
        echo "$pr_number"
        return 0
    else
        return 1
    fi
}

# 获取PR完整状态信息
github_pr_get_status() {
    local branch="$1"
    local target_branch="$2"
    
    local pr_number
    if ! pr_number=$(github_pr_get_status "$branch" "$target_branch"); then
        echo "no_pr"
        return 1
    fi
    
    # 获取PR详细状态
    local pr_info
    pr_info=$(gh pr view "$pr_number" --json state,reviewDecision,title,url,mergeable 2>/dev/null)
    
    if [[ -z "$pr_info" ]]; then
        echo "error"
        return 1
    fi
    
    echo "$pr_info"
    return 0
}

# 检查PR是否已安全合并（供clean命令使用）
github_pr_get_status() {
    local branch="$1"
    local target_branch="$2"
    
    local pr_info
    pr_info=$(github_pr_get_status "$branch" "$target_branch")
    
    if [[ "$pr_info" == "no_pr" ]]; then
        echo "no_pr_found"
        return 1
    fi
    
    if [[ "$pr_info" == "error" ]]; then
        echo "check_failed"
        return 1
    fi
    
    local state
    state=$(echo "$pr_info" | jq -r '.state')
    
    case "$state" in
        "MERGED")
            echo "safely_merged"
            return 0
            ;;
        "OPEN")
            echo "still_open"
            return 1
            ;;
        "CLOSED")
            echo "closed_not_merged"
            return 1
            ;;
        *)
            echo "unknown_state"
            return 1
            ;;
    esac
}

# 创建PR（供gpf pr命令使用）
create_github_pr() {
    local source_branch="$1"
    local target_branch="$2"
    local issue_numbers="$3"
    
    # 检查环境
    if ! github_check_environment; then
        return 1
    fi
    
    # 构建PR创建命令
    local pr_args=("--base" "$target_branch" "--head" "$source_branch")
    
    # 添加issue关联
    if [[ -n "$issue_numbers" ]]; then
        local body=""
        IFS=',' read -ra issue_array <<< "$issue_numbers"
        for issue in "${issue_array[@]}"; do
            issue=$(echo "$issue" | tr -d ' ')
            if [[ "$issue" =~ ^[0-9]+$ ]]; then
                if [[ -n "$body" ]]; then
                    body="$body, "
                fi
                body="${body}Closes #$issue"
            fi
        done
        
        if [[ -n "$body" ]]; then
            pr_args+=("--body" "$body")
        fi
    fi
    
    # 创建PR
    echo "🚀 创建GitHub PR: $source_branch → $target_branch"
    if gh pr create "${pr_args[@]}"; then
        echo "✅ PR创建成功"
        return 0
    else
        echo "❌ PR创建失败"
        return 1
    fi
}
```

### Status命令集成方法

```bash
# 供status命令调用的PR状态显示
status_show_github_pr_info() {
    local branch="$1"
    local target_branch="$2"
    local show_pr_only="${3:-false}"
    
    echo "🔗 GitHub PR状态:"
    
    # GitHub CLI环境检查
    if ! github_check_environment_silent; then
        echo "   ⚠️ 无法检查（GitHub CLI未配置）"
        echo "   💡 配置方法: gh auth login"
        return 1
    fi
    
    # 获取PR状态
    local pr_info
    pr_info=$(github_pr_get_status "$branch" "$target_branch")
    
    if [[ "$pr_info" == "no_pr" ]]; then
        echo "   📋 PR状态: 未创建"
        echo "   💡 建议: 运行 gpf pr 创建PR"
        if [[ "$show_pr_only" != "true" ]]; then
            echo ""
            echo "🎯 操作权限:"
            echo "   ✅ gpf pr: 可以创建新PR"
        fi
        return 0
    fi
    
    if [[ "$pr_info" == "error" ]]; then
        echo "   ❌ 检查失败（网络或权限问题）"
        return 1
    fi
    
    # 解析PR详细信息
    local state review_decision title url
    state=$(echo "$pr_info" | jq -r '.state')
    review_decision=$(echo "$pr_info" | jq -r '.reviewDecision // "null"')
    title=$(echo "$pr_info" | jq -r '.title')
    url=$(echo "$pr_info" | jq -r '.url')
    
    # 获取PR号码
    local pr_number
    pr_number=$(github_pr_get_status "$branch" "$target_branch")
    
    echo "   📋 PR #$pr_number: $title"
    echo "   🔗 链接: $url"
    
    # 显示详细状态和操作权限
    case "$state" in
        "OPEN")
            case "$review_decision" in
                "APPROVED")
                    echo "   👥 审核状态: ✅ 已审核通过"
                    echo "   🎯 下一步: 等待合并"
                    [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: 已有PR存在 | ⚠️ gpf clean: 等待PR合并"
                    ;;
                "REVIEW_REQUIRED"|"null")
                    echo "   👥 审核状态: ⏳ 等待审核"
                    echo "   🎯 下一步: 等待代码审核"
                    [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: 已有PR存在 | ❌ gpf clean: 等待审核完成"
                    ;;
                "CHANGES_REQUESTED")
                    echo "   👥 审核状态: 🔄 需要修改"
                    echo "   🎯 下一步: 处理审核意见"
                    [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: 已有PR存在 | ❌ gpf clean: 需要处理审核意见"
                    ;;
            esac
            ;;
        "MERGED")
            echo "   ✅ 状态: 已合并"
            echo "   🎯 下一步: 可以清理分支"
            [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: 分支已合并 | ✅ gpf clean: 可以安全清理"
            ;;
        "CLOSED")
            echo "   ❌ 状态: 已关闭（未合并）"
            echo "   ⚠️ 代码未合并到目标分支"
            [[ "$show_pr_only" != "true" ]] && echo "   🎯 操作权限: ❌ gpf pr: PR已关闭 | ⚠️ gpf clean: 需要确认是否保留代码"
            ;;
    esac
}
```

## 🆕 12. issue-handler.sh - Issue 关联处理

### 核心功能
处理PR与GitHub issue的关联，确保遵循最佳实践。

### Issue关联方法

```bash
# Issue关联检查和处理（供gpf pr命令使用）
handle_issue_association() {
    local branch="$1"
    local cmd_line_issues="$2"  # 来自 --issue 参数
    
    # 1. 命令参数优先
    if [[ -n "$cmd_line_issues" ]]; then
        if validate_issue_numbers "$cmd_line_issues"; then
            echo "🔗 使用命令行指定的issue: $cmd_line_issues"
            echo "$cmd_line_issues"
            return 0
        else
            echo "❌ Issue号格式错误: $cmd_line_issues"
            echo "💡 正确格式: --issue 123 或 --issue 123,456"
            return 1
        fi
    fi
    
    # 2. 从分支名自动解析
    local auto_issue
    if auto_issue=$(extract_issue_from_branch_name "$branch"); then
        echo "🔗 从分支名检测到issue: #$auto_issue"
        echo "$auto_issue"
        return 0
    fi
    
    # 3. 交互式输入（AI友好设计）
    if is_non_interactive; then
        echo "❌ 非交互式环境中必须通过 --issue 参数指定issue"
        echo "💡 示例: gpf pr --issue 123,456"
        return 1
    fi
    
    echo "⚠️ PR最佳实践要求关联GitHub issue"
    echo "请输入相关的issue编号（多个用逗号分隔）："
    read -r user_issues
    
    if [[ -z "$user_issues" ]]; then
        echo "❌ 必须关联issue才能创建PR"
        echo "💡 或使用: gpf pr --issue <numbers>"
        return 1
    fi
    
    if validate_issue_numbers "$user_issues"; then
        echo "$user_issues"
        return 0
    else
        echo "❌ Issue号格式错误，请重新输入"
        return 1
    fi
}

# 从分支名解析issue号
extract_issue_from_branch_name() {
    local branch="$1"
    
    # 匹配格式: epic-auth-123-e 或 epic-auth-login-456-ef
    if [[ "$branch" =~ -([0-9]+)-(e|ef)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# 验证issue号码格式
validate_issue_numbers() {
    local issues="$1"
    
    # 移除所有空格
    issues=$(echo "$issues" | tr -d ' ')
    
    # 检查是否为空
    if [[ -z "$issues" ]]; then
        return 1
    fi
    
    # 分割并验证每个issue号
    IFS=',' read -ra issue_array <<< "$issues"
    for issue in "${issue_array[@]}"; do
        if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
            echo "❌ 无效的issue号: $issue"
            return 1
        fi
    done
    
    return 0
}

# 检查issue是否存在（可选功能）
verify_issues_exist() {
    local issues="$1"
    
    if ! github_check_environment_silent; then
        echo "⚠️ 无法验证issue存在性（GitHub CLI不可用）"
        return 0  # 不阻断流程
    fi
    
    IFS=',' read -ra issue_array <<< "$issues"
    for issue in "${issue_array[@]}"; do
        issue=$(echo "$issue" | tr -d ' ')
        if ! gh issue view "$issue" >/dev/null 2>&1; then
            echo "⚠️ Issue #$issue 可能不存在或无权限访问"
            echo "是否继续？(y/N)"
            read -r confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || return 1
        fi
    done
    
    return 0
}
```

