# **🛡️ Pi-hole + DNSCrypt-Proxy + Unbound: Ultimate Masterpiece Edition**

An enterprise-grade, self-healing, and hardened DNS automation suite for home labs and production environments. This script deploys a triple-tier DNS stack designed for maximum privacy, zero-leak security, and high availability.

## **🚀 Overview**

This isn't just an installer; it's a complete DNS ecosystem management tool. It bridges the gap between basic ad-blocking and professional-grade infrastructure by combining:

1.  **Pi-hole**: The world's best network-wide ad and tracker blocker.
2.  **DNSCrypt-Proxy (Primary)**: Encrypted, anonymized DNS for maximum privacy on port 5053.
3.  **Unbound (Secondary/Failover)**: A recursive resolver with **DNS-over-TLS (DoT)** and **DoH fallback** on port 5335.

## **✨ Key Features (v1.1.0)**

### **🔒 Security & Privacy**

*   **Zero-Leak Hardening**: Implements no-resolv and strict-order to prevent ISP DNS leakage even during service restarts.
*   **DNSSEC Validation**: Full recursive validation handled at the root level by Unbound.
*   **Anonymized DNS**: Leveraging DNSCrypt-Proxy to hide your identity from upstream providers.
*   **Rate Limiting**: Built-in protection (1000 queries/60s) to prevent DNS amplification and IoT "query storms".

### **🛠️ Intelligent Automation**

*   **Self-Healing Watchdog**: A background service monitors ports every 60 seconds and auto-restarts failed services.
*   **Resource Auto-Tuning**: Automatically calculates caches and threads based on your system's RAM and CPU.
*   **Safe Cron Management**: Uses duplicate-detection logic for gravity and regex updates to keep crontab clean.
*   **Conflict Detection**: Scans for existing DHCP servers and IPv6 Router Advertisements (RA) to prevent network-wide outages.

### **🌐 Web Compatibility**

*   **Microsoft Teams & O365 Guaranteed**: Direct SQL injection of a curated whitelist into the Pi-hole database ensures critical services work from second one—no manual pihole -w required.
*   **Optimized Performance**: "Happy Eyeballs" enabled in DNSCrypt-Proxy to minimize double-hop latency.

## **📊 Technical Architecture**

The script configures a hierarchical failover path to ensure you never lose internet access:

1.  **Tier 1**: Pi-hole receives the query.
2.  **Tier 2 (Primary)**: Query is forwarded to DNSCrypt-Proxy (Port 5053).
3.  **Tier 3 (Backup)**: If DNSCrypt is slow or down, Pi-hole fails over to Unbound (Port 5335).
4.  **Tier 4 (Recursive)**: Unbound resolves via Quad9 using DoT, with an automatic fallback to DoH (Port 443) if Port 853 is throttled.

## **📝 Configuration Summary**

Component Port Role Protocol

**Pi-hole** 53 Ad-Blocker / Controller DNS

**DNSCrypt-Proxy** 5053 **Primary Upstream** Anonymized DNS

**Unbound** 53335 **Secondary / Failover** DoT / DoH Fallback

**Monitoring UI** Configurable DNSCrypt Dashboard HTTP

## **📥 Installation**

Bash

# Clone the repository git clone https://github.com/waelisa/pi-hole-full-Installation-with-dns.git # Navigate to the directorycd pi-hole-full-Installation-with-dns # Make the script executable chmod +x pihole-auto-installation-with-dns.sh # Run the Masterpiece installer sudo ./pihole-auto-installation-with-dns.sh

## **🔄 Restore & Uninstall**

This build features a **Triple-Verified SQLite Cleanup**. Running the generated restore.sh will:

*   Remove all injected whitelist/blacklist entries (no ghost entries).
*   Clean up the gravity.db by version and comment.
*   Restore your original network and service configurations.

## **☕ Support the Project**

If this "Masterpiece" script has saved you time and secured your network, consider supporting further development:

👉 [**Donate via PayPal**](https://www.paypal.me/WaelIsa)

**Author**: [Wael Isa](https://www.wael.name/) | **Build Date**: 02/18/2026 | **Version**: 1.1.0
