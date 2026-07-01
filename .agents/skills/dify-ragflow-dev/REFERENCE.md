# Dify + RAGFlow + ef_agent_kits — 详细参考

## 凭据统览

| 服务 | 凭据 |
|------|------|
| RAGFlow API | key: `ragflow-307044760fae4f548209426ba6191d9e` |
| RAGFlow KB (wiki) | id: `abfeeC35Ff4AfcDfF5Fa88b8D38Fb4Ce` |
| MySQL (ragflow) | root / infini_rag_flow |
| MySQL (dify) | 见 `dify/docker/.env` |
| MinIO | minioadmin / minioadmin @ 172.16.90.36:9000, bucket: rag-data |
| PG (metadata) | postgres / enflame @ 10.9.200.14:5432, db: metadata |
| Elasticsearch | elastic / Changeme123! |
| Redis | Redispw123! |
| Dify KA Key | `app-QBq16zEi03iM1VG8rScdpmbH` |
| Dify 平台 | admin@enflame.cn / EnflameAdmin123! |
| VLLM API | http://172.16.90.45:8082/v1 (scs_qwen3.5-397b) |
| Embedding | qwen3-vl-embedding-8b (源头 10.12.116.244:8006) |
| Model Proxy | 172.21.6.6:4000 (LiteLLM 风格) |
| SSO (Authing) | app_id: `668b55e3eda6f12f6de169fe` @ sso.enflame.cn |

## Dify 架构

### 目录

```
~/.hub/dify/
├── api/                    # Python Flask 后端（DDD 架构）
│   ├── core/               # 领域核心（RAG/Agent/Model/Workflow）
│   ├── models/             # SQLAlchemy 模型
│   ├── services/           # 业务服务层
│   ├── controllers/        # REST 控制器
│   ├── tasks/              # Celery 异步任务
│   └── tests/              # pytest
├── web/                    # Next.js 前端
├── dify-agent/             # 独立 Agent 服务（Python/Pydantic/Protocol）
├── docker/                 # 部署 + 插件同步脚本
└── sdks/                   # Node 等 SDK
```

### 分层架构

```
Controller → Service → Core/Domain → Model/ORM → Libs/Extensions
```

### 外部知识 API 对接

**Dify 侧配置：**
1. 创建 API 模板：`POST /datasets/external-knowledge-api` → `{name, settings: {endpoint, api_key}}`
2. 创建外部数据集：`POST /datasets/external` → `{external_knowledge_api_id, external_knowledge_id, name}`

**Dify 请求格式（POST /retrieval）：**
```json
{
  "knowledge_id": "abfeeC35Ff4AfcDfF5Fa88b8D38Fb4Ce",
  "query": "用户的搜索问题",
  "retrieval_setting": {"top_k": 10, "score_threshold": 0.0}
}
```

**Dify 期望响应：**
```json
{
  "records": [{
    "content": "chunk 文本",
    "score": 0.9123,
    "title": "文档标题",
    "metadata": {"document_id": "xxx", "dataset_id": "xxx", "source_url": "http://..."}
  }]
}
```

### 检索分流

`api/core/rag/retrieval/dataset_retrieval.py`:
- `provider == "external"` → `ExternalDatasetService.fetch_external_knowledge_retrieval()`
- 否则 → 内部向量/关键字/混合检索

## RAGFlow 架构

### 目录

```
~/.hub/ragflow/
├── api/                    # Quart API（Peewee ORM）
├── rag/                    # 核心 RAG（flow/nlp/llm/graphrag）
├── deepdoc/                # 文档解析（PDF/DOCX/XLSX/MD/HTML/图片）
├── agent/                  # Agent 工作流引擎（canvas/component/templates）
├── web/                    # React 前端
└── docker/                 # Docker 部署
```

### 运行时双进程

- **API Server** (`api/ragflow_server.py`)：Quart 异步 HTTP
- **Task Executors** (`rag/svr/task_executor.py`)：Redis 驱动后台 Worker，数量由 `WS` 控制

### Document Ingestion 流水线

```
File → Parser(deepdoc) → Chunker → Tokenizer → Embedding → Index(ES/Infinity)
```

### 检索算法

`rag/nlp/search.py` — Dealer：向量检索 + BM25 关键词 + Reranker 融合

### 容器版(v0.25.6) ≠ 仓库版(main)

`docker cp` 代码进容器可能不兼容，修复需用同版本源文件。

## ef_agent_kits 架构

### 目录

```
~/.hub/ef_agent_kits/
├── skills/                 # Agent 技能（wiki/jira/wangpan/ka/graphify）
├── platform/               # 平台级服务
│   ├── ragflow/            #   RAGFlow 工具集（batch_import / proxy / kb_admin / kb_ops_server）
│   ├── Rag/                #   RAG Web 服务（FastAPI, 爬虫管理）
│   ├── KA_bot/             #   企业微信 Bot（Dify 后端）
│   └── rag-stack/          #   共享 RAG Docker Compose（ES/Redis/LightRAG/RAGFlow/MySQL）
├── mcp/                    # MCP 协议组件
│   ├── ka/                 #   KA MCP Bridge + Dify KA Client + 工作流代理
│   └── ka-agent/           #   LangChain EDA Agent（ReAct + 多工具）
├── kits/                   # 核心套装
│   ├── dify/               #   Dify Docker 部署配置
│   └── sso/                #   SSO 认证（Authing OAuth2 + LDAP/AD）
├── tools/eod/              # AI Hub 容器化管理
│   ├── init_env.sh         #   环境初始化（模型切换/podman/config 同步）
│   ├── models.yaml         #   模型配置
│   └── podman/             #   容器构建/部署/启动脚本
├── cli/                    # 运维 CLI
├── examples/               # 示例和模板
└── plugins/                # Claude Code 插件
```

### AI Hub 容器化

AI 开发工具运行在 Podman 容器（Ubuntu 24.04）中：
```bash
./tools/eod/init_env.sh                      # 交互式初始化
./tools/eod/init_env.sh -m /model/scs_qwen3.5-397b  # 指定模型
bash tools/eod/podman/scripts/ai-run.sh       # 启动容器
```

容器内挂载：`$HOME`, `/AI`, `/tools`, `/edatools` (rw)

### 模型配置 (models.yaml)

所有模型通过内部代理 `http://172.21.6.6:4000` (LiteLLM 风格) 访问：
- `deepseek-v4-pro` (默认 opus/sonnet/haiku)
- `glm-5.2`
- `kimi-k2.7-code`
- `scs_qwen3.5-397b`
- `mixture_model` (按角色自动路由)

### 技能列表

| 技能 | 路径 | 功能 |
|------|------|------|
| wiki | `skills/wiki/` | Confluence REST API (11 命令) |
| jira | `skills/jira/` | Jira Server 9.2.0 Issue CRUD + JQL |
| wangpan | `skills/wangpan/` | 网盘文件管理 |
| ka | `skills/ka/` | Synopsys EDA 知识库（14 工具） |
| graphify | `skills/graphify/` | 代码知识图谱生成（MCP/JSON/HTML/Obsidian） |
| ai-hub | `.agents/skills/ai-hub/` | AI Hub 环境管理 |

### KA Agent 链路

```
用户(企微Bot) → KA_bot → Dify Chat API (10.9.200.12:8086)
                 → MCP Bridge (:8766) → Synopsys KA
                 → LangChain Agent (:8768) → 多工具编排(ReAct)
```

### Git 工作流

```bash
# 发布
git tag ai-hub-vX.Y.Z && git push origin main --tags

# 手动部署
scp -r -o ProxyJump=ai.hse@10.9.200.12 tools/eod/* sp.shentao.lu@10.9.200.16:/path/
```

CI/CD：Push main 或创建 `ai-hub-v*` tag 触发 GitLab pipeline。

### SSH 跳板

```bash
ssh -J ai.hse@10.9.200.12 sp.shentao.lu@10.9.200.16
scp -o ProxyJump=ai.hse@10.9.200.12 <local> sp.shentao.lu@10.9.200.16:<remote>
```

## Proxy 集成层

### 转换逻辑

```python
# Dify knowledge_id → RAGFlow dataset_ids（支持多 KB 联合）
dataset_ids = knowledge_id.split(",")

# Dify → RAGFlow
{"question": query, "dataset_ids": dataset_ids, "document_ids": [], "top_k": top_k}

# RAGFlow chunks → Dify records
for chunk in ragf_data["data"]["chunks"]:
    records.append({
        "content":  chunk["content"],
        "score":    chunk.get("similarity") or chunk.get("vector_similarity"),
        "title":    chunk.get("document_keyword") or chunk.get("document_id"),
        "metadata": {"document_id": chunk["document_id"], "dataset_id": chunk["dataset_id"]}
    })
```

### 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `RAGFLOW_BASE_URL` | `http://192.168.20.21:8088` | RAGFlow 上游 |
| `RAGFLOW_API_KEY` | (见凭据表) | RAGFlow API key |
| `REQUEST_TIMEOUT` | `90` | 上游超时(秒) |
| `RETRY_MAX` | `2` | 重试次数 |
| `CACHE_TTL` | `60` | 缓存 TTL(秒) |

### Wiki URL 溯源

Proxy 可选 MySQL+PG 交叉查询，注入 `source_url` 到 metadata：
- MySQL：`document_id → location`
- PG：`minio_key → source_url`

### 重启

```bash
ssh ai.hse@10.9.200.13
pkill -f 'gunicorn.*proxy_server'
MYSQL_PORT=3307 PG_ENABLED=1 nohup python3 -m gunicorn proxy_server:app \
  --bind 0.0.0.0:8090 --workers 4 --worker-class gevent > /tmp/proxy.log 2>&1 &
```

## KB 运维

### 批量导入

```bash
# 本机（html）
PYTHONUNBUFFERED=1 docker exec ragflow-test python3 \
  /ragflow/tools/batch_import.py --config /ragflow/tools/batch_config.yaml --source html --wait

# 远程（wiki）
ssh ai.hse@10.9.200.13 "docker exec -e VLM_ENABLED=1 ragflow-server python3 \
  /ragflow/tools/batch_import.py --config /ragflow/tools/batch_config.yaml --source wiki --wait"
```

### 清理重建

```bash
docker exec ragflow-test pkill -9 -f batch_import
docker exec docker-mysql-1 mysql -u root -pinfini_rag_flow -e "
  DELETE FROM rag_flow.task WHERE doc_id IN (SELECT id FROM rag_flow.document WHERE kb_id='KB_ID');
  DELETE FROM rag_flow.file2document WHERE document_id IN (SELECT id FROM rag_flow.document WHERE kb_id='KB_ID');
  DELETE FROM rag_flow.document WHERE kb_id='KB_ID';
"
```

### 失败重试 / RAPTOR

详见 ragflow-kb-ops skill。

## 多数据源联合检索

| source | KB 名 | 表 | 行数 | VLM |
|--------|-------|-----|------|-----|
| wiki | enflame-wiki | wiki_metadata | ~233 | Y |
| html | enflame-docs | html_metadata | ~60 | N |
| wangpan | enflame-wangpan | wangpan_metadata | 0 | N |

Dify 配置 `knowledge_id: "kb_wiki_id,kb_html_id"`，proxy 自动拆分为多个 dataset_ids。

## 已知 Bug 与修复

1. **Redis host 需含端口**：`dify-redis-1:6379` 而非 `dify-redis-1`（`rag/utils/redis_conn.py:129`）
2. **batch_import --limit 误删**：`limit > 0` 跳过删除逻辑（`tools/batch_import.py:601`）
3. **MinIO 路径重复拼接**：去掉 `service_conf` 中 `minio.bucket`（`rag/utils/minio_conn.py:82-86`）
4. **VLM 描述不完整**：`VLLM_MAX_TOKENS=1024` + 逐行列出生数据 prompt
5. **图片 URL 匹配错误**：dict 精确映射，不用 `in` 子串
6. **VLM Pipeline**：type=md + 图片 URL 保留，VLM 单独预处理
7. **代理扩容**：HTTPServer → ThreadingMixIn
8. **RAGFlow 版本兼容**：容器版 ≠ 仓库版
9. **type=md vs type=txt**：md 结构好+VLM 开销，txt 快丢结构
10. **网络拓扑**：本机必须走代理，200.13 可直连后端
11. **Podman 命名空间错误**：检查 `~/.config/containers/storage.conf`，然后 `podman system reset -f`
12. **AI Hub 容器无外网**：预下载二进制到镜像，设 `DEEPSEEK_TUI_RELEASE_BASE_URL=file:///opt/codewhale`

## 模型代理

### 172.16.90.45:8082（老代理）
- HTTPServer → ThreadingMixIn (systemd: model-proxy)
- embedding → 10.12.116.244:8006
- VLM → 172.21.6.6:4000

### 172.21.6.6:4000（新代理，LiteLLM 风格）
- AI Hub 容器的默认模型路由
- 统一的 OpenAI-compatible API
