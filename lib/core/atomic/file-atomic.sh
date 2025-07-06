#!/bin/bash
# GPF Core - File Operations Atomic Methods
# 文件操作原子方法 - 单一职责，无副作用，可独立测试

set -euo pipefail

# 检查文件是否存在
# 参数：(file_path)
# 返回：0（存在）或1（不存在）
file_exists() {
    local file_path="$1"
    [[ -f "$file_path" ]]
}

# 检查目录是否存在
# 参数：(dir_path)
# 返回：0（存在）或1（不存在）
dir_exists() {
    local dir_path="$1"
    [[ -d "$dir_path" ]]
}

# 检查文件内容是否包含指定行
# 参数：(file_path, pattern)
# 返回：0（包含）或1（不包含）
file_contains_line() {
    local file_path="$1"
    local pattern="$2"
    
    [[ -f "$file_path" ]] && grep -qF "$pattern" "$file_path"
}

# 检查文件内容是否包含指定正则表达式
# 参数：(file_path, regex_pattern)
# 返回：0（匹配）或1（不匹配）
file_contains_regex() {
    local file_path="$1"
    local regex_pattern="$2"
    
    [[ -f "$file_path" ]] && grep -q "$regex_pattern" "$file_path"
}

# 安全地向文件追加内容（避免重复添加）
# 参数：(file_path, content)
# 返回：0（成功）或1（失败）
file_append_safe() {
    local file_path="$1"
    local content="$2"
    
    # 如果文件不存在，创建它
    if [[ ! -f "$file_path" ]]; then
        echo "$content" > "$file_path"
        return 0
    fi
    
    # 如果内容已存在，不重复添加
    if echo "$content" | grep -qF "$(head -1 <<< "$content")" "$file_path" 2>/dev/null; then
        return 0  # 内容已存在，无需添加
    fi
    
    # 追加内容
    echo "$content" >> "$file_path"
}

# 创建文件备份
# 参数：(file_path, backup_suffix)
# 返回：0（成功）或1（失败）
file_create_backup() {
    local file_path="$1"
    local backup_suffix="${2:-backup}"
    
    if [[ -f "$file_path" ]]; then
        cp "$file_path" "${file_path}.${backup_suffix}"
    fi
}

# 获取文件的绝对路径
# 参数：(file_path)
# 返回：绝对路径字符串
file_get_absolute_path() {
    local file_path="$1"
    
    if [[ -f "$file_path" ]]; then
        local dir_path
        local file_name
        dir_path=$(dirname "$file_path")
        file_name=$(basename "$file_path")
        
        # 获取目录的绝对路径，然后拼接文件名
        echo "$(cd "$dir_path" && pwd)/$file_name"
    else
        # 文件不存在，返回基于当前目录的绝对路径
        local dir_path
        local file_name
        dir_path=$(dirname "$file_path")
        file_name=$(basename "$file_path")
        
        if [[ "$dir_path" == "." ]]; then
            echo "$(pwd)/$file_name"
        else
            echo "$(cd "$dir_path" 2>/dev/null && pwd || echo "$dir_path")/$file_name"
        fi
    fi
}