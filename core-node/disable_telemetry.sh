#!/bin/bash
set -euo pipefail

# ==============================================================================
# Disable Telemetry & Remove Monitoring Agent
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Privilege escalation required. Please run as root."
  exit 1
fi

echo "======================================================="
echo "  Telemetry Agent Removal (Node Exporter)"
echo "======================================================="
echo "[WARNING] This will completely remove the monitoring agent"
echo "          and block the telemetry port (9100) on this server."

read -p "Are you sure you want to proceed? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo "[INFO] Stopping and disabling Prometheus Node Exporter..."
systemctl stop prometheus-node-exporter || true
systemctl disable prometheus-node-exporter || true

echo "[INFO] Uninstalling Node Exporter package..."
export DEBIAN_FRONTEND=noninteractive
apt-get remove --purge -y prometheus-node-exporter || true
apt-get autoremove -y || true

echo "[INFO] Locating and removing UFW rules for port 9100..."
RULES=$(ufw status numbered | grep '9100' | awk -F"[][]" '{print $2}' | sort -nr || true)

if [ -n "$RULES" ]; then
    for rule_num in $RULES; do
        echo "y" | ufw delete $rule_num > /dev/null 2>&1 || true
    done
    ufw reload
    echo "[SUCCESS] Firewall rules successfully removed."
else
    echo "[INFO] No UFW rules found for port 9100."
fi

echo "======================================================="
echo "[SUCCESS] Telemetry Agent is completely removed and secured!"
echo "======================================================="
