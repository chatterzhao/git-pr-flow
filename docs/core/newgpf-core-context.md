# NewGPF 核心公共组件设计 - 环境检测

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
    git_branch: "epic-auth-e" | "epic-auth-e-login-ef" | "develop"  # 分支名
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
