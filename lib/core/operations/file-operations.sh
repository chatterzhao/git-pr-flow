#!/bin/bash
# GPF 文件操作层 - 纯文件系统操作，无业务逻辑
# 提供安全的文件操作原语，包含备份和rollback机制

set -euo pipefail

# ==============================================================================
# 文件操作层 - 核心原语
# ==============================================================================

# 文件创建操作
file_create_operation() {
    local file_path="$1"
    local content="${2:-}"
    local backup_existing="${3:-true}"
    local force_create="${4:-false}"
    
    # 前置安全检查
    [[ -n "$file_path" ]] || {
        echo "❌ 错误：文件路径不能为空" >&2
        return 1
    }
    
    # 验证路径安全性
    file_validate_path_safety "$file_path" || return 1
    
    # 确保父目录存在
    local parent_dir
    parent_dir=$(dirname "$file_path")
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || {
            echo "❌ 错误：无法创建父目录: $parent_dir" >&2
            return 1
        }
    fi
    
    # 处理现有文件
    if [[ -e "$file_path" ]]; then
        if [[ "$force_create" != "true" ]]; then
            echo "❌ 错误：文件已存在: $file_path" >&2
            return 1
        fi
        
        # 创建备份
        if [[ "$backup_existing" == "true" ]]; then
            file_backup_operation "$file_path" || {
                echo "❌ 错误：无法备份现有文件" >&2
                return 1
            }
        fi
    fi
    
    # 执行文件创建
    if [[ -n "$content" ]]; then
        echo "$content" > "$file_path" || {
            echo "❌ 错误：写入文件失败: $file_path" >&2
            return 1
        }
    else
        touch "$file_path" || {
            echo "❌ 错误：创建文件失败: $file_path" >&2
            return 1
        }
    fi
    
    echo "✅ 成功创建文件: $file_path"
    [[ "$backup_existing" == "true" && -e "${file_path}.backup" ]] && \
        echo "🔄 Rollback信息: mv ${file_path}.backup $file_path" >&2
    
    return 0
}

# 文件删除操作
file_delete_operation() {
    local file_path="$1"
    local backup_before_delete="${2:-true}"
    local force_delete="${3:-false}"
    
    # 前置安全检查
    [[ -n "$file_path" ]] || {
        echo "❌ 错误：文件路径不能为空" >&2
        return 1
    }
    
    # 验证路径安全性
    file_validate_path_safety "$file_path" || return 1
    
    # 检查文件存在性
    if [[ ! -e "$file_path" ]]; then
        echo "⚠️ 警告：文件不存在，跳过删除: $file_path"
        return 0
    fi
    
    # 安全检查：重要文件保护
    if [[ "$force_delete" != "true" ]]; then
        file_check_important_file "$file_path" || {
            echo "❌ 错误：重要文件受保护，使用force_delete=true强制删除" >&2
            return 1
        }
    fi
    
    # 创建备份（用于rollback）
    local backup_path=""
    if [[ "$backup_before_delete" == "true" ]]; then
        backup_path=$(file_backup_operation "$file_path")
        if [[ $? -ne 0 ]]; then
            echo "❌ 错误：无法创建备份" >&2
            return 1
        fi
    fi
    
    # 执行删除操作
    if rm "$file_path" 2>/dev/null; then
        echo "✅ 成功删除文件: $file_path"
        [[ -n "$backup_path" ]] && \
            echo "🔄 Rollback信息: mv $backup_path $file_path" >&2
        return 0
    else
        echo "❌ 删除文件失败: $file_path" >&2
        return 1
    fi
}

# 文件复制操作
file_copy_operation() {
    local source_path="$1"
    local dest_path="$2"
    local preserve_metadata="${3:-true}"
    local backup_existing="${4:-true}"
    
    # 前置安全检查
    [[ -n "$source_path" && -n "$dest_path" ]] || {
        echo "❌ 错误：源路径和目标路径不能为空" >&2
        return 1
    }
    
    # 验证路径安全性
    file_validate_path_safety "$source_path" || return 1
    file_validate_path_safety "$dest_path" || return 1
    
    # 检查源文件存在性
    [[ -f "$source_path" ]] || {
        echo "❌ 错误：源文件不存在: $source_path" >&2
        return 1
    }
    
    # 确保目标目录存在
    local dest_dir
    dest_dir=$(dirname "$dest_path")
    [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir" || {
        echo "❌ 错误：无法创建目标目录: $dest_dir" >&2
        return 1
    }
    
    # 处理现有目标文件
    if [[ -e "$dest_path" && "$backup_existing" == "true" ]]; then
        file_backup_operation "$dest_path" || {
            echo "❌ 错误：无法备份现有目标文件" >&2
            return 1
        }
    fi
    
    # 构造复制参数
    local cp_args=()
    [[ "$preserve_metadata" == "true" ]] && cp_args+=("-p")
    
    # 执行复制操作
    if cp "${cp_args[@]}" "$source_path" "$dest_path" 2>/dev/null; then
        echo "✅ 成功复制文件: $source_path → $dest_path"
        return 0
    else
        echo "❌ 复制文件失败: $source_path → $dest_path" >&2
        return 1
    fi
}

# 文件移动操作
file_move_operation() {
    local source_path="$1"
    local dest_path="$2"
    local backup_existing="${3:-true}"
    
    # 前置安全检查
    [[ -n "$source_path" && -n "$dest_path" ]] || {
        echo "❌ 错误：源路径和目标路径不能为空" >&2
        return 1
    }
    
    # 验证路径安全性
    file_validate_path_safety "$source_path" || return 1
    file_validate_path_safety "$dest_path" || return 1
    
    # 检查源文件存在性
    [[ -e "$source_path" ]] || {
        echo "❌ 错误：源文件不存在: $source_path" >&2
        return 1
    }
    
    # 确保目标目录存在
    local dest_dir
    dest_dir=$(dirname "$dest_path")
    [[ -d "$dest_dir" ]] || mkdir -p "$dest_dir" || {
        echo "❌ 错误：无法创建目标目录: $dest_dir" >&2
        return 1
    }
    
    # 处理现有目标文件
    local dest_backup_path=""
    if [[ -e "$dest_path" && "$backup_existing" == "true" ]]; then
        dest_backup_path=$(file_backup_operation "$dest_path")
        if [[ $? -ne 0 ]]; then
            echo "❌ 错误：无法备份现有目标文件" >&2
            return 1
        fi
    fi
    
    # 执行移动操作
    if mv "$source_path" "$dest_path" 2>/dev/null; then
        echo "✅ 成功移动文件: $source_path → $dest_path"
        
        # 生成rollback信息
        local rollback_info="mv $dest_path $source_path"
        [[ -n "$dest_backup_path" ]] && rollback_info="$rollback_info && mv $dest_backup_path $dest_path"
        echo "🔄 Rollback信息: $rollback_info" >&2
        
        return 0
    else
        echo "❌ 移动文件失败: $source_path → $dest_path" >&2
        return 1
    fi
}

# 文件备份操作
file_backup_operation() {
    local file_path="$1"
    local backup_suffix="${2:-.backup}"
    local backup_dir="${3:-}"
    
    # 前置安全检查
    [[ -n "$file_path" ]] || {
        echo "❌ 错误：文件路径不能为空" >&2
        return 1
    }
    
    # 检查文件存在性
    [[ -e "$file_path" ]] || {
        echo "❌ 错误：源文件不存在: $file_path" >&2
        return 1
    }
    
    # 确定备份路径
    local backup_path
    if [[ -n "$backup_dir" ]]; then
        [[ -d "$backup_dir" ]] || mkdir -p "$backup_dir" || {
            echo "❌ 错误：无法创建备份目录: $backup_dir" >&2
            return 1
        }
        local filename
        filename=$(basename "$file_path")
        backup_path="$backup_dir/${filename}${backup_suffix}"
    else
        backup_path="${file_path}${backup_suffix}"
    fi
    
    # 生成唯一备份名（如果已存在）
    local counter=1
    local original_backup_path="$backup_path"
    while [[ -e "$backup_path" ]]; do
        backup_path="${original_backup_path}.${counter}"
        counter=$((counter + 1))
    done
    
    # 执行备份操作
    if cp -p "$file_path" "$backup_path" 2>/dev/null; then
        echo "$backup_path"  # 返回备份路径
        return 0
    else
        echo "❌ 创建备份失败: $file_path" >&2
        return 1
    fi
}

# 文件恢复操作
file_restore_operation() {
    local backup_path="$1"
    local original_path="${2:-}"
    local force_restore="${3:-false}"
    
    # 前置安全检查
    [[ -n "$backup_path" ]] || {
        echo "❌ 错误：备份路径不能为空" >&2
        return 1
    }
    
    # 检查备份文件存在性
    [[ -f "$backup_path" ]] || {
        echo "❌ 错误：备份文件不存在: $backup_path" >&2
        return 1
    }
    
    # 确定原始路径
    if [[ -z "$original_path" ]]; then
        # 尝试从备份路径推断原始路径
        if [[ "$backup_path" =~ ^(.+)\.backup ]]; then
            original_path="${BASH_REMATCH[1]}"
        else
            echo "❌ 错误：无法推断原始路径，请明确指定" >&2
            return 1
        fi
    fi
    
    # 验证路径安全性
    file_validate_path_safety "$original_path" || return 1
    
    # 检查原始文件冲突
    if [[ -e "$original_path" && "$force_restore" != "true" ]]; then
        echo "❌ 错误：原始文件已存在，使用force_restore=true强制恢复" >&2
        return 1
    fi
    
    # 确保目标目录存在
    local target_dir
    target_dir=$(dirname "$original_path")
    [[ -d "$target_dir" ]] || mkdir -p "$target_dir" || {
        echo "❌ 错误：无法创建目标目录: $target_dir" >&2
        return 1
    }
    
    # 执行恢复操作
    if cp -p "$backup_path" "$original_path" 2>/dev/null; then
        echo "✅ 成功恢复文件: $backup_path → $original_path"
        return 0
    else
        echo "❌ 恢复文件失败: $backup_path → $original_path" >&2
        return 1
    fi
}

# ==============================================================================
# 辅助操作方法
# ==============================================================================

# 验证路径安全性
file_validate_path_safety() {
    local file_path="$1"
    
    # 检查路径为空
    [[ -n "$file_path" ]] || {
        echo "❌ 文件路径不能为空" >&2
        return 1
    }
    
    # 防止路径遍历攻击
    if [[ "$file_path" =~ \.\./|^/ ]]; then
        echo "❌ 不安全的文件路径: $file_path" >&2
        return 1
    fi
    
    # 检查保留文件名
    local basename_file
    basename_file=$(basename "$file_path")
    local reserved_names=("." ".." ".git" ".gitignore")
    
    for reserved in "${reserved_names[@]}"; do
        if [[ "$basename_file" == "$reserved" ]]; then
            echo "❌ 不能操作保留文件: $basename_file" >&2
            return 1
        fi
    done
    
    return 0
}

# 检查重要文件保护
file_check_important_file() {
    local file_path="$1"
    
    # 重要文件列表
    local important_files=(
        "package.json"
        "package-lock.json"
        "yarn.lock"
        "Cargo.toml"
        "Cargo.lock"
        "go.mod"
        "go.sum"
        "requirements.txt"
        "Pipfile"
        "Pipfile.lock"
        "composer.json"
        "composer.lock"
        "Gemfile"
        "Gemfile.lock"
        ".env"
        ".env.local"
        ".env.production"
        "config.json"
        "settings.json"
        "tsconfig.json"
        "webpack.config.js"
        "vite.config.js"
        "next.config.js"
        "nuxt.config.js"
        "vue.config.js"
        "angular.json"
        "Dockerfile"
        "docker-compose.yml"
        "docker-compose.yaml"
        "README.md"
        "LICENSE"
        "CHANGELOG.md"
    )
    
    local basename_file
    basename_file=$(basename "$file_path")
    
    for important in "${important_files[@]}"; do
        if [[ "$basename_file" == "$important" ]]; then
            return 1  # 文件受保护
        fi
    done
    
    return 0  # 文件不受保护
}

# 获取文件信息
file_get_info() {
    local file_path="$1"
    local output_format="${2:-json}"
    
    # 检查文件存在性
    [[ -e "$file_path" ]] || {
        echo "❌ 文件不存在: $file_path" >&2
        return 1
    }
    
    # 获取文件信息
    local file_type size permissions modified_time
    file_type=$(file -b "$file_path" 2>/dev/null || echo "unknown")
    
    if command -v stat >/dev/null 2>&1; then
        # 使用stat命令（跨平台兼容）
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS版本
            size=$(stat -f%z "$file_path" 2>/dev/null || echo "0")
            permissions=$(stat -f%Mp%Lp "$file_path" 2>/dev/null || echo "unknown")
            modified_time=$(stat -f%m "$file_path" 2>/dev/null || echo "0")
        else
            # Linux版本
            size=$(stat -f%s "$file_path" 2>/dev/null || echo "0")
            permissions=$(stat -c%a "$file_path" 2>/dev/null || echo "unknown")
            modified_time=$(stat -c%Y "$file_path" 2>/dev/null || echo "0")
        fi
    else
        # 降级到ls命令
        local ls_output
        ls_output=$(ls -la "$file_path" 2>/dev/null)
        size=$(echo "$ls_output" | awk '{print $5}')
        permissions=$(echo "$ls_output" | awk '{print $1}')
        modified_time="unknown"
    fi
    
    # 输出格式化信息
    case "$output_format" in
        "json")
            cat <<EOF
{
    "path": "$file_path",
    "type": "$file_type",
    "size": $size,
    "permissions": "$permissions",
    "modified_time": $modified_time,
    "exists": true
}
EOF
            ;;
        "text")
            echo "文件: $file_path"
            echo "类型: $file_type"
            echo "大小: $size 字节"
            echo "权限: $permissions"
            echo "修改时间: $modified_time"
            ;;
        *)
            echo "❌ 错误：未知的输出格式: $output_format" >&2
            return 1
            ;;
    esac
}

# 批量文件操作
file_batch_operation() {
    local operation="$1"        # create/delete/copy/move/backup
    local file_list="$2"        # JSON数组或换行分隔的文件列表
    local operation_options="${3:-}"  # 操作选项
    local fail_fast="${4:-false}"
    
    local success_count=0
    local failed_count=0
    local results="[]"
    
    # 解析文件列表
    local files
    if [[ "$file_list" =~ ^\[.*\]$ ]]; then
        # JSON数组格式
        files=$(echo "$file_list" | jq -r '.[]' 2>/dev/null)
    else
        # 换行分隔格式
        files="$file_list"
    fi
    
    # 遍历文件列表
    while IFS= read -r file_path; do
        [[ -n "$file_path" ]] || continue
        
        local result
        case "$operation" in
            "delete")
                if file_delete_operation "$file_path" >/dev/null 2>&1; then
                    result='{"file": "'$file_path'", "status": "success"}'
                    success_count=$((success_count + 1))
                else
                    result='{"file": "'$file_path'", "status": "failed"}'
                    failed_count=$((failed_count + 1))
                fi
                ;;
            "backup")
                if file_backup_operation "$file_path" >/dev/null 2>&1; then
                    result='{"file": "'$file_path'", "status": "success"}'
                    success_count=$((success_count + 1))
                else
                    result='{"file": "'$file_path'", "status": "failed"}'
                    failed_count=$((failed_count + 1))
                fi
                ;;
            *)
                result='{"file": "'$file_path'", "status": "unsupported"}'
                failed_count=$((failed_count + 1))
                ;;
        esac
        
        results=$(echo "$results" | jq --argjson result "$result" '. += [$result]')
        
        # 快速失败模式
        if [[ "$fail_fast" == "true" && "$failed_count" -gt 0 ]]; then
            break
        fi
    done <<< "$files"
    
    # 输出批量操作结果
    cat <<EOF
{
    "operation": "$operation",
    "success_count": $success_count,
    "failed_count": $failed_count,
    "total_files": $((success_count + failed_count)),
    "results": $results
}
EOF
}