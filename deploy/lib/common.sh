#!/bin/bash
# ================================================================
# deploy/lib/common.sh — Shared utilities for deployment framework
# ================================================================

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠${NC} $1"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $1"; }
info() { echo -e "${CYAN}[$(date +%H:%M:%S)] ℹ${NC} $1"; }

# --- State management ---
STATE_DIR=""
init_state() {
    STATE_DIR="/tmp/deploy-state/${COMPONENT}@${TARGET_HOST}"
    mkdir -p "$STATE_DIR"
}
phase_done()  { [[ -f "${STATE_DIR}/$1" ]]; }
mark_done()   { touch "${STATE_DIR}/$1"; }
phase_skip()  { ok "Phase '$1' already done — skipping"; }

# --- Remote execution ---
remote() {
    ssh ${SSH_OPTS:-} "${REMOTE_USER}@${TARGET_HOST}" "$@"
}

# --- Rsync with progress ---
transfer_file() {
    local src="$1" dst="$2"
    local fname=$(basename "$src")
    local fsize=$(du -h "$src" 2>/dev/null | cut -f1)
    log "Transferring $fname ($fsize)..."
    rsync -avP --progress "$src" "${REMOTE_USER}@${TARGET_HOST}:${dst}"
}

# --- Pre-flight checks ---
check_local() {
    [[ -d "$LOCAL_DIR" ]] || { err "Local dir not found: $LOCAL_DIR"; return 1; }
    [[ -f "${LOCAL_DIR}/.env" ]] || { err ".env not found in $LOCAL_DIR"; return 1; }
    return 0
}

check_remote() {
    local timeout=${1:-5}
    if remote -o ConnectTimeout="$timeout" "echo ok" &>/dev/null; then
        ok "SSH connection to ${TARGET_HOST} OK"
        # Detect docker compose flavor
        local flavor=$(remote "docker compose version &>/dev/null && echo 'docker compose' || (docker-compose version &>/dev/null && echo 'docker-compose' || echo 'none')")
        if [[ "$flavor" == "none" ]]; then
            err "Docker Compose not found on remote"
            return 1
        fi
        export REMOTE_COMPOSE="$flavor"
        ok "Remote compose: $REMOTE_COMPOSE"
        return 0
    else
        err "Cannot connect to ${REMOTE_USER}@${TARGET_HOST}"
        return 1
    fi
}

# --- Banner ---
banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Deploy: ${COMPONENT}${NC}  →  ${YELLOW}${REMOTE_USER}@${TARGET_HOST}${NC}"
    echo -e "${CYAN}║${NC}  Remote path: ${REMOTE_PATH}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- Progress display ---
show_progress() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Deploy Progress: ${COMPONENT} → ${TARGET_HOST}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local phases=(
        "preflight"
        "images_exported"
        "data_packaged"
        "transferred"
        "images_loaded"
        "data_extracted"
        "configured"
        "started"
        "verified"
    )
    local labels=(
        "Pre-flight checks"
        "Images exported"
        "Config/data packaged"
        "Files transferred"
        "Images loaded (remote)"
        "Data extracted (remote)"
        "Config applied (remote)"
        "Services started"
        "Health check"
    )
    for i in "${!phases[@]}"; do
        if phase_done "${phases[$i]}"; then
            echo -e "  ${GREEN}✓${NC} ${labels[$i]}"
        else
            echo -e "  ${YELLOW}○${NC} ${labels[$i]}"
        fi
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# --- Dependency check ---
check_dependencies() {
    [[ -z "${DEPENDS_ON:-}" ]] && return 0

    for dep in $DEPENDS_ON; do
        local dep_state="/tmp/deploy-state/${dep}@${TARGET_HOST}"
        if [[ ! -f "${dep_state}/started" ]]; then
            warn "Dependency '$dep' not yet deployed to ${TARGET_HOST}"
            warn "Run: ./deploy.sh $dep --target ${TARGET_HOST} --start"
            return 1
        fi
        ok "Dependency '$dep' is deployed"
    done
    return 0
}

# --- Cleanup temp files ---
do_cleanup() {
    local tmp="/tmp/deploy-payload/${COMPONENT}"
    if phase_done "started"; then
        log "Cleaning up temporary files..."
        rm -rf "$tmp"
        remote "rm -rf /tmp/${COMPONENT}-migration" 2>/dev/null || true
        ok "Cleanup done"
    else
        warn "Deployment incomplete — keeping temp files for resume"
    fi
}
