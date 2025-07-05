#!/bin/bash
# GPF 路径管理模块 - 提供统一的路径处理和转换接口
# 本模块为所有命令提供一致的路径计算、分支名转换和前缀后缀处理

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载依赖
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/composite/path-composite.sh"
source "$PROJECT_ROOT/lib/core/composite/validation-composite.sh"

# ==============================================================================
# 路径管理模块 - 核心方法
# ==============================================================================

# 路径转换和验证（统一入口）
paths_module_convert_and_validate() {
    local input_value="$1"              # 用户输入
    local conversion_type="$2"          # epic_branch/feature_branch/worktree_path/roadmap_path
    local conversion_context="$3"       # Epic名称（Feature转换时需要）
    local validation_options="${4:-}"   # JSON格式验证选项
    
    # 解析验证选项
    local strict_validation=$(echo "${validation_options:-{}}" | jq -r '.strict_validation // true')
    local auto_correction=$(echo "${validation_options:-{}}" | jq -r '.auto_correction // true')
    local return_alternatives=$(echo "${validation_options:-{}}" | jq -r '.return_alternatives // false')
    
    # 第一阶段：输入清理和标准化
    local normalized_input
    normalized_input=$(paths_module_normalize_user_input "$input_value" "$conversion_type" "$auto_correction") || return 1
    
    # 第二阶段：路径转换
    local conversion_result
    conversion_result=$(paths_module_execute_conversion "$normalized_input" "$conversion_type" "$conversion_context") || return 1
    
    # 第三阶段：验证和完整性检查
    if [[ "$strict_validation" == "true" ]]; then
        local validation_result
        validation_result=$(paths_module_validate_conversion_result "$conversion_result" "$conversion_type") || return 1
    fi
    
    # 第四阶段：返回结果
    if [[ "$return_alternatives" == "true" ]]; then
        paths_module_generate_path_alternatives "$conversion_result" "$conversion_type"
    else
        echo "$conversion_result"
    fi
}

# 智能路径推断（从用户输入推断意图）
paths_module_intelligent_path_inference() {
    local user_input="$1"
    local current_context="${2:-auto}"   # 当前环境上下文
    local inference_options="${3:-}"     # JSON格式推断选项
    
    # 解析推断选项
    local prefer_existing=$(echo "${inference_options:-{}}" | jq -r '.prefer_existing // true')
    local suggest_alternatives=$(echo "${inference_options:-{}}" | jq -r '.suggest_alternatives // true')
    
    # 分析用户输入模式
    local input_analysis
    input_analysis=$(paths_module_analyze_input_patterns "$user_input") || return 1
    
    local input_type=$(echo "$input_analysis" | jq -r '.detected_type')
    local confidence=$(echo "$input_analysis" | jq -r '.confidence')
    
    # 根据当前上下文调整推断
    local context_adjusted_result
    context_adjusted_result=$(paths_module_adjust_inference_by_context "$input_analysis" "$current_context") || return 1
    
    # 生成路径建议
    local path_suggestions
    path_suggestions=$(paths_module_generate_path_suggestions "$context_adjusted_result" "$prefer_existing") || return 1
    
    # 返回推断结果
    cat <<EOF
{
    "user_input": "$user_input",
    "current_context": "$current_context",
    "input_analysis": $input_analysis,
    "adjusted_result": $context_adjusted_result,
    "path_suggestions": $path_suggestions,
    "confidence": $confidence
}
EOF
}

# 批量路径转换（为复杂操作提供批量处理）
paths_module_batch_path_conversion() {
    local conversion_requests="$1"      # JSON数组：转换请求列表
    local batch_options="${2:-}"        # 批量处理选项
    
    local conversion_results="[]"
    local successful_count=0
    local failed_count=0
    
    # 解析批量选项
    local fail_fast=$(echo "${batch_options:-{}}" | jq -r '.fail_fast // false')
    local include_errors=$(echo "${batch_options:-{}}" | jq -r '.include_errors // true')
    
    # 遍历转换请求
    echo "$conversion_requests" | jq -c '.[]' | while read -r request; do
        local input=$(echo "$request" | jq -r '.input')
        local type=$(echo "$request" | jq -r '.type')
        local context=$(echo "$request" | jq -r '.context // ""')
        local options=$(echo "$request" | jq -r '.options // {}')
        
        local result
        if result=$(paths_module_convert_and_validate "$input" "$type" "$context" "$options" 2>&1); then
            successful_count=$((successful_count + 1))
            
            local success_result
            success_result=$(cat <<EOF
{
    "input": "$input",
    "type": "$type",
    "success": true,
    "result": "$result"
}
EOF
            )
            conversion_results=$(echo "$conversion_results" | jq --argjson result "$success_result" '. += [$result]')
        else
            failed_count=$((failed_count + 1))
            
            if [[ "$include_errors" == "true" ]]; then
                local error_result
                error_result=$(cat <<EOF
{
    "input": "$input",
    "type": "$type",
    "success": false,
    "error": "$result"
}
EOF
                )
                conversion_results=$(echo "$conversion_results" | jq --argjson result "$error_result" '. += [$result]')
            fi
            
            if [[ "$fail_fast" == "true" ]]; then
                break
            fi
        fi
    done
    
    # 返回批量转换结果
    cat <<EOF
{
    "successful_count": $successful_count,
    "failed_count": $failed_count,
    "total_requests": $(echo "$conversion_requests" | jq 'length'),
    "results": $conversion_results
}
EOF
}

# ==============================================================================
# 输入处理和标准化
# ==============================================================================

# 标准化用户输入
paths_module_normalize_user_input() {
    local user_input="$1"
    local target_type="$2"
    local auto_correction="$3"
    
    # 第一步：基础清理
    local cleaned_input="$user_input"
    
    # 移除多余的空白字符
    cleaned_input=$(echo "$cleaned_input" | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    # 转换为小写（根据需要）
    if [[ "$target_type" =~ ^(epic_branch|feature_branch)$ ]]; then
        cleaned_input=$(echo "$cleaned_input" | tr '[:upper:]' '[:lower:]')
    fi
    
    # 第二步：前缀后缀处理
    case "$target_type" in
        "epic_branch")
            # 移除epic-前缀和-e后缀
            cleaned_input=$(strip_epic_prefix_from_input "$cleaned_input")
            cleaned_input=$(strip_suffix_from_input "$cleaned_input")
            ;;
        "feature_branch")
            # 移除epic-前缀和-ef后缀
            cleaned_input=$(strip_epic_prefix_from_input "$cleaned_input")
            cleaned_input=$(strip_suffix_from_input "$cleaned_input")
            
            # 对于Feature，可能需要移除Epic名称前缀
            if [[ "$cleaned_input" =~ ^[^-]+-(.+)$ ]]; then
                cleaned_input="${BASH_REMATCH[1]}"
            fi
            ;;
        "worktree_path"|"roadmap_path")
            # 路径清理：移除多余的斜杠
            cleaned_input=$(echo "$cleaned_input" | sed 's|//\+|/|g' | sed 's|/$||')
            ;;
    esac
    
    # 第三步：自动纠错（如果启用）
    if [[ "$auto_correction" == "true" ]]; then
        cleaned_input=$(paths_module_apply_auto_corrections "$cleaned_input" "$target_type")
    fi
    
    # 第四步：验证清理结果
    if ! paths_module_validate_normalized_input "$cleaned_input" "$target_type"; then
        echo "❌ 错误：输入标准化失败: $user_input" >&2
        return 1
    fi
    
    echo "$cleaned_input"
}

# 应用自动纠错
paths_module_apply_auto_corrections() {
    local input="$1"
    local target_type="$2"
    
    local corrected_input="$input"
    
    case "$target_type" in
        "epic_branch"|"feature_branch")
            # 替换不允许的字符
            corrected_input=$(echo "$corrected_input" | sed 's/[^a-zA-Z0-9_-]/-/g')
            
            # 移除连续的连字符
            corrected_input=$(echo "$corrected_input" | sed 's/--\+/-/g')
            
            # 移除开头和结尾的连字符
            corrected_input=$(echo "$corrected_input" | sed 's/^-\+\|-\+$//g')
            
            # 确保不为空
            if [[ -z "$corrected_input" ]]; then
                corrected_input="unnamed"
            fi
            ;;
        "worktree_path")
            # 确保是相对路径
            corrected_input=$(echo "$corrected_input" | sed 's|^/||')
            ;;
    esac
    
    echo "$corrected_input"
}

# 验证标准化输入
paths_module_validate_normalized_input() {
    local input="$1"
    local target_type="$2"
    
    case "$target_type" in
        "epic_branch"|"feature_branch")
            # 验证名称格式
            validate_name_format "$input"
            ;;
        "worktree_path"|"roadmap_path")
            # 验证路径格式
            [[ -n "$input" && ! "$input" =~ \.\./|^/ ]]
            ;;
        *)
            return 0
            ;;
    esac
}

# ==============================================================================
# 路径转换引擎
# ==============================================================================

# 执行路径转换
paths_module_execute_conversion() {
    local normalized_input="$1"
    local conversion_type="$2"
    local conversion_context="$3"
    
    case "$conversion_type" in
        "epic_branch")
            paths_module_convert_to_epic_branch "$normalized_input"
            ;;
        "feature_branch")
            paths_module_convert_to_feature_branch "$normalized_input" "$conversion_context"
            ;;
        "worktree_path")
            paths_module_convert_to_worktree_path "$normalized_input"
            ;;
        "roadmap_path")
            paths_module_convert_to_roadmap_path "$normalized_input"
            ;;
        "relative_path")
            paths_module_convert_to_relative_path "$normalized_input"
            ;;
        *)
            echo "❌ 错误：未知的转换类型: $conversion_type" >&2
            return 1
            ;;
    esac
}

# 转换为Epic分支名
paths_module_convert_to_epic_branch() {
    local epic_name="$1"
    
    # 验证Epic名称
    if ! validate_name_format "$epic_name"; then
        echo "❌ 错误：无效的Epic名称: $epic_name" >&2
        return 1
    fi
    
    local epic_branch="epic-$epic_name-e"
    
    cat <<EOF
{
    "original_input": "$epic_name",
    "conversion_type": "epic_branch",
    "result": "$epic_branch",
    "worktree_path": "$PROJECT_ROOT/.worktrees/$epic_branch",
    "roadmap_path": "$PROJECT_ROOT/docs/epic_roadmap/epic-$epic_name-e-roadmap.md"
}
EOF
}

# 转换为Feature分支名
paths_module_convert_to_feature_branch() {
    local feature_name="$1"
    local epic_context="$2"
    
    # 验证Feature名称
    if ! validate_name_format "$feature_name"; then
        echo "❌ 错误：无效的Feature名称: $feature_name" >&2
        return 1
    fi
    
    # 确定Epic上下文
    local epic_name
    if [[ -n "$epic_context" ]]; then
        # 清理Epic上下文
        epic_name=$(strip_epic_prefix_from_input "$epic_context")
        epic_name=$(strip_suffix_from_input "$epic_name")
    else
        # 尝试从当前环境推断
        epic_name=$(extract_current_epic_name 2>/dev/null) || {
            echo "❌ 错误：无法确定Epic上下文，请提供Epic名称" >&2
            return 1
        }
    fi
    
    local feature_branch="epic-$epic_name-e-$feature_name-ef"
    
    cat <<EOF
{
    "original_input": "$feature_name",
    "conversion_type": "feature_branch",
    "epic_context": "$epic_name",
    "result": "$feature_branch",
    "worktree_path": "$PROJECT_ROOT/.worktrees/$feature_branch",
    "epic_branch": "epic-$epic_name-e"
}
EOF
}

# 转换为工作树路径
paths_module_convert_to_worktree_path() {
    local branch_identifier="$1"
    
    local worktree_path
    local branch_name
    
    # 判断输入类型
    if [[ "$branch_identifier" =~ ^epic-.*-e(-.+-ef)?$ ]]; then
        # 已经是分支名
        branch_name="$branch_identifier"
        worktree_path="$PROJECT_ROOT/.worktrees/$branch_name"
    else
        # 需要转换为分支名
        if [[ "$branch_identifier" =~ - ]]; then
            # 可能是Feature
            local conversion_result
            conversion_result=$(paths_module_convert_to_feature_branch "$branch_identifier" "")
            branch_name=$(echo "$conversion_result" | jq -r '.result')
        else
            # 可能是Epic
            local conversion_result
            conversion_result=$(paths_module_convert_to_epic_branch "$branch_identifier")
            branch_name=$(echo "$conversion_result" | jq -r '.result')
        fi
        worktree_path="$PROJECT_ROOT/.worktrees/$branch_name"
    fi
    
    cat <<EOF
{
    "original_input": "$branch_identifier",
    "conversion_type": "worktree_path",
    "branch_name": "$branch_name",
    "result": "$worktree_path",
    "relative_path": ".worktrees/$branch_name",
    "exists": $([ -d "$worktree_path" ] && echo "true" || echo "false")
}
EOF
}

# 转换为roadmap路径
paths_module_convert_to_roadmap_path() {
    local epic_identifier="$1"
    
    # 确保是Epic名称
    local epic_name
    if [[ "$epic_identifier" =~ ^epic-(.+)-e$ ]]; then
        epic_name="${BASH_REMATCH[1]}"
    else
        epic_name=$(strip_epic_prefix_from_input "$epic_identifier")
        epic_name=$(strip_suffix_from_input "$epic_name")
    fi
    
    local roadmap_path="$PROJECT_ROOT/docs/epic_roadmap/epic-$epic_name-e-roadmap.md"
    
    cat <<EOF
{
    "original_input": "$epic_identifier",
    "conversion_type": "roadmap_path",
    "epic_name": "$epic_name",
    "result": "$roadmap_path",
    "relative_path": "docs/epic_roadmap/epic-$epic_name-e-roadmap.md",
    "exists": $([ -f "$roadmap_path" ] && echo "true" || echo "false")
}
EOF
}

# 转换为相对路径
paths_module_convert_to_relative_path() {
    local absolute_path="$1"
    
    # 计算相对于项目根目录的路径
    local relative_path
    if [[ "$absolute_path" == "$PROJECT_ROOT"* ]]; then
        relative_path="${absolute_path#$PROJECT_ROOT/}"
        # 移除开头的斜杠（如果有）
        relative_path="${relative_path#/}"
    else
        echo "❌ 错误：路径不在项目根目录内: $absolute_path" >&2
        return 1
    fi
    
    cat <<EOF
{
    "original_input": "$absolute_path",
    "conversion_type": "relative_path",
    "result": "$relative_path",
    "project_root": "$PROJECT_ROOT"
}
EOF
}

# ==============================================================================
# 智能推断和建议
# ==============================================================================

# 分析输入模式
paths_module_analyze_input_patterns() {
    local user_input="$1"
    
    local detected_type="unknown"
    local confidence=0
    local patterns_matched="[]"
    
    # Epic分支模式
    if [[ "$user_input" =~ ^epic-[a-zA-Z0-9_-]+-e$ ]]; then
        detected_type="epic_branch"
        confidence=95
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["epic_branch_exact"]')
    elif [[ "$user_input" =~ ^epic-[a-zA-Z0-9_-]+$ ]]; then
        detected_type="epic_name"
        confidence=85
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["epic_branch_prefix"]')
    elif [[ "$user_input" =~ ^[a-zA-Z0-9_-]+-e$ ]]; then
        detected_type="epic_name"
        confidence=75
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["epic_branch_suffix"]')
    fi
    
    # Feature分支模式
    if [[ "$user_input" =~ ^epic-[a-zA-Z0-9_-]+-e-[a-zA-Z0-9_-]+-ef$ ]]; then
        detected_type="feature_branch"
        confidence=95
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["feature_branch_exact"]')
    elif [[ "$user_input" =~ ^[a-zA-Z0-9_-]+-[a-zA-Z0-9_-]+-ef$ ]]; then
        detected_type="feature_name"
        confidence=80
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["feature_branch_partial"]')
    elif [[ "$user_input" =~ ^[a-zA-Z0-9_-]+-[a-zA-Z0-9_-]+$ ]]; then
        detected_type="feature_name"
        confidence=60
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["feature_name_compound"]')
    fi
    
    # 路径模式
    if [[ "$user_input" =~ ^\.worktrees/ ]]; then
        detected_type="worktree_path"
        confidence=90
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["worktree_path"]')
    elif [[ "$user_input" =~ ^docs/epic_roadmap/ ]]; then
        detected_type="roadmap_path"
        confidence=90
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["roadmap_path"]')
    fi
    
    # 简单名称模式
    if [[ "$confidence" -eq 0 && "$user_input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        detected_type="simple_name"
        confidence=50
        patterns_matched=$(echo "$patterns_matched" | jq '. += ["simple_name"]')
    fi
    
    cat <<EOF
{
    "user_input": "$user_input",
    "detected_type": "$detected_type",
    "confidence": $confidence,
    "patterns_matched": $patterns_matched
}
EOF
}

# 根据上下文调整推断
paths_module_adjust_inference_by_context() {
    local input_analysis="$1"
    local current_context="$2"
    
    local detected_type=$(echo "$input_analysis" | jq -r '.detected_type')
    local confidence=$(echo "$input_analysis" | jq -r '.confidence')
    local adjusted_type="$detected_type"
    local adjusted_confidence=$confidence
    
    # 获取当前环境
    local current_env="unknown"
    if [[ "$current_context" == "auto" ]]; then
        current_env=$(environment_detect_complete 2>/dev/null || echo "unknown")
    else
        current_env="$current_context"
    fi
    
    # 根据当前环境调整推断
    case "$current_env" in
        "epic")
            if [[ "$detected_type" == "simple_name" ]]; then
                adjusted_type="feature_name"
                adjusted_confidence=70
            fi
            ;;
        "feature")
            if [[ "$detected_type" == "simple_name" ]]; then
                adjusted_type="feature_name"
                adjusted_confidence=60
            fi
            ;;
        "root")
            if [[ "$detected_type" == "simple_name" ]]; then
                adjusted_type="epic_name"
                adjusted_confidence=65
            fi
            ;;
    esac
    
    cat <<EOF
{
    "original_analysis": $input_analysis,
    "current_context": "$current_env",
    "adjusted_type": "$adjusted_type",
    "adjusted_confidence": $adjusted_confidence,
    "adjustment_reason": "context_based_inference"
}
EOF
}

# 生成路径建议
paths_module_generate_path_suggestions() {
    local adjusted_result="$1"
    local prefer_existing="$2"
    
    local adjusted_type=$(echo "$adjusted_result" | jq -r '.adjusted_type')
    local user_input=$(echo "$adjusted_result" | jq -r '.original_analysis.user_input')
    
    local suggestions="[]"
    
    case "$adjusted_type" in
        "epic_name"|"epic_branch")
            # Epic相关建议
            local epic_conversion
            epic_conversion=$(paths_module_convert_to_epic_branch "$user_input" 2>/dev/null) || epic_conversion="{}"
            
            if [[ "$epic_conversion" != "{}" ]]; then
                suggestions=$(echo "$suggestions" | jq --argjson conv "$epic_conversion" '. += [$conv]')
            fi
            ;;
        "feature_name"|"feature_branch")
            # Feature相关建议
            local feature_conversion
            feature_conversion=$(paths_module_convert_to_feature_branch "$user_input" "" 2>/dev/null) || feature_conversion="{}"
            
            if [[ "$feature_conversion" != "{}" ]]; then
                suggestions=$(echo "$suggestions" | jq --argjson conv "$feature_conversion" '. += [$conv]')
            fi
            ;;
    esac
    
    # 如果偏好现有路径，过滤掉不存在的
    if [[ "$prefer_existing" == "true" ]]; then
        suggestions=$(echo "$suggestions" | jq '[.[] | select(.exists == true or has("exists") | not)]')
    fi
    
    echo "$suggestions"
}

# 生成路径替代方案
paths_module_generate_path_alternatives() {
    local conversion_result="$1"
    local conversion_type="$2"
    
    local alternatives="[]"
    local primary_result="$conversion_result"
    
    # 添加主要结果
    alternatives=$(echo "$alternatives" | jq --argjson result "$primary_result" '. += [$result]')
    
    # 根据转换类型生成替代方案
    case "$conversion_type" in
        "epic_branch")
            local epic_name=$(echo "$conversion_result" | jq -r '.original_input')
            
            # 生成worktree路径替代
            local worktree_alt
            worktree_alt=$(paths_module_convert_to_worktree_path "$epic_name")
            alternatives=$(echo "$alternatives" | jq --argjson alt "$worktree_alt" '. += [$alt]')
            
            # 生成roadmap路径替代
            local roadmap_alt
            roadmap_alt=$(paths_module_convert_to_roadmap_path "$epic_name")
            alternatives=$(echo "$alternatives" | jq --argjson alt "$roadmap_alt" '. += [$alt]')
            ;;
        "feature_branch")
            local feature_name=$(echo "$conversion_result" | jq -r '.original_input')
            local epic_context=$(echo "$conversion_result" | jq -r '.epic_context')
            
            # 生成worktree路径替代
            local worktree_alt
            worktree_alt=$(paths_module_convert_to_worktree_path "$feature_name")
            alternatives=$(echo "$alternatives" | jq --argjson alt "$worktree_alt" '. += [$alt]')
            ;;
    esac
    
    cat <<EOF
{
    "primary_result": $primary_result,
    "alternatives": $alternatives,
    "conversion_type": "$conversion_type"
}
EOF
}

# ==============================================================================
# 验证和完整性检查
# ==============================================================================

# 验证转换结果
paths_module_validate_conversion_result() {
    local conversion_result="$1"
    local conversion_type="$2"
    
    local result_path=$(echo "$conversion_result" | jq -r '.result')
    local validation_issues="[]"
    local is_valid="true"
    
    case "$conversion_type" in
        "epic_branch"|"feature_branch")
            # 验证分支名格式
            if [[ ! "$result_path" =~ ^epic-[a-zA-Z0-9_-]+-e(-.+-ef)?$ ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["分支名格式不正确"]')
                is_valid="false"
            fi
            ;;
        "worktree_path"|"roadmap_path")
            # 验证路径格式
            if [[ ! "$result_path" =~ ^$PROJECT_ROOT/ ]]; then
                validation_issues=$(echo "$validation_issues" | jq '. += ["路径不在项目根目录内"]')
                is_valid="false"
            fi
            ;;
    esac
    
    if [[ "$is_valid" != "true" ]]; then
        echo "❌ 路径转换验证失败:" >&2
        echo "$validation_issues" | jq -r '.[]' | while read -r issue; do
            echo "  - $issue" >&2
        done
        return 1
    fi
    
    return 0
}