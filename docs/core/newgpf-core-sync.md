# NewGPF 核心公共组件设计 - 同步管理

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
    feature_branches=$(list_all_worktrees | grep "^epic-$epic_name-e-.*-ef:")
    
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
    local source_branch="$1"    # epic-auth-e-login-ef
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