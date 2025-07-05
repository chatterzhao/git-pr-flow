#!/bin/bash
# GPF Core - Roadmap Composite Methods
# Roadmap管理组合方法 - 组合原子方法实现Epic roadmap管理工作流

set -euo pipefail

# 导入依赖的原子方法
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/roadmap-template.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/epic-validation.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/path-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/environment-atomic.sh"

# Epic Roadmap初始化
# 参数：(epic_name, base_branch, project_root)
# 返回：0（成功）或1（失败），创建结果输出到stdout
roadmap_initialize_epic() {
    local epic_name="$1"
    local base_branch="${2:-develop}"
    local project_root="${3:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 验证Epic名称格式
    if ! validate_name_format "$epic_name"; then
        echo "❌ 错误：Epic名称格式不正确" >&2
        return 1
    fi
    
    # 创建目录结构（在验证路径之前）
    if ! roadmap_create_directory_structure "$project_root"; then
        echo "❌ 错误：无法创建roadmap目录结构" >&2
        return 1
    fi
    
    # 验证roadmap路径
    if ! roadmap_validate_path "$epic_name" "$project_root"; then
        echo "❌ 错误：Roadmap路径验证失败" >&2
        return 1
    fi
    
    # 检查roadmap文件是否已存在
    if roadmap_file_exists "$epic_name" "$project_root"; then
        echo "⚠️ 警告：Roadmap文件已存在" >&2
        return 2
    fi
    
    # 生成roadmap模板
    local template_content
    template_content=$(roadmap_generate_template "$epic_name" "$base_branch" "$(date -u +"%Y-%m-%d %H:%M:%S")") || {
        echo "❌ 错误：无法生成roadmap模板" >&2
        return 1
    }
    
    # 获取文件路径
    local roadmap_file_path
    roadmap_file_path=$(roadmap_generate_file_path "$epic_name" "$project_root") || {
        echo "❌ 错误：无法生成roadmap文件路径" >&2
        return 1
    }
    
    # 创建roadmap文件
    echo "$template_content" > "$roadmap_file_path" || {
        echo "❌ 错误：无法创建roadmap文件" >&2
        return 1
    }
    
    # 验证生成的文件格式
    if ! roadmap_validate_format "$roadmap_file_path"; then
        echo "❌ 错误：生成的roadmap文件格式不正确" >&2
        return 1
    fi
    
    # 返回成功信息
    cat << EOF
{
    "success": true,
    "epic_name": "$epic_name",
    "roadmap_file": "$roadmap_file_path",
    "base_branch": "$base_branch",
    "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# Epic分支提交验证
# 参数：(epic_branch, project_root)
# 返回：0（验证通过）或1（验证失败），验证结果输出到stdout
roadmap_validate_epic_commit() {
    local epic_branch="$1"
    local project_root="${2:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 验证Epic分支命名
    if ! epic_validate_branch_naming "$epic_branch"; then
        echo "❌ 错误：Epic分支命名不符合规范" >&2
        return 1
    fi
    
    # 提取Epic名称
    local epic_name
    epic_name=$(epic_extract_name_from_branch "$epic_branch") || {
        echo "❌ 错误：无法从分支名提取Epic名称" >&2
        return 1
    }
    
    # 检查分支是否只包含roadmap文件
    if ! epic_check_roadmap_only "$epic_branch" "$project_root"; then
        echo "❌ 错误：Epic分支包含非roadmap文件" >&2
        return 1
    fi
    
    # 验证提交文件类型
    if ! epic_validate_commit_files "$epic_branch" "$project_root"; then
        echo "❌ 错误：Epic分支提交包含不允许的文件类型" >&2
        return 1
    fi
    
    # 验证roadmap完整性
    if ! epic_validate_roadmap_completeness "$epic_name" "$epic_branch" "$project_root"; then
        echo "❌ 错误：Roadmap文件完整性验证失败" >&2
        return 1
    fi
    
    # 获取完整验证报告
    local validation_report
    validation_report=$(epic_get_validation_report "$epic_branch" "$project_root") || {
        echo "❌ 错误：无法生成验证报告" >&2
        return 1
    }
    
    # 检查是否可以安全合并
    if ! epic_check_safe_to_merge "$epic_branch" "$project_root"; then
        echo "❌ 错误：Epic分支不能安全合并" >&2
        return 1
    fi
    
    # 返回验证成功信息
    cat << EOF
{
    "success": true,
    "epic_branch": "$epic_branch",
    "epic_name": "$epic_name",
    "safe_to_merge": true,
    "validation_report": $validation_report,
    "validated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# Roadmap状态更新
# 参数：(epic_name, feature_name, new_status, project_root)
# 返回：0（成功）或1（失败）
roadmap_update_feature_status() {
    local epic_name="$1"
    local feature_name="$2"
    local new_status="$3"  # 待实现|进行中|已完成
    local project_root="${4:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 验证输入
    if ! validate_name_format "$epic_name" || ! validate_name_format "$feature_name"; then
        echo "❌ 错误：Epic或Feature名称格式不正确" >&2
        return 1
    fi
    
    # 检查roadmap文件是否存在
    if ! roadmap_file_exists "$epic_name" "$project_root"; then
        echo "❌ 错误：Roadmap文件不存在" >&2
        return 1
    fi
    
    # 获取roadmap文件路径
    local roadmap_file_path
    roadmap_file_path=$(roadmap_generate_file_path "$epic_name" "$project_root")
    
    # 根据状态确定emoji
    local status_emoji
    case "$new_status" in
        "待实现") status_emoji="⏳" ;;
        "进行中") status_emoji="🔄" ;;
        "已完成") status_emoji="✅" ;;
        *) 
            echo "❌ 错误：无效的状态值：$new_status" >&2
            return 1
            ;;
    esac
    
    # 构建Feature全名
    local feature_full_name="$epic_name-$feature_name"
    
    # 使用sed更新roadmap文件中的Feature状态
    if grep -q "\*\*$feature_full_name\*\*" "$roadmap_file_path"; then
        # 更新现有Feature的状态
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS版本的sed
            sed -i .bak "s/\*\*$feature_full_name\*\*.*[⏳🔄✅].*\*\*[^*]*\*\*/\*\*$feature_full_name\*\* - Feature描述 $status_emoji \*\*$new_status\*\*/" "$roadmap_file_path"
        else
            # Linux版本的sed
            sed -i.bak "s/\*\*$feature_full_name\*\*.*[⏳🔄✅].*\*\*[^*]*\*\*/\*\*$feature_full_name\*\* - Feature描述 $status_emoji \*\*$new_status\*\*/" "$roadmap_file_path"
        fi
        rm -f "$roadmap_file_path.bak" 2>/dev/null || true
    else
        echo "❌ 错误：在roadmap中未找到Feature：$feature_full_name" >&2
        return 1
    fi
    
    echo "✅ 已更新Feature状态：$feature_full_name -> $new_status"
}

# 生成Roadmap状态总结
# 参数：(epic_name, project_root)
# 返回：JSON格式的状态总结
roadmap_get_status_summary() {
    local epic_name="$1"
    local project_root="${2:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 检查roadmap文件是否存在
    if ! roadmap_file_exists "$epic_name" "$project_root"; then
        cat << EOF
{
    "exists": false,
    "epic_name": "$epic_name",
    "error": "Roadmap file not found"
}
EOF
        return 1
    fi
    
    # 获取roadmap文件路径并解析状态
    local roadmap_file_path
    roadmap_file_path=$(roadmap_generate_file_path "$epic_name" "$project_root")
    
    local epic_status
    epic_status=$(roadmap_parse_epic_status "$roadmap_file_path")
    
    # 获取Epic信息
    local epic_info
    epic_info=$(roadmap_get_epic_info "$epic_name")
    
    # 合并信息
    cat << EOF
{
    "exists": true,
    "epic_name": "$epic_name",
    "roadmap_file": "$roadmap_file_path",
    "status": $epic_status,
    "info": $epic_info,
    "summary_generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}