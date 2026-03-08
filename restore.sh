#!/bin/bash
# ================================================================
#  🛠️  PI DISASTER RECOVERY — raspberrypi / piadmin
#  Repo: github.com/apsrathee/pi-recovery
# ================================================================
set -euo pipefail

# ── Colour helpers ───────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info() { echo -e "\n${CYAN}${BOLD}▶  $*${RESET}"; }
ok()   { echo -e "${GREEN}✅  $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️   $*${RESET}"; }
die()  { echo -e "\n${RED}❌  $*${RESET}" >&2; exit 1; }

# ── Trap: catch unexpected exits ─────────────────────────────────
trap 'die "Unexpected failure at line $LINENO. Review the log above."' ERR

# ── Constants ────────────────────────────────────────────────────
PI_USER="piadmin"
PI_HOME="/home/${PI_USER}"
MEDIA_STACK="${PI_HOME}/docker/media-stack"
PIALERTS_DIR="${PI_HOME}/.pialerts"
RCLONE_REMOTE="gcrypt:pi-backups"
MEDIA_MOUNT="${PI_HOME}/media"
LOG_FILE="/tmp/pi-restore-$(date +%Y%m%d_%H%M%S).log"

# Tee all output to log file from the start
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Guard: must be run as piadmin ────────────────────────────────
[[ "$(whoami)" == "$PI_USER" ]] || \
    die "Run this script as '${PI_USER}', not '$(whoami)'."

# ── Confirmation ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   🚨  FULL PI DISASTER RECOVERY                      ║${RESET}"
echo -e "${BOLD}║   Host: raspberrypi  |  User: piadmin                ║${RESET}"
echo -e "${BOLD}║   This will rebuild your ENTIRE infrastructure.      ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${YELLOW}Log file: ${LOG_FILE}${RESET}"
echo ""
read -rp "  Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

# ================================================================
# STEP 1 — Base packages
# ================================================================
info "STEP 1/9 — Installing base packages..."
sudo apt update -qq
sudo apt install -y curl rclone git
ok "Base packages installed."

# ================================================================
# STEP 2 — Docker + Compose v2 plugin
# ================================================================
info "STEP 2/9 — Installing Docker + Compose v2..."

if command -v docker &>/dev/null; then
    warn "Docker already installed ($(docker --version)). Skipping install."
else
    curl -fsSL https://get.docker.com | sh
    ok "Docker installed."
fi

# Add piadmin to docker group (takes effect after re-login)
sudo usermod -aG docker "$PI_USER" 2>/dev/null || true
sudo systemctl enable docker
sudo systemctl start docker

# Install Compose v2 plugin for aarch64 (Pi 4)
COMPOSE_DIR="/usr/local/lib/docker/cli-plugins"
sudo mkdir -p "$COMPOSE_DIR"
if ! sudo docker compose version &>/dev/null 2>&1; then
    info "Downloading Docker Compose v2 plugin (aarch64)..."
    COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64"
    sudo curl -fsSL "$COMPOSE_URL" -o "${COMPOSE_DIR}/docker-compose"
    sudo chmod +x "${COMPOSE_DIR}/docker-compose"
fi
ok "$(sudo docker compose version)"

# Docker cmd wrapper — use sudo since group membership requires re-login
DOCKER="sudo docker"
ok "Docker cmd set to: ${DOCKER}"

# ================================================================
# STEP 3 — rclone config + verify
# ================================================================
info "STEP 3/9 — Configuring rclone (gcrypt remote)..."
echo ""
echo -e "${YELLOW}  ⚠️  The remote MUST be named exactly: gcrypt${RESET}"
echo -e "${YELLOW}     It should point to your Google Drive gcrypt path.${RESET}"
echo ""
rclone config

# Verify remote exists before proceeding
if ! rclone listremotes | grep -q "^gcrypt:"; then
    die "rclone remote 'gcrypt' not found after config. Did you name it correctly?"
fi

# Quick test: list the backup root to confirm decryption key is correct
info "Verifying gcrypt remote is readable..."
if ! rclone lsd "${RCLONE_REMOTE}" &>/dev/null; then
    die "Cannot list ${RCLONE_REMOTE}. Check your encryption password and remote config."
fi
ok "rclone gcrypt remote verified — backup is accessible."

# ================================================================
# STEP 4 — Restore /home/piadmin from backup
# ================================================================
info "STEP 4/9 — Restoring ${PI_HOME} from ${RCLONE_REMOTE}..."
echo -e "${YELLOW}  This may take several minutes depending on backup size...${RESET}"
echo ""

rclone sync "${RCLONE_REMOTE}" "${PI_HOME}" \
    --exclude "media/**" \
    --progress \
    --stats-one-line \
    --transfers 4

ok "rclone restore complete."

# Sanity check — key directories should exist
for DIR in "${PIALERTS_DIR}" "${MEDIA_STACK}" "${PI_HOME}/docker"; do
    [[ -d "$DIR" ]] && ok "Found: ${DIR}" || warn "Missing after restore: ${DIR}"
done

# File count
RESTORED=$(find "$PI_HOME" \
    -not -path '*/media/*' \
    -not -path '*/.cache/*' \
    -not -path '*/node_modules/*' \
    | wc -l)
ok "Restored approximately ${RESTORED} files."

# Restore execute permissions on all scripts (rclone may drop +x)
find "$PI_HOME" -name "*.sh" -exec chmod +x {} \;
ok "Script permissions (+x) restored across ${PI_HOME}."

# ================================================================
# STEP 5 — 4TB external HDD mount
# ================================================================
info "STEP 5/9 — Checking external HDD mount (${MEDIA_MOUNT})..."
mkdir -p "$MEDIA_MOUNT"

# Auto-detect the EXT4 drive by size (looks for 2T–5T range to catch 4TB)
# Excludes mmcblk (SD card) and any loop/ram devices
HDD_DEV=$(lsblk -rno NAME,FSTYPE,SIZE \
    | awk '$2=="ext4" && $1!~/^mmcblk|^loop|^ram/ && $3~/[2-5]\.?[0-9]*T/ {print "/dev/"$1}' \
    | head -1)

if [[ -n "$HDD_DEV" ]]; then
    HDD_UUID=$(sudo blkid -s UUID -o value "$HDD_DEV")
    HDD_SIZE=$(lsblk -rno SIZE "$HDD_DEV")
    info "Detected HDD: ${HDD_DEV} | Size: ${HDD_SIZE} | UUID: ${HDD_UUID}"

    if ! grep -q "$HDD_UUID" /etc/fstab; then
        echo "UUID=${HDD_UUID}  ${MEDIA_MOUNT}  ext4  defaults,nofail  0  2" \
            | sudo tee -a /etc/fstab > /dev/null
        ok "Added HDD to /etc/fstab with 'nofail' option."
    else
        ok "HDD UUID already in /etc/fstab."
    fi

    if mountpoint -q "$MEDIA_MOUNT"; then
        ok "HDD already mounted at ${MEDIA_MOUNT}."
    else
        sudo mount "$MEDIA_MOUNT"
        ok "HDD mounted at ${MEDIA_MOUNT}."
    fi

    # Show media folder structure
    echo ""
    echo "  Media folder contents:"
    ls -lh "$MEDIA_MOUNT" 2>/dev/null | awk '{print "    " $0}' || true
else
    warn "Could not auto-detect 4TB HDD."
    warn "Run: sudo lsblk -f  — find your EXT4 partition and mount manually."
    warn "Docker containers requiring /media paths WILL FAIL until this is fixed."
    echo ""
    echo "  Manual fix:"
    echo "    sudo blkid                                    # find UUID"
    echo "    echo 'UUID=<uuid>  ${MEDIA_MOUNT}  ext4  defaults,nofail  0  2' | sudo tee -a /etc/fstab"
    echo "    sudo mount ${MEDIA_MOUNT}"
fi

# ================================================================
# STEP 6 — System config (IPv6, hostname)
# ================================================================
info "STEP 6/9 — Applying system configuration..."

# Hostname
CURRENT_HOST=$(hostname)
if [[ "$CURRENT_HOST" != "raspberrypi" ]]; then
    sudo hostnamectl set-hostname raspberrypi
    ok "Hostname set to raspberrypi (was: ${CURRENT_HOST})."
else
    ok "Hostname already correct: raspberrypi."
fi

# IPv6 — force IPv4 preference in gai.conf
# (Prevents Docker pull / rclone / pip / apt from preferring IPv6 and timing out)
if ! grep -q "precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
    echo "precedence ::ffff:0:0/96  100" | sudo tee -a /etc/gai.conf > /dev/null
    ok "IPv4 preference forced in /etc/gai.conf."
else
    ok "IPv4 preference already configured in /etc/gai.conf."
fi

# ================================================================
# STEP 7 — Crontab + systemd services
# ================================================================
info "STEP 7/9 — Restoring crontab and systemd services..."

# --- Crontab ---
CRONTAB_BACKUP="${PIALERTS_DIR}/crontab_backup"
if [[ -f "$CRONTAB_BACKUP" ]]; then
    crontab "$CRONTAB_BACKUP"
    ok "Crontab restored from ${CRONTAB_BACKUP}."
    echo "  Installed crontab entries:"
    crontab -l | awk '{print "    " $0}'
else
    warn "crontab_backup not found at ${CRONTAB_BACKUP} — skipping."
fi

# --- Systemd services ---
# Known services in your stack
declare -a SERVICES=(
    "pialertsbot.service"
    "pialerts-auto-update.timer"
    "pi-dashboard.service"
)

echo ""
for SERVICE in "${SERVICES[@]}"; do
    SRC="${PIALERTS_DIR}/${SERVICE}"
    DEST="/etc/systemd/system/${SERVICE}"
    if [[ -f "$SRC" ]]; then
        sudo cp "$SRC" "$DEST"
        ok "Installed ${SERVICE} → ${DEST}"
    else
        warn "${SERVICE} not found in ${PIALERTS_DIR} — skipping."
    fi
done

sudo systemctl daemon-reload
ok "systemd daemon reloaded."

# Enable + start each service found
for SERVICE in "${SERVICES[@]}"; do
    if [[ -f "/etc/systemd/system/${SERVICE}" ]]; then
        sudo systemctl enable "$SERVICE" 2>/dev/null && ok "Enabled: ${SERVICE}"

        # Timers: just enable, they activate on schedule
        # Services: start now
        if [[ "$SERVICE" == *.service ]]; then
            sudo systemctl start "$SERVICE" \
                && ok "Started: ${SERVICE}" \
                || warn "Failed to start ${SERVICE} — check: journalctl -u ${SERVICE} -n 30"
        fi
    fi
done

# ================================================================
# STEP 8 — Tailscale
# ================================================================
info "STEP 8/9 — Installing Tailscale..."

if command -v tailscale &>/dev/null; then
    warn "Tailscale already installed ($(tailscale version | head -1))."
else
    curl -fsSL https://tailscale.com/install.sh | sh
    ok "Tailscale installed."
fi

echo ""
echo -e "${YELLOW}  ⚠️  Tailscale needs interactive auth — a URL will appear below.${RESET}"
echo -e "${YELLOW}     Open it in your browser to authenticate, then this script continues.${RESET}"
echo -e "${YELLOW}     --accept-dns=false keeps AdGuard Home as your DNS resolver.${RESET}"
echo ""

sudo tailscale up \
    --hostname=raspberrypi \
    --accept-routes \
    --accept-dns=false

ok "Tailscale connected."
echo "  Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'check: tailscale ip')"

# ================================================================
# STEP 9 — Docker media stack
# ================================================================
info "STEP 9/9 — Starting Docker media stack..."

[[ -d "$MEDIA_STACK" ]] || \
    die "Stack directory not found: ${MEDIA_STACK}. rclone restore may have failed."

cd "$MEDIA_STACK"

# Pull fresh images before starting
info "Pulling latest Docker images (this may take a while)..."
$DOCKER compose pull --quiet || warn "Image pull had warnings — continuing anyway."

# Start the stack
$DOCKER compose up -d
ok "Docker stack launched."

# ── Health check loop ─────────────────────────────────────────
echo ""
info "Waiting for containers to stabilise (up to 90s)..."
echo ""
for i in $(seq 1 18); do
    sleep 5
    TOTAL=$($DOCKER compose ps --services 2>/dev/null | wc -l)
    RUNNING=$($DOCKER compose ps \
        --filter "status=running" \
        --format "{{.Service}}" 2>/dev/null | wc -l)
    PROGRESS=$(printf '%-18s' "$(printf '#%.0s' $(seq 1 $i))")
    echo -e "  [${PROGRESS}]  ${RUNNING}/${TOTAL} containers running"
    [[ "$RUNNING" -ge "$TOTAL" ]] && break
done

echo ""
$DOCKER compose ps
echo ""

# ── Port spot-check for known services ───────────────────────
info "Spot-checking key service ports..."
echo ""

# Format: "Name Port Protocol"
declare -A PORTS=(
    ["Plex"]="32400"
    ["qBittorrent"]="8080"
    ["Radarr"]="7878"
    ["Sonarr"]="8989"
    ["Prowlarr"]="9696"
    ["Jackett"]="9117"
    ["FlareSolverr"]="8191"
    ["Grafana"]="3001"        # host 3001 → container 3000
    ["Prometheus"]="9090"
    ["cAdvisor"]="8081"       # host 8081 → container 8080
    ["Node Exporter"]="9100"  # network_mode: host, exposes directly
    ["Portainer"]="9000"
    ["Uptime Kuma"]="3100"
    ["Omni-Tools"]="8082"
    ["Pi Dashboard"]="9096"
    ["Tautulli"]="8181"
    ["NPM Admin"]="81"
)

ALL_OK=true
for NAME in "${!PORTS[@]}"; do
    PORT="${PORTS[$NAME]}"
    if curl -sk --max-time 3 "http://localhost:${PORT}" > /dev/null 2>&1 || \
       curl -sk --max-time 3 "https://localhost:${PORT}" > /dev/null 2>&1; then
        ok "  ${NAME} (port ${PORT})"
    else
        warn "  ${NAME} (port ${PORT}) — not responding yet"
        ALL_OK=false
    fi
done

if $ALL_OK; then
    ok "All services responding."
else
    warn "Some services not yet responding — they may still be initialising."
    warn "Re-run check: for p in 32400 8080 7878 8989 9696 3000 8181 9096; do curl -s --max-time 2 http://localhost:\$p > /dev/null && echo \"\$p OK\" || echo \"\$p FAIL\"; done"
fi

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║   🎉  GOD MODE RESTORE COMPLETE                      ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Restore details${RESET}"
echo    "  ├── Home dir     : ${PI_HOME}"
echo    "  ├── Media mount  : ${MEDIA_MOUNT} ($(mountpoint -q "$MEDIA_MOUNT" && echo "✅ mounted" || echo "❌ NOT mounted"))"
echo    "  ├── Docker stack : ${MEDIA_STACK}"
echo    "  ├── Tailscale IP : $(tailscale ip -4 2>/dev/null || echo 'unknown')"
echo    "  └── Log file     : ${LOG_FILE}"

# Copy log to home now that it's available
cp "$LOG_FILE" "${PI_HOME}/restore_$(date +%Y%m%d_%H%M%S).log" 2>/dev/null || true

echo ""
echo -e "  ${BOLD}${YELLOW}⚠️  Manual steps still required:${RESET}"
echo    "  1. Nginx Proxy Manager — re-verify SSL certs and access lists (port 81)"
echo    "  2. Grafana — re-import dashboards if missing (IDs: 10578, 1860, 193)"
echo    "  3. Tailscale — re-enable subnet routing (192.168.0.0/24) in admin panel"
echo    "  4. AdGuard Home — verify DNS rewrites and upstream resolvers are intact"
echo    "  5. qBittorrent — verify download path still points to ${MEDIA_MOUNT}/downloads"
echo    "  6. Plex — re-scan libraries if media was added since last backup"
echo    "  7. Telegram bots — send a test message to confirm tokens are working"
echo ""

# ── Telegram notification ────────────────────────────────────
SEND_MSG="${PIALERTS_DIR}/send_message.sh"
HDD_STATUS=$(mountpoint -q "$MEDIA_MOUNT" && echo "✅ Mounted" || echo "❌ NOT mounted")
CONTAINER_COUNT=$($DOCKER compose -f "${MEDIA_STACK}/docker-compose.yml" \
    ps --filter "status=running" --format "{{.Service}}" 2>/dev/null | wc -l)
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")

if [[ -x "$SEND_MSG" ]]; then
    "$SEND_MSG" "🟢 *PI RESTORE COMPLETE*
━━━━━━━━━━━━━━━━━━━━
🖥 Host: \`raspberrypi\`
💾 HDD: ${HDD_STATUS}
🐳 Containers: ${CONTAINER_COUNT} running
🔒 Tailscale: \`${TAILSCALE_IP}\`
📋 Log: \`$(basename "$LOG_FILE")\`
━━━━━━━━━━━━━━━━━━━━
⚠️ Check NPM, Grafana, AdGuard manually."
    ok "Telegram notification sent."
else
    warn "send_message.sh not found or not executable — Telegram alert skipped."
    warn "Expected at: ${SEND_MSG}"
fi
