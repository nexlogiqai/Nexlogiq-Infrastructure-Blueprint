#!/bin/bash
set -euo pipefail

# ==============================================================================
# Dynamic Target Removal for Prometheus
# ==============================================================================

echo "======================================================="
echo "  Remove Core Node from Prometheus Monitoring"
echo "======================================================="

if ! command -v jq &> /dev/null; then
    echo "[ERROR] 'jq' is not installed. Please install it first."
    exit 1
fi

read -p "Enter the monitor node username [default: nexlogiq_monitor]: " input_user
TARGET_USER=${input_user:-nexlogiq_monitor}

TARGET_FILE="/home/$TARGET_USER/observability/prometheus/targets.json"

if [ ! -f "$TARGET_FILE" ]; then
    echo "[ERROR] Target file not found at $TARGET_FILE."
    exit 1
fi

TARGET_COUNT=$(jq '. | length' "$TARGET_FILE")

if [ "$TARGET_COUNT" -eq 0 ]; then
    echo "[INFO] No servers are currently being monitored in the file."
    exit 0
fi

echo ""
echo "Currently Monitored Servers:"
echo "-------------------------------------------------------"
jq -r 'to_entries | .[] | "[\(.key)] Server: \(.value.labels.server_name)  |  IP: \(.value.targets[0])"' "$TARGET_FILE"
echo "-------------------------------------------------------"

read -p "Enter the number of the server to remove (e.g., 0, 1) or 'q' to quit: " SELECTION

if [[ "$SELECTION" == "q" ]]; then
    echo "Operation cancelled."
    exit 0
fi

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -ge "$TARGET_COUNT" ]; then
    echo "[ERROR] Invalid selection. Please enter a valid number from the list."
    exit 1
fi

SERVER_NAME=$(jq -r ".[$SELECTION].labels.server_name" "$TARGET_FILE")
SERVER_IP=$(jq -r ".[$SELECTION].targets[0]" "$TARGET_FILE")

echo ""
read -p "Are you SURE you want to STOP monitoring $SERVER_NAME ($SERVER_IP)? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo "[INFO] Removing $SERVER_NAME from $TARGET_FILE..."

jq "del(.[$SELECTION])" "$TARGET_FILE" > "$TARGET_FILE.tmp" && mv "$TARGET_FILE.tmp" "$TARGET_FILE"
chown $TARGET_USER:$TARGET_USER "$TARGET_FILE"

echo "======================================================="
echo "[SUCCESS] $SERVER_NAME ($SERVER_IP) has been removed!"
echo "[INFO] Prometheus will stop scraping this node within 15s."
echo "======================================================="
