#!/usr/bin/env bash
#
# pgvector-maintenance.sh - Spencer's Homelab Database & Vector Maintenance Pipeline
#
# Automates:
#   1. Reclaiming bloat and optimizing performance via VACUUM (ANALYZE) across active homelab databases (openwebui, authentik, gitea)
#   2. Optional archival & pruning of legacy LiteLLM spend logs if present
#   3. Push notification summary delivery via ntfy
#
# Usage:
#   scripts/pgvector-maintenance.sh [OPTIONS]
#
# Options:
#   --dry-run             Preview actions and record counts without altering data
#   --spend-days <N>      Retention period in days for LiteLLM spend logs (default: 30)
#   --no-vacuum           Skip VACUUM ANALYZE
#   --no-archive          Prune aged records without creating compressed CSV archives
#   --no-notify           Skip sending push notification via ntfy
#   --topic <topic>       ntfy notification topic (default: backups)
#   -h, --help            Show this help message
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_TIME=$(date +%s)

# Default Configuration
PG_CONTAINER="${PGVECTOR_CONTAINER:-pgvector}"
PG_USER="${PGVECTOR_USER:-postgres}"
SPEND_DAYS="${SPEND_DAYS:-30}"
ASYNC_DAYS="${ASYNC_DAYS:-14}"
NTFY_TOPIC="${NTFY_TOPIC:-backups}"
DO_REINDEX=true
DO_VACUUM=true
DO_ARCHIVE=true
DO_NOTIFY=true
DRY_RUN=false

# Locate Archive Directory
if [ -d "/data/homelab/pgvector" ]; then
    ARCHIVE_DIR="/data/homelab/pgvector/archives"
elif [ -d "/opt/data" ]; then
    ARCHIVE_DIR="/opt/data/backups/pgvector-archives"
else
    ARCHIVE_DIR="${SCRIPT_DIR}/../pgvector/archives"
fi

# Locate notify.sh script
NOTIFY_BIN=""
for candidate in \
    "${SCRIPT_DIR}/notify.sh" \
    "/opt/data/scripts/notify.sh" \
    "/data/homelab/scripts/notify.sh"; do
    if [ -x "$candidate" ]; then
        NOTIFY_BIN="$candidate"
        break
    fi
done

# Parse CLI Arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --spend-days)
            SPEND_DAYS="$2"
            shift 2
            ;;
        --async-days)
            ASYNC_DAYS="$2"
            shift 2
            ;;
        --no-reindex)
            DO_REINDEX=false
            shift
            ;;
        --no-vacuum)
            DO_VACUUM=false
            shift
            ;;
        --no-archive)
            DO_ARCHIVE=false
            shift
            ;;
        --no-notify)
            DO_NOTIFY=false
            shift
            ;;
        --topic)
            NTFY_TOPIC="$2"
            shift 2
            ;;
        -h|--help)
            sed -ne 's/^# //p; /^set -euo/q' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Helper to execute queries inside pgvector container
run_psql() {
    local db="$1"
    shift
    docker exec -i "$PG_CONTAINER" psql -U "$PG_USER" -d "$db" -v ON_ERROR_STOP=1 "$@"
}

run_psql_val() {
    local db="$1"
    local sql="$2"
    docker exec -i "$PG_CONTAINER" psql -U "$PG_USER" -d "$db" -t -A -c "$sql"
}

# Pre-flight Check
log "🔍 Checking pgvector container status..."
if ! docker inspect -f '{{.State.Status}}' "$PG_CONTAINER" >/dev/null 2>&1; then
    log "❌ Error: pgvector container '$PG_CONTAINER' is not running." >&2
    exit 1
fi

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
mkdir -p "$ARCHIVE_DIR"

log "=================================================="
log "🚀 Starting Spencer's Homelab Database Maintenance"
log "Mode: $([ "$DRY_RUN" = true ] && echo 'DRY-RUN (Simulated)' || echo 'LIVE EXECUTION')"
log "Spend Log Retention: ${SPEND_DAYS} days"
log "Async Operations Retention: ${ASYNC_DAYS} days"
log "Archive Storage: ${ARCHIVE_DIR}"
log "=================================================="

# Collect initial database sizes
LITELLM_EXISTS=$(run_psql postgres -tAc "SELECT 1 FROM pg_database WHERE datname='litellm';" || echo "0")
if [ "$LITELLM_EXISTS" = "1" ]; then
    LITELLM_SIZE_BEFORE=$(run_psql_val litellm "SELECT pg_size_pretty(pg_database_size('litellm'));")
    SPEND_LOGS_SIZE_BEFORE=$(run_psql_val litellm "SELECT pg_size_pretty(pg_total_relation_size('\"LiteLLM_SpendLogs\"'));" 2>/dev/null || echo "N/A")
else
    LITELLM_SIZE_BEFORE="Decommissioned"
    SPEND_LOGS_SIZE_BEFORE="N/A"
fi
OPENWEBUI_SIZE_BEFORE=$(run_psql_val openwebui "SELECT pg_size_pretty(pg_database_size('openwebui'));")

log "📊 Initial Database Sizes:"
if [ "$LITELLM_EXISTS" = "1" ]; then
    log "   • litellm DB:   ${LITELLM_SIZE_BEFORE} (LiteLLM_SpendLogs: ${SPEND_LOGS_SIZE_BEFORE})"
fi
log "   • openwebui DB: ${OPENWEBUI_SIZE_BEFORE}"

# --- STEP 1: Legacy LiteLLM Spend Logs Archival & Pruning ---
PRUNED_SPEND=0
if [ "$LITELLM_EXISTS" = "1" ]; then
    log "\n🧹 Step 1: Evaluating LiteLLM Spend Logs (> ${SPEND_DAYS} days)..."
    SPEND_COUNT=$(run_psql_val litellm "SELECT count(*) FROM \"LiteLLM_SpendLogs\" WHERE \"startTime\" < NOW() - INTERVAL '${SPEND_DAYS} days';" 2>/dev/null || echo "0")
    log "   Found ${SPEND_COUNT} aged spend log records."

    if [ "$SPEND_COUNT" -gt 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            log "   [DRY-RUN] Would archive and delete ${SPEND_COUNT} spend logs."
            PRUNED_SPEND="$SPEND_COUNT"
        else
            if [ "$DO_ARCHIVE" = true ]; then
                SPEND_ARCHIVE="${ARCHIVE_DIR}/litellm_spend_logs_${TIMESTAMP}.csv.gz"
                log "   📦 Archiving ${SPEND_COUNT} records to ${SPEND_ARCHIVE}..."
                run_psql litellm -c "\COPY (SELECT * FROM \"LiteLLM_SpendLogs\" WHERE \"startTime\" < NOW() - INTERVAL '${SPEND_DAYS} days') TO STDOUT WITH CSV HEADER;" | gzip -9 > "$SPEND_ARCHIVE"
                log "   ✓ Archive created ($(du -h "$SPEND_ARCHIVE" | awk '{print $1}'))."
            fi
            log "   🗑️ Deleting aged records from LiteLLM_SpendLogs..."
            run_psql litellm -c "DELETE FROM \"LiteLLM_SpendLogs\" WHERE \"startTime\" < NOW() - INTERVAL '${SPEND_DAYS} days';"
            PRUNED_SPEND="$SPEND_COUNT"
        fi
    fi

    # Optional LiteLLM Workflow Event pruning
    WORKFLOW_COUNT=$(run_psql_val litellm "SELECT count(*) FROM \"LiteLLM_WorkflowEvent\" WHERE created_at < NOW() - INTERVAL '${SPEND_DAYS} days';" 2>/dev/null || echo "0")
    if [ "$WORKFLOW_COUNT" -gt 0 ] && [ "$DRY_RUN" = false ]; then
        log "   🗑️ Pruning ${WORKFLOW_COUNT} aged LiteLLM_WorkflowEvent records..."
        run_psql litellm -c "DELETE FROM \"LiteLLM_WorkflowEvent\" WHERE created_at < NOW() - INTERVAL '${SPEND_DAYS} days';" || true
    fi
else
    log "\n🧹 Step 1: Skipping LiteLLM Spend Logs (OmniRoute active, LiteLLM PostgreSQL database decommissioned)."
fi

# --- STEP 2: Vacuum & Analyze ---
if [ "$DO_VACUUM" = true ]; then
    log "\n🧽 Step 2: Reclaiming storage and updating statistics with VACUUM ANALYZE..."
    if [ "$DRY_RUN" = true ]; then
        log "   [DRY-RUN] Would run VACUUM ANALYZE across openwebui, authentik, gitea$( [ "$LITELLM_EXISTS" = "1" ] && echo ", and litellm" )."
    else
        if [ "$LITELLM_EXISTS" = "1" ]; then
            log "   • Vacuuming litellm DB..."
            run_psql litellm -c "VACUUM (ANALYZE, VERBOSE) \"LiteLLM_SpendLogs\";" 2>/dev/null || true
            run_psql litellm -c "VACUUM ANALYZE;" 2>/dev/null || true
        fi

        log "   • Vacuuming openwebui DB..."
        run_psql openwebui -c "VACUUM ANALYZE;"

        log "   • Vacuuming authentik DB..."
        run_psql authentik -c "VACUUM ANALYZE;"

        log "   • Vacuuming gitea DB..."
        run_psql gitea -c "VACUUM ANALYZE;"
        log "   ✓ Cluster vacuum and optimizer statistics refreshed."
    fi
else
    log "\n⏩ Step 2: Skipping VACUUM ANALYZE (--no-vacuum specified)."
fi

# --- STEP 3: Final Metrics & Summary ---
if [ "$LITELLM_EXISTS" = "1" ]; then
    LITELLM_SIZE_AFTER=$(run_psql_val litellm "SELECT pg_size_pretty(pg_database_size('litellm'));" 2>/dev/null || echo "N/A")
    SPEND_LOGS_SIZE_AFTER=$(run_psql_val litellm "SELECT pg_size_pretty(pg_total_relation_size('\"LiteLLM_SpendLogs\"'));" 2>/dev/null || echo "N/A")
    LITELLM_SUMMARY="• litellm DB:   ${LITELLM_SIZE_BEFORE} ➔ ${LITELLM_SIZE_AFTER} (SpendLogs: ${SPEND_LOGS_SIZE_BEFORE} ➔ ${SPEND_LOGS_SIZE_AFTER})"
else
    LITELLM_SUMMARY="• Gateway DB:   OmniRoute active (local SQLite, zero PostgreSQL load)"
fi
OPENWEBUI_SIZE_AFTER=$(run_psql_val openwebui "SELECT pg_size_pretty(pg_database_size('openwebui'));")

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

SUMMARY_MSG="Database maintenance completed in ${DURATION}s.
• Pruned: ${PRUNED_SPEND} LiteLLM spend logs
${LITELLM_SUMMARY}
• openwebui DB: ${OPENWEBUI_SIZE_BEFORE} ➔ ${OPENWEBUI_SIZE_AFTER}"

log "\n=================================================="
log "🎉 Maintenance Run Complete!"
log "$SUMMARY_MSG"
log "=================================================="

# --- STEP 4: Push Notification Delivery ---
if [ "$DO_NOTIFY" = true ] && [ -n "$NOTIFY_BIN" ]; then
    log "📲 Dispatching notification via ntfy topic '${NTFY_TOPIC}'..."
    NOTIF_TITLE="pgvector Maintenance Complete"
    [ "$DRY_RUN" = true ] && NOTIF_TITLE="pgvector Maintenance [DRY RUN]"
    
    "$NOTIFY_BIN" \
        -t "$NOTIF_TITLE" \
        -p 3 \
        -g "broom,database,sparkles" \
        "$NTFY_TOPIC" \
        "$SUMMARY_MSG" || log "⚠️ Warning: Failed to send push notification via ntfy."
else
    log "ℹ️ Skipping push notification (DO_NOTIFY=$DO_NOTIFY, NOTIFY_BIN=$NOTIFY_BIN)."
fi
