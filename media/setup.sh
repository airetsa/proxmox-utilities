#!/usr/bin/env bash
# =============================================================================
# mediastack/setup.sh
# Automated setup for mediastack (Immich + Jellyfin) on Ubuntu
# =============================================================================
set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()     { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
section "Preflight Checks"

[[ $EUID -ne 0 ]] && error "Run this script with sudo: sudo bash setup.sh"

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

# Sanity check key variables
[[ "$DB_PASSWORD" == "change_me_please" ]] && \
    error "Please set a real DB_PASSWORD in your .env file before running setup"

[[ -z "${MEDIASTACK_ROOT:-}" ]] && error "MEDIASTACK_ROOT is not set in .env"

# ── System Update ─────────────────────────────────────────────────────────────
section "System Update"
log "Updating package lists..."
apt-get update -qq
log "Installing prerequisites..."
apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    htop \
    net-tools \
    ufw
success "Prerequisites installed"

# ── Docker Installation ───────────────────────────────────────────────────────
section "Docker"

if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version)
    success "Docker already installed: $DOCKER_VER"
else
    log "Installing Docker CE..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker
    success "Docker installed and started"
fi

# Add current sudo user to docker group (not root itself)
REAL_USER="${SUDO_USER:-$USER}"
if [[ "$REAL_USER" != "root" ]]; then
    if ! groups "$REAL_USER" | grep -q docker; then
        usermod -aG docker "$REAL_USER"
        warn "Added $REAL_USER to docker group — you'll need to log out/in (or run 'newgrp docker')"
    else
        success "$REAL_USER is already in the docker group"
    fi
fi

# ── Directory Structure ───────────────────────────────────────────────────────
section "Creating Directory Structure"

DIRS=(
    # Immich
    "${IMMICH_UPLOAD_LOCATION}"
    "${IMMICH_DATA}"
    "${IMMICH_DB_DATA}"

    # Jellyfin
    "${JELLYFIN_CONFIG}"
    "${JELLYFIN_CACHE}"

    # Media library
    "${MEDIA_MOVIES}"
    "${MEDIA_TVSHOWS}"
    "${MEDIA_MUSIC}"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
    chown -R "${PUID}:${PGID}" "$dir"
done

success "Directory structure created under ${MEDIASTACK_ROOT}"
log "Layout:"
find "${MEDIASTACK_ROOT}" -maxdepth 3 -type d | sed 's|[^/]*/|  |g'

# ── Firewall ──────────────────────────────────────────────────────────────────
section "Firewall (UFW)"

if ufw status | grep -q "Status: inactive"; then
    log "Configuring UFW..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow "${IMMICH_PORT}/tcp" comment 'Immich'
    ufw allow "${JELLYFIN_PORT}/tcp" comment 'Jellyfin HTTP'
    ufw allow "${JELLYFIN_HTTPS_PORT}/tcp" comment 'Jellyfin HTTPS'
    ufw --force enable
    success "UFW enabled with rules for SSH, Immich (:${IMMICH_PORT}), Jellyfin (:${JELLYFIN_PORT})"
else
    log "UFW already active — adding mediastack rules..."
    ufw allow "${IMMICH_PORT}/tcp" comment 'Immich' 2>/dev/null || true
    ufw allow "${JELLYFIN_PORT}/tcp" comment 'Jellyfin HTTP' 2>/dev/null || true
    success "Firewall rules added"
fi

# ── Docker Compose ────────────────────────────────────────────────────────────
section "Starting Services"

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
[[ ! -f "$COMPOSE_FILE" ]] && error "docker-compose.yml not found in $SCRIPT_DIR"

log "Pulling images (this may take a while)..."
docker compose --env-file "$SCRIPT_DIR/.env" -f "$COMPOSE_FILE" pull

log "Starting containers..."
docker compose --env-file "$SCRIPT_DIR/.env" -f "$COMPOSE_FILE" up -d

success "Containers started"

# ── Summary ───────────────────────────────────────────────────────────────────
VM_IP=$(hostname -I | awk '{print $1}')

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
echo -e "    Point libraries at: /media/movies, /media/tvshows, /media/music"
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "  docker compose -f $COMPOSE_FILE ps          # status"
echo -e "  docker compose -f $COMPOSE_FILE logs -f     # live logs"
echo -e "  docker compose -f $COMPOSE_FILE down        # stop all"
echo -e "  docker compose -f $COMPOSE_FILE pull && docker compose -f $COMPOSE_FILE up -d  # update"
echo ""
