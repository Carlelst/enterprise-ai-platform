---
name: ka
description: Query Synopsys EDA knowledge base via Dify Chat API. Covers VCS, Verdi, PrimeTime, Fusion Compiler, Design Compiler, IC Validator and other Synopsys tools. Use when user asks about Synopsys EDA tool usage, commands, error messages, methodology, or tool comparison.
---

# Dify Chat - Synopsys 知识库问答

## 概述

通过 Shell 脚本查询 Synopsys EDA 工具知识库，覆盖 VCS、Verdi、PrimeTime、Fusion Compiler、Design Compiler、IC Validator 等工具。

## 触发条件

当用户消息涉及以下意图时调用：
- 询问 Synopsys EDA 工具使用方法、命令、选项
- 遇到仿真/综合/时序/物理验证报错需要排查
- 对比不同工具或版本的功能差异
- 咨询 EDA 工具最佳实践或方法论

## Skills 根目录解析

Agent 执行命令前需按以下优先级确定 `$SKILLS_ROOT`：

1. **全局 skills 目录**：`~/.claude/skills/ka/scripts/dify_ka.sh` 存在 → `SKILLS_ROOT=~/.claude/skills`
2. **用户 hub 目录**：`~/.hub/ka/ka/scripts/dify_ka.sh` 存在 → `SKILLS_ROOT=~/.hub/ka`
3. **默认回退**：`SKILLS_ROOT=~/.hub/ka`

解析后确认 `${SKILLS_ROOT}/ka/scripts/dify_ka.sh` 存在再执行。

## 执行入口

```bash
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh query \
    --tool-name <工具名> \
    --tool-version <版本> \
    --query "<用户问题>"
```

| 参数 | 必填 | 说明 |
|------|------|------|
| `--query` | **是** | 用户的完整问题 |
| `--tool-name` | 否 | EDA 工具名，从用户问题推断。详见 [references/tool_mapping.md](references/tool_mapping.md) |
| `--tool-version` | 否 | 工具版本，默认 `Y-2026.03` |
| `--new-session` | 否 | 开启新会话，不复用之前的 conversation_id |

## 命令参考

### 查询知识库 — `query`

```bash
# 基本查询
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh query --query "VCS 编译时报错 undefined reference 怎么办？"

# 指定工具
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh query \
    --tool-name vcs \
    --query "如何在 VCS 中启用 FSDB dump？"

# 指定版本
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh query \
    --tool-name pt \
    --tool-version Y-2025.12 \
    --query "PrimeTime report_timing 支持哪些选项？"

# 开启新会话（不复用之前的上下文）
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh query \
    --new-session \
    --query "Fusion Compiler 的 floorplan 流程是怎样的？"
```

### 清除会话 — `clear`

```bash
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh clear
```

## 用户对话示例

### 示例 1：工具使用查询

**用户：** VCS 编译时遇到 undefined reference 错误怎么解决？

**Agent：** [推断 tool_name=vcs]

```bash
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh query \
    --tool-name vcs \
    --query "VCS 编译时遇到 undefined reference 错误怎么解决？"
```

### 示例 2：追问（自动复用上下文）

**用户：** 那 `-LDFLAGS` 参数具体怎么用？

**Agent：** [不传 --new-session，自动复用 conversation_id]

```bash
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh query \
    --tool-name vcs \
    --query "-LDFLAGS 参数具体怎么用？"
```

### 示例 3：跨工具查询

**用户：** PrimeTime 怎么做多 corner 时序分析？

**Agent：** [推断 tool_name=pt]

```bash
bash ${SKILLS_ROOT}/ka/scripts/dify_ka.sh query \
    --new-session \
    --tool-name pt \
    --query "PrimeTime 怎么做多 corner 时序分析？"
```

> 跨工具时应加 `--new-session` 清空上轮上下文，因为工具已切换。

## Agent 执行指南

### 执行规则

1. **首先解析 `$SKILLS_ROOT`**：参照上文章节确定路径
2. **推断 tool_name**：根据用户问题中的关键词映射，详见 [references/tool_mapping.md](references/tool_mapping.md)
3. **默认版本**：未指定时使用 `Y-2026.03`
4. **追问复用上下文**：同一话题的追问不加 `--new-session`，跨工具时加
5. **结果整理呈现**：脚本返回 `answer` 字段内容，Agent 用中文整理后呈现

### 常见场景映射

| 用户问题 | 执行命令 |
|---------|---------|
| "VCS 编译报错 XXX" | `query --tool-name vcs --query "VCS 编译报错 XXX"` |
| "Verdi 怎么看波形" | `query --tool-name verdi --query "Verdi 怎么看波形"` |
| "PT 时序分析命令" | `query --tool-name pt --query "PT 时序分析命令"` |
| "DC 综合选项有哪些" | `query --tool-name dc --query "DC 综合选项有哪些"` |
| "FC floorplan 怎么设" | `query --tool-name fc --query "FC floorplan 怎么设"` |
| "ICV DRC 检查流程" | `query --tool-name icv --query "ICV DRC 检查流程"` |
| "清除知识库会话" | `clear` |

## 配置

技能依赖 `${SKILLS_ROOT}/ka/config.yaml`：

```yaml
auth:
  token: "app-bvjMDhHFvU3oKF5NwtDjXYCI"
base_url: "http://10.9.200.12:8086"
```

| 配置项 | 说明 |
|--------|------|
| `auth.token` | Dify API 访问令牌 |
| `base_url` | Dify Chat API 地址 |

## 依赖

- bash 4.0+
- curl
- jq
- python3
