#!/bin/bash
set -e

# === CONFIG & LOG ===
LOG="deploy_$(date +%F_%H-%M-%S).log"
log(){ echo "[$(date '+%F %T')] $1" | tee -a "$LOG"; }

# === INPUTS ===
read -p "Git repo URL: " REPO
read -p "Personal Access Token: " TOKEN
read -p "Branch (default: main): " BRANCH
BRANCH=${BRANCH:-main}
read -p "Remote username: " USER
read -p "Remote server IP: " HOST
read -p "Path to SSH key: " KEY
read -p "App port (default 5000): " PORT
PORT=${PORT:-5000}

# === CLONE OR UPDATE ===
APP_DIR=$(basename "$REPO" .git)
if [ -d "$APP_DIR" ]; then
  log "Updating existing repo..."
  cd "$APP_DIR" && git pull origin "$BRANCH" >> "../$LOG" 2>&1
else
  log "Cloning repo..."
  git clone -b "$BRANCH" "https://${TOKEN}@${REPO#https://}" >> "$LOG" 2>&1
  cd "$APP_DIR"
fi

# === CHECK DOCKERFILE ===
[ -f Dockerfile ] || { log "❌ No Dockerfile found"; exit 1; }

# === TEST SSH ===
log "Checking SSH connection..."
ssh -i "$KEY" -o StrictHostKeyChecking=no "$USER@$HOST" "echo Connected" || { log "❌ SSH failed"; exit 1; }

# === COPY FILES ===
log "Copying project to remote..."
scp -i "$KEY" -r . "$USER@$HOST:/home/$USER/app" >> "$LOG" 2>&1

# === DEPLOY REMOTELY ===
log "Deploying on remote server..."
ssh -i "$KEY" "$USER@$HOST" bash -s <<EOF
set -e
sudo apt update -y && sudo apt install -y docker.io nginx >> deploy.log 2>&1
sudo systemctl enable --now docker nginx

cd /home/$USER/app
sudo docker stop flask-docker-app || true && sudo docker rm flask-docker-app || true
sudo docker build -t flask-docker-app . >> deploy.log 2>&1
sudo docker run -d -p ${PORT}:5000 --name flask-docker-app flask-docker-app >> deploy.log 2>&1

# --- NGINX CONFIG ---
sudo bash -c 'cat > /etc/nginx/sites-available/flask-docker-app <<NGX
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGX'
sudo ln -sf /etc/nginx/sites-available/flask-docker-app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
EOF

log "✅ Deployment complete! App accessible at: http://${HOST}"
