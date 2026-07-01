# 统一部署框架

本地构建 → 测试 → 离线传输 → 远程部署，一条命令完成。

## 快速开始

```bash
cd .hub/deploy

# 查看可用组件
./deploy.sh --list

# 干跑（看会做什么但不执行）
./deploy.sh dify --dry-run
./deploy.sh ragflow --dry-run

# 完整部署
./deploy.sh dify --target 10.9.200.13 --start
./deploy.sh ragflow --target 10.9.200.13 --start

# 一次性部署全部
./deploy.sh all --target 10.9.200.13 --start
```

## 部署流程

每个组件执行标准 9 阶段流水线：

| 阶段 | 说明 | 可跳过 |
|------|------|--------|
| preflight | 检查本地镜像、SSH 连接、远程 docker-compose | — |
| images_export | `docker save` 导出镜像 | `--skip-images` |
| data_pack | `tar` 打包配置和数据目录 | `--skip-data` |
| transfer | `rsync` 传输到远程 | `--skip-images/--skip-data` |
| images_load | 远程 `docker load` 导入镜像 | `--skip-images` |
| data_extract | 远程解压到目标路径 | `--skip-data` |
| configure | 应用组件特定配置（IP 替换等） | — |
| start | `docker-compose up -d` | `--no-start` |
| verify | 健康检查 | — |

每个阶段完成后写入状态文件，中断后可 **断点续传**。

## 常用场景

### 只改配置（不重传镜像）

```bash
# 改了 .env 或 service_conf.yaml
./deploy.sh ragflow --target 10.9.200.13 --skip-images --start
```

### 升级组件版本

1. 本地构建新镜像（如 `docker build -t dify-api:v1.15.0-p1 .`）
2. 本地 `docker compose up` 测试通过
3. 编辑 `components/<name>/<name>.conf`，更新 `IMAGES` 数组
4. 部署：`./deploy.sh dify --target 10.9.200.13 --start`

### 跳过大数据卷

```bash
# Dify 的 plugin_daemon 卷 ~5GB，可跳过
./deploy.sh dify --target 10.9.200.13 --skip-plugin --start
```

### 查看进度

```bash
./deploy.sh ragflow --status
```

### 重置从头开始

```bash
./deploy.sh ragflow --reset
```

## 添加新组件

创建 `components/<name>/<name>.conf`，定义以下内容：

```bash
COMPONENT="myapp"
DISPLAY_NAME="My App"
LOCAL_DIR="/path/to/local/docker"
REMOTE_PATH="/opt/myapp/docker"
COMPOSE_PROJECT="myapp"
REMOTE_COMPOSE_FILE="docker-compose.yml"

IMAGES=("myapp:v1.0" "postgres:15")

DATA_CONFIGS=(".env" "docker-compose.yml")
DATA_DIRS=("volumes")
DATA_EXCLUDE=()                # 排除目录，如 ("volumes/cache")

DEPENDS_ON="dify"              # 依赖的组件（先部署）
EXTERNAL_NETWORKS=("dify_default")

HEALTH_CHECK_URL="http://${TARGET_IP:-localhost}:8080/health"
HEALTH_CHECK_TIMEOUT=30
SOURCE_IP="192.168.20.21"

# 远程配置变换（必须实现）
apply_remote_config() {
    remote "sed -i 's/${SOURCE_IP}/${TARGET_IP}/g' ${REMOTE_PATH}/.env"
}

# 健康检查（必须实现）
do_health_check() {
    curl -sf "${HEALTH_CHECK_URL}" && echo "OK" || echo "FAIL"
}
```

无需改 `deploy.sh` 或 `common.sh`。新组件会自动出现在 `--list` 中。

## 远程管理

```bash
# SSH 到服务器
ssh ai.hse@10.9.200.13

# Dify
cd /opt/dify/docker
docker-compose -p dify ps
docker-compose -p dify logs -f --tail=50

# RAGFlow
cd /opt/ragflow/docker
docker-compose -f docker-compose.remote.yml -p ragflow ps
docker-compose -f docker-compose.remote.yml -p ragflow logs -f --tail=50
```

## 网络拓扑

```
10.9.200.13
│
├── Dify (/opt/dify/docker/)
│   ├── dify_default (Docker 网络)
│   ├── Redis (dify-redis-1:6379)
│   ├── PostgreSQL, Weaviate, Nginx...
│   └── :8086 (Web UI)
│
├── RAGFlow (/opt/ragflow/docker/)
│   ├── ragflow (Docker 网络, bridge)
│   │   ├── MySQL, Elasticsearch
│   │   └── ragflow-server (:80, :9380, :9381)
│   ├── dify-proxy (:8090) — 双网卡
│   └── 复用 Dify 的 Redis (db 1) + dify_default 网络
│
└── Dify Proxy (ragflow compose 内)
    └── Dify 外部知识库 API 适配层
```

## 目标服务器

| 主机名 | IP | 用户 |
|--------|-----|------|
| AIMP01 | 10.9.200.12 | ai.hse |
| AIMP02 | 10.9.200.13 | ai.hse |

## RAGFlow v0.26.2 升级要点

从 v0.25.6 升级到 v0.26.2 需要注意：

1. **端口映射**：v0.26.2 镜像 EXPOSE 8088，但 nginx 监听 80。`docker run` 必须用 `-p 8088:80`（不是 `-p 8088:8088`）
2. **Docker 网络**：容器需同时加入 `ragflow-net`（连接 MySQL/ES）和 `dify_default`（连接 Redis）
3. **配置挂载**：`service_conf.yaml` 必须是文件，部署脚本可能误创为目录
4. **首次启动**：数据库迁移耗时较长，`/api/v1/version` 端点已移除（用 `/` 或 `/api/v1/datasets` 验证）
5. **自定义工具同步**：升级后需 `docker cp` 将 `batch_import.py` 和 `kb_ops_server.py` 拷入容器
6. **kb_ops_server**：升级后需重启服务进程（端口 8100）
7. **KB 数据保留**：MySQL/ES/Redis 为独立容器，升级 ragflow-server 不影响数据

### 升级命令

```bash
# 200.13 上执行
docker stop ragflow-server && docker rm ragflow-server
docker run -d --name ragflow-server \
  --network ragflow-net --network dify_default \
  -p 8088:80 -p 9380:9380 -p 9381:9381 \
  -v /path/to/service_conf.yaml:/ragflow/conf/service_conf.yaml.template \
  -v /path/to/logs:/ragflow/logs \
  infiniflow/ragflow:v0.26.2

# 同步自定义工具
docker cp /home/ai.hse/.hub/ragflow/tools/batch_import.py ragflow-server:/ragflow/tools/
docker cp /home/ai.hse/.hub/ragflow/tools/kb_ops_server.py ragflow-server:/ragflow/tools/

# 重启 kb_ops_server
kill $(lsof -ti:8100)
cd /home/ai.hse/.hub/ragflow/tools && MYSQL_PORT=3307 nohup python3 kb_ops_server.py --port 8100 > /tmp/kb_ops.log 2>&1 &
