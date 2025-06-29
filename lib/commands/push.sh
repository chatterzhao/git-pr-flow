#!/usr/bin/env bash

# Git PR Flow - 智能推送命令
# 提供适配不同Git配置的智能推送功能

# 引入依赖
source "$(dirname "${BASH_SOURCE[0]}")/../utils/ui.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../utils/smart-push.sh"

# 主命令函数
cmd_push() {
    # 调用智能推送接口
    gpf_smart_push "$@"
}