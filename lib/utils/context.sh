#!/usr/bin/env bash

# Git PR Flow - 上下文推导引擎
# 基于 Git 分支名、目录结构、worktree 信息推导配置，替代 YAML 文件依赖

# 引入依赖 (如果文件存在)
[[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]] && source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ -f "$(dirname "${BASH_SOURCE[0]}")/git.sh" ]] && source "$(dirname "${BASH_SOURCE[0]}")/git.sh"

# ============================================================================
# Epic 上下文推导
# ============================================================================

# 从当前位置推导 Epic 上下文信息
detect_epic_context() {
    local current_dir=$(pwd)
    local git_branch=$(git branch --show-current 2>/dev/null)
    local epic_name=""
    local epic_branch=""
    local worktree_path=""
    
    # 方法1: 从目录路径推导
    if [[ "$current_dir" == */.worktrees/epic--* && "$current_dir" != *--*--* ]]; then
        # Epic worktree 格式: epic--xxx (不包含第二个 --)
        epic_name=$(echo "$current_dir" | sed 's|.*/epic--||')
        epic_branch="epic/$epic_name"
        worktree_path=".worktrees/epic--$epic_name"
        
        # 输出结果
        echo "epic_name:$epic_name"
        echo "epic_branch:$epic_branch"
        echo "worktree_path:$worktree_path"
        echo "branch_type:epic"
        echo "source:directory_path"
        return 0
    fi
    
    # 方法2: 从 Git 分支名推导
    if [[ "$git_branch" =~ ^epic/(.+)$ ]]; then
        epic_name="${BASH_REMATCH[1]}"
        epic_branch="epic/$epic_name"
        worktree_path=".worktrees/epic--$epic_name"
        
        # 验证 worktree 是否存在
        local git_root
        git_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
        local full_worktree_path="$git_root/$worktree_path"
        
        if [[ -d "$full_worktree_path" ]]; then
            echo "epic_name:$epic_name"
            echo "epic_branch:$epic_branch"
            echo "worktree_path:$worktree_path"
            echo "branch_type:epic"
            echo "source:branch_name"
            return 0
        fi
    fi
    
    # 方法3: 从父目录中的 worktree 推导
    local parent_dir="$current_dir"
    while [[ "$parent_dir" != "/" ]]; do
        if [[ "$parent_dir" =~ \.worktrees/epic--([^/]+) ]]; then
            epic_name="${BASH_REMATCH[1]}"
            epic_branch="epic/$epic_name"
            worktree_path=".worktrees/epic--$epic_name"
            
            echo "epic_name:$epic_name"
            echo "epic_branch:$epic_branch"
            echo "worktree_path:$worktree_path"
            echo "branch_type:epic"
            echo "source:parent_directory"
            return 0
        fi
        parent_dir=$(dirname "$parent_dir")
    done
    
    return 1
}

# ============================================================================
# Feature 上下文推导
# ============================================================================

# 从当前位置推导 Feature 上下文信息
detect_feature_context() {
    local current_dir=$(pwd)
    local git_branch=$(git branch --show-current 2>/dev/null)
    local epic_name=""
    local feature_name=""
    local epic_branch=""
    local feature_branch=""
    local worktree_path=""
    
    # 方法1: 从目录路径推导 (epic--name--feature格式)
    if [[ "$current_dir" =~ \.worktrees/epic--.*--.*$ ]]; then
        # 使用 sed 解析复杂的目录名
        local parsed_parts
        parsed_parts=$(echo "$current_dir" | sed 's|.*/epic--||' | sed 's|--| |g')
        read -r epic_name feature_part <<< "$parsed_parts"
        
        if [[ -n "$epic_name" ]] && [[ -n "$feature_part" ]]; then
            feature_name="$epic_name/$feature_part"
            epic_branch="epic/$epic_name"
            feature_branch="$feature_name"
            worktree_path=".worktrees/epic--$epic_name--$feature_part"
            
            # 输出结果
            echo "epic_name:$epic_name"
            echo "feature_name:$feature_name"
            echo "epic_branch:$epic_branch"
            echo "feature_branch:$feature_branch"
            echo "worktree_path:$worktree_path"
            echo "branch_type:feature"
            echo "source:directory_path"
            return 0
        fi
    fi
    
    # 方法2: 从 Git 分支名推导 (epic/feature格式)
    if [[ "$git_branch" =~ ^([^/]+)/(.+)$ ]]; then
        epic_name="${BASH_REMATCH[1]}"
        local feature_part="${BASH_REMATCH[2]}"
        
        # 排除 epic/xxx 格式的分支
        if [[ "$epic_name" != "epic" ]]; then
            feature_name="$epic_name/$feature_part"
            epic_branch="epic/$epic_name"
            feature_branch="$git_branch"
            worktree_path=".worktrees/epic--$epic_name--$feature_part"
            
            # 验证 worktree 是否存在
            local git_root
            git_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
            local full_worktree_path="$git_root/$worktree_path"
            
            if [[ -d "$full_worktree_path" ]]; then
                echo "epic_name:$epic_name"
                echo "feature_name:$feature_name"
                echo "epic_branch:$epic_branch"
                echo "feature_branch:$feature_branch"
                echo "worktree_path:$worktree_path"
                echo "branch_type:feature"
                echo "source:branch_name"
                return 0
            fi
        fi
    fi
    
    return 1
}

# ============================================================================
# 智能上下文检测 (统一入口)
# ============================================================================

# 智能检测当前上下文 (Epic 或 Feature)
detect_current_context() {
    # 先尝试检测 Feature 上下文
    if detect_feature_context; then
        return 0
    fi
    
    # 再尝试检测 Epic 上下文
    if detect_epic_context; then
        return 0
    fi
    
    return 1
}

# ============================================================================
# 基础分支推导
# ============================================================================

# 智能检测项目默认分支
detect_base_branch() {
    local context_type="${1:-project}"  # project, epic, feature
    local epic_name="$2"
    
    case "$context_type" in
        "project")
            # 项目级别的基础分支检测
            # 优先级：develop > main > master
            for branch in develop main master; do
                if git show-ref --verify --quiet "refs/heads/$branch"; then
                    echo "$branch"
                    return 0
                fi
            done
            
            # 如果都不存在，返回当前分支
            git branch --show-current 2>/dev/null || echo "main"
            ;;
            
        "epic")
            # Epic 的基础分支是项目默认分支
            detect_base_branch "project"
            ;;
            
        "feature")
            # Feature 的基础分支是对应的 Epic 分支
            if [[ -n "$epic_name" ]]; then
                echo "epic/$epic_name"
            else
                # 如果没有提供 epic_name，尝试从上下文推导
                local context_info
                context_info=$(detect_current_context 2>/dev/null)
                if [[ $? -eq 0 ]]; then
                    local epic_branch
                    epic_branch=$(echo "$context_info" | grep "^epic_branch:" | cut -d: -f2)
                    if [[ -n "$epic_branch" ]]; then
                        echo "$epic_branch"
                        return 0
                    fi
                fi
                
                # 降级到项目默认分支
                detect_base_branch "project"
            fi
            ;;
            
        *)
            log_error "无效的上下文类型: $context_type"
            return 1
            ;;
    esac
}

# ============================================================================
# 辅助函数
# ============================================================================

# 从上下文信息中提取特定字段
get_context_field() {
    local field="$1"
    local context_info="${2:-}"
    
    if [[ -z "$context_info" ]]; then
        context_info=$(detect_current_context 2>/dev/null) || return 1
    fi
    
    echo "$context_info" | grep "^$field:" | cut -d: -f2
}

# 获取当前 Epic 名称
get_current_epic_name() {
    get_context_field "epic_name"
}

# 获取当前 Feature 名称
get_current_feature_name() {
    get_context_field "feature_name"
}

# 获取当前分支类型
get_current_branch_type() {
    get_context_field "branch_type"
}

# 获取当前 worktree 路径
get_current_worktree_path() {
    get_context_field "worktree_path"
}

# ============================================================================
# 配置信息生成 (替代 YAML 读取)
# ============================================================================

# 生成 Epic 配置信息 (替代 config_epic_get)
generate_epic_config() {
    local epic_name="$1"
    local context_info
    
    if [[ -n "$epic_name" ]]; then
        # 如果提供了 epic_name，基于名称生成配置
        local base_branch
        base_branch=$(detect_base_branch "epic")
        
        cat << EOF
epic_name:$epic_name
epic_branch:epic/$epic_name
base_branch:$base_branch
worktree_path:.worktrees/epic--$epic_name
branch_type:epic
workflow_type:gitflow
pr_strategy:progressive
auto_switch_branch:true
auto_sync:false
auto_cleanup:false
EOF
    else
        # 从当前上下文生成配置
        context_info=$(detect_epic_context) || return 1
        local epic_name_detected
        epic_name_detected=$(echo "$context_info" | grep "^epic_name:" | cut -d: -f2)
        
        if [[ -n "$epic_name_detected" ]]; then
            generate_epic_config "$epic_name_detected"
        else
            return 1
        fi
    fi
}

# 生成 Feature 配置信息 (替代 config_feature_get)
generate_feature_config() {
    local feature_name="$1"
    local epic_name="$2"
    local context_info
    
    if [[ -n "$feature_name" ]] && [[ -n "$epic_name" ]]; then
        # 如果提供了完整信息，基于参数生成配置
        local base_branch="epic/$epic_name"
        local feature_part="${feature_name#$epic_name/}"
        
        cat << EOF
feature_name:$feature_name
epic_name:$epic_name
epic_branch:epic/$epic_name
feature_branch:$feature_name
base_branch:$base_branch
worktree_path:.worktrees/epic--$epic_name--$feature_part
branch_type:feature
workflow_type:gitflow
pr_strategy:feature_to_epic
auto_switch_branch:true
auto_sync:false
auto_cleanup:false
EOF
    else
        # 从当前上下文生成配置
        context_info=$(detect_feature_context) || return 1
        
        # 提取字段并生成配置
        local epic_name_detected feature_name_detected epic_branch_detected feature_branch_detected worktree_path_detected
        epic_name_detected=$(echo "$context_info" | grep "^epic_name:" | cut -d: -f2)
        feature_name_detected=$(echo "$context_info" | grep "^feature_name:" | cut -d: -f2)
        epic_branch_detected=$(echo "$context_info" | grep "^epic_branch:" | cut -d: -f2)
        feature_branch_detected=$(echo "$context_info" | grep "^feature_branch:" | cut -d: -f2)
        worktree_path_detected=$(echo "$context_info" | grep "^worktree_path:" | cut -d: -f2)
        
        cat << EOF
feature_name:$feature_name_detected
epic_name:$epic_name_detected
epic_branch:$epic_branch_detected
feature_branch:$feature_branch_detected
base_branch:$epic_branch_detected
worktree_path:$worktree_path_detected
branch_type:feature
workflow_type:gitflow
pr_strategy:feature_to_epic
auto_switch_branch:true
auto_sync:false
auto_cleanup:false
EOF
    fi
}

# ============================================================================
# 兼容性函数 (替代现有 YAML 读取函数)
# ============================================================================

# 替代 detect_current_epic 函数
context_detect_current_epic() {
    get_current_epic_name
}

# 替代 config_epic_exists 函数
context_epic_exists() {
    local epic_name="$1"
    
    if [[ -z "$epic_name" ]]; then
        epic_name=$(get_current_epic_name)
    fi
    
    if [[ -z "$epic_name" ]]; then
        return 1
    fi
    
    # 检查 Epic 分支是否存在
    git show-ref --verify --quiet "refs/heads/epic/$epic_name"
}

# 替代 config_epic_get 函数
context_epic_get() {
    local key="$1"
    local epic_name="$2"
    
    local config_info
    config_info=$(generate_epic_config "$epic_name") || return 1
    
    echo "$config_info" | grep "^$key:" | cut -d: -f2
}

# 替代 config_feature_get 函数
context_feature_get() {
    local key="$1"
    local default="$2"
    local feature_path="$3"
    
    local config_info
    config_info=$(generate_feature_config) || {
        echo "$default"
        return 0
    }
    
    local value
    value=$(echo "$config_info" | grep "^$key:" | cut -d: -f2)
    
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# ============================================================================
# 调试和测试函数
# ============================================================================

# 显示当前上下文信息 (调试用)
debug_show_context() {
    echo "=== Git PR Flow 上下文信息 ==="
    echo
    
    echo "📂 当前目录: $(pwd)"
    echo "🌿 当前分支: $(git branch --show-current 2>/dev/null || echo 'N/A')"
    echo
    
    echo "🔍 上下文检测结果:"
    local context_info
    context_info=$(detect_current_context 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        echo "$context_info" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        echo "  ❌ 未检测到有效的 Epic/Feature 上下文"
    fi
    
    echo
    echo "🎯 推荐的基础分支:"
    echo "  项目级: $(detect_base_branch "project")"
    echo "  Epic级: $(detect_base_branch "epic")"
    echo "  Feature级: $(detect_base_branch "feature")"
    
    echo
    echo "==========================="
}

# 测试所有上下文推导函数
test_context_detection() {
    echo "🧪 测试上下文推导引擎..."
    echo
    
    echo "1. 测试 Epic 上下文推导:"
    detect_epic_context && echo "  ✅ Epic 上下文检测成功" || echo "  ❌ Epic 上下文检测失败"
    
    echo
    echo "2. 测试 Feature 上下文推导:"
    detect_feature_context && echo "  ✅ Feature 上下文检测成功" || echo "  ❌ Feature 上下文检测失败"
    
    echo
    echo "3. 测试基础分支推导:"
    local project_base epic_base feature_base
    project_base=$(detect_base_branch "project")
    epic_base=$(detect_base_branch "epic")
    feature_base=$(detect_base_branch "feature")
    
    echo "  项目基础分支: $project_base"
    echo "  Epic基础分支: $epic_base" 
    echo "  Feature基础分支: $feature_base"
    
    echo
    echo "4. 测试配置生成:"
    echo "  Epic 配置生成:"
    generate_epic_config 2>/dev/null && echo "    ✅ 成功" || echo "    ❌ 失败"
    
    echo "  Feature 配置生成:"
    generate_feature_config 2>/dev/null && echo "    ✅ 成功" || echo "    ❌ 失败"
    
    echo
    echo "🎉 测试完成"
}