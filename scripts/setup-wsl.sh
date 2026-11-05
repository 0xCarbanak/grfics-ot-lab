#!/usr/bin/env bash
#
# GRFICS OT Lab — native Docker Engine bootstrap for WSL2 / Linux
#
# Installs Docker Engine natively so the lab's bridge networks
# (192.168.95.0/24, 192.168.90.0/24) become REAL routable interfaces in
# your network namespace. You then scan and attack them directly, exactly
# like plugging into a plant floor — no port-forward hacks, no exec-ing
# into containers.
#
# Run once on a fresh machine:   sudo ./scripts/setup-wsl.sh
#
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1" >&2; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_USER="${SUDO_USER:-$(whoami)}"

[ "$(id -u)" -eq 0 ] || { err "Run with sudo: sudo ./scripts/setup-wsl.sh"; exit 1; }

echo
echo "=================================================================="
echo "  GRFICS OT Lab — Native Docker Engine Bootstrap"
echo "=================================================================="
echo

# --- 1. Detect Docker Desktop interference --------------------------------
if [ -L /usr/bin/docker ] && readlink /usr/bin/docker | grep -q docker-desktop; then
  warn "Docker Desktop WSL integration is active in this distro."
  warn "It owns /usr/bin/docker and /var/run/docker.sock, which will fight"
  warn "the native engine. For a clean setup, in Docker Desktop go to:"
  warn "    Settings > Resources > WSL Integration > turn OFF for this distro"
  warn "then run 'wsl --shutdown' in PowerShell, reopen, and re-run this script."
  echo
  read -rp "Continue anyway and let native Docker take over the socket? [y/N] " a
  [[ "${a:-N}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# --- 2. Install Docker Engine ---------------------------------------------
if command -v dockerd >/dev/null 2>&1 && [ -f /usr/bin/dockerd ]; then
  ok "Native Docker Engine already installed ($(dockerd --version 2>/dev/null || echo present))"
else
  log "Installing Docker Engine (docker.io)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq docker.io uidmap >/dev/null
  ok "Docker Engine installed"
fi

# --- 3. Install Docker Compose v2 plugin ----------------------------------
if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose v2 already available"
else
  log "Installing Docker Compose v2 plugin..."
  ARCH="$(uname -m)"; case "$ARCH" in x86_64) ARCH=x86_64;; aarch64|arm64) ARCH=aarch64;; esac
  mkdir -p /usr/local/lib/docker/cli-plugins
  CV="v2.32.4"
  curl -fsSL "https://github.com/docker/compose/releases/download/${CV}/docker-compose-linux-${ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  ok "Docker Compose v2 installed ($CV)"
fi

# --- 4. Enable + start the daemon (systemd) -------------------------------
if [ -d /run/systemd/system ]; then
  log "Enabling docker.service via systemd..."
  systemctl enable --now docker >/dev/null 2>&1 || systemctl restart docker
  ok "docker.service running"
else
  warn "systemd not detected — starting dockerd manually."
  warn "Add 'systemd=true' under [boot] in /etc/wsl.conf for persistence."
  pgrep -x dockerd >/dev/null || (dockerd >/var/log/dockerd.log 2>&1 &)
  sleep 3
fi

# --- 5. Docker group membership -------------------------------------------
if ! getent group docker | grep -qw "$REAL_USER"; then
  log "Adding $REAL_USER to the docker group..."
  usermod -aG docker "$REAL_USER"
  warn "Group change takes effect on next login. Run 'newgrp docker' or restart WSL."
fi

# --- 6. Verify we're on the native engine ---------------------------------
if docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi "Docker Desktop"; then
  err "docker CLI is still talking to Docker Desktop, not the native engine."
  err "Disable DD WSL integration for this distro, 'wsl --shutdown', re-run."
  exit 1
fi
ok "Talking to native Docker Engine: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"

# --- 7. Bring up the lab ---------------------------------------------------
cd "$REPO_DIR"
log "Pulling lab images (first run takes a few minutes)..."
docker compose --profile siem pull
log "Starting the full lab (plant + PLC + HMI + EWS + router + SIEM)..."
docker compose --profile siem up -d

echo
log "Waiting for the plant floor to come online..."
sleep 20

# --- 8. Show the routable subnet ------------------------------------------
echo
echo "=================================================================="
ok  "Lab is up on NATIVE Docker — the OT subnets are now routable."
echo "=================================================================="
echo
echo "  Scan the plant floor directly from this box:"
echo "      nmap -sn 192.168.95.0/24"
echo
echo "  ICS network  192.168.95.0/24   (PLC .2, remote I/O .10-.15, EWS .5)"
echo "  DMZ network  192.168.90.0/24   (HMI .107, Wazuh .20, Zeek .30)"
echo
echo "  Web UIs (from Windows browser via WSL localhost forwarding):"
echo "      http://localhost       3D plant"
echo "      http://localhost:8080  OpenPLC   (openplc/openplc)"
echo "      http://localhost:6081  HMI       (admin/admin)"
echo "      http://localhost:5601  Wazuh SIEM"
echo
echo "  Verify routing:  ip addr | grep -E 'br-|192.168.9'"
echo "=================================================================="
