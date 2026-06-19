#!/usr/bin/env bash
# =============================================================================
# mediastack | deploy.sh
# Run to deploy and start Docker containers (Made for Ubuntu Server 22.04.04)
# =============================================================================


# Script Setup
# =============================================================================
# Failure Prep
# -e = exit immediatly if anyting fails
# -u = treats unset variables as an error
# -o pipefail = whole pipeline fails if any part of it fails
set -euo pipefail

# Formatting
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_WAIT=60

# Load .env
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck source=.env
    source "$SCRIPT_DIR/.env"
    set +a
    success "Loaded .env"
else
    error ".env file not found in $SCRIPT_DIR — copy .env.example and edit it first"
fi


# Docker Deployment
# =============================================================================

# Start gluetun VPN tunnel first
section "Starting Mullvad via gluetun VPN tunnel..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d gluetun

# Wait loop for VPN tunnel setup
log "Waiting for VPN tunnel..."
ELAPSED=0
until [ "$(docker inspect --format='{{.State.Health.Status}}' "$GLUETUN_CONTAINER_NAME")" = "healthy" ]; do
    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        error "Gluetun did not become healthy after ${MAX_WAIT}s. Check: docker logs $GLUETUN_CONTAINER_NAME"
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
success "VPN tunnel is up"

# Verify Mullvad exit IP
log "Verifying exit IP..."
RESULT=$(docker exec "$GLUETUN_CONTAINER_NAME" wget -qO- https://am.i.mullvad.net/json 2>/dev/null || true)
if echo "$RESULT" | grep -q '"mullvad_exit_ip":true'; then
    success "Confirmed exit through Mullvad"
else
    error "Exit IP check failed — not routing through Mullvad. Aborting."
fi

Section "Starting remaining services..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
success "mediastack is up"