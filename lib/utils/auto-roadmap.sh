#!/usr/bin/env bash

# Git PR Flow - 自动路线图生成工具
# 在Epic初始化时自动创建roadmap文件

# 为Epic生成路线图文件
generate_epic_roadmap() {
    local epic_name="$1"
    local epic_description="${2:-$epic_name Epic功能开发}"
    local base_branch="${3:-develop}"
    
    # 确保docs/epic目录存在
    if [[ ! -d "docs/epic" ]]; then
        mkdir -p "docs/epic"
    fi
    
    local roadmap_file="docs/epic/${epic_name}-roadmap.md"
    
    # 生成路线图内容
    cat > "$roadmap_file" << EOF
# $epic_name

## 本epic的职责:

请在这里描述这个Epic要解决的核心问题和职责：

- [ ] 具体职责1：请描述
- [ ] 具体职责2：请描述  
- [ ] 具体职责3：请描述

## 计划有哪些子功能

### 子功能1：功能名称1

**创建命令：** \`gpf start $epic_name/feature-name-1\`

**功能描述：**
请描述这个子功能的具体内容

#### 验收标准：
- [ ] 验收标准1
- [ ] 验收标准2
- [ ] 验收标准3

---

### 子功能2：功能名称2

**创建命令：** \`gpf start $epic_name/feature-name-2\`

**功能描述：**
请描述这个子功能的具体内容

#### 验收标准：
- [ ] 验收标准1
- [ ] 验收标准2
- [ ] 验收标准3

---

### 子功能3：功能名称3

**创建命令：** \`gpf start $epic_name/feature-name-3\`

**功能描述：**
请描述这个子功能的具体内容

#### 验收标准：
- [ ] 验收标准1
- [ ] 验收标准2
- [ ] 验收标准3

---

**创建时间：** $(date "+%Y-%m-%d %H:%M:%S")  
**基础分支：** $base_branch
EOF
    
    echo "$roadmap_file"
}