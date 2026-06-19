#!/usr/bin/env bash
# =============================================================================
# mediastack | startup.sh
# Run to start Docker containers (Made for Ubuntu 22.04.04)
# =============================================================================


# Script Setup
# =============================================================================
# -e = exit immediatly if anyting fails
# -u = treats unset variables as an error
# -o pipefail = whole pipeline fails if any part of it fails
set -euo pipefail

# Colors
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


# Docker
# =============================================================================
section "Starting Docker Services"

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
[[ ! -f "$COMPOSE_FILE" ]] && error "docker-compose.yml not found in $SCRIPT_DIR"

log "Pulling images (this may take a while)..."
docker compose --env-file "$SCRIPT_DIR/.env" -f "$COMPOSE_FILE" pull

log "Starting containers..."
docker compose --env-file "$SCRIPT_DIR/.env" -f "$COMPOSE_FILE" up -d

success "Containers started"
VM_IP=$(hostname -I | awk '{print $1}')


# Summary
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║         mediastack is up and running!        ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Immich${NC}    →  http://${VM_IP}:${IMMICH_PORT}"
echo -e "  ${BOLD}Jellyfin${NC}  →  http://${VM_IP}:${JELLYFIN_PORT}"
echo ""
echo -e "  ${BOLD}Media root:${NC} ${MEDIASTACK_ROOT}"
echo ""
echo -e "  ${YELLOW}First run:${NC}"
echo -e "  • Immich: open the URL above and create your admin account"
echo -e "  • Jellyfin: open the URL above and run through the setup wizard"
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "  docker compose -f $COMPOSE_FILE ps          # status"
echo -e "  docker compose -f $COMPOSE_FILE logs -f     # live logs"
echo -e "  docker compose -f $COMPOSE_FILE down        # stop all"
echo -e "  docker compose -f $COMPOSE_FILE pull && docker compose -f $COMPOSE_FILE up -d  # update"
echo ""