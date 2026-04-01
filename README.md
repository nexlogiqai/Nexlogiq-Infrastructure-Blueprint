# Nexlogiq AI - Enterprise Distributed Infrastructure Blueprint

An automated, military-grade Infrastructure as Code (IaC) repository designed to provision, harden, and optimize Linux-based Virtual Private Servers (VPS). Engineered by the **Nexlogiq AI Infrastructure Team**, this blueprint is built so that even those without deep DevOps experience can deploy a highly secure, distributed architecture.

---

## 1. Architecture Overview (Simply Explained)

Imagine your infrastructure as a highly secure bank. 
* **`core-node`**: This is the vault. It runs your databases, AI agents, and main applications (like Coolify). It is optimized to handle heavy traffic and is completely hidden from the public.
* **`monitor-node`**: This is the security camera room. It sits on a completely different server and connects to the vault through a secret, encrypted tunnel (Tailscale) to monitor its health without exposing the vault to the outside world.

We use a **"Zero-Trust"** approach, which means we assume the internet is full of attackers, and we don't even trust connections coming from inside unless they are cryptographically proven.

---

## 2. Security & Performance (What's Inside?)

### 🛡️ Military-Grade Security
* **Unbreakable Login:** Passwords are disabled. You can only log in using a modern cryptographic key (`Ed25519`) PLUS a code from your phone (Google Authenticator MFA).
* **Smart Key Discovery:** The provisioning scripts automatically detect your existing SSH keys from default users (`ubuntu`, `root`, `opc`) and securely migrate them to your new admin user.
* **AI Security Guard (CrowdSec):** Automatically reads server logs, detects attackers trying to guess passwords or scan ports, and permanently blocks their IP addresses.
* **Jail for Apps (Container Security):** Apps like Grafana run in isolated "jails" with zero privileges (`cap_drop: ALL`). If an app is hacked, the hacker cannot touch the main server.
* **Forensic Auditing:** `auditd` and `Monit` act as a black-box flight recorder, alerting you if anyone modifies critical system files.

### ⚡ Extreme Performance & Stability
* **BBR Network Acceleration:** Uses Google's algorithm to make network traffic much faster and reduce lag.
* **Heavy Workload Ready:** Configured to handle up to 65,535 simultaneous connections and includes an 8GB/9GB Swap file so the server never crashes from running out of RAM.
* **Systemd Socket Fix:** Automatically resolves modern Ubuntu SSH socket conflicts to ensure seamless custom port bindings.

---

## 3. Advanced OpSec Tricks (The Secret Sauce)

### Trick 1: The "Invisible Node" Strategy
Once everything is set up, you will go to your Cloud Provider (Oracle/AWS/DigitalOcean/Hetzner) and **delete the firewall rule that allows SSH (Port 22/2222/3333)**.
* **Result:** Your server disappears from the internet. Hackers cannot even scan it. You will only be able to log in by connecting to your Tailscale VPN first, then SSHing into the internal `100.x.x.x` IP.

### Trick 2: Emergency "Break-Glass" Procedure
What if your Tailscale VPN breaks and you are locked out?
1. Log into your Cloud Provider's Web Console.
2. Temporarily open your custom SSH port (e.g., 2222) to the public internet.
3. SSH in using your Public IP, fix the issue, and immediately close the port again.

### Trick 3: Cloudflare Strict Lockdown (Optional)
If you host websites on the `core-node` and use Cloudflare, hackers can still attack your server's Public IP directly, bypassing Cloudflare's protections. Run this script to tell the firewall to DROP all web traffic unless it comes strictly from Cloudflare's official servers:

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

### Trick 4: High Availability (S3 Backups)
Always configure your apps (like Coolify) to backup their databases to an external S3 Bucket (like AWS S3 or Cloudflare R2). Since this server can be provisioned from zero to 100% in 5 minutes using these scripts, if the server burns down, you just run the script on a new VPS and pull your S3 backup.

---

## 4. Step-by-Step Deployment Guide

Follow these steps carefully. The scripts are interactive and will ask you for all the necessary details.

### Step 0: The Most Important Step (Creating Your Key)
Before running the scripts, you MUST create a modern `Ed25519` key and put it on the server. The script features *Smart Discovery*, but it needs a key to discover!

1. **On your personal computer (Terminal or PowerShell):**
   ```bash
   ssh-keygen -t ed25519 -C "admin_key"
   ```
   *(Press Enter to save it in the default location, and set a passphrase).*

2. **Push the key to your new server:**
   * **Method A (Terminal):** `ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<SERVER_PUBLIC_IP>`
   * **Method B (MobaXterm visually):** 1. Login to the server with the default user (`ubuntu` or `root`).
     2. Run: `mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`
     3. Open the `authorized_keys` file via the left panel and paste the contents of your `id_ed25519.pub` file into it.

### Step 1: Download the Blueprint
Log into your server and run:
```bash
git clone https://github.com/nexlogiqai/Nexlogiq-Infrastructure.git
cd Nexlogiq-Infrastructure
```

### Step 2: Run the Provisioning Script
* **If this is your Main Server:**
  ```bash
  sudo bash core-node/provision_core.sh
  ```
* **If this is your Monitoring Server:**
  ```bash
  sudo bash monitor-node/provision_monitor.sh
  ```
*(The scripts will ask you to choose a username, a custom SSH port, and secure passwords. Once finished, the server will automatically reboot).*

### Step 3: Post-Reboot Setup (Securing the Gates)
1. **Login with your new Port and Key:**
   ```bash
   ssh -i ~/.ssh/id_ed25519 -p <YOUR_NEW_PORT> <YOUR_NEW_USERNAME>@<SERVER_PUBLIC_IP>
   ```
2. **Setup Phone MFA (Google Authenticator):**
   Run the command `google-authenticator`, answer 'y' to everything, and scan the QR code with your phone.
3. **Connect to Tailscale:**
   Run `sudo tailscale up` and click the link to authenticate the server to your VPN.
4. **Go Invisible:** Delete the SSH port rule from your Cloud Provider's firewall.

---

## 5. Connecting the Servers (Observability)

Now that both servers are secured and on Tailscale, let's connect them.

1. **On the Core Node (Allow Monitoring):**
   ```bash
   sudo ./core-node/enable_telemetry.sh
   ```
   *(Type the Tailscale IP of your Monitor Node).*

2. **On the Monitor Node (Start Watching):**
   ```bash
   ./monitor-node/add_target.sh
   ```
   *(Type the Tailscale IP of your Core Node. Prometheus will detect it in 15 seconds).*

*(To remove a server, simply run `./monitor-node/remove_target.sh` on the Monitor Node, and `./core-node/disable_telemetry.sh` on the Core node).*

---

## 6. Accessing Your Dashboards

Connect your personal computer to Tailscale, then open your browser:

* **Grafana (Beautiful Charts):** `http://<MONITOR_TAILSCALE_IP>:3000`
  * **Login:** `admin` / *(The password you typed during the script)*
  * *Tip: Go to Dashboards -> Import -> Type `1860` to get the ultimate server dashboard instantly.*

* **Uptime Kuma (Is my site down?):** `http://<MONITOR_TAILSCALE_IP>:3001`
  * **Login:** Create a new admin account on your first visit.

---

## 7. The Ultimate Verification (Is Everything Working?)

Run these commands to verify that your setup is flawless and secure:

### 🐳 1. Verify Docker & Containers
```bash
# Check if Docker is running and healthy
sudo systemctl status docker

# List running containers (Should see Prometheus, Grafana, and Kuma on Monitor Node)
docker ps -a
```

### 🛡️ 2. Verify Security & Firewall
```bash
# See active UFW Firewall rules (Ensure Port 9100 is ONLY allowed from Tailscale)
sudo ufw status verbose

# Check CrowdSec (Verify it's reading logs and collections are loaded)
sudo cscli metrics

# Check if Auditd is actively monitoring your identity files
sudo auditctl -l
```

### 🚪 3. Verify Ports & Connections
```bash
# See what ports are listening on the server
sudo ss -tuln

# Test if the Telemetry Agent (Port 9100) is working (Run on Core Node)
curl -s http://localhost:9100/metrics | head -n 5
```

### 🩺 4. Verify System Health Monitor (Monit)
```bash
# Check if Monit is actively watching your passwords and SSH configs
sudo monit status
```

## 🛠️ Troubleshooting (FAQ)

**1. I can't access the Grafana/Uptime Kuma dashboards?**
* **Cause:** The Docker UFW patch strictly blocks external traffic. 
* **Fix:** Ensure you are actively connected to your Tailscale VPN on your personal device. You must use the `http://100.x.x.x` IP address, not the public IP.

**2. I'm locked out of my server! (Server refused key)**
* **Cause:** Modifying `authorized_keys` directly from a Windows environment often injects hidden `\r\n` characters, which SSH strictly rejects.
* **Fix:** Use your Cloud Provider's Emergency Console (Serial Console) and run this exact command to sanitize your key:
  `echo "YOUR_PUBLIC_KEY" > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys`

**3. The provisioning script hangs or fails on `fallocate`?**
* **Fix:** Our script includes a `dd` fallback, but ensure your VPS has at least 15GB of free disk space before running the setup.

---
## 📄 License
This project is licensed under the MIT License.

---
**Maintained by Nexlogiq AI** | Infrastructure Engineering Division
