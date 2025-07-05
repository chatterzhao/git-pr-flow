#!/bin/bash
# GPF Core - Path Processing Composite Methods
# 路径处理组合方法 - 组合原子方法实现复杂逻辑

set -euo pipefail

# 导入依赖的原子方法
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/path-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/environment-atomic.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../atomic/platform-utils.sh"

# 智能解析用户输入意图
# 参数：(user_input, expected_type)
# expected_type: "epic" | "feature" | "auto"
# 返回：JSON格式的解析结果
intelligent_parse_user_intent() {
    local user_input="$1"
    local expected_type="${2:-auto}"
    
    # 提取前缀和后缀信息
    local prefix suffix clean_input
    prefix=$(extract_prefix_from_input "$user_input")
    suffix=$(path_extract_suffix "$user_input")
    clean_input=$(strip_epic_prefix_from_input "$user_input")
    clean_input=$(strip_suffix_from_input "$clean_input")
    
    # 基于后缀判断类型
    local detected_type
    case "$suffix" in
        "e")
            detected_type="epic"
            ;;
        "ef")
            detected_type="feature"
            ;;
        "none")
            detected_type="$expected_type"
            ;;
        *)
            detected_type="unknown"
            ;;
    esac
    
    # 如果是feature类型，尝试解析epic和feature名称
    local epic_name="" feature_name=""
    if [[ "$detected_type" == "feature" ]]; then
        # 尝试从输入中解析epic-feature结构
        if [[ "$clean_input" == *-e-* ]]; then
            epic_name="${clean_input%-e-*}"
            feature_name="${clean_input#*-e-}"
        elif [[ "$clean_input" == *-* ]]; then
            # 假设最后一个连字符分割epic和feature
            epic_name="${clean_input%-*}"
            feature_name="${clean_input##*-}"
        else
            # 无法解析，返回错误
            epic_name=""
            feature_name="$clean_input"
        fi
    else
        epic_name="$clean_input"
        feature_name=""
    fi
    
    cat << EOF
{
    "original_input": "$user_input",
    "detected_type": "$detected_type",
    "expected_type": "$expected_type",
    "prefix": "$prefix",
    "suffix": "$suffix",
    "epic_name": "$epic_name",
    "feature_name": "$feature_name",
    "clean_input": "$clean_input"
}
EOF
}

# 标准化和验证用户输入
# 参数：(user_input, expected_type)
# expected_type: "epic" | "feature"
# 返回：0（成功）或1（失败），标准化结果输出到stdout
normalize_and_validate_input() {
    local user_input="$1"
    local expected_type="$2"
    
    # 解析用户意图
    local intent_json
    intent_json=$(intelligent_parse_user_intent "$user_input" "$expected_type")
    
    # 提取解析结果
    local detected_type epic_name feature_name
    detected_type=$(echo "$intent_json" | grep -o '"detected_type": "[^"]*"' | cut -d'"' -f4)
    epic_name=$(echo "$intent_json" | grep -o '"epic_name": "[^"]*"' | cut -d'"' -f4)
    feature_name=$(echo "$intent_json" | grep -o '"feature_name": "[^"]*"' | cut -d'"' -f4)
    
    # 验证类型匹配
    if [[ "$detected_type" != "$expected_type" && "$detected_type" != "auto" ]]; then
        echo "❌ 错误：输入类型 $detected_type 与期望类型 $expected_type 不匹配" >&2
        return 1
    fi
    
    # 验证Epic名称
    if [[ -z "$epic_name" ]]; then
        echo "❌ 错误：无法解析Epic名称" >&2
        return 1
    fi
    
    if ! validate_name_format "$epic_name"; then
        return 1
    fi
    
    # 验证Feature名称（如果是feature类型）
    if [[ "$expected_type" == "feature" ]]; then
        if [[ -z "$feature_name" ]]; then
            echo "❌ 错误：无法解析Feature名称" >&2
            return 1
        fi
        
        if ! validate_name_format "$feature_name"; then
            return 1
        fi
    fi
    
    # 输出标准化结果
    local result_json
    result_json=$(cat << EOF
{
    "type": "$expected_type",
    "epic_name": "$epic_name",
    "feature_name": "$feature_name",
    "validated": true
}
EOF
)
    
    echo "$result_json"
    return 0
}

# 构建标准分支名称
# 参数：(epic_name, feature_name) - feature_name可选
# 返回：标准分支名称
build_standard_branch_names() {
    local epic_name="$1"
    local feature_name="${2:-}"
    
    if [[ -n "$feature_name" ]]; then
        # Feature分支：epic-{epic}-e-{feature}-ef
        echo "epic-$epic_name-e-$feature_name-ef"
    else
        # Epic分支：epic-{epic}-e
        echo "epic-$epic_name-e"
    fi
}

# 生成所有相关的标准名称
# 参数：(epic_name, feature_name) - feature_name可选
# 返回：JSON格式的所有标准名称
generate_all_standard_names() {
    local epic_name="$1"
    local feature_name="${2:-}"
    
    local epic_branch feature_branch worktree_path
    epic_branch=$(build_standard_branch_names "$epic_name")
    
    if [[ -n "$feature_name" ]]; then
        feature_branch=$(build_standard_branch_names "$epic_name" "$feature_name")
        worktree_path=".worktrees/$feature_branch"
    else
        feature_branch=""
        worktree_path=".worktrees/$epic_branch"
    fi
    
    cat << EOF
{
    "epic_name": "$epic_name",
    "feature_name": "$feature_name",
    "epic_branch": "$epic_branch",
    "feature_branch": "$feature_branch",
    "worktree_path": "$worktree_path"
}
EOF
}

# 完整的路径处理流程
# 参数：(user_input, expected_type, project_root)
# expected_type: "epic" | "feature"
# 返回：0（成功）或1（失败），完整结果输出到stdout
path_complete_processing() {
    local user_input="$1"
    local expected_type="$2"
    local project_root="${3:-}"
    
    # 如果没有提供project_root，尝试自动获取
    if [[ -z "$project_root" ]]; then
        project_root=$(find_project_root) || {
            echo "❌ 错误：无法找到项目根目录" >&2
            return 1
        }
    fi
    
    # 标准化和验证输入
    local validation_result
    validation_result=$(normalize_and_validate_input "$user_input" "$expected_type") || {
        return 1
    }
    
    # 提取验证结果
    local epic_name feature_name
    epic_name=$(echo "$validation_result" | grep -o '"epic_name": "[^"]*"' | cut -d'"' -f4)
    feature_name=$(echo "$validation_result" | grep -o '"feature_name": "[^"]*"' | cut -d'"' -f4)
    
    # 生成标准名称
    local standard_names
    standard_names=$(generate_all_standard_names "$epic_name" "$feature_name")
    
    # 合并结果
    cat << EOF
{
    "success": true,
    "project_root": "$project_root",
    "input": {
        "original": "$user_input",
        "type": "$expected_type"
    },
    "validation": $validation_result,
    "names": $standard_names
}
EOF
}

# 智能路径转换
# 参数：(input_path, target_type)
# target_type: "epic" | "feature"
# 返回：转换后的路径信息
intelligent_path_transformation() {
    local input_path="$1"
    local target_type="$2"
    
    # 尝试从路径中提取信息
    local path_base
    path_base=$(basename "$input_path")
    
    # 如果是worktree路径，提取分支名
    if [[ "$path_base" =~ ^epic-.*-(e|ef)$ ]]; then
        local branch_name="$path_base"
        local clean_name
        clean_name=$(strip_suffix_from_input "$branch_name")
        clean_name=$(strip_epic_prefix_from_input "$clean_name")
        
        # 根据目标类型进行转换
        if [[ "$target_type" == "epic" ]]; then
            echo "epic-$clean_name-e"
        else
            echo "epic-$clean_name-ef"
        fi
    else
        # 直接处理为用户输入
        path_complete_processing "$input_path" "$target_type"
    fi
}