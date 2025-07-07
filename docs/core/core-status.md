# GPF 核心公共组件设计 - 状态检查

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

# 🆕 冲突状态检查（远程）
check_merge_conflict_remote() {
    local worktree_path="$1"
    [[ -d "$worktree_path" ]] || return 1
    
    # 检查是否存在冲突标记文件
    [[ -f "$worktree_path/.git/MERGE_HEAD" ]] || \
    [[ -f "$worktree_path/.git/CHERRY_PICK_HEAD" ]] || \
    [[ -f "$worktree_path/.git/REBASE_HEAD" ]]
}

# 🆕 基础分支新鲜度检查（for start命令）
check_base_branch_freshness_remote() {
    local base_branch="$1"
    local project_root="$2"
    
    # 检查本地base分支是否落后远程
    local behind_count
    behind_count=$(git -C "$project_root" rev-list --count "$base_branch..origin/$base_branch" 2>/dev/null || echo "0")
    [[ "$behind_count" -eq 0 ]]
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