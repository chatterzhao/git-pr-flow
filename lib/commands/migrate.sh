#!/usr/bin/env bash

# Git PR Flow - 配置迁移命令
# 实现 Story 5: 向后兼容和迁移支持

# 引入依赖
source "$(dirname "${BASH_SOURCE[0]}")/../utils/config-context-bridge.sh"

# migrate 命令主函数
cmd_migrate() {
    local action="${1:-check}"
    
    case "$action" in
        "check")
            check_migration_status
            ;;
        "auto")
            auto_migrate_all
            ;;
        "yaml")
            migrate_yaml_configs
            ;;
        "clean")
            clean_old_configs
            ;;
        "status")
            show_migration_status
            ;;
        *)
            show_migrate_help
            ;;
    esac
}

# 检查迁移状态
check_migration_status() {
    echo "🔍 检查配置迁移状态..."
    echo
    
    # 检查新配置系统
    if gpf_project_config_exists; then
        echo "✅ 新配置系统已初始化"
    else
        echo "❌ 新配置系统未初始化"
        echo "   💡 运行 'gpf init' 来初始化"
    fi
    
    # 检查旧YAML文件
    local yaml_files
    yaml_files=$(find .worktrees -name ".git-pr-flow.yaml" 2>/dev/null)
    
    if [[ -n "$yaml_files" ]]; then
        local count=$(echo "$yaml_files" | wc -l)
        echo "⚠️  发现 $count 个旧的YAML配置文件需要迁移:"
        echo "$yaml_files" | while read -r file; do
            echo "   📄 $file"
        done
        echo
        echo "💡 建议运行 'gpf migrate auto' 自动迁移"
    else
        echo "✅ 没有发现需要迁移的YAML配置文件"
    fi
    
    # 建议下一步操作
    if need_migration; then
        echo
        echo "📋 迁移建议:"
        echo "1. 运行 'gpf migrate auto' - 自动迁移所有配置"
        echo "2. 运行 'gpf migrate yaml' - 仅迁移YAML文件"
        echo "3. 运行 'gpf migrate clean' - 清理旧配置文件"
    fi
}

# 自动迁移所有配置
auto_migrate_all() {
    echo "🚀 开始自动配置迁移..."
    echo
    
    # 1. 初始化新配置系统
    if ! gpf_project_config_exists; then
        echo "📁 初始化新配置系统..."
        local base_branch
        base_branch=$(detect_base_branch "project")
        init_project_config "$base_branch"
        echo
    fi
    
    # 2. 迁移YAML配置
    echo "📋 迁移YAML配置文件..."
    migrate_all_yaml_configs
    echo
    
    # 3. 验证迁移结果
    echo "🔍 验证迁移结果..."
    validate_migration
    echo
    
    # 4. 询问是否清理旧文件
    if [[ -t 0 ]]; then  # 交互式环境
        echo "🗑️  是否清理旧的YAML配置文件? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy] ]]; then
            clean_old_configs
        fi
    else
        echo "ℹ️  非交互式环境，跳过清理。手动运行 'gpf migrate clean' 来清理旧文件"
    fi
    
    echo "🎉 配置迁移完成!"
}

# 迁移YAML配置文件
migrate_yaml_configs() {
    echo "📋 迁移YAML配置文件..."
    
    if ! gpf_project_config_exists; then
        echo "❌ 新配置系统未初始化，请先运行 'gpf init'"
        return 1
    fi
    
    migrate_all_yaml_configs
}

# 清理旧配置文件
clean_old_configs() {
    echo "🗑️  清理旧配置文件..."
    
    # 检查备份目录
    if [[ ! -d ".gpf/yaml-backup" ]]; then
        echo "⚠️  没有找到备份目录，为安全起见不进行清理"
        echo "   请确保已备份重要配置后手动删除"
        return 1
    fi
    
    local yaml_files
    yaml_files=$(find .worktrees -name ".git-pr-flow.yaml" 2>/dev/null)
    
    if [[ -z "$yaml_files" ]]; then
        echo "ℹ️  没有找到需要清理的YAML文件"
        return 0
    fi
    
    local count=0
    echo "$yaml_files" | while read -r yaml_file; do
        if [[ -f "$yaml_file" ]]; then
            echo "  🗑️ 删除: $yaml_file"
            rm "$yaml_file"
            ((count++))
        fi
    done
    
    echo "✅ 清理完成，共删除 $count 个YAML配置文件"
    echo "   备份位置: .gpf/yaml-backup/"
}

# 显示迁移状态
show_migration_status() {
    echo "📊 配置迁移状态报告"
    echo "==================="
    echo
    
    # 系统状态
    echo "🔧 配置系统状态:"
    if gpf_project_config_exists; then
        echo "  ✅ 新配置系统: 已初始化"
        echo "  📁 配置目录: .gpf/"
        echo "  📝 主配置: .gpf/config.yaml"
        
        # 检查Epic索引
        if [[ -f ".gpf/epics.yaml" ]]; then
            local epic_count
            epic_count=$(grep -c "name: \"" ".gpf/epics.yaml" 2>/dev/null || echo "0")
            echo "  📋 Epic索引: $epic_count 个Epic"
        fi
    else
        echo "  ❌ 新配置系统: 未初始化"
    fi
    echo
    
    # 旧配置文件状态
    echo "📄 旧配置文件:"
    local yaml_files
    yaml_files=$(find .worktrees -name ".git-pr-flow.yaml" 2>/dev/null)
    
    if [[ -n "$yaml_files" ]]; then
        local count=$(echo "$yaml_files" | wc -l)
        echo "  ⚠️  YAML文件: $count 个待迁移"
        echo "  📁 位置:"
        echo "$yaml_files" | while read -r file; do
            echo "    - $file"
        done
    else
        echo "  ✅ YAML文件: 无需迁移"
    fi
    echo
    
    # 备份状态
    echo "💾 备份状态:"
    if [[ -d ".gpf/yaml-backup" ]]; then
        local backup_count
        backup_count=$(find ".gpf/yaml-backup" -name "*.yaml*" 2>/dev/null | wc -l)
        echo "  ✅ 备份目录: 存在 ($backup_count 个备份文件)"
    else
        echo "  ⚠️  备份目录: 不存在"
    fi
    echo
    
    # 建议操作
    echo "💡 建议操作:"
    if need_migration; then
        echo "  1. 运行 'gpf migrate auto' - 完整自动迁移"
        echo "  2. 运行 'gpf migrate check' - 检查迁移状态"
    else
        echo "  ✅ 配置系统已是最新状态，无需迁移"
        if [[ -n "$yaml_files" ]]; then
            echo "  💡 可运行 'gpf migrate clean' 清理残留的YAML文件"
        fi
    fi
}

# 验证迁移结果
validate_migration() {
    echo "🔍 验证迁移结果..."
    
    local errors=0
    
    # 检查新配置系统
    if ! gpf_project_config_exists; then
        echo "❌ 新配置系统验证失败"
        ((errors++))
    else
        echo "✅ 新配置系统正常"
    fi
    
    # 检查上下文推导
    if ! diagnose_config_system > /dev/null 2>&1; then
        echo "⚠️  上下文推导系统可能有问题"
    else
        echo "✅ 上下文推导系统正常"
    fi
    
    # 检查配置读取
    local test_config
    test_config=$(get_config "workflow_type" "" "gitflow" 2>/dev/null)
    if [[ -n "$test_config" ]]; then
        echo "✅ 配置读取功能正常"
    else
        echo "⚠️  配置读取可能有问题"
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "🎉 迁移验证通过!"
    else
        echo "❌ 迁移验证发现 $errors 个问题"
        return 1
    fi
}

# 显示帮助信息
show_migrate_help() {
    cat << EOF
📋 Git PR Flow 配置迁移工具

用法: gpf migrate <action>

可用操作:
  check     检查迁移状态和需要迁移的文件
  auto      自动迁移所有配置 (推荐)
  yaml      仅迁移YAML配置文件
  clean     清理旧的配置文件 (需要先备份)
  status    显示详细的迁移状态报告

示例:
  gpf migrate check         # 检查是否需要迁移
  gpf migrate auto          # 完整自动迁移
  gpf migrate yaml          # 仅迁移YAML文件
  gpf migrate clean         # 清理旧文件
  gpf migrate status        # 查看迁移状态

注意:
- 迁移会自动备份原文件到 .gpf/yaml-backup/
- 建议在迁移前先运行 'check' 查看状态
- 'auto' 操作包含完整的迁移和验证流程
EOF
}

# 性能基准测试 (Story 6)
benchmark_config_performance() {
    echo "⚡ 配置系统性能基准测试"
    echo "======================"
    echo
    
    local iterations=100
    
    # 测试上下文推导性能
    echo "🎯 上下文推导性能测试 ($iterations 次):"
    local start_time=$(date +%s%N)
    
    for ((i=1; i<=iterations; i++)); do
        detect_current_context > /dev/null 2>&1
    done
    
    local end_time=$(date +%s%N)
    local duration=$((($end_time - $start_time) / 1000000))  # 转换为毫秒
    local avg_time=$(($duration / $iterations))
    
    echo "  总耗时: ${duration}ms"
    echo "  平均耗时: ${avg_time}ms/次"
    echo "  QPS: $((1000 / $avg_time)) 次/秒"
    echo
    
    # 测试配置读取性能
    echo "📖 配置读取性能测试 ($iterations 次):"
    start_time=$(date +%s%N)
    
    for ((i=1; i<=iterations; i++)); do
        get_config "workflow_type" "" "gitflow" > /dev/null 2>&1
    done
    
    end_time=$(date +%s%N)
    duration=$((($end_time - $start_time) / 1000000))
    avg_time=$(($duration / $iterations))
    
    echo "  总耗时: ${duration}ms"
    echo "  平均耗时: ${avg_time}ms/次"
    echo "  QPS: $((1000 / $avg_time)) 次/秒"
    echo
    
    # 性能评价
    if [[ $avg_time -lt 10 ]]; then
        echo "🚀 性能评价: 优秀 (< 10ms)"
    elif [[ $avg_time -lt 50 ]]; then
        echo "⚡ 性能评价: 良好 (< 50ms)"
    elif [[ $avg_time -lt 100 ]]; then
        echo "✅ 性能评价: 可接受 (< 100ms)"
    else
        echo "⚠️  性能评价: 需要优化 (> 100ms)"
    fi
}

# 压力测试
stress_test_config_system() {
    echo "🔥 配置系统压力测试"
    echo "=================="
    echo
    
    local concurrent_processes=10
    local operations_per_process=50
    
    echo "📊 测试参数:"
    echo "  并发进程: $concurrent_processes"
    echo "  每进程操作数: $operations_per_process"
    echo "  总操作数: $((concurrent_processes * operations_per_process))"
    echo
    
    echo "🔄 开始压力测试..."
    local start_time=$(date +%s)
    
    # 启动并发测试
    for ((i=1; i<=concurrent_processes; i++)); do
        (
            for ((j=1; j<=operations_per_process; j++)); do
                # 混合操作测试
                detect_current_context > /dev/null 2>&1
                get_config "workflow_type" > /dev/null 2>&1
                context_detect_current_epic > /dev/null 2>&1
            done
        ) &
    done
    
    # 等待所有后台进程完成
    wait
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local total_ops=$((concurrent_processes * operations_per_process * 3))  # 每个循环3个操作
    local ops_per_sec=$((total_ops / duration))
    
    echo
    echo "📈 压力测试结果:"
    echo "  总耗时: ${duration}s"
    echo "  总操作数: $total_ops"
    echo "  平均QPS: $ops_per_sec 操作/秒"
    echo "  并发性能: $(if [[ $ops_per_sec -gt 1000 ]]; then echo "优秀"; elif [[ $ops_per_sec -gt 500 ]]; then echo "良好"; else echo "需要优化"; fi)"
}