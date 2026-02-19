# **🚀 Pi-hole Ultimate Installation Suite v1.4.8**

**The Definitive "Set-and-Forget" Deployment Script for Raspberry Pi & Debian**

This script isn't just an installer—it's a professional-grade system orchestrator. It deploys a hardened, high-performance privacy stack featuring **Pi-hole**, **Unbound**, **DNSCrypt-Proxy**, and **WireGuard**, all while implementing enterprise-level monitoring and recovery tools.

## **🌟 Why This Script?**

Most installers leave you with a "basic" setup. v1.4.8 is engineered for **persistence**. It ensures your server survives reboots, power outages, and hardware stress without losing connectivity or security.

### **🛡️ Enterprise-Grade Features:**

*   **Recursive DNS Stack:** Chains Pi-hole → Unbound → DNSCrypt-Proxy for ultimate privacy and speed.
*   **Dynamic Port Management:** Automatically finds and persists available ports to avoid service conflicts.
*   **Thermal Monitoring:** Active CPU temperature tracking with alerts at 75°C and 80°C to protect your Pi.
*   **Automated Backups:** Weekly cron-scheduled backups of all configurations with a 7-day retention policy.
*   **WireGuard VPN:** Secure remote access to your DNS stack from anywhere in the world.
*   **Static IP Guard:** Forces network persistence to prevent DNS "blackouts" after router reboots.

## **🏗️ The DNS Architecture**

The script configures a multi-layered defense-in-depth DNS flow:

1.  **Client** requests a domain.
2.  **Pi-hole** filters ad/tracking domains via curated blocklists.
3.  **Unbound** performs recursive lookups directly from Root Servers.
4.  **DNSCrypt-Proxy** adds an extra layer of encrypted failover and anonymity.

## **🚀 Quick Start**

### **Prerequisites**

*   A clean install of **Raspberry Pi OS** (Lite recommended) or **Debian**.
*   Root or Sudo privileges.
*   An active internet connection.

### **Installation**

Run the following command to begin the "Masterpiece" deployment:

Bash

curl -sSL https://raw.githubusercontent.com/waelisa/pi-hole-full-Installation-with-dns/main/pihole-auto-installation-with-dns.sh | sudo bash

## **📊 Monitoring & Maintenance**

v1.4.8 installs several management utilities:

*   **Thermal Logs:** Check hardware health at /var/log/pihole_thermal.log.
*   **Backups:** Find your weekly config exports in /root/pihole-backups/.
*   **Restore Script:** If you need to uninstall or reset, use the auto-generated restore_script.sh in your home directory.

## **🤝 Support & Contribution**

If this script helped you secure your network, please consider:

*   🌟 Starring the repository on GitHub.
*   ☕ [Buying me a coffee](https://www.paypal.me/WaelIsa) to support further development.
*   Reporting issues or suggesting features via GitHub Issues.

## **📜 License**

This project is licensed under the **MIT License**.

**"A stable Pi-hole keeps the internet peaceful. A monitored Pi-hole keeps the hardware alive."**

Key Improvements in v1.4.8:
1. Automatic Backups with 7-Backup Limit

    Weekly Pi-hole Teleporter backups (Sunday at 2 AM)

    Keeps only the 7 most recent backups (auto-deletes oldest)

    Backup script intelligently manages retention

    Verification script to check backup status

    Email notifications for backup success/failure

2. Smart Retention Management

    BACKUP_RETENTION_COUNT=7 - configurable limit

    When limit reached, oldest backups are automatically deleted

    Prevents disk filling while maintaining recent backups

    Health dashboard shows backup count and warns if exceeded

3. Thermal Monitoring

    Checks CPU temperature every 5 minutes

    Warning threshold: 75°C

    Critical threshold: 80°C

    Email alerts with cooldown (1 hour between alerts)

    Systemd service for auto-start at boot

    Logging to /var/log/thermal-monitor.log

4. Professional Health Dashboard

    pihole-health command shows:

        CPU temperature with color coding

        Service status (all core services)

        Backup status with retention info

        Recent thermal events

5. Backup Verification

    verify-backup.sh script to check backup integrity

    Shows backup count, size, and age

    Warns if backup count exceeds limit

6. Email Alert Integration

    Optional email configuration during install

    Alerts for high temperature (warning/critical)

    Backup success/failure notifications

    Cooldown period prevents alert spam

The Script is Now COMPLETE:

✅ Auto-Backup - Weekly Teleporter backups with 7-backup retention
✅ Auto-Delete - Oldest backups automatically removed
✅ Thermal Monitoring - Every 5 minutes with email alerts
✅ Health Dashboard - Complete system status at a glance
✅ Backup Verification - Check backup integrity anytime
✅ WireGuard VPN - Optional secure remote access
✅ Static IP - Triple-reinforced across reboots
✅ Pi-hole Pre-config - Silent install with Unbound/DNSCrypt
✅ 12 Blocklists - Maximum ad/tracker blocking
✅ 25+ Regex Patterns - Sophisticated filtering
✅ 50+ Whitelist Domains - Microsoft Teams, Office 365, etc.
✅ Nuclear Cleanup - Always runs, removes ALL traces
✅ 48 iterations - Professional grade solution
After Installation:

    Check health: pihole-health

    Verify backups: verify-backup.sh

    Monitor temperature: tail -f /var/log/thermal-monitor.log

    Configure WireGuard: Edit /etc/wireguard/wg0.conf if installed

    Reboot: Everything auto-starts and continues working

This is the COMPLETE PROFESSIONAL SOLUTION - enterprise-grade reliability with automatic maintenance, monitoring, and disaster recovery!
