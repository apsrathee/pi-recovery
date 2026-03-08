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

1. Installing Docker (Compose v2), rclone, curl, git
2. Configuring the **rclone gcrypt remote** (Google Drive encrypted backup)
3. Restoring `/home/piadmin` from the encrypted backup
4. Auto-detecting and mounting the **4TB external HDD**
5. Applying system config (IPv6 fix, hostname, gai.conf)
6. Restoring **crontab** and **systemd services**
7. Connecting **Tailscale** (interactive auth required)
8. Pulling and starting the full **Docker stack**
9. Running a **port health check** across all 18 services
10. Sending a **Telegram notification** with restore summary

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

---

## 🗂️ Repository Structure

```
pi-recovery/
└── restore.sh       # Full automated recovery script
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
