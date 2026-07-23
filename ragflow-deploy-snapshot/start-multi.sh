#!/bin/bash
# RAGFlow 多实例启动器 — 在已有 ragflow-server 容器内配置 2 实例 + nginx LB
# 用法: bash start-multi.sh [实例数，默认2]
#
# 做两件事：
# 1. 配置容器内 nginx upstream 负载均衡 N 个 ragflow_server 实例
# 2. 启动第 2..N 个实例（第 1 个由容器 entrypoint 自动起在 9380）
#
# 注意：容器重建后需重新跑此脚本（nginx 配置和第 2 实例都在容器内，非持久化卷）
set -e

INSTANCES=${1:-2}
CONTAINER=ragflow-server
# 实例端口：9380, 9382, 9384, 9386... (偶数，避开 9381 admin / 9383 备用)
port_for() { echo $((9380 + $1 * 2)); }

echo "[1/3] 配置 nginx upstream ($INSTANCES 实例)..."

# 生成 upstream server 列表
SERVERS=""
for i in $(seq 0 $((INSTANCES-1))); do
  PORT=$(port_for $i)
  SERVERS="$SERVERS    server 127.0.0.1:$PORT;
"
done

# 直接写完整配置文件（不用 sed，避免清空风险）
docker exec $CONTAINER sh -c "cat > /etc/nginx/conf.d/ragflow.conf << 'NGINXEOF'
upstream ragflow_api {
$SERVERS}

server {
    listen 80;
    server_name _;
    root /ragflow/web/dist;

    gzip on;
    gzip_min_length 1k;
    gzip_comp_level 9;
    gzip_types text/plain application/javascript application/x-javascript text/css application/xml text/javascript application/x-httpd-php image/jpeg image/gif image/png;
    gzip_vary on;
    gzip_disable \"MSIE [1-6].\";

    location ~ ^/api/v1/admin {
        proxy_pass http://localhost:9381;
        include proxy.conf;
    }

    location ~ ^/(v1|api) {
        proxy_pass http://ragflow_api;
        include proxy.conf;
    }

    location / {
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }

    location ~ ^/static/(css|js|media)/ {
        expires 10y;
        access_log off;
    }
}
NGINXEOF
nginx -t && nginx -s reload && echo 'nginx OK'"

echo "[2/3] 启动第 2..$INSTANCES 实例..."
# 第 1 个实例 (9380) 由容器 entrypoint 自动起，从第 2 个开始
for i in $(seq 1 $((INSTANCES-1))); do
  PORT=$(port_for $i)
  LAUNCHER="/ragflow/ragflow_instance_${PORT}.py"
  docker exec $CONTAINER sh -c "cat > $LAUNCHER << 'PYEOF'
import os
os.environ.setdefault('LITELLM_LOCAL_MODEL_COST_MAP', 'True')
from api.apps import app
print(f'Starting ragflow instance on 127.0.0.1:$PORT (API only)', flush=True)
app.run(host='127.0.0.1', port=$PORT, debug=False, use_reloader=False)
PYEOF
"
  # 用 curl 探测端口是否已响应（比 pgrep 精确）
  CODE=$(docker exec $CONTAINER curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/ --max-time 3 2>/dev/null || echo 000)
  if [ "$CODE" = "404" ] || [ "$CODE" = "200" ]; then
    echo "  $PORT 已在跑 (HTTP $CODE)，跳过"
  else
    echo "  启动 $PORT..."
    docker exec -d $CONTAINER python3 $LAUNCHER
  fi
done

echo "[3/3] 等待实例就绪..."
for i in $(seq 0 $((INSTANCES-1))); do
  PORT=$(port_for $i)
  for try in $(seq 1 30); do
    CODE=$(docker exec $CONTAINER curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/ --max-time 5 2>/dev/null || echo 000)
    if [ "$CODE" = "404" ] || [ "$CODE" = "200" ]; then
      echo "  $PORT 就绪 ($CODE)"
      break
    fi
    sleep 2
  done
done

echo ""
echo "=== 完成：$INSTANCES 实例 + nginx LB ==="
echo "验证: curl -X POST http://127.0.0.1:8090/retrieval -H 'Content-Type: application/json' -d '{\"knowledge_id\":\"<kb>\",\"query\":\"test\",\"top_k\":5}'"
