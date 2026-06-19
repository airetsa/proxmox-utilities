#!/usr/bin/env bash
# =============================================================================
# update.sh
# Pull latest images and restart any changed containers
# Usage: bash update.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/update.log"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

# Tee all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "========================================"
echo "  mediastack update — $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ ! -f "$COMPOSE_FILE" ]] && { echo "docker-compose.yml not found"; exit 1; }
[[ ! -f "$ENV_FILE" ]]     && { echo ".env not found"; exit 1; }

# ── Backup Immich DB ──────────────────────────────────────────────────────────
section "Immich DB Backup"

BACKUP_DIR="$SCRIPT_DIR/backups"
mkdir -p "$BACKUP_DIR"

# Keep only the last 5 backups
BACKUP_FILE="$BACKUP_DIR/immich_$(date +%F).sql"

if docker ps --format '{{.Names}}' | grep -q "immich_postgres"; then
    log "Backing up Immich database..."
    docker exec immich_postgres pg_dumpall -U immich > "$BACKUP_FILE"
    success "Backup saved to $BACKUP_FILE"

    # Prune old backups — keep last 5
    ls -t "$BACKUP_DIR"/immich_*.sql 2>/dev/null | tail -n +6 | xargs -r rm
    log "Old backups pruned (keeping last 5)"
else
    warn "immich_postgres not running — skipping backup"
fi

# ── Pull & Update ─────────────────────────────────────────────────────────────
section "Pulling Images"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull

section "Restarting Changed Containers"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d

# ── Cleanup ───────────────────────────────────────────────────────────────────
section "Cleanup"
log "Removing unused images..."
docker image prune -f
success "Done"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
success "Update complete — $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
echo ""
