#!/bin/bash

echo "🚨 FULL PI DISASTER RECOVERY"
read -p "This will rebuild your infrastructure. Type YES to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

echo "📦 Installing base packages..."
sudo apt update
sudo apt install -y docker.io docker-compose rclone curl

sudo systemctl enable docker
sudo systemctl start docker

echo "🔐 Configure rclone (gcrypt remote) now..."
rclone config

echo "📥 Restoring /home/piadmin ..."
rclone sync gcrypt:pi-backups /home/piadmin \
  --exclude "media/**" \
  --progress

echo "🔁 Restoring crontab..."
crontab /home/piadmin/.pialerts/crontab_backup 2>/dev/null

echo "⚙ Restoring systemd services..."
sudo cp /home/piadmin/.pialerts/*.service /etc/systemd/system/ 2>/dev/null
sudo systemctl daemon-reload

sudo systemctl enable pialertsbot.service 2>/dev/null
sudo systemctl enable pialerts-auto-update.timer 2>/dev/null
sudo systemctl enable pi-dashboard.service 2>/dev/null

echo "🌐 Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

echo "🚀 Starting Docker stack..."
cd /home/piadmin/docker/media-stack
docker compose up -d

echo "⏳ Waiting for containers..."
sleep 15

docker ps

echo "📡 Sending Telegram confirmation..."
/home/piadmin/.pialerts/send_message.sh "🟢 FULL INFRASTRUCTURE RESTORED SUCCESSFULLY"

echo "🎉 GOD MODE RESTORE COMPLETE"
