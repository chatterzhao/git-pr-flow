# GPF 核心公共组件设计 - 工作流方法

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
                echo "epic-$epic_environment-e-$clean_name-ef"
            else
                # 不包含epic前缀：login
                echo "epic-$epic_environment-e-$clean_name-ef"
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
    
    # epic-auth-e-login-ef -> login
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