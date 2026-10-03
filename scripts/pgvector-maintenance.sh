#!/usr/bin/env bash
#
# pgvector-maintenance.sh - Spencer's Homelab Database & Vector Maintenance Pipeline
#
# Automates:
#   1. Concurrent HNSW vector index & GIN full-text index reindexing in Hindsight
#   2. Archival & pruning of aged LiteLLM spend logs (> 30 days default)
#   3. Archival & pruning of completed Hindsight async operations (> 14 days default)
#   4. Reclaiming bloat via VACUUM (ANALYZE) across all homelab databases
#   5. Push notification summary delivery via ntfy
#
# Usage:
#   scripts/pgvector-maintenance.sh [OPTIONS]
#
# Options:
#   --dry-run             Preview actions and record counts without altering data
#   --spend-days <N>      Retention period in days for LiteLLM spend logs (default: 30)
#   --async-days <N>      Retention period in days for Hindsight async ops (default: 14)
#   --no-reindex          Skip vector index reindexing
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
HINDSIGHT_SIZE_BEFORE=$(run_psql_val hindsight "SELECT pg_size_pretty(pg_database_size('hindsight'));")
LITELLM_SIZE_BEFORE=$(run_psql_val litellm "SELECT pg_size_pretty(pg_database_size('litellm'));")
SPEND_LOGS_SIZE_BEFORE=$(run_psql_val litellm "SELECT pg_size_pretty(pg_total_relation_size('\"LiteLLM_SpendLogs\"'));")
MEMORY_UNITS_SIZE_BEFORE=$(run_psql_val hindsight "SELECT pg_size_pretty(pg_total_relation_size('memory_units'));")

log "📊 Initial Database Sizes:"
log "   • hindsight DB: ${HINDSIGHT_SIZE_BEFORE} (memory_units: ${MEMORY_UNITS_SIZE_BEFORE})"
log "   • litellm DB:   ${LITELLM_SIZE_BEFORE} (LiteLLM_SpendLogs: ${SPEND_LOGS_SIZE_BEFORE})"

# --- STEP 1: LiteLLM Spend Logs Archival & Pruning ---
log "\n🧹 Step 1: Evaluating LiteLLM Spend Logs (> ${SPEND_DAYS} days)..."
SPEND_COUNT=$(run_psql_val litellm "SELECT count(*) FROM \"LiteLLM_SpendLogs\" WHERE \"startTime\" < NOW() - INTERVAL '${SPEND_DAYS} days';")
log "   Found ${SPEND_COUNT} aged spend log records."

PRUNED_SPEND=0
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
WORKFLOW_COUNT=$(run_psql_val litellm "SELECT count(*) FROM \"LiteLLM_WorkflowEvent\" WHERE created_at < NOW() - INTERVAL '${SPEND_DAYS} days';" || echo "0")
if [ "$WORKFLOW_COUNT" -gt 0 ] && [ "$DRY_RUN" = false ]; then
    log "   🗑️ Pruning ${WORKFLOW_COUNT} aged LiteLLM_WorkflowEvent records..."
    run_psql litellm -c "DELETE FROM \"LiteLLM_WorkflowEvent\" WHERE created_at < NOW() - INTERVAL '${SPEND_DAYS} days';" || true
fi

# --- STEP 2: Hindsight Ephemeral Task States Archival & Pruning ---
log "\n🧹 Step 2: Evaluating Hindsight Ephemeral Operations (> ${ASYNC_DAYS} days)..."
ASYNC_COUNT=$(run_psql_val hindsight "SELECT count(*) FROM async_operations WHERE status IN ('completed', 'failed') AND completed_at < NOW() - INTERVAL '${ASYNC_DAYS} days';")
log "   Found ${ASYNC_COUNT} aged completed/failed async operations."

PRUNED_ASYNC=0
if [ "$ASYNC_COUNT" -gt 0 ]; then
    if [ "$DRY_RUN" = true ]; then
        log "   [DRY-RUN] Would archive and delete ${ASYNC_COUNT} async operations."
        PRUNED_ASYNC="$ASYNC_COUNT"
    else
        if [ "$DO_ARCHIVE" = true ]; then
            ASYNC_ARCHIVE="${ARCHIVE_DIR}/hindsight_async_ops_${TIMESTAMP}.csv.gz"
            log "   📦 Archiving ${ASYNC_COUNT} records to ${ASYNC_ARCHIVE}..."
            run_psql hindsight -c "\COPY (SELECT * FROM async_operations WHERE status IN ('completed', 'failed') AND completed_at < NOW() - INTERVAL '${ASYNC_DAYS} days') TO STDOUT WITH CSV HEADER;" | gzip -9 > "$ASYNC_ARCHIVE"
            log "   ✓ Archive created ($(du -h "$ASYNC_ARCHIVE" | awk '{print $1}'))."
        fi
        log "   🗑️ Deleting aged records from async_operations..."
        run_psql hindsight -c "DELETE FROM async_operations WHERE status IN ('completed', 'failed') AND completed_at < NOW() - INTERVAL '${ASYNC_DAYS} days';"
        PRUNED_ASYNC="$ASYNC_COUNT"
    fi
fi

# Clean up aged Hindsight llm_requests if any exist
LLM_REQ_COUNT=$(run_psql_val hindsight "SELECT count(*) FROM llm_requests WHERE started_at < NOW() - INTERVAL '30 days';" || echo "0")
if [ "$LLM_REQ_COUNT" -gt 0 ] && [ "$DRY_RUN" = false ]; then
    log "   🗑️ Pruning ${LLM_REQ_COUNT} aged llm_requests..."
    run_psql hindsight -c "DELETE FROM llm_requests WHERE started_at < NOW() - INTERVAL '30 days';" || true
fi

# --- STEP 3: Vector Index Optimization (HNSW & GIN) ---
if [ "$DO_REINDEX" = true ]; then
    log "\n⚡ Step 3: Reindexing HNSW vector indexes and GIN text indexes..."
    if [ "$DRY_RUN" = true ]; then
        log "   [DRY-RUN] Would run REINDEX TABLE CONCURRENTLY on memory_units and mental_models."
    else
        log "   🔨 Reindexing table 'memory_units' concurrently..."
        run_psql hindsight -c "REINDEX TABLE CONCURRENTLY memory_units;"
        log "   🔨 Reindexing table 'mental_models' concurrently..."
        run_psql hindsight -c "REINDEX TABLE CONCURRENTLY mental_models;"
        log "   ✓ Vector and search indexes rebuilt successfully."
    fi
else
    log "\n⏩ Step 3: Skipping reindexing (--no-reindex specified)."
fi

# --- STEP 4: Vacuum & Analyze ---
if [ "$DO_VACUUM" = true ]; then
    log "\n🧽 Step 4: Reclaiming storage and updating statistics with VACUUM ANALYZE..."
    if [ "$DRY_RUN" = true ]; then
        log "   [DRY-RUN] Would run VACUUM ANALYZE across hindsight, litellm, authentik, and gitea."
    else
        log "   • Vacuuming hindsight DB (vector & relation tables)..."
        run_psql hindsight -c "VACUUM (ANALYZE, VERBOSE) memory_units;"
        run_psql hindsight -c "VACUUM (ANALYZE, VERBOSE) mental_models;"
        run_psql hindsight -c "VACUUM (ANALYZE, VERBOSE) async_operations;"
        run_psql hindsight -c "VACUUM ANALYZE;"

        log "   • Vacuuming litellm DB..."
        run_psql litellm -c "VACUUM (ANALYZE, VERBOSE) \"LiteLLM_SpendLogs\";"
        run_psql litellm -c "VACUUM ANALYZE;"

        log "   • Vacuuming authentik DB..."
        run_psql authentik -c "VACUUM ANALYZE;"

        log "   • Vacuuming gitea DB..."
        run_psql gitea -c "VACUUM ANALYZE;"
        log "   ✓ Cluster vacuum and optimizer statistics refreshed."
    fi
else
    log "\n⏩ Step 4: Skipping VACUUM ANALYZE (--no-vacuum specified)."
fi

# --- STEP 5: Final Metrics & Summary ---
HINDSIGHT_SIZE_AFTER=$(run_psql_val hindsight "SELECT pg_size_pretty(pg_database_size('hindsight'));")
LITELLM_SIZE_AFTER=$(run_psql_val litellm "SELECT pg_size_pretty(pg_database_size('litellm'));")
SPEND_LOGS_SIZE_AFTER=$(run_psql_val litellm "SELECT pg_size_pretty(pg_total_relation_size('\"LiteLLM_SpendLogs\"'));")
MEMORY_UNITS_SIZE_AFTER=$(run_psql_val hindsight "SELECT pg_size_pretty(pg_total_relation_size('memory_units'));")

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

SUMMARY_MSG="Database maintenance completed in ${DURATION}s.
• Pruned: ${PRUNED_SPEND} LiteLLM spend logs, ${PRUNED_ASYNC} Hindsight async tasks
• litellm DB: ${LITELLM_SIZE_BEFORE} ➔ ${LITELLM_SIZE_AFTER} (SpendLogs: ${SPEND_LOGS_SIZE_BEFORE} ➔ ${SPEND_LOGS_SIZE_AFTER})
• hindsight DB: ${HINDSIGHT_SIZE_BEFORE} ➔ ${HINDSIGHT_SIZE_AFTER} (memory_units: ${MEMORY_UNITS_SIZE_BEFORE} ➔ ${MEMORY_UNITS_SIZE_AFTER})
• Reindex HNSW: $([ "$DO_REINDEX" = true ] && echo 'Completed' || echo 'Skipped')"

log "\n=================================================="
log "🎉 Maintenance Run Complete!"
log "$SUMMARY_MSG"
log "=================================================="

# --- STEP 6: Push Notification Delivery ---
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
