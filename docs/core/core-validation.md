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