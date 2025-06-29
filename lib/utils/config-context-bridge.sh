#!/usr/bin/env bash

# Git PR Flow - 配置系统桥接
# 提供向后兼容的配置读取接口，使用上下文推导替代 YAML 读取

# 引入新的系统
[[ -f "$(dirname "${BASH_SOURCE[0]}")/context.sh" ]] && source "$(dirname "${BASH_SOURCE[0]}")/context.sh"
[[ -f "$(dirname "${BASH_SOURCE[0]}")/project-config.sh" ]] && source "$(dirname "${BASH_SOURCE[0]}")/project-config.sh"

# ============================================================================
# 向后兼容的配置读取函数 (替代 config.sh 中的函数)
# ============================================================================

# 替代 detect_current_epic 函数
detect_current_epic() {
    context_detect_current_epic
}

# 替代 config_epic_exists 函数
config_epic_exists() {
    local epic_name="$1"
    context_epic_exists "$epic_name"
}

# 替代 config_epic_validate 函数
config_epic_validate() {
    local epic_name="$1"
    
    # 新的验证逻辑：检查Epic分支和基本上下文信息
    if [[ -z "$epic_name" ]]; then
        epic_name=$(detect_current_epic)
    fi
    
    if [[ -z "$epic_name" ]]; then
        return 1
    fi
    
    # 检查Epic分支是否存在
    if ! git show-ref --verify --quiet "refs/heads/epic/$epic_name" 2>/dev/null; then
        return 1
    fi
    
    # 检查上下文是否可以正确推导
    local context_info
    context_info=$(detect_current_context 2>/dev/null)
    if [[ -z "$context_info" ]]; then
        return 1
    fi
    
    return 0
}

# 替代 config_epic_get 函数
config_epic_get() {
    local key="$1"
    local epic_name="$2"
    
    # 优先级：上下文推导 > 项目配置 > 默认值
    local value=""
    
    # 尝试从上下文推导获取
    value=$(context_epic_get "$key" "$epic_name" 2>/dev/null)
    if [[ -n "$value" ]] && [[ "$value" != "N/A" ]]; then
        echo "$value"
        return 0
    fi
    
    # 尝试从项目配置获取
    case "$key" in
        "base_branch")
            get_project_base_branch
            ;;
        "worktree_dir")
            get_worktree_dir
            ;;
        "workflow_type")
            get_workflow_type
            ;;
        "auto_switch_branch")
            read_user_preference "auto_switch_branch" "true"
            ;;
        "auto_sync")
            read_user_preference "auto_sync" "false"
            ;;
        "auto_cleanup")
            read_user_preference "auto_cleanup" "false"
            ;;
        *)
            # 未知字段，尝试上下文推导
            context_epic_get "$key" "$epic_name" 2>/dev/null || echo ""
            ;;
    esac
}

# 替代 config_feature_get 函数
config_feature_get() {
    local key="$1"
    local default="$2"
    local feature_path="$3"
    
    # 使用上下文推导获取功能分支配置
    context_feature_get "$key" "$default" "$feature_path"
}

# 替代 config_epic_validate 函数
config_epic_validate() {
    local epic_name="$1"
    
    # 使用上下文推导验证Epic
    if [[ -z "$epic_name" ]]; then
        epic_name=$(context_detect_current_epic)
    fi
    
    if [[ -z "$epic_name" ]]; then
        echo "❌ 无法检测Epic名称"
        return 1
    fi
    
    # 检查Epic分支是否存在
    if ! git show-ref --verify --quiet "refs/heads/epic/$epic_name"; then
        echo "❌ Epic分支不存在: epic/$epic_name"
        return 1
    fi
    
    # 检查项目配置
    if gpf_project_config_exists; then
        echo "✅ Epic配置验证通过 (使用上下文推导)"
    else
        echo "⚠️  未找到项目配置，建议运行 'gpf init' 初始化"
    fi
    
    return 0
}

# 替代 config_epic_show 函数
config_epic_show() {
    local epic_name="$1"
    
    if [[ -z "$epic_name" ]]; then
        epic_name=$(context_detect_current_epic)
    fi
    
    if [[ -z "$epic_name" ]]; then
        echo "❌ 无法检测Epic名称"
        return 1
    fi
    
    echo "📊 Epic配置信息 (上下文推导)"
    echo "=============================="
    
    local epic_config
    epic_config=$(generate_epic_config "$epic_name") || {
        echo "❌ 无法生成Epic配置"
        return 1
    }
    
    echo "$epic_config" | while IFS=: read -r key value; do
        case "$key" in
            "epic_name") echo "  Epic名称: $value" ;;
            "epic_branch") echo "  Epic分支: $value" ;;
            "base_branch") echo "  基础分支: $value" ;;
            "worktree_path") echo "  工作树路径: $value" ;;
            "workflow_type") echo "  工作流类型: $value" ;;
            "pr_strategy") echo "  PR策略: $value" ;;
        esac
    done
    
    echo "  配置来源: 上下文推导"
    echo
}

# ============================================================================
# 增强的配置管理函数
# ============================================================================

# 智能配置获取 (统一入口)
get_config() {
    local key="$1"
    local context_type="$2"  # epic, feature, project
    local default="$3"
    
    case "$context_type" in
        "epic")
            config_epic_get "$key"
            ;;
        "feature")
            config_feature_get "$key" "$default"
            ;;
        "project")
            read_project_config "$key" "$default"
            ;;
        *)
            # 自动检测上下文
            local current_context
            current_context=$(detect_current_context 2>/dev/null)
            if [[ $? -eq 0 ]]; then
                local branch_type
                branch_type=$(echo "$current_context" | grep "^branch_type:" | cut -d: -f2)
                get_config "$key" "$branch_type" "$default"
            else
                # 降级到项目配置
                read_project_config "$key" "$default"
            fi
            ;;
    esac
}

# 显示完整配置状态
show_config_status() {
    echo "🔧 Git PR Flow 配置状态"
    echo "======================="
    echo
    
    # 项目配置状态
    echo "📁 项目配置:"
    if gpf_project_config_exists; then
        echo "  ✅ 项目配置已初始化"
        echo "  📝 配置文件: $GPF_MAIN_CONFIG"
        echo "  🎯 基础分支: $(get_project_base_branch)"
        echo "  🏗️  工作流: $(get_workflow_type)"
    else
        echo "  ❌ 项目配置未初始化"
        echo "  💡 运行 'gpf init' 来初始化配置"
    fi
    echo
    
    # 当前上下文状态
    echo "📍 当前上下文:"
    local context_info
    context_info=$(detect_current_context 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "  ✅ 检测到有效上下文"
        local branch_type epic_name feature_name
        branch_type=$(echo "$context_info" | grep "^branch_type:" | cut -d: -f2)
        epic_name=$(echo "$context_info" | grep "^epic_name:" | cut -d: -f2)
        feature_name=$(echo "$context_info" | grep "^feature_name:" | cut -d: -f2)
        
        echo "  🏷️  类型: $branch_type"
        echo "  🎯 Epic: $epic_name"
        if [[ "$branch_type" == "feature" ]]; then
            echo "  ⚡ Feature: $feature_name"
        fi
    else
        echo "  ⚠️  未检测到Epic/Feature上下文"
        echo "  📂 当前目录: $(pwd)"
        echo "  🌿 当前分支: $(git branch --show-current 2>/dev/null || echo 'N/A')"
    fi
    echo
    
    # 配置获取测试
    echo "🧪 配置获取测试:"
    echo "  auto_switch_branch: $(get_config "auto_switch_branch" "" "default")"
    echo "  workflow_type: $(get_config "workflow_type" "" "default")"
    echo "  base_branch: $(get_config "base_branch" "" "default")"
    echo
}

# ============================================================================
# 迁移和兼容性函数
# ============================================================================

# 检查是否需要迁移
need_migration() {
    # 检查是否存在旧的YAML配置文件
    local yaml_files
    yaml_files=$(find .worktrees -name ".git-pr-flow.yaml" 2>/dev/null)
    
    if [[ -n "$yaml_files" ]] && ! gpf_project_config_exists; then
        return 0  # 需要迁移
    fi
    
    return 1  # 不需要迁移
}

# 自动迁移提示
suggest_migration() {
    if need_migration; then
        echo "💡 检测到旧的YAML配置文件，建议迁移到新的配置系统："
        echo "   1. 运行 'gpf migrate' 自动迁移配置"
        echo "   2. 或手动运行 'gpf init' 初始化新配置系统"
        echo
    fi
}

# 向后兼容检查
check_compatibility() {
    local function_name="$1"
    
    case "$function_name" in
        "config_epic_get"|"config_feature_get"|"detect_current_epic")
            # 这些函数已被替换，发出兼容性警告
            echo "⚠️  函数 $function_name 已使用上下文推导重新实现" >&2
            ;;
    esac
}

# ============================================================================
# 调试和诊断函数
# ============================================================================

# 配置系统诊断
diagnose_config_system() {
    echo "🔍 Git PR Flow 配置系统诊断"
    echo "=========================="
    echo
    
    # 1. 检查文件系统
    echo "📁 文件系统检查:"
    echo "  项目根目录: $(git rev-parse --show-toplevel 2>/dev/null || echo 'N/A')"
    echo "  当前工作目录: $(pwd)"
    echo "  .gpf 目录: $(if [[ -d ".gpf" ]]; then echo "✅ 存在"; else echo "❌ 不存在"; fi)"
    echo "  .worktrees 目录: $(if [[ -d ".worktrees" ]]; then echo "✅ 存在"; else echo "❌ 不存在"; fi)"
    echo
    
    # 2. 检查Git状态
    echo "🌿 Git 状态检查:"
    echo "  当前分支: $(git branch --show-current 2>/dev/null || echo 'N/A')"
    echo "  远程仓库: $(git remote get-url origin 2>/dev/null || echo 'N/A')"
    echo "  Worktree 列表:"
    git worktree list 2>/dev/null | while read -r line; do
        echo "    $line"
    done
    echo
    
    # 3. 上下文推导测试
    echo "🎯 上下文推导测试:"
    debug_show_context
    echo
    
    # 4. 配置文件检查
    echo "📝 配置文件检查:"
    for config_file in "$GPF_MAIN_CONFIG" "$GPF_USER_PREFERENCES" "$GPF_EPICS_INDEX"; do
        if [[ -f "$config_file" ]]; then
            echo "  ✅ $config_file"
            echo "     大小: $(stat -f%z "$config_file" 2>/dev/null || stat -c%s "$config_file" 2>/dev/null || echo 'N/A') bytes"
            echo "     修改时间: $(stat -f%Sm "$config_file" 2>/dev/null || stat -c%y "$config_file" 2>/dev/null || echo 'N/A')"
        else
            echo "  ❌ $config_file (不存在)"
        fi
    done
    echo
    
    # 5. 旧YAML文件检查
    echo "📋 旧YAML配置文件:"
    local yaml_count=0
    find .worktrees -name ".git-pr-flow.yaml" 2>/dev/null | while read -r yaml_file; do
        echo "  📄 $yaml_file"
        ((yaml_count++))
    done
    
    if [[ $yaml_count -eq 0 ]]; then
        echo "  ✅ 没有发现旧的YAML配置文件"
    else
        echo "  ⚠️  发现 $yaml_count 个旧的YAML配置文件，建议迁移"
    fi
    echo
    
    echo "🎉 诊断完成"
}