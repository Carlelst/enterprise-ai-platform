---
name: dify-ragflow-dev
description: Dify + RAGFlow + ef_agent_kits 三项目整合开发技能。覆盖架构导航、开发命令、外部知识 API 代理联调、KB 运维、插件同步、AI Hub 部署、各项目技能调用。Use when 跨项目开发 Dify/RAGFlow/ef_agent_kits、联调 proxy 层、配置外部知识库、排查检索链路、部署或同步环境、操作 KB/模型/AI Hub 容器。
---

# Dify + RAGFlow + ef_agent_kits 整合开发

## 项目位置

| 项目 | 路径 | 定位 |
|------|------|------|
| Dify | `~/.hub/dify/` | AI 平台引擎（LLM 应用编排） |
| RAGFlow | `~/.hub/ragflow/` | 知识库引擎（文档解析+向量检索） |
| ef_agent_kits | `~/.hub/ef_agent_kits/` | 基础设施底座（部署/技能/代理/MCP） |

## 全局架构

```
┌─ Dify (AI 平台) ──────────────────────────────────────────┐
│ 前端 (Next.js) + 后端 (Flask/DDD) + Agent 服务              │
│                                                            │
│ 外部知识检索:                                               │
│   DatasetRetrieval → provider=="external"                  │
│     → ExternalDatasetService → POST /retrieval             │
└───────────────────────┬────────────────────────────────────┘
                        │ Dify External Knowledge API
┌─ Proxy (ef_agent_kits) ───────────────────────────────────┐
│ platform/ragflow/proxy/proxy_server.py                     │
│   Dify {knowledge_id, query, top_k}                        │
│     ⇄ RAGFlow {question, dataset_ids, top_k}              │
└───────────────────────┬────────────────────────────────────┘
                        │ RAGFlow REST API
┌─ RAGFlow (知识库引擎) ─────────────────────────────────────┐
│ 文档解析 → 分块 → 向量化 → ES/Infinity 索引                 │
│ 检索: Dealer (向量+BM25+重排)                               │
└────────────────────────────────────────────────────────────┘
                        │
┌─ ef_agent_kits (基础设施) ─────────────────────────────────┐
│ skills/: wiki/jira/wangpan/ka/graphify                     │
│ platform/: ragflow 工具 / RAG 服务 / KA_bot                 │
│ mcp/: KA MCP Bridge / LangChain Agent                      │
│ tools/eod/: AI Hub 容器化环境 (init_env / podman)           │
│ kits/: Dify 部署 / SSO 认证                                  │
└────────────────────────────────────────────────────────────┘
```

## 开发命令速查

### Dify (`~/.hub/dify/`)

```bash
make format && make lint && make type-check   # 后端三连
make test                                     # 后端 pytest
cd web && pnpm lint:fix && pnpm type-check    # 前端
cd dify-agent && make typecheck && make test  # Agent 服务
```

### RAGFlow (`~/.hub/ragflow/`)

```bash
uv run ruff check && uv run ruff format   # lint
uv run pytest                             # 测试
cd web && npm run lint && npm run test    # 前端
```

### ef_agent_kits (`~/.hub/ef_agent_kits/`)

```bash
./tools/eod/init_env.sh                                  # 环境初始化
./tools/eod/init_env.sh -m /model/scs_qwen3.5-397b       # 指定模型
bash tools/eod/podman/scripts/ai-run.sh                   # 启动 AI 容器
bash tools/eod/podman/tests/run_all_tests.sh              # 回归测试
python3 tools/eod/podman/tests/test_proxy.py              # proxy 测试
git tag ai-hub-vX.Y.Z && git push origin main --tags      # 发布
```

## 环境速查

| 机器 | 服务 | 端口 |
|------|------|------|
| 192.168.20.21 | RAGFlow 测试 / Dify 本地开发 | 8088 / 8086 |
| 10.9.200.12 | AI Platform (Dify 生产) + KA MCP/Agent + SSH Bastion | 8080/8086/8766-8768 |
| 10.9.200.13 | RAGFlow 生产 + Dify 生产 (72核) + Proxy | 8088/8086/8090 |
| 172.16.90.36 | MinIO (对象存储) | 9000 |
| 10.9.200.14 | PostgreSQL (元数据) | 5432 |
| 172.21.6.6 | 模型代理 (LiteLLM) | 4000 |
| 10.9.200.16 | 开发机 (sp.shentao.lu) | - |

SSH 跳板：`ssh -J ai.hse@10.9.200.12 sp.shentao.lu@10.9.200.16`

## 项目结构速查

### Dify 关键路径

| 路径 | 作用 |
|------|------|
| `api/core/rag/retrieval/dataset_retrieval.py` | 检索分流（provider=="external" 分支） |
| `api/services/external_knowledge_service.py` | 外部知识检索编排 |
| `api/models/dataset.py:1390-1479` | ExternalKnowledgeApis / Bindings 模型 |
| `api/controllers/console/datasets/external.py` | REST 控制器 |

### RAGFlow 关键路径

| 路径 | 作用 |
|------|------|
| `rag/nlp/search.py` | Dealer 检索（向量+BM25+重排） |
| `rag/flow/pipeline.py` | 文档 ingestion DAG |
| `deepdoc/parser/` | 格式解析器（PDF/DOCX/MD/HTML） |
| `api/db/db_models.py` | Peewee ORM 模型 |

### ef_agent_kits 关键路径

| 路径 | 作用 |
|------|------|
| `platform/ragflow/` | RAGFlow 工具集（batch_import / proxy / kb_admin / kb_ops_server） |
| `skills/` | wiki/jira/wangpan/ka/graphify 技能 |
| `mcp/ka/` | KA MCP Bridge + Dify KA Client |
| `mcp/ka-agent/` | LangChain EDA Agent |
| `platform/KA_bot/` | 企业微信 Bot（Dify 后端） |
| `platform/Rag/` | RAG Web 服务（FastAPI） |
| `platform/rag-stack/` | 共享 RAG Docker Compose 环境 |
| `kits/dify/` | Dify Docker 部署配置 |
| `tools/eod/` | AI Hub 容器化管理（podman） |

## 跨项目常见任务

### 1. 全链路检索联调（Dify → Proxy → RAGFlow）

```
Dify 调用 → proxy_server.py 转换 → RAGFlow /api/v1/retrieval
```

- Dify 端：检查 `provider=="external"` 分支
- Proxy 端：检查 `_make_ragflow_request` / `_to_dify_records`
- RAGFlow 端：检查 `Dealer.search()` 返回

### 2. KB 运维（批量导入、清理、RAPTOR）

详见 [REFERENCE.md](REFERENCE.md) KB 运维章节，工具在 `ef_agent_kits/platform/ragflow/`。

### 3. 部署 Dify 插件到远程

Dify 插件在本地安装后，通过 `~/.hub/dify/docker/sync-plugins-to-remote.sh` 同步到 10.9.200.13。

### 4. 部署 ef_agent_kits 变更

```bash
git tag ai-hub-vX.Y.Z && git push origin main --tags
# 或手动：
scp -r -o ProxyJump=ai.hse@10.9.200.12 tools/eod/* sp.shentao.lu@10.9.200.16:/path/
```

### 5. KA Agent 开发

位于 `ef_agent_kits/mcp/ka-agent/`，LangChain ReAct 循环 + 多工具编排。Dify 端点：`http://10.9.200.12:8086/v1/chat-messages`。

## 各项目已注册技能

| 技能 | 来源 | 触发场景 |
|------|------|----------|
| ragflow-kb-ops | `~/.agents/skills/` | RAGFlow KB 导入/清理/运维 |
| dify-deploy | `dify/.agents/skills/` | Dify 镜像构建/部署/插件同步 |
| backend-code-review | `dify/.agents/skills/` | Dify 后端代码审查 |
| frontend-code-review | `dify/.agents/skills/` | Dify 前端代码审查 |
| wiki | `ef_agent_kits/skills/` | Wiki (Confluence) 操作 |
| jira | `ef_agent_kits/skills/` | Jira Issue 管理 |
| wangpan | `ef_agent_kits/skills/` | 网盘文件管理 |
| ka | `ef_agent_kits/skills/` | Synopsys EDA 知识库查询 |
| graphify | `ef_agent_kits/skills/` | 代码知识图谱生成 |
| ai-hub | `ef_agent_kits/.agents/skills/` | AI Hub 环境初始化/容器管理 |

## 快速排查

| 症状 | 检查方向 |
|------|----------|
| Dify 外部知识返回空 | proxy 日志 `/tmp/proxy.log`、RAGFlow 可达性 |
| batch_import 失败 | MySQL/Redis/MinIO 连通性、容器内 Python 环境 |
| Proxy 超时 (90s) | 大 KB 检索 → 调高 `REQUEST_TIMEOUT` |
| VLM/Embedding 堵塞 | 172.16.90.45:8082 代理拥塞 → ThreadingMixIn |
| RAGFlow 版本兼容 | 容器版(v0.25.6) ≠ 仓库版(main) |
| Podman 命名空间错误 | 检查 `~/.config/containers/storage.conf` |
| AI Hub 容器无外网 | 预下载二进制到镜像 |
