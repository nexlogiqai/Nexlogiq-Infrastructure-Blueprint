#!/bin/bash
set -euo pipefail

# ==============================================================================
# Dynamic Target Addition for Prometheus
# ==============================================================================

echo "======================================================="
echo "  Add New Core Node to Prometheus Monitoring"
echo "======================================================="

if ! command -v jq &> /dev/null; then
    echo "[ERROR] 'jq' is not installed."
    exit 1
fi

read -p "Enter the monitor node username [default: nexlogiq_monitor]: " input_user
TARGET_USER=${input_user:-nexlogiq_monitor}

TARGET_FILE="/home/$TARGET_USER/observability/prometheus/targets.json"

read -p "Enter the Tailscale IP of the new server (e.g., 100.x.x.x): " NODE_IP
read -p "Enter a friendly name for this server (e.g., prod-core-01): " NODE_NAME

if [ ! -f "$TARGET_FILE" ]; then
    echo "[INFO] Target file not found at $TARGET_FILE. Creating a new one..."
    mkdir -p "$(dirname "$TARGET_FILE")"
    echo "[]" > "$TARGET_FILE"
    chown $TARGET_USER:$TARGET_USER "$TARGET_FILE"
fi

echo "[INFO] Updating $TARGET_FILE..."

jq ". += [{\"targets\": [\"$NODE_IP:9100\"], \"labels\": {\"server_name\": \"$NODE_NAME\"}}]" "$TARGET_FILE" > "$TARGET_FILE.tmp" && mv "$TARGET_FILE.tmp" "$TARGET_FILE"

chown $TARGET_USER:$TARGET_USER "$TARGET_FILE"

echo "======================================================="
echo "[SUCCESS] Added $NODE_NAME ($NODE_IP) to monitoring targets."
echo "[INFO] Prometheus will detect this automatically within 15 seconds."
echo "======================================================="
