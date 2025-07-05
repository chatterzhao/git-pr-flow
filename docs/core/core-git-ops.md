# GPF 核心公共组件设计 - Git操作

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