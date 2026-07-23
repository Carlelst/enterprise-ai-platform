# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->


## Build & Test

### 本地开发

```bash
# Dify
cd dify/docker && ./start-local.sh --depts

# RAGFlow
cd ragflow/docker && docker compose -f docker-compose.yml -f docker-compose-base.yml up -d
```

### 部署到远程(无外网)

```bash
cd deploy

# 干跑
./deploy.sh <dify|ragflow> --dry-run

# 全量部署
./deploy.sh <dify|ragflow> --target 10.9.200.13 --start

# 只更新配置(快)
./deploy.sh <dify|ragflow> --target 10.9.200.13 --skip-images --start

# 全部
./deploy.sh all --target 10.9.200.13 --start
```

详见 `deploy/README.md`

## Architecture Overview

```
.hub/                           # 项目根(本仓库)
├── deploy/                     # 统一部署框架
│   ├── deploy.sh               #   入口 CLI
│   ├── lib/common.sh           #   共享函数库
│   └── components/             #   组件配置(每个组件一个 .conf)
│       ├── dify/dify.conf
│       └── ragflow/ragflow.conf
├── dify/                       # Dify 源码(git sub-repo)
│   └── docker/                 #   docker-compose 部署
├── ragflow/                    # RAGFlow 源码(git sub-repo)
│   └── docker/                 #   docker-compose 部署
│       └── docker-compose.remote.yml  # 远程精简版 compose
└── ka/                         # KA 工具相关
```

**部署拓扑(10.9.200.13):**
- Dify: `/opt/dify/docker/` — docker-compose 管理, 端口 8086
- RAGFlow: `/opt/ragflow/docker/` — docker-compose 管理, 端口 8088/9380/9381
- 共享: Dify 的 Redis (Dify 用 db 0, RAGFlow 用 db 1), Docker 网络 `dify_default`
- 桥接: Dify Proxy (:8090) 适配 Dify 外部知识库 API → RAGFlow

## Conventions & Patterns

- 镜像命名: `<组件>-<角色>:v<上游版本>-<补丁序号>` (如 `dify-api:v1.14.1-p1`)
- 部署: 本地构建+测试 → `deploy.sh` 离线传输 → 远程 `docker-compose up`
- 配置变更: 用 `--skip-images` 跳过镜像传输, 秒级部署
