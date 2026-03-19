# 🛠️ Pi Infrastructure Recovery
> **One-command disaster recovery for a full Raspberry Pi 4B homelab stack.**  
> Restores Docker services, system config, HDD mount, Tailscale, crontab, and systemd services automatically from an encrypted Google Drive backup.

---

## 📋 Stack Overview

| Category | Services |
|---|---|
| **Media** | Plex, Radarr, Sonarr, qBittorrent, Jackett, Prowlarr, FlareSolverr, Tautulli |
| **Monitoring** | Grafana, Prometheus, cAdvisor, Node Exporter, Uptime Kuma |
| **Automation** | Media Request Bot (Telegram), PiAlertsBot, Pi Command Center |
| **Minecraft** | MC Command Center (Flask API), MC Telegram Bot |
| **Infrastructure** | Nginx Proxy Manager, Portainer, Omni-Tools, Tailscale, AdGuard Home |

---

## 🚨 Disaster Recovery Steps

### Prerequisites
- Fresh **Raspberry Pi OS Lite 64-bit** flashed
- User **`piadmin`** created
- SSH access available

### Recovery
```bash
# 1. Download the restore script
curl -O https://raw.githubusercontent.com/apsrathee/pi-recovery/main/restore.sh

# 2. Make it executable
chmod +x restore.sh

# 3. Run it
bash restore.sh
```

The script will guide you interactively through:

1. **sudo check** — installs sudo automatically if missing (handles minimal Debian/Raspberry Pi OS)
2. Installing **Docker** (Compose v2), rclone, curl, git
3. Configuring the **rclone gcrypt remote** (Google Drive encrypted backup) — with step-by-step instructions printed on screen
4. Restoring `/home/piadmin` from the encrypted backup
5. Auto-detecting and mounting the **4TB external HDD**
6. Applying system config (IPv6 fix, hostname, gai.conf)
7. Restoring **crontab** and **systemd services**
8. Connecting **Tailscale** (interactive auth required)
9. Pulling and starting the full **Docker stack**
10. Running a **port health check** across all 18 services
11. Sending a **Telegram notification** with restore summary

---

## ⚠️ Manual Steps After Restore

These require manual verification after the script completes:

- **Nginx Proxy Manager** — re-verify SSL certificates and access lists (`port 81`)
- **Grafana** — re-import dashboards if missing (IDs: `10578`, `1860`, `193`)
- **Tailscale** — re-enable subnet routing (`192.168.0.0/24`) in the admin panel
- **AdGuard Home** — verify DNS rewrites and upstream resolvers are intact
- **qBittorrent** — confirm download path points to `/home/piadmin/media/downloads`
- **Plex** — re-scan libraries if media was added since last backup
- **Telegram bots** — send a test message to confirm tokens are working
- **Uptime Kuma** — re-add Docker container ports and Telegram bot token

---

## 🗂️ Repository Structure

```
pi-recovery/
├── restore.sh       # Full automated recovery script
└── README.md        # This file
```

> 🔐 Secrets (`bot_token`, `chat_id`) are **never stored here**.  
> They live under `/home/piadmin/.pialerts/` and are restored automatically via the encrypted rclone backup.

---

## 🖥️ System Reference

| Property | Value |
|---|---|
| **Hardware** | Raspberry Pi 4B |
| **OS** | Raspberry Pi OS Lite 64-bit |
| **Hostname** | `raspberrypi` |
| **User** | `piadmin` |
| **Home** | `/home/piadmin` |
| **Media HDD** | 4TB EXT4 → `/home/piadmin/media` |
| **Docker Stack** | `/home/piadmin/docker/media-stack/` |
| **Backup** | rclone + gcrypt → Google Drive |

---

## 🔌 Service Ports

| Service | Port |
|---|---|
| Plex | `32400` |
| qBittorrent | `8080` |
| Radarr | `7878` |
| Sonarr | `8989` |
| Prowlarr | `9696` |
| Jackett | `9117` |
| FlareSolverr | `8191` |
| Grafana | `3001` |
| Prometheus | `9090` |
| cAdvisor | `8081` |
| Node Exporter | `9100` |
| Portainer | `9000` |
| Uptime Kuma | `3100` |
| Omni-Tools | `8082` |
| Pi Command Center | `9096` |
| Tautulli | `8181` |
| NPM Admin | `81` |
| NPM Proxy | `80` / `443` |
| MC Command Center | `5050` |

---

## 🎮 Minecraft Reference

| Property | Value |
|---|---|
| **MC Command Center** | Flask API → `port 5050`, web dashboard at `mcserver.home` |
| **MC Telegram Bot** | service `mc-bot`, file `mcbot.py` |
| **great-server** | PaperMC, RCON port `25575` |
| **gooners-server** | Fabric, RCON port `25576` |
| **Bluemap (great)** | `port 8200` → `greatbluemap.home` |
| **Bluemap (gooners)** | `port 8100` → `bluemap.home` |

---

## 🔧 Systemd Services Restored

The following service files are backed up in `/home/piadmin/.pialerts/` and automatically reinstalled by the script:

| Service | Description |
|---|---|
| `pi-dashboard.service` | Pi Home Dashboard (port 9096) |
| `pialertsbot.service` | PiAlerts Telegram bot |
| `pialerts-auto-update.service` | PiAlerts auto-update |
| `pialerts-auto-update.timer` | PiAlerts update timer |
| `pialertsbot.timer` | PiAlerts bot timer |
| `mc-command-center.service` | MC Command Center Flask API |
| `mc-bot.service` | MC Telegram bot |
