#!/bin/bash
# 轮询监控 ragflow-server 多实例状态：9382 没跑就自动配 nginx + 起第 2 实例
# 由 systemd ragflow-multi-watcher.service 调用（Type=simple, Restart=always）
# 比 docker events 方案更可靠（events 流在 systemd 环境会退出，轮询不会）
set -uo pipefail

CONTAINER=ragflow-server
START_MULTI=/home/ai.hse/ragflow-deploy-v2/start-multi.sh
LOG=/home/ai.hse/ragflow-deploy-v2/logs/multi-watcher.log
INSTANCES=${1:-2}
INTERVAL=${2:-30}

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG" >&2; }

log "poll watcher started (container=$CONTAINER instances=$INSTANCES interval=${INTERVAL}s)"

while true; do
  # 检查容器是否在跑
  if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
    sleep "$INTERVAL"
    continue
  fi
  # 检查 9382 是否响应（第 2 实例健康标志）
  CODE=$(docker exec "$CONTAINER" curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9382/ --max-time 5 2>/dev/null || echo 000)
  if [ "$CODE" = "404" ] || [ "$CODE" = "200" ]; then
    : # 第 2 实例在跑，无需操作
  else
    log "9382 not responding (code=$CODE), running start-multi.sh to restore..."
    # 先等主实例 9380 就绪（容器可能刚重启）
    for i in $(seq 1 24); do
      C0=$(docker exec "$CONTAINER" curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9380/ --max-time 5 2>/dev/null || echo 000)
      [ "$C0" = "404" ] || [ "$C0" = "200" ] && break
      sleep 5
    done
    if bash "$START_MULTI" "$INSTANCES" >>"$LOG" 2>&1; then
      log "start-multi.sh OK, 2 instances restored"
    else
      log "start-multi.sh FAILED (exit $?)"
    fi
    # 配置后等待实例完全就绪，避免重复触发
    sleep 60
  fi
  sleep "$INTERVAL"
done
