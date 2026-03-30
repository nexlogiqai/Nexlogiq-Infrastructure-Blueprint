#!/bin/bash
set -euo pipefail

# ==============================================================================
# Nexlogiq AI - Out-of-Band Monitoring Node Provisioning
# ==============================================================================

# --- Helper Functions for Verification ---
verify_command() {
    if command -v "$1" >/dev/null 2>&1; then echo "[✔] SUCCESS: '$1' is installed."; else echo "[✘] ERROR: '$1' is not installed!"; exit 1; fi
}
verify_service() {
    if systemctl is-active --quiet "$1"; then echo "[✔] SUCCESS: Service '$1' is running."; else echo "[✘] ERROR: Service '$1' failed to start!"; exit 1; fi
}
# -----------------------------------------

echo "========================================================================"
echo "  Nexlogiq AI - Monitor Node Interactive Setup (Military-Grade)"
echo "========================================================================"

read -p "Enter the new admin username [default: nexlogiq_monitor]: " input_user
USER_NAME=${input_user:-nexlogiq_monitor}

read -p "Enter the custom SSH port [default: 3333]: " input_port
SSH_PORT=${input_port:-3333}

while ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; do
    echo "[ERROR] Invalid port. Must be a number."
    read -p "Enter the custom SSH port [default: 3333]: " input_port
    SSH_PORT=${input_port:-3333}
done

while true; do
    read -sp "Enter a secure password for system user '$USER_NAME': " USER_PASS
    echo ""
    read -sp "Confirm user password: " USER_PASS_CONFIRM
    echo ""
    if [[ -z "$USER_PASS" ]]; then echo "[ERROR] Cannot be empty."; elif [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then echo "[ERROR] Passwords mismatch."; else break; fi
done

while true; do
    read -sp "Enter a secure password for Grafana (admin) login: " GRAFANA_PASS
    echo ""
    read -sp "Confirm Grafana password: " GRAFANA_PASS_CONFIRM
    echo ""
    if [[ -z "$GRAFANA_PASS" ]]; then echo "[ERROR] Cannot be empty."; elif [[ "$GRAFANA_PASS" != "$GRAFANA_PASS_CONFIRM" ]]; then echo "[ERROR] Passwords mismatch."; else break; fi
done

echo "========================================================================"
echo "[INFO] Provisioning Username: $USER_NAME | SSH Port: $SSH_PORT"
echo "========================================================================"

if [ "$EUID" -ne 0 ]; then echo "[ERROR] Run as root (sudo)."; exit 1; fi

echo "[INFO] Waiting for background updates to finish (dpkg lock)..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do sleep 3; done

export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl ufw unattended-upgrades libpam-google-authenticator chrony auditd monit jq wget

verify_command jq
verify_command ufw

cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat <<EOF > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

systemctl enable chrony && systemctl start chrony
verify_service chrony

systemctl enable auditd && systemctl start auditd
verify_service auditd

echo "[INFO] Configuring Auditd Enterprise Rules..."
cat <<EOF > /etc/audit/rules.d/nexlogiq.rules
-w /etc/shadow -p wa -k identity_changes
-w /etc/passwd -p wa -k identity_changes
-w /etc/sudoers -p wa -k admin_changes
-w /var/log/auth.log -p wa -k auth_logs
EOF
augenrules --load || true

useradd -m -s /bin/bash $USER_NAME
echo "$USER_NAME:$USER_PASS" | chpasswd
usermod -aG sudo $USER_NAME

# --- SMART SSH KEY DISCOVERY ---
echo "[INFO] Searching for existing SSH keys to copy to $USER_NAME..."
KEY_FOUND=false
for CHECK_USER in "${SUDO_USER:-}" ubuntu opc debian root; do
    if [ -n "$CHECK_USER" ] && [ -f "/home/$CHECK_USER/.ssh/authorized_keys" ]; then
        mkdir -p /home/$USER_NAME/.ssh
        cp /home/$CHECK_USER/.ssh/authorized_keys /home/$USER_NAME/.ssh/
        chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh
        chmod 700 /home/$USER_NAME/.ssh
        chmod 600 /home/$USER_NAME/.ssh/authorized_keys
        echo "[✔] SUCCESS: SSH key automatically copied from user '$CHECK_USER'."
        KEY_FOUND=true
        break
    elif [ "$CHECK_USER" == "root" ] && [ -f "/root/.ssh/authorized_keys" ]; then
        mkdir -p /home/$USER_NAME/.ssh
        cp /root/.ssh/authorized_keys /home/$USER_NAME/.ssh/
        chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh
        chmod 700 /home/$USER_NAME/.ssh
        chmod 600 /home/$USER_NAME/.ssh/authorized_keys
        echo "[✔] SUCCESS: SSH key automatically copied from 'root'."
        KEY_FOUND=true
        break
    fi
done

if [ "$KEY_FOUND" = false ]; then
    echo "[✘] WARNING: No existing SSH key found! You MUST add one manually or you will be locked out."
fi
# -------------------------------

echo "[INFO] Installing Docker..."
curl -fsSL https://get.docker.com | sh
usermod -aG docker $USER_NAME
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl restart docker
verify_command docker
verify_service docker

sed -i 's/.*SystemMaxUse=.*/SystemMaxUse=100M/' /etc/systemd/journald.conf
systemctl restart systemd-journald

echo "[INFO] Installing Tailscale & CrowdSec..."
curl -fsSL https://tailscale.com/install.sh | sh
verify_command tailscale
verify_service tailscaled

curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
apt install -y crowdsec crowdsec-firewall-bouncer-iptables
verify_command cscli
verify_service crowdsec

cscli collections install crowdsecurity/sshd
cscli collections install crowdsecurity/linux
systemctl reload crowdsec || true

ufw default deny incoming
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow $SSH_PORT/tcp
ufw allow in on tailscale0
ufw route allow in on tailscale0
echo "y" | ufw enable
if ufw status | grep -qw active; then echo "[✔] SUCCESS: UFW is active."; else echo "[✘] ERROR: UFW is NOT active!"; exit 1; fi

echo "[INFO] Securing Docker against UFW bypass..."
wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
chmod +x /usr/local/bin/ufw-docker
ufw-docker install
systemctl restart ufw

sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config
sed -i "s/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication yes/" /etc/ssh/sshd_config
sed -i "s/^#*KbdInteractiveAuthentication .*/KbdInteractiveAuthentication yes/" /etc/ssh/sshd_config

if ! grep -q "AuthenticationMethods" /etc/ssh/sshd_config; then echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config; fi
if ! grep -q "pam_google_authenticator.so" /etc/pam.d/sshd; then echo "auth required pam_google_authenticator.so nullok" >> /etc/pam.d/sshd; fi

cat <<EOF >> /etc/ssh/sshd_config
# Nexlogiq AI Strict Cryptography
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com
EOF

if sshd -t; then echo "[✔] SUCCESS: SSH configuration syntax is valid."; else echo "[✘] ERROR: SSH configuration is broken!"; exit 1; fi

# --- MODERN UBUNTU SOCKET FIX ---
echo "[INFO] Applying SSH port changes and fixing systemd sockets..."
if systemctl is-active --quiet ssh.socket; then
    systemctl disable --now ssh.socket || true
    systemctl enable --now ssh.service || true
fi
systemctl restart ssh || systemctl restart sshd
# --------------------------------

cat <<EOF >> /etc/sysctl.conf
fs.file-max = 2097152
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
EOF

cat <<EOF >> /etc/security/limits.conf
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

if [ ! -f /swapfile ]; then
    fallocate -l 9G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile && swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi

echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

cat <<EOF >> /etc/monit/monitrc
set httpd port 2812 and
    use address localhost
    allow localhost
check file passwd with path /etc/passwd
    if changed sha1 checksum then alert
check file sshd_config with path /etc/ssh/sshd_config
    if changed sha1 checksum then alert
check system \$HOST
    if cpu usage > 85% for 5 cycles then alert
    if memory usage > 85% for 5 cycles then alert
check process docker with pidfile /var/run/docker.pid
    start program = "/usr/bin/systemctl start docker"
    stop program = "/usr/bin/systemctl stop docker"
    if failed host 127.0.0.1 port 2375 type tcp then restart
EOF
systemctl restart monit
verify_service monit

echo "[INFO] Deploying Observability Stack..."
OBS_DIR="/home/$USER_NAME/observability"
mkdir -p $OBS_DIR/prometheus

cat <<EOF > $OBS_DIR/prometheus/targets.json
[]
EOF

cat <<EOF > $OBS_DIR/prometheus/prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus_self'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'nexlogiq_core_nodes'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets.json'
        refresh_interval: 15s
EOF

cat <<EOF > $OBS_DIR/docker-compose.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: nexlogiq_prometheus
    volumes:
      - ./prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=7d'
      - '--web.max-connections=20'
    ports:
      - "127.0.0.1:9090:9090"
    restart: unless-stopped
    networks:
      - monitor-net
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          memory: 400M

  grafana:
    image: grafana/grafana:latest
    container_name: nexlogiq_grafana
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASS}
    ports:
      - "3000:3000"
    restart: unless-stopped
    networks:
      - monitor-net
    depends_on:
      - prometheus
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          memory: 300M

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: nexlogiq_uptime_kuma
    volumes:
      - uptime-kuma_data:/app/data
    ports:
      - "3001:3001"
    restart: unless-stopped
    networks:
      - monitor-net
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          memory: 200M

networks:
  monitor-net:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
  uptime-kuma_data:
EOF

chown -R 65534:65534 $OBS_DIR/prometheus
chmod -R 755 $OBS_DIR/prometheus
chown $USER_NAME:$USER_NAME $OBS_DIR/docker-compose.yml

echo "[INFO] Waiting for Docker daemon to stabilize..."
while ! docker info > /dev/null 2>&1; do sleep 2; done

cd $OBS_DIR
docker compose up -d

# Verify containers are running
if [ $(docker ps -q | wc -l) -ge 3 ]; then
    echo "[✔] SUCCESS: Observability Stack containers are running!"
else
    echo "[✘] ERROR: Observability Stack failed to deploy correctly!"
    exit 1
fi

chmod -x /etc/update-motd.d/* 2>/dev/null || true
cat << 'EOF' > /etc/update-motd.d/99-nexlogiq
#!/bin/sh
echo "========================================================================"
echo "  _    _ _______   ___        ____   _____ _____  ___         /\    |_   _| "
echo " | \ | |  ___\ \ / / |      / __ \ / ____|_   _|/ _ \       /  \    | |   "
echo " |  \| | |__  \ V /| |     | |  | | |  __  | | | | | |     / /\ \   | |   "
echo " | . \` |  __|  > < | |     | |  | | | |_ | | | | | | |    / ____ \  | |   "
echo " | |\  | |____/ . \| |____| |__| | |__| |_| |_| |_| |   /_/    \_\_| |_  "
echo " |_| \_|______/_/ \_\______\____/ \_____|____ |\__\_\            |_____| "
echo "========================================================================"
echo "[WARNING]  UNAUTHORIZED ACCESS. THIS IS A RESTRICTED OOB MONITORING NODE."
echo "[SECURITY] INFRASTRUCTURE HARDENED & PROVISIONED BY NEXLOGIQ AI."
echo "[AUDIT]    ALL ACTIVITIES ARE LOGGED AND MONITORED (ZERO-TRUST NODE)."
echo "========================================================================"
EOF
chmod +x /etc/update-motd.d/99-nexlogiq

SCRIPT_DIR=$(dirname "$0")
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true

echo "[INFO] Monitoring Node Provisioning complete and verified. Rebooting in 5 seconds..."
sleep 5
reboot
