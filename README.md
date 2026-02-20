# **🚀 Pi-hole Ultimate Installation Suite v1.4.8**

**The Definitive "Set-and-Forget" Deployment Script**

Here is the official release title and comprehensive release notes for **Pi-hole Ultimate Edition v2.0.0**, based on the finalized script logic.

---

# 🚀 Release Title: Pi-hole Ultimate Edition v2.0.0 - Production Ready

## 📝 Release Notes

Version 2.0.0 marks a significant milestone in the project, shifting from a "monitoring-only" tool to an **Autonomous Production-Grade Resolver**. This release is focused on performance, privacy, and long-term stability by eliminating external dependencies and hardening the system core.

### 🌟 High-Availability Features

* **Zero-Dependency Architecture**: Completely removed all email dependencies (`mailutils`, `ssmtp`, `mailx`) to ensure the script never hangs on network timeouts and remains 100% private.
* **Autonomous Emergency Backup**: Introduced a new `systemd` watchdog service that automatically triggers a full Teleporter backup if the CPU temperature hits the **80°C critical threshold**.
* **Proactive System Cleanup**: The new installation process now automatically purges old backup files, previous script versions, and redundant cron jobs to prevent configuration drift.

### 🔒 Security & Performance Hardening

* **Quad9 DNS-over-TLS (DoT)**: Secure, encrypted upstream forwarding to Quad9 on port 853.
* **Internal DNSSEC Validation**: Pi-hole DNSSEC is disabled to prevent "double-validation" lag, while Unbound acts as the high-speed local validator.
* **Static IP Guard**: Hardened network persistence logic ensures the Pi-hole maintains its IP address even after router reboots or DHCP lease table wipes.
* **SD Card Preservation**: Weekly log rotation and compressed logs for Unbound to minimize NAND writes.

### 🛠️ Technical Improvements

* **Refined Installation Path**: Reduced to **13 lean steps** for a faster deployment experience.
* **Enhanced Unbound Permissions**: Integrated "Permission Guards" to ensure the `unbound` user always has access to its log files, preventing the common "Permission Denied" startup failure.
* **7-Day Rolling Backups**: Automated 7-day backup retention logic is now fully local and silent.

### 📥 Installation & Recommended Blocklists

🚀 One-Step Installation Command

Copy and paste this into your Linux terminal:
```bash

wget -O pihole-install.sh https://github.com/waelisa/pi-hole-full-Installation-with-dns/raw/refs/heads/main/pihole-auto-installation-with-dns.sh && chmod +x pihole-install.sh && sudo ./pihole-install.sh
```

📋 Post-Installation Guide
1. Add Recommended Blocklists

Since v2.0.0 uses a "Clean Slate" approach to avoid database locking, you should run this command after the script finishes to inject the Top 5 "Industrial Grade" Blocklists into your new installation:
```bash

sudo pihole -a addadlist "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" "https://adaway.org/hosts.txt" "https://v.firebog.net/hosts/AdguardDNS.txt" "https://v.firebog.net/hosts/Admiral.txt" "https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt" && sudo pihole -g
```

2. Verify Your "Industrial Grade" Status

Once installed, you can use these built-in commands to confirm your privacy and security are active:

    System Health: Type pihole-health to view real-time stats, including the CPU temperature monitor.

    DoT Encryption Check:
    dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335
    (Should return "dot").

    DNSSEC Validation Check:
    dig @127.0.0.1 -p 5335 sigfail.verteiltesysteme.net
    (Should return SERVFAIL).

3. Test the Emergency Backup

To verify that your autonomous 80°C fail-safe is working, you can manually trigger a backup test with:
sudo systemctl start thermal-emergency.service
Then, check /var/backups/pihole/ for your saved Teleporter file.

**Support**: [PayPal.me/WaelIsa](https://www.paypal.me/WaelIsa)
