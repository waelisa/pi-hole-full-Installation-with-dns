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
