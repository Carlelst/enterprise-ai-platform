#!/bin/bash
# ================================================================
# deploy.sh — Unified deployment CLI for all components
#
# Usage:
#   ./deploy.sh <component> [--target <host>] [options]
#   ./deploy.sh all      [--target <host>] [options]
#
# Components: dify, ragflow
# Targets:    10.9.200.12 (AIMP01), 10.9.200.13 (AIMP02)
#
# Standard pipeline:
#   0. preflight   — validate local + remote
#   1. export      — docker save images
#   2. pack        — tar configs + data dirs
#   3. transfer    — rsync to remote
#   4. load        — docker load on remote
#   5. extract     — untar to remote path
#   6. configure   — apply IP replaces, customize config
#   7. start       — docker-compose up
#   8. verify      — health check
#
# Options:
#   --target <host>     Target server IP (default: 10.9.200.13)
#   --skip-images       Skip image export/transfer/load
#   --skip-data         Skip config/data packaging/transfer
#   --dry-run           Print what would be done without doing it
#   --start             Auto-start services after deploy (default: ask)
#   --no-start          Don't start services
#   --status            Show deployment progress
#   --reset             Reset state and start fresh
#   --list              List available components
#   -h, --help          Show this help
# ================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
COMPONENTS_DIR="${SCRIPT_DIR}/components"

# --- Source shared library ---
source "${LIB_DIR}/common.sh"

# --- Defaults ---
TARGET_HOST="10.9.200.13"
REMOTE_USER="ai.hse"
SSH_OPTS="-o ConnectTimeout=5"
TARGET_IP="${TARGET_HOST}"
SKIP_IMAGES=false
SKIP_DATA=false
SKIP_PLUGIN=false
DRY_RUN=false
DO_START=""
SHOW_STATUS=false
RESET_STATE=false
TMP_DIR="/tmp/deploy-payload"

# ================================================================
# CLI
# ================================================================
usage() {
    cat <<'EOF'
Usage: ./deploy.sh <component> [--target <host>] [options]
       ./deploy.sh all       [--target <host>] [options]

Components:
  dify        Dify platform (API, Web, Worker, Plugin, etc.)
  ragflow     RAGFlow knowledge base engine

Options:
  --target <host>     Target server IP (default: 10.9.200.13)
  --skip-images       Skip image export/transfer/load phases
  --skip-data         Skip config/data packaging/transfer phases
  --dry-run           Show what would be done without doing it
  --start             Auto-start services after deployment
  --no-start          Don't start services after deployment
  --status            Show deployment progress for this component
  --reset             Reset deployment state (start fresh)
  --list              List available components
  -h, --help          Show this help

Examples:
  ./deploy.sh dify --target 10.9.200.12 --start
  ./deploy.sh ragflow --skip-images --dry-run
  ./deploy.sh all --target 10.9.200.13 --start
  ./deploy.sh dify --status
EOF
    exit 0
}

list_components() {
    echo ""
    echo -e "${CYAN}Available components:${NC}"
    echo ""
    for d in "${COMPONENTS_DIR}"/*/; do
        local name=$(basename "$d")
        local conf="${d}${name}.conf"
        if [[ -f "$conf" ]]; then
            # Extract display name
            local display=$(grep '^DISPLAY_NAME=' "$conf" | head -1 | cut -d'"' -f2)
            echo -e "  ${GREEN}${name}${NC}  — ${display}"
        fi
    done
    echo ""
    exit 0
}

# --- Parse args ---
COMPONENT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)       TARGET_HOST="$2"; TARGET_IP="$2"; shift 2 ;;
        --skip-images)  SKIP_IMAGES=true; shift ;;
        --skip-data)    SKIP_DATA=true; shift ;;
        --skip-plugin)  SKIP_PLUGIN=true; shift ;;
        --dry-run)      DRY_RUN=true; shift ;;
        --start)        DO_START="true"; shift ;;
        --no-start)     DO_START="false"; shift ;;
        --status)       SHOW_STATUS=true; shift ;;
        --reset)        RESET_STATE=true; shift ;;
        --list)         list_components ;;
        -h|--help)      usage ;;
        -*)
            err "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$COMPONENT" ]]; then
                COMPONENT="$1"
            else
                err "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

[[ -z "$COMPONENT" ]] && { err "Component required. Use --list to see available components."; usage; }

# --- Special: "all" deploys all components in order ---
if [[ "$COMPONENT" == "all" ]]; then
    COMPONENTS_TO_DEPLOY=()
    for d in "${COMPONENTS_DIR}"/*/; do
        local name=$(basename "$d")
        [[ -f "${d}${name}.conf" ]] && COMPONENTS_TO_DEPLOY+=("$name")
    done
    # Sort: non-dependent components first
    log "Deploying all components: ${COMPONENTS_TO_DEPLOY[*]}"
    FAILED=""
    for comp in "${COMPONENTS_TO_DEPLOY[@]}"; do
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  Deploying: ${comp}${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        if ! "$0" "$comp" --target "$TARGET_HOST" ${DO_START:+--start} ${SKIP_IMAGES:+--skip-images} ${SKIP_DATA:+--skip-data}; then
            err "Failed to deploy: $comp"
            FAILED="$FAILED $comp"
            # Continue with next component (don't fail fast)
        fi
    done
    if [[ -n "$FAILED" ]]; then
        err "Failed components:$FAILED"
        exit 1
    fi
    ok "All components deployed successfully"
    exit 0
fi

# --- Load component config ---
COMPONENT_CONF="${COMPONENTS_DIR}/${COMPONENT}/${COMPONENT}.conf"
[[ -f "$COMPONENT_CONF" ]] || { err "Component not found: ${COMPONENT}. Use --list to see available."; exit 1; }
source "$COMPONENT_CONF"

# --- Route to handler based on quick actions ---
if $SHOW_STATUS; then
    init_state
    banner
    show_progress
    exit 0
fi

if $RESET_STATE; then
    init_state
    log "Resetting deployment state for ${COMPONENT}@${TARGET_HOST}..."
    rm -rf "$STATE_DIR"
    ok "State reset."
    exit 0
fi

# ================================================================
# Pipeline Phases
# ================================================================

PHASE_PREFLIGHT="preflight"
PHASE_IMAGES_EXPORTED="images_exported"
PHASE_DATA_PACKAGED="data_packaged"
PHASE_TRANSFERRED="transferred"
PHASE_IMAGES_LOADED="images_loaded"
PHASE_DATA_EXTRACTED="data_extracted"
PHASE_CONFIGURED="configured"
PHASE_STARTED="started"
PHASE_VERIFIED="verified"

# --- Phase 0: Pre-flight ---
phase_preflight() {
    phase_done "$PHASE_PREFLIGHT" && { phase_skip "preflight"; return; }

    log "Phase 0: Pre-flight checks for ${DISPLAY_NAME}..."

    # Local checks
    check_local || exit 1

    # Verify all images exist locally
    if ! $SKIP_IMAGES; then
        for img in "${IMAGES[@]}"; do
            if ! docker image inspect "$img" &>/dev/null; then
                err "Local image not found: $img"
                err "Build or pull it first, then retry."
                exit 1
            fi
        done
        ok "All ${#IMAGES[@]} images verified locally"
    fi

    # Remote checks
    if ! $DRY_RUN; then
        check_remote || exit 1
        # Ensure remote base path parent exists
        remote "mkdir -p ${REMOTE_PATH}"
    fi

    # Check dependencies
    check_dependencies || {
        warn "Proceeding anyway — dependent services may fail to start"
    }

    ok "Pre-flight checks passed"
    mark_done "$PHASE_PREFLIGHT"
}

# --- Phase 1: Export images ---
phase_images_export() {
    phase_done "$PHASE_IMAGES_EXPORTED" && { phase_skip "image export"; return; }
    $SKIP_IMAGES && { warn "Skipping image export (--skip-images)"; return; }

    log "Phase 1: Exporting ${#IMAGES[@]} Docker images..."
    local payload="${TMP_DIR}/${COMPONENT}"
    mkdir -p "$payload"

    if $DRY_RUN; then
        log "[DRY-RUN] Would save ${#IMAGES[@]} images to ${payload}/${COMPONENT}-images.tar.gz"
        for img in "${IMAGES[@]}"; do
            echo "         - $img"
        done
        mark_done "$PHASE_IMAGES_EXPORTED"
        return
    fi

    log "Saving images (this may take several minutes)..."
    docker save "${IMAGES[@]}" -o "${payload}/${COMPONENT}-images.tar"
    log "Compressing..."
    gzip -f "${payload}/${COMPONENT}-images.tar"
    local size=$(du -h "${payload}/${COMPONENT}-images.tar.gz" | cut -f1)
    ok "Images exported: ${payload}/${COMPONENT}-images.tar.gz ($size)"
    mark_done "$PHASE_IMAGES_EXPORTED"
}

# --- Phase 2: Package config + data ---
phase_data_pack() {
    phase_done "$PHASE_DATA_PACKAGED" && { phase_skip "data packaging"; return; }
    $SKIP_DATA && { warn "Skipping data packaging (--skip-data)"; return; }

    log "Phase 2: Packaging config + data files..."
    local payload="${TMP_DIR}/${COMPONENT}"
    mkdir -p "$payload"

    if $DRY_RUN; then
        log "[DRY-RUN] Would package from ${LOCAL_DIR}:"
        [[ ${#DATA_CONFIGS[@]} -gt 0 ]] && echo "         configs: ${DATA_CONFIGS[*]}"
        [[ ${#DATA_DIRS[@]} -gt 0 ]] && echo "         dirs:    ${DATA_DIRS[*]}"
        [[ ${#DATA_EXCLUDE[@]} -gt 0 ]] && echo "         exclude: ${DATA_EXCLUDE[*]}"
        mark_done "$PHASE_DATA_PACKAGED"
        return
    fi

    # Build tar args
    local tar_args=()
    tar_args+=("-czf" "${payload}/${COMPONENT}-data.tar.gz")
    tar_args+=("-C" "$LOCAL_DIR")

    # Add exclusions
    for ex in "${DATA_EXCLUDE[@]}"; do
        tar_args+=("--exclude=$ex")
    done

    # Handle --skip-plugin for Dify
    if $SKIP_PLUGIN && [[ "$COMPONENT" == "dify" ]]; then
        tar_args+=("--exclude=volumes/plugin_daemon")
        warn "Excluding plugin_daemon volume (~5GB)"
    fi

    # Collect items
    local items=()
    for c in "${DATA_CONFIGS[@]}"; do
        [[ -e "${LOCAL_DIR}/${c}" ]] && items+=("$c")
    done
    for d in "${DATA_DIRS[@]}"; do
        [[ -d "${LOCAL_DIR}/${d}" ]] && items+=("$d")
    done

    if [[ ${#items[@]} -eq 0 ]]; then
        warn "No files/dirs to package"
        mark_done "$PHASE_DATA_PACKAGED"
        return
    fi

    tar_args+=("${items[@]}")
    tar "${tar_args[@]}"

    local size=$(du -h "${payload}/${COMPONENT}-data.tar.gz" | cut -f1)
    ok "Data packaged: ${payload}/${COMPONENT}-data.tar.gz ($size)"
    mark_done "$PHASE_DATA_PACKAGED"
}

# --- Phase 3: Transfer ---
phase_transfer() {
    phase_done "$PHASE_TRANSFERRED" && { phase_skip "transfer"; return; }

    log "Phase 3: Transferring files to ${TARGET_HOST}..."
    local payload="${TMP_DIR}/${COMPONENT}"

    if $DRY_RUN; then
        log "[DRY-RUN] Would rsync ${payload}/ to ${REMOTE_USER}@${TARGET_HOST}:/tmp/${COMPONENT}-migration/"
        mark_done "$PHASE_TRANSFERRED"
        return
    fi

    remote "mkdir -p /tmp/${COMPONENT}-migration"

    local has_files=false
    if ! $SKIP_IMAGES && [[ -f "${payload}/${COMPONENT}-images.tar.gz" ]]; then
        transfer_file "${payload}/${COMPONENT}-images.tar.gz" "/tmp/${COMPONENT}-migration/"
        has_files=true
    fi
    if ! $SKIP_DATA && [[ -f "${payload}/${COMPONENT}-data.tar.gz" ]]; then
        transfer_file "${payload}/${COMPONENT}-data.tar.gz" "/tmp/${COMPONENT}-migration/"
        has_files=true
    fi

    $has_files || warn "No files to transfer"
    ok "Transfer complete"
    mark_done "$PHASE_TRANSFERRED"
}

# --- Phase 4: Load images on remote ---
phase_images_load() {
    phase_done "$PHASE_IMAGES_LOADED" && { phase_skip "image load"; return; }
    $SKIP_IMAGES && { warn "Skipping image load (--skip-images)"; return; }

    log "Phase 4: Loading images on remote..."

    if $DRY_RUN; then
        log "[DRY-RUN] Would gunzip + docker load on remote"
        mark_done "$PHASE_IMAGES_LOADED"
        return
    fi

    remote "
        set -e
        cd /tmp/${COMPONENT}-migration
        archive='${COMPONENT}-images.tar.gz'
        tarfile='${COMPONENT}-images.tar'
        if [[ -f \"\$archive\" ]] && [[ ! -f \"\$tarfile\" ]]; then
            echo 'Decompressing...'
            gunzip -k \"\$archive\"
        fi
        if [[ -f \"\$tarfile\" ]]; then
            echo 'Loading into Docker...'
            docker load -i \"\$tarfile\"
            echo ''
            echo 'Loaded images:'
            docker images --format '{{.Repository}}:{{.Tag}}' | head -20
        fi
    "
    ok "Images loaded on remote"
    mark_done "$PHASE_IMAGES_LOADED"
}

# --- Phase 5: Extract data on remote ---
phase_data_extract() {
    phase_done "$PHASE_DATA_EXTRACTED" && { phase_skip "data extract"; return; }
    $SKIP_DATA && { warn "Skipping data extraction (--skip-data)"; return; }

    log "Phase 5: Extracting data on remote..."

    if $DRY_RUN; then
        log "[DRY-RUN] Would mkdir -p ${REMOTE_PATH} && tar -xzf"
        mark_done "$PHASE_DATA_EXTRACTED"
        return
    fi

    remote "
        set -e
        mkdir -p ${REMOTE_PATH}
        cd /tmp/${COMPONENT}-migration
        if [[ -f ${COMPONENT}-data.tar.gz ]]; then
            echo 'Extracting to ${REMOTE_PATH}...'
            tar -xzf ${COMPONENT}-data.tar.gz -C ${REMOTE_PATH}/
            echo 'Contents:'
            ls -la ${REMOTE_PATH}/
        else
            echo 'No data archive found, skipping.'
        fi
    "
    ok "Data extracted to ${REMOTE_PATH}"
    mark_done "$PHASE_DATA_EXTRACTED"
}

# --- Phase 6: Configure ---
phase_configure() {
    phase_done "$PHASE_CONFIGURED" && { phase_skip "configure"; return; }
    $SKIP_DATA && { warn "Skipping config (--skip-data)"; return; }

    log "Phase 6: Applying remote configuration..."

    if $DRY_RUN; then
        log "[DRY-RUN] Would call apply_remote_config()"
        mark_done "$PHASE_CONFIGURED"
        return
    fi

    # Call component-specific config transform
    if declare -f apply_remote_config > /dev/null; then
        apply_remote_config
    else
        warn "No apply_remote_config() defined for ${COMPONENT}"
    fi

    ok "Configuration applied"
    mark_done "$PHASE_CONFIGURED"
}

# --- Phase 7: Start services ---
phase_start() {
    phase_done "$PHASE_STARTED" && { phase_skip "start"; return; }

    # Determine if we should start
    if [[ "$DO_START" == "false" ]]; then
        warn "Skipping service start (--no-start)"
        return
    fi
    if [[ "$DO_START" != "true" ]]; then
        # Interactive: ask
        echo ""
        read -rp "  Start services on ${TARGET_HOST} now? [Y/n]: " answer
        [[ "$answer" =~ ^[Nn] ]] && { warn "Start skipped. Run with --start to auto-start."; return; }
    fi

    log "Phase 7: Starting ${DISPLAY_NAME} services on remote..."

    if $DRY_RUN; then
        log "[DRY-RUN] Would run: cd ${REMOTE_PATH} && ${REMOTE_COMPOSE:-docker compose} -f ${REMOTE_COMPOSE_FILE} -p ${COMPOSE_PROJECT} up -d"
        mark_done "$PHASE_STARTED"
        return
    fi

    remote "
        set -e
        cd ${REMOTE_PATH}
        echo 'Starting ${DISPLAY_NAME}...'
        ${REMOTE_COMPOSE} -f ${REMOTE_COMPOSE_FILE} -p ${COMPOSE_PROJECT} up -d
        echo ''
        echo 'Container status:'
        ${REMOTE_COMPOSE} -f ${REMOTE_COMPOSE_FILE} -p ${COMPOSE_PROJECT} ps
    "
    ok "Services started"
    mark_done "$PHASE_STARTED"

    # Show version info
    if declare -f show_version > /dev/null; then
        show_version
    fi
}

# --- Phase 8: Verify ---
phase_verify() {
    phase_done "$PHASE_VERIFIED" && { phase_skip "verify"; return; }

    log "Phase 8: Health check..."

    if $DRY_RUN; then
        log "[DRY-RUN] Would check: ${HEALTH_CHECK_URL}"
        mark_done "$PHASE_VERIFIED"
        return
    fi

    if declare -f do_health_check > /dev/null; then
        do_health_check && mark_done "$PHASE_VERIFIED"
    else
        warn "No health check defined for ${COMPONENT}"
        mark_done "$PHASE_VERIFIED"
    fi
}

# ================================================================
# Main
# ================================================================

# Initialize state
init_state

# Banner
banner

# Show current progress
show_progress

# Dry run notice
$DRY_RUN && log "DRY RUN — no changes will be made"

echo ""

# Execute pipeline
phase_preflight
phase_images_export
phase_data_pack
phase_transfer
phase_images_load
phase_data_extract
phase_configure
phase_start
phase_verify

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "${DISPLAY_NAME} deployment to ${TARGET_HOST} complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
show_progress

# Cleanup
do_cleanup

# Show access info
echo ""
echo -e "${CYAN}Access info:${NC}"
if declare -f show_access > /dev/null; then
    show_access
elif [[ -n "${HEALTH_CHECK_URL:-}" ]]; then
    echo "  Health: ${HEALTH_CHECK_URL}"
fi
echo ""
echo -e "  Remote: ${REMOTE_USER}@${TARGET_HOST}:${REMOTE_PATH}"
echo -e "  Manage: ssh ${REMOTE_USER}@${TARGET_HOST}"
echo -e "          cd ${REMOTE_PATH} && ${REMOTE_COMPOSE:-docker compose} -f ${REMOTE_COMPOSE_FILE} -p ${COMPOSE_PROJECT} ps"
echo ""
