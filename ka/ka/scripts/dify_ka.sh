#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.yaml"
CONV_STATE_FILE="/tmp/dify_ka_conversation_id"

# 默认值
DIFY_URL=""
AUTH_TOKEN=""

# 从 config.yaml 读取配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        DIFY_URL="$(sed -n 's/^[[:space:]]*base_url:[[:space:]]*"\(.*\)"/\1/p' "$CONFIG_FILE" 2>/dev/null)"
        AUTH_TOKEN="$(sed -n 's/^[[:space:]]*token:[[:space:]]*"\(.*\)"/\1/p' "$CONFIG_FILE" 2>/dev/null)"
    fi
    DIFY_URL="${DIFY_URL:-http://10.9.200.12:8086}"
}

usage() {
    cat <<EOF
用法: $(basename "$0") <command> [选项]

命令:
  query      查询知识库（默认）
  clear      清除会话上下文

选项（query）:
  --tool-name <名称>        EDA 工具名（vcs, verdi, pt, fc, dc, icv 等）
  --tool-version <版本>     工具版本（默认: Y-2026.03）
  --query <问题>            用户问题（必填）
  --new-session             开启新会话（不复用之前的 conversation_id）
EOF
    exit 0
}

# 读取上次保存的 conversation_id
load_conv_id() {
    if [[ -f "$CONV_STATE_FILE" ]]; then
        cat "$CONV_STATE_FILE"
    else
        echo ""
    fi
}

# 保存 conversation_id
save_conv_id() {
    echo "$1" > "$CONV_STATE_FILE"
}

# 清除会话
clear_session() {
    rm -f "$CONV_STATE_FILE"
    echo "会话已清除"
}

# 查询知识库
do_query() {
    local tool_name=""
    local tool_version="Y-2026.03"
    local query=""
    local conv_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool-name)      tool_name="$2"; shift 2 ;;
            --tool-version)   tool_version="$2"; shift 2 ;;
            --query)          query="$2"; shift 2 ;;
            --new-session)    conv_id=""; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$query" ]]; then
        echo "错误: --query 是必填参数"
        exit 1
    fi

    # 加载会话 ID（除非显式指定新会话）
    if [[ -z "$conv_id" ]]; then
        conv_id="$(load_conv_id)"
    fi

    # 构造请求 JSON
    local data
    data=$(jq -n \
        --arg context "help user with Synopsys EDA tools" \
        --arg user_question "" \
        --arg tool_name "$tool_name" \
        --arg tool_version "$tool_version" \
        --arg search_metadata "" \
        --arg query "$query" \
        --arg user "claude-code" \
        --arg conv_id "$conv_id" \
        '{
            inputs: {
                context: $context,
                user_question: $user_question,
                tool_name: $tool_name,
                tool_version: $tool_version,
                search_metadata: $search_metadata
            },
            query: $query,
            response_mode: "blocking",
            user: $user,
            conversation_id: $conv_id
        }')

    local response
    echo "正在查询知识库..." >&2
    response=$(curl -s --connect-timeout 10 --max-time 120 -X POST "$DIFY_URL/v1/chat-messages" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer ${AUTH_TOKEN}" \
        -d "$data")

    # 提取 answer 字段
    local answer
    answer=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('answer', '错误: 未获取到回答'))" 2>/dev/null || echo "错误: API 响应解析失败")

    # 提取并保存新的 conversation_id
    local new_conv_id
    new_conv_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('conversation_id', ''))" 2>/dev/null || echo "")
    if [[ -n "$new_conv_id" ]]; then
        save_conv_id "$new_conv_id"
    fi

    echo "$answer"
}

# ---- 入口 ----
load_config

COMMAND="${1:-query}"
case "$COMMAND" in
    query)   shift; do_query "$@" ;;
    clear)   clear_session ;;
    -h|--help) usage ;;
    *)       do_query "$@" ;;   # 默认当 query 处理
esac
