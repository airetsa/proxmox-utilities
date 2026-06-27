#!/usr/bin/env bash
# =============================================================================
# mediastack | setup.sh
# Run once on install on new Ubuntu Server VM (Made for 22.04.04)
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

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_USER="${SUDO_USER:-$USER}"


# Setup Essentials
# =============================================================================
section "Basic Updates"
apt-get update -qq && apt-get upgrade -y -qq
success "System update successful."

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

# Ubuntu Essentials
section "Installing Packages"
apt-get install -y -qq \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    htop \
    net-tools \
    ufw \
    unzip \
    vim
success "Packages installed"

# Docker
section "Installing Docker"
if command -v docker &>/dev/null; then
    success "Docker already installed: $(docker --version)"
else
    log "Installing Docker CE..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
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

# Add user to docker group
if [[ "$REAL_USER" != "root" ]]; then
    if ! groups "$REAL_USER" | grep -q docker; then
        usermod -aG docker "$REAL_USER"
        warn "Added $REAL_USER to docker group — log out and back in for this to take effect"
    else
        success "$REAL_USER already in docker group"
    fi
fi

# Tailscale
section "Tailscale"
if command -v tailscale &>/dev/null; then
    success "Tailscale already installed: $(tailscale version | head -1)"
else
    log "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    success "Tailscale installed and daemon started"
    warn "Tailscale is installed but NOT yet connected to your network."
fi


## Directory Setup
# =============================================================================
# /opt/mediastack/
# ├── config/
# │   ├── jellyfin/
# │   ├── lidarr/
# │   ├── prowlarr/
# │   ├── sonarr/
# │   ├── bazarr/
# │   ├── qbittorrent/
# │   ├── filebrowser/
# │   └── gluetun/
# ├── downloads/
# │   ├── tv/
# │   └── music/
# └── media/
# │   ├── tv/
#     └── music/
mkdir -p /opt/mediastack/{config/{jellyfin,lidarr,prowlarr,sonarr,bazarr,qbittorent,filebrowser,gluetun},downloads/{tv,music},media/{tv,music}}

sudo chown -R $PUID:$PGID /opt/mediastack/
sudo chmod -R a=,a+rX,u+w,g+w /opt/mediastack/

# Security and Networking
# =============================================================================
section "Firewall (UFW)"

if ufw status | grep -q "Status: inactive"; then
    log "Configuring UFW..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh

    # Allow Tailscale
    ufw allow in on tailscale0

    # Jellyfin
    ufw allow 8096/tcp comment 'Jellyfin'

    ufw --force enable
    success "UFW enabled with rules for SSH, Tailscale, Jellyfin"
else
    log "UFW already active"
    success "Skipping firewall configuration..."
fi


# :3 Completion :3
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}Script setup.sh complete.{NC}"
echo ""
echo -e "  Next steps:"
echo -e "  1. Connect Tailscale:    sudo tailscale up (only if necessary)"
echo -e "  2. Log out and back in   (picks up docker group)"
echo -e "  3. Run deployment        deploy.sh"
echo ""

