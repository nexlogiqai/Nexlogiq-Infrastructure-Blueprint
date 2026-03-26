# Nexlogiq AI - Enterprise Distributed Infrastructure Blueprint

An automated, enterprise-grade Infrastructure as Code (IaC) repository designed to provision, harden, and optimize Linux-based Virtual Private Servers (VPS). Engineered by the **Nexlogiq AI Infrastructure Team**, this blueprint establishes a highly secure, distributed architecture that splits critical application workloads from observability stacks.

---

## 1. Architecture Overview

This infrastructure strictly adheres to the **NIST SP 800-207 Zero-Trust architecture** and **CIS Benchmarks** for Linux system hardening. It assumes the public internet is a hostile environment and removes reliance on traditional perimeter-only defenses.

The repository is divided into two distinct node types:

* **`core-node`**: The primary engine for databases, AI agents, and production applications (e.g., Coolify). Optimized for heavy workloads with an 8GB Swap allocation, TCP BBR network acceleration, and self-healing mechanisms.
* **`monitor-node`**: An isolated Out-of-Band (OOB) server. Connects to the core node securely via an encrypted tunnel to collect metrics without exposing telemetry to the public internet. Includes a pre-configured Docker stack for Prometheus, Grafana, and Uptime Kuma.

---

## 2. Core Defense & Performance Features

### Security & Auditing
* **Active Defense:** CrowdSec analyzes behavioral patterns and automatically blocks malicious IPs via `iptables`.
* **Strict Authentication:** Disables root login and password authentication entirely. Enforces SSH Key pairs combined with Google Authenticator (PAM) for mandatory Multi-Factor Authentication (MFA).
* **Docker Firewall Lockdown:** Includes a dedicated UFW patch to prevent Docker containers from bypassing firewall rules and exposing ports.
* **System Auditing:** Uses `auditd` to act as a "black box," logging all root-level commands.
* **Integrity Monitoring:** `Monit` actively watches critical files (`/etc/passwd`, `/etc/ssh/sshd_config`) and alerts on unauthorized SHA1 checksum changes.
* **Kernel Hardening:** Implements advanced `sysctl` rules to mitigate DDoS attacks (e.g., TCP Syncookies) and restrict kernel pointer leaks.

### Performance Optimization
* **Concurrency:** Raises system file descriptor limits (`fs.file-max`) to 65,535 for high-traffic handling.
* **Throughput:** Enables Google's TCP BBR algorithm to reduce latency.
* **Resource Protection:** Strict log rotation limits for Docker (max 10MB) and Systemd Journald (max 100MB) to prevent Out-Of-Space crashes.

---

## 3. Advanced Operational Tactics (OpSec)

### The "Invisible Node" Strategy
While the OS-level firewall (UFW) allows the custom SSH port, **the Cloud Provider's Firewall (VCN Security Lists / AWS Security Groups) must be configured to DROP all incoming SSH traffic from the public internet (0.0.0.0/0).**

By doing this:
1. The server becomes completely invisible to automated port scanners and botnets.
2. Administrative SSH access is **only possible** by pinging the internal Tailscale VPN IP (e.g., `100.x.x.x`).

### Cloudflare Strict Lockdown (Optional)
**⚠️ WARNING:** ONLY execute this script if your domains are strictly routed through **Cloudflare**. If you use another CDN or direct DNS, this will block all incoming web traffic to your server.

```bash
#!/bin/bash
# Allow IPv4 from Cloudflare
for ip in $(curl -s https://www.cloudflare.com/ips-v4); do
    sudo ufw allow proto tcp from $ip to any port 80,443 comment 'Cloudflare IP'
done

# Allow IPv6 from Cloudflare
for ip in $(curl -s https://www.cloudflare.com/ips-v6); do
    sudo ufw allow proto tcp from $ip to any port 80,443 comment 'Cloudflare IP'
done

# Deny all other direct web traffic
sudo ufw deny 80/tcp comment 'Deny direct HTTP'
sudo ufw deny 443/tcp comment 'Deny direct HTTPS'
sudo ufw reload
```

---

## 4. Step-by-Step Deployment Guide

**Zero Manual Editing Required:** The provisioning scripts are fully interactive. They will prompt you securely for usernames, custom ports, and passwords during execution.

### Prerequisites
1. Fresh installation of **Ubuntu 22.04 or 24.04**.
2. Root (`sudo`) access.
3. Active [Tailscale](https://tailscale.com/) account.
4. Google Authenticator app on your mobile device.

### Phase 1: Execution (Interactive CLI)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/nexlogiqai/Nexlogiq-Infrastructure.git
   cd Nexlogiq-Infrastructure
   ```

2. **Deploy the Core Node:**
   Execute the core script. It will prompt you for the admin username, SSH port, and a secure password.
   ```bash
   sudo bash core-node/provision_core.sh
   ```

3. **Deploy the Monitor Node:**
   Execute the monitor script. It will prompt you for system credentials AND a dedicated Grafana Admin password.
   ```bash
   sudo bash monitor-node/provision_monitor.sh
   ```
*(Note: Once the provisioning is complete, the scripts will automatically make all auxiliary management scripts executable).*

### Phase 2: Post-Deployment Initialization (CRITICAL FOR BOTH NODES)

**Step 1: First-Time Login (Public IP)**
Login using your **Public IP** and **SSH Key**. The script allows a one-time login without MFA via `nullok`:
```bash
ssh -i /path/to/private_key -p <YOUR_CUSTOM_PORT> <USER_NAME>@<PUBLIC_IP>
```

**Step 2: Setup MFA**
Immediately run:
```bash
google-authenticator
```
*(Answer **y** to all prompts, scan QR code, and save backup codes).*

**Step 3: Activate Zero-Trust VPN**
```bash
sudo tailscale up
```

**Step 4: The "Invisible" Switch**
Go to Cloud Console and **DELETE** the Port Ingress Rule for SSH. Access is now Tailscale only.

---

## 5. Observability Lifecycle Management

Once both nodes are connected to your Tailscale network, you can securely link or unlink them dynamically.

### Adding a Node to Monitoring
1. **Enable Telemetry (Run on Core Node):**
   ```bash
   sudo ./core-node/enable_telemetry.sh
   ```
   *(Enter the Monitor Node's Tailscale IP when prompted to whitelist it).*

2. **Add Target (Run on Monitor Node):**
   ```bash
   ./monitor-node/add_target.sh
   ```
   *(Follow the prompts. Prometheus will automatically detect the new target within 15 seconds).*

### Removing a Node from Monitoring
1. **Remove Target (Run on Monitor Node):**
   ```bash
   ./monitor-node/remove_target.sh
   ```
   *(Select the server from the dynamic list to safely stop scraping it).*

2. **Disable Telemetry (Run on Core Node):**
   ```bash
   sudo ./core-node/disable_telemetry.sh
   ```
   *(This completely uninstalls the Node Exporter agent and locks down the UFW port).*

---

## 6. Accessing Observability Dashboards

Ensure your local machine is connected to the Tailscale VPN to access these URLs using the Monitor Node's Tailscale IP:

* **Grafana (Metrics & Dashboards):**
  * **URL:** `http://<MONITOR_TAILSCALE_IP>:3000`
  * **Login:** `admin` / *(The Grafana password you set during the interactive setup)*
  * *Tip: Import Dashboard ID `1860` (Node Exporter Full) to visualize the incoming metrics instantly.*

* **Uptime Kuma (Uptime Monitoring & Alerts):**
  * **URL:** `http://<MONITOR_TAILSCALE_IP>:3001`
  * **Login:** Create an admin account on your first visit.

---

## 7. System Verification Commands

```bash
# Check Firewall Rules
sudo ufw status numbered

# Check Active Threat Defense
sudo cscli metrics

# Check Integrity & Health Status
sudo monit status

# Check Docker Daemon Logging
docker info | grep "Logging Driver"

# Check Active Prometheus Targets (Run on monitor-node)
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels'
```

---
**Maintained by Nexlogiq AI** | Infrastructure Engineering Division
