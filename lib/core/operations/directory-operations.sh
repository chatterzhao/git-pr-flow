#!/bin/bash
# GPF 目录操作层 - 纯目录系统操作，无业务逻辑
# 提供安全的目录操作原语，包含路径验证和rollback机制

set -euo pipefail

# ==============================================================================
# 目录操作层 - 核心原语
# ==============================================================================

# 目录创建操作
directory_create_operation() {
    local dir_path="$1"
    local create_parents="${2:-true}"
    local mode="${3:-755}"
    local backup_existing="${4:-false}"
    
    # 前置安全检查
    [[ -n "$dir_path" ]] || {
        echo "❌ 错误：目录路径不能为空" >&2
        return 1
    }
    
    # 验证路径安全性
    directory_validate_path_safety "$dir_path" || return 1
    
    # 检查目录是否已存在
    if [[ -d "$dir_path" ]]; then
        echo "⚠️ 警告：目录已存在: $dir_path"
        return 0
    fi
    
    # 如果存在同名文件，处理冲突
    if [[ -e "$dir_path" ]]; then
        if [[ "$backup_existing" == "true" ]]; then
            local backup_path="${dir_path}.backup"
            mv "$dir_path" "$backup_path" || {
                echo "❌ 错误：无法备份现有文件: $dir_path" >&2
                return 1
            }
            echo "🔄 Rollback信息: mv $backup_path $dir_path" >&2
        else
            echo "❌ 错误：路径已被文件占用: $dir_path" >&2
            return 1
        fi
    fi
    
    # 构造mkdir参数
    local mkdir_args=()
    [[ "$create_parents" == "true" ]] && mkdir_args+=("-p")
    mkdir_args+=("-m" "$mode")
    mkdir_args+=("$dir_path")
    
    # 执行目录创建
    if mkdir "${mkdir_args[@]}" 2>/dev/null; then
        echo "✅ 成功创建目录: $dir_path"
        echo "🔄 Rollback信息: rmdir $dir_path" >&2
        return 0
    else
        echo "❌ 创建目录失败: $dir_path" >&2
        return 1
    fi
}

# 目录删除操作
directory_delete_operation() {
    local dir_path="$1"
    local force_delete="${2:-false}"
    local backup_before_delete="${3:-true}"
    local recursive="${4:-false}"
    
    # 前置安全检查
    [[ -n "$dir_path" ]] || {
        echo "❌ 错误：目录路径不能为空" >&2
        return 1
    }
    
    # 验证路径安全性
    directory_validate_path_safety "$dir_path" || return 1
    
    # 检查目录存在性
    if [[ ! -d "$dir_path" ]]; then
        echo "⚠️ 警告：目录不存在，跳过删除: $dir_path"
        return 0
    fi
    
    # 安全检查：重要目录保护
    if [[ "$force_delete" != "true" ]]; then
        directory_check_important_directory "$dir_path" || {
            echo "❌ 错误：重要目录受保护，使用force_delete=true强制删除" >&2
            return 1
        }
    fi
    
    # 检查目录是否为空（非递归模式）
    if [[ "$recursive" != "true" ]]; then
        if [[ -n "$(ls -A "$dir_path" 2>/dev/null)" ]]; then
            echo "❌ 错误：目录非空，使用recursive=true递归删除" >&2
            return 1
        fi
    fi
    
    # 创建备份（用于rollback）
    local backup_path=""
    if [[ "$backup_before_delete" == "true" && "$recursive" == "true" ]]; then
        backup_path="${dir_path}.backup.$(date +%s)"
        if cp -r "$dir_path" "$backup_path" 2>/dev/null; then
            echo "📦 已创建备份: $backup_path" >&2
        else
            echo "⚠️ 警告：无法创建备份，继续删除操作" >&2
            backup_path=""
        fi
    fi
    
    # 执行删除操作
    local delete_command
    if [[ "$recursive" == "true" ]]; then
        delete_command="rm -rf"
    else
        delete_command="rmdir"
    fi
    
    if $delete_command "$dir_path" 2>/dev/null; then
        echo "✅ 成功删除目录: $dir_path"
        [[ -n "$backup_path" ]] && \
            echo "🔄 Rollback信息: mv $backup_path $dir_path" >&2
        return 0
    else
        echo "❌ 删除目录失败: $dir_path" >&2
        return 1
    fi
}

# 目录切换操作
directory_change_operation() {
    local target_dir="$1"
    local create_if_not_exists="${2:-false}"
    local verify_change="${3:-true}"
    
    # 前置安全检查
    [[ -n "$target_dir" ]] || {
        echo "❌ 错误：目标目录不能为空" >&2
        return 1
    }
    
    # 验证路径安全性
    directory_validate_path_safety "$target_dir" || return 1
    
    # 保存当前目录作为rollback点
    local original_dir
    original_dir=$(pwd)
    
    # 处理目录不存在的情况
    if [[ ! -d "$target_dir" ]]; then
        if [[ "$create_if_not_exists" == "true" ]]; then
            directory_create_operation "$target_dir" || {
                echo "❌ 错误：无法创建目标目录: $target_dir" >&2
                return 1
            }
        else
            echo "❌ 错误：目标目录不存在: $target_dir" >&2
            return 1
        fi
    fi
    
    # 执行目录切换
    if cd "$target_dir" 2>/dev/null; then
        # 验证切换结果
        if [[ "$verify_change" == "true" ]]; then
            local current_dir
            current_dir=$(pwd)
            local target_real_path
            target_real_path=$(realpath "$target_dir" 2>/dev/null || echo "$target_dir")
            
            if [[ "$current_dir" != "$target_real_path" ]]; then
                echo "❌ 错误：目录切换验证失败" >&2
                cd "$original_dir" 2>/dev/null || true
                return 1
            fi
        fi
        
        echo "✅ 成功切换到目录: $target_dir"
        echo "🔄 Rollback信息: cd $original_dir" >&2
        return 0
    else
        echo "❌ 切换目录失败: $target_dir" >&2
        return 1
    fi
}

# 目录列表操作
directory_list_operation() {
    local target_dir="${1:-$(pwd)}"
    local list_format="${2:-default}"      # default/long/json/tree
    local show_hidden="${3:-false}"
    local recursive="${4:-false}"
    
    # 验证目录存在性
    [[ -d "$target_dir" ]] || {
        echo "❌ 错误：目录不存在: $target_dir" >&2
        return 1
    }
    
    # 构造列表参数
    case "$list_format" in
        "default")
            local ls_args=()
            [[ "$show_hidden" == "true" ]] && ls_args+=("-a")
            [[ "$recursive" == "true" ]] && ls_args+=("-R")
            
            ls "${ls_args[@]}" "$target_dir" 2>/dev/null || {
                echo "❌ 列出目录内容失败: $target_dir" >&2
                return 1
            }
            ;;
        "long")
            local ls_args=("-l")
            [[ "$show_hidden" == "true" ]] && ls_args+=("-a")
            [[ "$recursive" == "true" ]] && ls_args+=("-R")
            
            ls "${ls_args[@]}" "$target_dir" 2>/dev/null || {
                echo "❌ 列出目录内容失败: $target_dir" >&2
                return 1
            }
            ;;
        "json")
            directory_list_to_json "$target_dir" "$show_hidden" "$recursive"
            ;;
        "tree")
            if command -v tree >/dev/null 2>&1; then
                local tree_args=()
                [[ "$show_hidden" == "true" ]] && tree_args+=("-a")
                [[ "$recursive" != "true" ]] && tree_args+=("-L" "1")
                
                tree "${tree_args[@]}" "$target_dir" 2>/dev/null || {
                    echo "❌ 树形显示失败: $target_dir" >&2
                    return 1
                }
            else
                echo "⚠️ tree命令不可用，使用默认格式" >&2
                directory_list_operation "$target_dir" "default" "$show_hidden" "$recursive"
            fi
            ;;
        *)
            echo "❌ 错误：未知的列表格式: $list_format" >&2
            return 1
            ;;
    esac
}

# 目录存在性检查操作
directory_exists_operation() {
    local dir_path="$1"
    local output_format="${2:-boolean}"  # boolean/json/text
    
    # 前置安全检查
    [[ -n "$dir_path" ]] || {
        echo "❌ 错误：目录路径不能为空" >&2
        return 1
    }
    
    local exists="false"
    [[ -d "$dir_path" ]] && exists="true"
    
    case "$output_format" in
        "boolean")
            [[ "$exists" == "true" ]]
            ;;
        "json")
            cat <<EOF
{
    "path": "$dir_path",
    "exists": $exists,
    "type": "directory"
}
EOF
            ;;
        "text")
            if [[ "$exists" == "true" ]]; then
                echo "目录存在: $dir_path"
            else
                echo "目录不存在: $dir_path"
            fi
            ;;
        *)
            echo "❌ 错误：未知的输出格式: $output_format" >&2
            return 1
            ;;
    esac
}

# ==============================================================================
# 辅助操作方法
# ==============================================================================

# 验证目录路径安全性
directory_validate_path_safety() {
    local dir_path="$1"
    
    # 检查路径为空
    [[ -n "$dir_path" ]] || {
        echo "❌ 目录路径不能为空" >&2
        return 1
    }
    
    # 防止路径遍历攻击
    if [[ "$dir_path" =~ \.\./|^/ ]]; then
        echo "❌ 不安全的目录路径: $dir_path" >&2
        return 1
    fi
    
    # 检查系统保留目录
    local system_dirs=("/bin" "/sbin" "/usr" "/etc" "/var" "/tmp" "/sys" "/proc" "/dev")
    for sys_dir in "${system_dirs[@]}"; do
        if [[ "$dir_path" == "$sys_dir"* ]]; then
            echo "❌ 不能操作系统目录: $dir_path" >&2
            return 1
        fi
    done
    
    # 检查相对路径的保留名称
    local basename_dir
    basename_dir=$(basename "$dir_path")
    local reserved_names=("." ".." ".git")
    
    for reserved in "${reserved_names[@]}"; do
        if [[ "$basename_dir" == "$reserved" ]]; then
            echo "❌ 不能操作保留目录: $basename_dir" >&2
            return 1
        fi
    done
    
    return 0
}

# 检查重要目录保护
directory_check_important_directory() {
    local dir_path="$1"
    
    # 重要目录列表
    local important_dirs=(
        ".git"
        "node_modules"
        "vendor"
        "dist"
        "build"
        ".venv"
        "venv"
        "__pycache__"
        ".pytest_cache"
        ".mypy_cache"
        "target"  # Rust
        "bin"     # Go
        "pkg"     # Go
        ".next"   # Next.js
        ".nuxt"   # Nuxt.js
        "coverage"
        ".coverage"
        "logs"
        "tmp"
        "temp"
        ".DS_Store"
        "Thumbs.db"
    )
    
    local basename_dir
    basename_dir=$(basename "$dir_path")
    
    for important in "${important_dirs[@]}"; do
        if [[ "$basename_dir" == "$important" ]]; then
            return 1  # 目录受保护
        fi
    done
    
    # 检查是否为项目根目录
    if [[ -f "$dir_path/package.json" || -f "$dir_path/Cargo.toml" || -f "$dir_path/go.mod" || -f "$dir_path/requirements.txt" ]]; then
        return 1  # 项目根目录受保护
    fi
    
    return 0  # 目录不受保护
}

# 获取目录信息
directory_get_info() {
    local dir_path="$1"
    local output_format="${2:-json}"
    
    # 检查目录存在性
    [[ -d "$dir_path" ]] || {
        echo "❌ 目录不存在: $dir_path" >&2
        return 1
    }
    
    # 获取目录信息
    local item_count permissions modified_time size
    item_count=$(ls -1 "$dir_path" 2>/dev/null | wc -l | tr -d ' ')
    
    if command -v stat >/dev/null 2>&1; then
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS版本
            permissions=$(stat -f%Mp%Lp "$dir_path" 2>/dev/null || echo "unknown")
            modified_time=$(stat -f%m "$dir_path" 2>/dev/null || echo "0")
            size=$(du -s "$dir_path" 2>/dev/null | cut -f1 || echo "0")
        else
            # Linux版本
            permissions=$(stat -c%a "$dir_path" 2>/dev/null || echo "unknown")
            modified_time=$(stat -c%Y "$dir_path" 2>/dev/null || echo "0")
            size=$(du -s "$dir_path" 2>/dev/null | cut -f1 || echo "0")
        fi
    else
        # 降级处理
        local ls_output
        ls_output=$(ls -la "$dir_path/.." 2>/dev/null | grep " $(basename "$dir_path")$" | head -1)
        permissions=$(echo "$ls_output" | awk '{print $1}')
        modified_time="unknown"
        size="unknown"
    fi
    
    # 输出格式化信息
    case "$output_format" in
        "json")
            cat <<EOF
{
    "path": "$dir_path",
    "type": "directory",
    "item_count": $item_count,
    "size": "$size",
    "permissions": "$permissions",
    "modified_time": $modified_time,
    "exists": true
}
EOF
            ;;
        "text")
            echo "目录: $dir_path"
            echo "项目数量: $item_count"
            echo "大小: $size KB"
            echo "权限: $permissions"
            echo "修改时间: $modified_time"
            ;;
        *)
            echo "❌ 错误：未知的输出格式: $output_format" >&2
            return 1
            ;;
    esac
}

# 将目录列表转换为JSON格式
directory_list_to_json() {
    local target_dir="$1"
    local show_hidden="$2"
    local recursive="$3"
    
    local items="[]"
    
    # 构造find参数
    local find_args=("$target_dir")
    if [[ "$recursive" != "true" ]]; then
        find_args+=("-maxdepth" "1")
    fi
    
    if [[ "$show_hidden" != "true" ]]; then
        find_args+=("-not" "-path" "*/.*")
    fi
    
    # 遍历目录项
    while IFS= read -r item_path; do
        [[ "$item_path" != "$target_dir" ]] || continue  # 跳过目录本身
        
        local item_name item_type item_size
        item_name=$(basename "$item_path")
        
        if [[ -d "$item_path" ]]; then
            item_type="directory"
            item_size=$(du -s "$item_path" 2>/dev/null | cut -f1 || echo "0")
        elif [[ -f "$item_path" ]]; then
            item_type="file"
            if command -v stat >/dev/null 2>&1; then
                if [[ "$(uname)" == "Darwin" ]]; then
                    item_size=$(stat -f%z "$item_path" 2>/dev/null || echo "0")
                else
                    item_size=$(stat -c%s "$item_path" 2>/dev/null || echo "0")
                fi
            else
                item_size=$(ls -la "$item_path" 2>/dev/null | awk '{print $5}' || echo "0")
            fi
        else
            item_type="other"
            item_size="0"
        fi
        
        local item_obj
        item_obj=$(cat <<EOF
{
    "name": "$item_name",
    "path": "$item_path",
    "type": "$item_type",
    "size": $item_size
}
EOF
        )
        items=$(echo "$items" | jq --argjson obj "$item_obj" '. += [$obj]')
        
    done < <(find "${find_args[@]}" 2>/dev/null | sort)
    
    cat <<EOF
{
    "directory": "$target_dir",
    "item_count": $(echo "$items" | jq 'length'),
    "items": $items
}
EOF
}

# 创建目录结构
directory_create_structure() {
    local structure_def="$1"    # JSON格式的目录结构定义
    local base_path="${2:-$(pwd)}"
    local dry_run="${3:-false}"
    
    local created_count=0
    local failed_count=0
    
    # 解析结构定义
    echo "$structure_def" | jq -c '.[]' 2>/dev/null | while read -r dir_def; do
        local dir_path mode
        dir_path=$(echo "$dir_def" | jq -r '.path')
        mode=$(echo "$dir_def" | jq -r '.mode // "755"')
        
        local full_path="$base_path/$dir_path"
        
        if [[ "$dry_run" == "true" ]]; then
            echo "🔍 会创建目录: $full_path (模式: $mode)"
        else
            if directory_create_operation "$full_path" "true" "$mode" >/dev/null 2>&1; then
                created_count=$((created_count + 1))
                echo "✅ 已创建: $full_path"
            else
                failed_count=$((failed_count + 1))
                echo "❌ 创建失败: $full_path"
            fi
        fi
    done
    
    if [[ "$dry_run" != "true" ]]; then
        echo "📊 创建统计: 成功 $created_count, 失败 $failed_count"
    fi
}

# 清理空目录
directory_cleanup_empty() {
    local target_dir="${1:-$(pwd)}"
    local recursive="${2:-true}"
    local dry_run="${3:-false}"
    
    local cleanup_count=0
    
    echo "🧹 清理空目录: $target_dir"
    
    # 构造find参数
    local find_args=("$target_dir" "-type" "d" "-empty")
    [[ "$recursive" != "true" ]] && find_args=("$target_dir" "-maxdepth" "1" "-type" "d" "-empty")
    
    # 查找并处理空目录
    while IFS= read -r empty_dir; do
        [[ "$empty_dir" != "$target_dir" ]] || continue  # 不删除根目录
        
        if [[ "$dry_run" == "true" ]]; then
            echo "🔸 会删除空目录: $empty_dir"
        else
            if rmdir "$empty_dir" 2>/dev/null; then
                cleanup_count=$((cleanup_count + 1))
                echo "  🗑️ 已删除: $empty_dir"
            fi
        fi
    done < <(find "${find_args[@]}" 2>/dev/null | sort -r)  # 逆序处理，先删除深层目录
    
    if [[ "$dry_run" == "true" ]]; then
        echo "🔍 Dry run完成"
    else
        echo "✅ 清理完成，删除了 $cleanup_count 个空目录"
    fi
}