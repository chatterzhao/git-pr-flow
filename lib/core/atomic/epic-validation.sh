#!/bin/bash
# GPF Core - Epic Validation Atomic Methods
# Epic分支验证原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 检查Epic分支是否只包含roadmap文件
# 参数：(epic_branch_name, optional: worktree_path)
# 返回：0（只包含roadmap）或1（包含其他文件）
epic_check_roadmap_only() {
    local epic_branch="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 获取Epic分支相对于基础分支的修改文件
    local base_branch="develop"
    local modified_files
    
    # 检查分支是否存在
    if ! git -C "$worktree_path" rev-parse --verify "$epic_branch" >/dev/null 2>&1; then
        return 1
    fi
    
    # 获取Epic分支相对于develop的所有修改文件
    modified_files=$(git -C "$worktree_path" diff --name-only "$base_branch...$epic_branch" 2>/dev/null || echo "")
    
    if [[ -z "$modified_files" ]]; then
        # 没有修改文件，符合要求
        return 0
    fi
    
    # 检查是否只包含roadmap文件
    local non_roadmap_files
    non_roadmap_files=$(echo "$modified_files" | grep -v '^docs/epic_roadmap/.*\.md$' || true)
    
    if [[ -z "$non_roadmap_files" ]]; then
        return 0  # 只包含roadmap文件
    else
        return 1  # 包含其他文件
    fi
}

# 验证Epic提交的文件类型
# 参数：(epic_branch_name, optional: worktree_path)
# 返回：0（文件类型合法）或1（包含非法文件）
epic_validate_commit_files() {
    local epic_branch="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 获取Epic分支的所有修改文件
    local base_branch="develop"
    local modified_files
    modified_files=$(git -C "$worktree_path" diff --name-only "$base_branch...$epic_branch" 2>/dev/null || echo "")
    
    if [[ -z "$modified_files" ]]; then
        return 0  # 没有修改文件
    fi
    
    # 定义允许的文件模式
    local allowed_patterns=(
        '^docs/epic_roadmap/.*\.md$'
        '^docs/.*\.md$'
        '^README\.md$'
        '^\.gitignore$'
    )
    
    # 检查每个文件是否符合允许的模式
    local invalid_files=()
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        local file_allowed=false
        for pattern in "${allowed_patterns[@]}"; do
            if [[ "$file" =~ $pattern ]]; then
                file_allowed=true
                break
            fi
        done
        
        if [[ "$file_allowed" == "false" ]]; then
            invalid_files+=("$file")
        fi
    done <<< "$modified_files"
    
    # 如果有无效文件，返回错误
    if [[ ${#invalid_files[@]} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# 获取Epic分支的修改文件列表
# 参数：(epic_branch_name, optional: worktree_path)
# 返回：JSON格式的文件列表信息
epic_get_modified_files() {
    local epic_branch="$1"
    local worktree_path="${2:-$(pwd)}"
    local base_branch="develop"
    
    # 检查分支是否存在
    if ! git -C "$worktree_path" rev-parse --verify "$epic_branch" >/dev/null 2>&1; then
        cat << EOF
{
    "valid": false,
    "files": [],
    "roadmap_files": [],
    "other_files": [],
    "total": 0,
    "error": "Epic branch not found: $epic_branch"
}
EOF
        return 1
    fi
    
    # 获取修改文件列表
    local modified_files
    modified_files=$(git -C "$worktree_path" diff --name-only "$base_branch...$epic_branch" 2>/dev/null || echo "")
    
    if [[ -z "$modified_files" ]]; then
        cat << EOF
{
    "valid": true,
    "files": [],
    "roadmap_files": [],
    "other_files": [],
    "total": 0
}
EOF
        return 0
    fi
    
    # 分类文件
    local roadmap_files=()
    local other_files=()
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        if [[ "$file" =~ ^docs/epic_roadmap/.*\.md$ ]]; then
            roadmap_files+=("$file")
        else
            other_files+=("$file")
        fi
    done <<< "$modified_files"
    
    # 生成JSON数组
    local roadmap_json other_json all_files_json
    roadmap_json=$(printf '%s\n' "${roadmap_files[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
    other_json=$(printf '%s\n' "${other_files[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
    all_files_json=$(echo "$modified_files" | jq -R . | jq -s . 2>/dev/null || echo '[]')
    
    local total_count
    total_count=$(echo "$modified_files" | wc -l)
    
    cat << EOF
{
    "valid": true,
    "files": $all_files_json,
    "roadmap_files": $roadmap_json,
    "other_files": $other_json,
    "total": $total_count
}
EOF
}

# 检查Epic分支的roadmap文件完整性
# 参数：(epic_name, epic_branch_name, optional: worktree_path)
# 返回：0（完整）或1（不完整）
epic_validate_roadmap_completeness() {
    local epic_name="$1"
    local epic_branch="$2"
    local worktree_path="${3:-$(pwd)}"
    
    # 预期的roadmap文件路径
    local expected_roadmap="docs/epic_roadmap/epic-$epic_name-roadmap.md"
    
    # 获取Epic分支的修改文件
    local base_branch="develop"
    local modified_files
    modified_files=$(git -C "$worktree_path" diff --name-only "$base_branch...$epic_branch" 2>/dev/null || echo "")
    
    # 检查是否包含预期的roadmap文件
    if echo "$modified_files" | grep -q "^$expected_roadmap$"; then
        return 0
    else
        return 1
    fi
}

# 获取Epic分支的提交信息
# 参数：(epic_branch_name, optional: worktree_path)
# 返回：JSON格式的提交信息
epic_get_commit_info() {
    local epic_branch="$1"
    local worktree_path="${2:-$(pwd)}"
    local base_branch="develop"
    
    # 检查分支是否存在
    if ! git -C "$worktree_path" rev-parse --verify "$epic_branch" >/dev/null 2>&1; then
        cat << EOF
{
    "valid": false,
    "commits": [],
    "total_commits": 0,
    "latest_commit": null,
    "error": "Epic branch not found: $epic_branch"
}
EOF
        return 1
    fi
    
    # 获取提交信息
    local commits_json
    commits_json=$(git -C "$worktree_path" log --format='{"hash": "%H", "short_hash": "%h", "author": "%an", "date": "%ai", "message": "%s"}' "$base_branch..$epic_branch" 2>/dev/null | jq -s . || echo '[]')
    
    local total_commits
    total_commits=$(echo "$commits_json" | jq 'length')
    
    local latest_commit
    if [[ "$total_commits" -gt 0 ]]; then
        latest_commit=$(echo "$commits_json" | jq '.[0]')
    else
        latest_commit="null"
    fi
    
    cat << EOF
{
    "valid": true,
    "commits": $commits_json,
    "total_commits": $total_commits,
    "latest_commit": $latest_commit
}
EOF
}

# 验证Epic分支命名规范
# 参数：(epic_branch_name)
# 返回：0（符合规范）或1（不符合规范）
epic_validate_branch_naming() {
    local epic_branch="$1"
    
    # Epic分支命名规范：epic-<name>-e
    if [[ "$epic_branch" =~ ^epic-[a-z0-9_-]+-e$ ]]; then
        return 0
    else
        return 1
    fi
}

# 从Epic分支名提取Epic名称
# 参数：(epic_branch_name)
# 返回：Epic名称 或 空字符串（格式错误）
epic_extract_name_from_branch() {
    local epic_branch="$1"
    
    if epic_validate_branch_naming "$epic_branch"; then
        # 提取Epic名称：epic-auth-e -> auth
        echo "${epic_branch#epic-}" | sed 's/-e$//'
    else
        echo ""
        return 1
    fi
}

# 检查Epic分支是否可以安全合并
# 参数：(epic_branch_name, optional: worktree_path)
# 返回：0（可安全合并）或1（不可安全合并）
epic_check_safe_to_merge() {
    local epic_branch="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 检查是否只包含roadmap文件
    if ! epic_check_roadmap_only "$epic_branch" "$worktree_path"; then
        return 1
    fi
    
    # 检查文件类型是否合法
    if ! epic_validate_commit_files "$epic_branch" "$worktree_path"; then
        return 1
    fi
    
    # 检查roadmap文件完整性
    local epic_name
    epic_name=$(epic_extract_name_from_branch "$epic_branch")
    if [[ -n "$epic_name" ]]; then
        if ! epic_validate_roadmap_completeness "$epic_name" "$epic_branch" "$worktree_path"; then
            return 1
        fi
    fi
    
    return 0
}

# 获取Epic验证的完整报告
# 参数：(epic_branch_name, optional: worktree_path)
# 返回：JSON格式的验证报告
epic_get_validation_report() {
    local epic_branch="$1"
    local worktree_path="${2:-$(pwd)}"
    
    # 检查分支是否存在
    if ! git -C "$worktree_path" rev-parse --verify "$epic_branch" >/dev/null 2>&1; then
        cat << EOF
{
    "valid": false,
    "epic_name": null,
    "branch_naming": false,
    "roadmap_only": false,
    "file_types_valid": false,
    "roadmap_complete": false,
    "safe_to_merge": false,
    "error": "Epic branch not found: $epic_branch"
}
EOF
        return 1
    fi
    
    # 执行各项验证
    local epic_name branch_naming roadmap_only file_types_valid roadmap_complete safe_to_merge
    
    epic_name=$(epic_extract_name_from_branch "$epic_branch")
    
    if epic_validate_branch_naming "$epic_branch"; then
        branch_naming="true"
    else
        branch_naming="false"
    fi
    
    if epic_check_roadmap_only "$epic_branch" "$worktree_path"; then
        roadmap_only="true"
    else
        roadmap_only="false"
    fi
    
    if epic_validate_commit_files "$epic_branch" "$worktree_path"; then
        file_types_valid="true"
    else
        file_types_valid="false"
    fi
    
    if [[ -n "$epic_name" ]] && epic_validate_roadmap_completeness "$epic_name" "$epic_branch" "$worktree_path"; then
        roadmap_complete="true"
    else
        roadmap_complete="false"
    fi
    
    if epic_check_safe_to_merge "$epic_branch" "$worktree_path"; then
        safe_to_merge="true"
    else
        safe_to_merge="false"
    fi
    
    cat << EOF
{
    "valid": true,
    "epic_name": "$epic_name",
    "branch_naming": $branch_naming,
    "roadmap_only": $roadmap_only,
    "file_types_valid": $file_types_valid,
    "roadmap_complete": $roadmap_complete,
    "safe_to_merge": $safe_to_merge
}
EOF
}