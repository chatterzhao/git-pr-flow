#!/bin/bash
# NewGPF Core - Platform Utilities
# 跨平台兼容性工具方法

set -euo pipefail

# 检测当前操作系统平台
# 返回：macos|linux|windows|unknown
detect_platform() {
    case "$(uname -s 2>/dev/null || echo 'Unknown')" in
        Darwin*)    echo "macos" ;;
        Linux*)     echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

# 获取平台特定的路径分隔符
# 返回：路径分隔符字符
get_path_separator() {
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")  echo "\\" ;;
        *)          echo "/" ;;
    esac
}

# 检查是否到达根路径
# 参数：(path)
# 返回：0（是根路径）或1（不是根路径）
is_root_path() {
    local path="$1"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")
            # Windows根路径：C:\, D:\, etc.
            [[ "$path" =~ ^[A-Za-z]:[\\]?$ ]]
            ;;
        *)
            # Unix-like根路径：/
            [[ "$path" == "/" ]]
            ;;
    esac
}

# 标准化路径分隔符
# 参数：(path)
# 返回：标准化后的路径
normalize_path_separators() {
    local path="$1"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")
            # 将正斜杠转换为反斜杠
            echo "$path" | sed 's|/|\\|g'
            ;;
        *)
            # 将反斜杠转换为正斜杠
            echo "$path" | sed 's|\\|/|g'
            ;;
    esac
}

# 跨平台的路径连接
# 参数：(base_path, sub_path)
# 返回：连接后的路径
join_paths() {
    local base_path="$1"
    local sub_path="$2"
    local separator
    separator=$(get_path_separator)
    
    # 移除base_path的尾部分隔符
    base_path="${base_path%/}"
    base_path="${base_path%\\}"
    
    # 移除sub_path的前导分隔符
    sub_path="${sub_path#/}"
    sub_path="${sub_path#\\}"
    
    echo "${base_path}${separator}${sub_path}"
}

# 检查路径是否包含指定子路径
# 参数：(full_path, sub_path_pattern)
# 返回：0（包含）或1（不包含）
path_contains() {
    local full_path="$1"
    local sub_path_pattern="$2"
    
    # 标准化路径分隔符进行比较
    local normalized_full
    local normalized_pattern
    normalized_full=$(normalize_path_separators "$full_path")
    normalized_pattern=$(normalize_path_separators "$sub_path_pattern")
    
    [[ "$normalized_full" == *"$normalized_pattern"* ]]
}

# 检查路径是否以指定路径开头
# 参数：(full_path, prefix_path)
# 返回：0（是）或1（不是）
path_starts_with() {
    local full_path="$1"
    local prefix_path="$2"
    
    # 标准化路径分隔符进行比较
    local normalized_full
    local normalized_prefix
    normalized_full=$(normalize_path_separators "$full_path")
    normalized_prefix=$(normalize_path_separators "$prefix_path")
    
    # 确保前缀路径以分隔符结尾，避免部分匹配
    local separator
    separator=$(get_path_separator)
    if [[ "$normalized_prefix" != *"$separator" ]]; then
        normalized_prefix="${normalized_prefix}${separator}"
    fi
    
    [[ "$normalized_full" == "$normalized_prefix"* ]]
}

# 获取绝对路径
# 参数：(path)
# 返回：绝对路径
get_absolute_path() {
    local path="$1"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")
            # Windows: 使用realpath或readlink -f（如果可用）
            if command -v realpath >/dev/null 2>&1; then
                realpath "$path" 2>/dev/null
            elif command -v readlink >/dev/null 2>&1; then
                readlink -f "$path" 2>/dev/null
            else
                # 回退方案：使用pwd
                (cd "$path" 2>/dev/null && pwd) || echo "$path"
            fi
            ;;
        *)
            # Unix-like: 使用realpath、readlink或pwd
            if command -v realpath >/dev/null 2>&1; then
                realpath "$path" 2>/dev/null
            elif command -v readlink >/dev/null 2>&1; then
                readlink -f "$path" 2>/dev/null
            else
                # 回退方案：使用pwd
                (cd "$path" 2>/dev/null && pwd) || echo "$path"
            fi
            ;;
    esac
}

# 跨平台的父目录获取
# 参数：(path)
# 返回：父目录路径
get_parent_directory() {
    local path="$1"
    
    # 使用dirname，它在大多数平台上都能正常工作
    dirname "$path"
}

# 验证路径格式是否有效
# 参数：(path)
# 返回：0（有效）或1（无效）
validate_path_format() {
    local path="$1"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")
            # Windows路径验证：检查是否包含非法字符
            if [[ "$path" =~ [\<\>\:\"\|\?\*] ]]; then
                return 1
            fi
            ;;
        *)
            # Unix-like路径验证：检查是否包含空字符
            if [[ "$path" =~ $'\0' ]]; then
                return 1
            fi
            ;;
    esac
    
    return 0
}

# 平台特定的临时目录获取
# 返回：临时目录路径
get_temp_directory() {
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")
            echo "${TEMP:-${TMP:-C:\\temp}}"
            ;;
        *)
            echo "${TMPDIR:-/tmp}"
            ;;
    esac
}

# 平台特定的用户主目录获取
# 返回：用户主目录路径
get_home_directory() {
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        "windows")
            echo "${USERPROFILE:-${HOME:-C:\\Users\\$(whoami)}}"
            ;;
        *)
            echo "${HOME:-/home/$(whoami)}"
            ;;
    esac
}