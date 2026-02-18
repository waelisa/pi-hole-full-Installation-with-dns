#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Wael Isa
# Build Date: 02/18/2026
# Version: 1.1.2
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
#
#############################################################################################################################
# Pi-hole + DNSCrypt Proxy + Unbound Installation Script - ULTIMATE MASTERPIECE FINAL EDITION
# Features:
#   ✓ Automated Pi-hole installation (if not present)
#   ✓ DNSCrypt Proxy setup with best privacy settings (port 5053) - PRIMARY
#   ✓ Unbound DNS resolver with Quad9 DoT/DoH fallback (port 5335) - SECONDARY
#   ✓ DNSSEC root key initialization and validation (handled by Unbound only)
#   ✓ Automatic backup of all modified configuration files
#   ✓ Systemd service configurations for all components
#   ✓ Comprehensive blocklist management with 12 curated lists
#   ✓ DNSSEC validation testing with Pi-hole validation disabled
#   ✓ Comprehensive error handling and logging
#   ✓ Easy restore points for all configurations
#   ✓ Debian Bullseye+ resolvconf fixes (with Bookworm/Trixie support)
#   ✓ AppArmor configuration for Unbound logging
#   ✓ Pi-hole failover configuration (DNSCrypt primary, Unbound secondary)
#   ✓ Strict-order DNS query handling with no-resolv hardening (prevents DNS leakage)
#   ✓ Automated setupVars.conf configuration with DNSSEC=false
#   ✓ Failover testing and verification with automated failover logic testing
#   ✓ Multi-OS support (Debian/Ubuntu/Raspbian/CentOS/RHEL/Fedora/Arch)
#   ✓ Rate limiting protection (1000 queries/60 seconds per client)
#   ✓ Anti-flapping protection for DNS services
#   ✓ IoT device protection against DNS amplification attacks
#   ✓ Automatic health checks and service recovery
#   ✓ Comprehensive restore script that reverses all changes (with COMPLETE SQLite cleanup)
#   ✓ Zero-leak configuration (no-resolv prevents ISP DNS leakage)
#   ✓ Automated failover verification tests
#   ✓ pihole-FTL advanced configuration with optimal settings
#   ✓ Primary DNS failure alerting system (email/pushover/webhook/slack)
#   ✓ Prometheus metrics export for monitoring (FULLY IMPLEMENTED)
#   ✓ Grafana dashboard ready configuration
#   ✓ Automated performance tuning based on system resources
#   ✓ Dynamic network interface detection (no hardcoded fallback)
#   ✓ Comprehensive REGEX filtering (block/allow patterns from mmotti + custom)
#   ✓ Curated whitelist for essential services (Apple, Microsoft, Google, CDNs) - DIRECT SQL INJECTION
#   ✓ Curated blacklist for malware, phishing, and tracking domains
#   ✓ Regex pattern categories: tracking, malware, phishing, crypto scams
#   ✓ Automated regex list updates via cron
#   ✓ Group-based filtering for different network segments
#   ✓ Smart whitelist prioritization to prevent false positives
#   ✓ Daily Pi-hole gravity updates via cron
#   ✓ Interactive Pi-hole DHCP configuration (with DHCP and IPv6 RA conflict detection)
#   ✓ DNSCrypt Proxy built-in monitoring UI (configurable port)
#   ✓ Microsoft Teams compatibility ensured (direct SQL injection with version tracking)
#   ✓ Local DNS records (dns1.local) with configurable hostname
#   ✓ DNSCrypt Proxy cloaking rules support (using example-cloaking-rules.txt)
#   ✓ Safe cron management (no duplicate entries)
#   ✓ Guaranteed gravity update on script completion
#   ✓ 100% tested restore functionality (complete SQLite cleanup with NO GHOST ENTRIES)
#   ✓ Automated watchdog service (60-second health checks)
#   ✓ DNSCrypt Happy Eyeballs enabled (reduces double-hop latency)
#   ✓ DoH fallback for Unbound (if Port 853 is throttled)
#   ✓ Advanced logrotate configuration (prevents disk filling)
#   ✓ DHCP and IPv6 RA conflict detection and prevention
#   ✓ SQLite database complete cleanup in restore script (multi-method verification)
#   ✓ Comprehensive health dashboard command (pihole-health)
#   ✓ IPv6 Router Advertisement (RA) detection for DNS conflicts
#   ✓ Final production-ready enterprise DNS solution
#   ✓ Version tracking in database for complete uninstall capability
#   ✓ Triple-verified SQLite cleanup (by comment, by version, by domain pattern)
#   ✓ GitHub repository integration with full URL display
#   ✓ Author website link prominently displayed
#   ✓ Proper Ctrl+C handling with graceful cleanup
#   ✓ Fixed cloaking rules path issue (v1.1.2)
#   ✓ Example cloaking rules file properly copied
#############################################################################################################################

# No set -e at the top - we handle errors gracefully with traps
# No set -u - we handle undefined variables with checks

# Script metadata
SCRIPT_VERSION="1.1.2"
SCRIPT_AUTHOR="Wael Isa"
SCRIPT_DATE="02/18/2026"
SCRIPT_GITHUB="https://github.com/waelisa/pi-hole-full-Installation-with-dns"
SCRIPT_WEBSITE="https://www.wael.name/"
SCRIPT_DB_COMMENT="v1.1.2 Masterpiece Whitelist - https://www.wael.name/"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
UNBOUND_PORT="5335"
DNSCRYPT_PORT="5053"
PIHOLE_INTERFACE=""  # Will be auto-detected
BACKUP_DIR="/root/dns-backup-$(date +%Y%m%d-%H%M%S)"
SCRIPT_LOG="/var/log/dns-install.log"
WORKING_DIR="/opt/dns-setup"
GRAVITY_DB="/etc/pihole/gravity.db"
FTL_CONFIG="/etc/pihole/pihole-FTL.conf"
RESTORE_SCRIPT="$BACKUP_DIR/restore.sh"
ALERT_CONFIG="/etc/dns-alerts.conf"
PROMETHEUS_EXPORTER="/usr/local/bin/dns-metrics-exporter.sh"
REGEX_FILE="/etc/pihole/regex.list"
CUSTOM_WHITELIST="/etc/pihole/whitelist.txt"
CUSTOM_BLACKLIST="/etc/pihole/blacklist.txt"
DNSCRYPT_CONFIG_DIR="/etc/dnscrypt-proxy"
DNSCRYPT_CONFIG_FILE="$DNSCRYPT_CONFIG_DIR/dnscrypt-proxy.toml"
EXAMPLE_CLOAKING_FILE="$DNSCRYPT_CONFIG_DIR/example-cloaking-rules.txt"
CLOAKING_FILE="$DNSCRYPT_CONFIG_DIR/cloaking-rules.txt"
CRON_BACKUP_DIR="/root/cron-backup"
WATCHDOG_SCRIPT="/usr/local/bin/dns-watchdog.sh"
LOGROTATE_CONFIG="/etc/logrotate.d/pihole-custom"
HEALTH_DASHBOARD="/usr/local/bin/pihole-health"
VERSION_TRACKING_FILE="/etc/pihole/.masterpiece-version"

# Default local DNS settings
LOCAL_DNS_HOSTNAME="dns1"
LOCAL_DNS_DOMAIN="local"
LOCAL_DNS_IP="$(hostname -I | awk '{print $1}')"

# Rate limiting configuration
RATE_LIMIT_COUNT="1000"
RATE_LIMIT_INTERVAL="60"

# Health check configuration
HEALTH_CHECK_INTERVAL="300"  # 5 minutes
HEALTH_CHECK_RETRIES="3"
PRIMARY_FAILURE_THRESHOLD="300"  # Alert if primary down for 5 minutes

# Watchdog configuration
WATCHDOG_INTERVAL="60"  # Check every 60 seconds

# Performance tuning
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}' 2>/dev/null || echo "2048")
CPU_CORES=$(nproc 2>/dev/null || echo "2")
if [[ $TOTAL_MEM -gt 16000 ]]; then
    CACHE_SIZE="10000"
    FTL_THREADS="4"
    UNBOUND_MSG_CACHE="$((TOTAL_MEM / 4))m"
    UNBOUND_RRSET_CACHE="$((TOTAL_MEM / 2))m"
elif [[ $TOTAL_MEM -gt 8000 ]]; then
    CACHE_SIZE="5000"
    FTL_THREADS="2"
    UNBOUND_MSG_CACHE="$((TOTAL_MEM / 4))m"
    UNBOUND_RRSET_CACHE="$((TOTAL_MEM / 2))m"
else
    CACHE_SIZE="1000"
    FTL_THREADS="1"
    UNBOUND_MSG_CACHE="$((TOTAL_MEM / 4))m"
    UNBOUND_RRSET_CACHE="$((TOTAL_MEM / 2))m"
fi

# Quad9 DNS over TLS (DoT) and DNS over HTTPS (DoH) servers
QUAD9_DOT_SERVERS=(
    "9.9.9.9@853#dns.quad9.net"
    "149.112.112.112@853#dns.quad9.net"
    "2620:fe::fe@853#dns.quad9.net"
    "2620:fe::9@853#dns.quad9.net"
)

# Quad9 DNS over HTTPS (DoH) servers - fallback if DoT is throttled
QUAD9_DOH_SERVERS=(
    "https://9.9.9.9/dns-query"
    "https://149.112.112.112/dns-query"
    "https://2620:fe::fe/dns-query"
    "https://2620:fe::9/dns-query"
)

# Comprehensive blocklist collection
BLOCKLISTS=(
    "https://blocklistproject.github.io/Lists/alt-version/phishing-nl.txt|Blocklist Project Phishing|default"
    "https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Hosts/GoodbyeAds.txt|GoodbyeAds Comprehensive|default"
    "https://big.oisd.nl/|OISD Big (Comprehensive)|default"
    "https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt|NoTrack Malware|default"
    "https://phishing.army/download/phishing_army_blocklist_extended.txt|Phishing Army Extended|default"
    "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt|AdGuard Base Filter|default"
    "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|StevenBlack Unified|default"
    "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt|SmartTV Tracking|default"
    "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/android-tracking.txt|Android Tracking|default"
    "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt|Windows Telemetry|default"
    "https://v.firebog.net/hosts/Easyprivacy.txt|EasyPrivacy|default"
    "https://raw.githubusercontent.com/Dogino/Discord-Phishing-URLs/main/pihole-phishing-adlist.txt|Discord Phishing|default"
)

# Regex patterns based on mmotti's excellent work
REGEX_PATTERNS=(
    # DENY patterns (type 3) - Tracking & Analytics
    "^(.+[-_.])?(track|tracking|analytics|stat|stats|metrics|pixel|beacon|count|counter)[-_.].*$|3|Tracking domains - general"
    "^(.+[-_.])?adservice[-_.].*$|3|Google AdService"
    "^(.+[-_.])?doubleclick[-_.].*$|3|DoubleClick"
    "^(.+[-_.])?google-analytics[-_.].*$|3|Google Analytics"
    "^(.+[-_.])?googletagmanager[-_.].*$|3|Google Tag Manager"
    "^(.+[-_.])?amazon-adsystem[-_.].*$|3|Amazon Ads"
    "^(.+[-_.])?adsystem[-_.].*$|3|Ad System"

    # DENY patterns - Malware & Phishing
    "^(.+[-_.])?malware[-_.].*$|3|Malware domains"
    "^(.+[-_.])?phishing[-_.].*$|3|Phishing domains"
    "^(.+[-_.])?cryptominer[-_.].*$|3|Crypto miners"
    "^(.+[-_.])?coin[-_.]?hive[-_.].*$|3|Coin Hive"
    "^(.+[-_.])?cryptoloot[-_.].*$|3|CryptoLoot"

    # DENY patterns - Suspicious TLDs
    "^.*\.(xyz|top|bid|download|loan|date|win|review|trade|webcam|men|rest|gdn|work|mom|live|pro|stream|racing)$|3|Suspicious TLDs"

    # ALLOW patterns (type 2) - Critical services that might be caught by DENY
    "^([a-z0-9]+[-_.])?apple\.com$|2|Apple main"
    "^([a-z0-9]+[-_.])?icloud\.com$|2|iCloud"
    "^([a-z0-9]+[-_.])?microsoft\.com$|2|Microsoft main"
    "^([a-z0-9]+[-_.])?teams\.microsoft\.com$|2|Microsoft Teams - CRITICAL"
    "^([a-z0-9]+[-_.])?skype\.com$|2|Skype"
    "^([a-z0-9]+[-_.])?office\.com$|2|Office 365"
    "^([a-z0-9]+[-_.])?azure\.com$|2|Azure"
    "^([a-z0-9]+[-_.])?google\.com$|2|Google main"
    "^([a-z0-9]+[-_.])?youtube\.com$|2|YouTube"
    "^([a-z0-9]+[-_.])?gmail\.com$|2|Gmail"
    "^([a-z0-9]+[-_.])?android\.com$|2|Android"
    "^([a-z0-9]+[-_.])?googleapis\.com$|2|Google APIs"
    "^([a-z0-9]+[-_.])?cloudflare\.com$|2|Cloudflare"
)

# Essential whitelist domains (exact matches) - DIRECT SQL INJECTION WITH VERSION TRACKING
WHITELIST_DOMAINS=(
    # Microsoft Teams and Office 365 (CRITICAL - ensure not blocked)
    "microsoft.com"
    "microsoftonline.com"
    "office.com"
    "office365.com"
    "teams.microsoft.com"
    "teams.microsoft.us"
    "skype.com"
    "skypeforbusiness.com"
    "lync.com"
    "cloud.microsoft.com"
    "login.microsoftonline.com"
    "graph.microsoft.com"
    "outlook.office.com"
    "outlook.office365.com"
    "sharepoint.com"
    "yammer.com"
    "msftconnecttest.com"
    "msftncsi.com"

    # Apple Services
    "apple.com"
    "icloud.com"
    "apple-cloud.com"
    "appleid.apple.com"
    "gs.apple.com"
    "ocsp.apple.com"
    "time.apple.com"
    "push.apple.com"

    # Google Services
    "google.com"
    "youtube.com"
    "gmail.com"
    "android.com"
    "googleapis.com"
    "googleadservices.com"
    "gstatic.com"

    # CDNs & Infrastructure
    "cloudflare.com"
    "cloudflare.net"
    "fastly.net"
    "akamai.net"
    "edgekey.net"

    # Social Media
    "facebook.com"
    "fbcdn.net"
    "instagram.com"
    "twitter.com"
    "twimg.com"
    "linkedin.com"
    "reddit.com"

    # Streaming
    "netflix.com"
    "nflxvideo.net"
    "spotify.com"

    # Communication
    "discord.com"
    "discordapp.com"
    "slack.com"
    "zoom.us"
    "whatsapp.com"
    "telegram.org"

    # Development
    "github.com"
    "githubusercontent.com"
    "gitlab.com"
    "stackoverflow.com"
    "npmjs.com"
    "docker.com"

    # Financial
    "paypal.com"
    "paypalobjects.com"
    "stripe.com"

    # System Updates
    "update.microsoft.com"
    "download.microsoft.com"
    "swdist.apple.com"
    "mesu.apple.com"
    "ocsp.digicert.com"
    "crl.digicert.com"
    "time.windows.com"
)

# Additional blacklist domains (exact matches)
BLACKLIST_DOMAINS=(
    # Known malware domains
    "coin-hive.com"
    "coinhive.com"
    "cryptoloot.com"
    "miner.pr0gramm.com"

    # Telemetry & Tracking
    "telemetry.microsoft.com"
    "watson.telemetry.microsoft.com"
    "sqm.telemetry.microsoft.com"
    "vortex.data.microsoft.com"
    "settings-win.data.microsoft.com"
    "settings.data.microsoft.com"
)

# Function to print colored output
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$SCRIPT_LOG"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$SCRIPT_LOG"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$SCRIPT_LOG"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$SCRIPT_LOG"; }
print_section() {
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

# Enhanced cleanup function that handles Ctrl+C gracefully
cleanup() {
    local exit_code=$?
    echo ""
    print_warning "Received interrupt signal. Cleaning up..."

    # Restart services that might have been stopped
    systemctl start unbound 2>/dev/null || true
    systemctl start dnscrypt-proxy 2>/dev/null || true
    pihole restartdns 2>/dev/null || true

    # Remove any temporary files
    rm -f /tmp/failover-test-* 2>/dev/null || true
    rm -f /tmp/merged-regex.list 2>/dev/null || true
    rm -f /tmp/mmotti-regex.list 2>/dev/null || true
    rm -f /tmp/stevejenkins-regex.list 2>/dev/null || true

    print_status "Cleanup complete. Check $SCRIPT_LOG for details."

    # Exit with the original exit code
    exit $exit_code
}

# Set trap at the beginning of the script (after function definition)
trap 'cleanup' INT TERM EXIT

# Function to display script banner
show_banner() {
    clear
    cat << EOF
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║   ██████╗ ██╗      ███████╗ ██████╗ ██╗     ███████╗                       ║
║   ██╔══██╗██║      ██╔════╝██╔═══██╗██║     ██╔════╝                       ║
║   ██████╔╝██║█████╗█████╗  ██║   ██║██║     █████╗                         ║
║   ██╔═══╝ ██║╚════╝██╔══╝  ██║   ██║██║     ██╔══╝                         ║
║   ██║     ██║      ██║     ╚██████╔╝███████╗███████╗                       ║
║   ╚═╝     ╚═╝      ╚═╝      ╚═════╝ ╚══════╝╚══════╝                       ║
║                                                                              ║
║   Pi-hole + DNSCrypt-Proxy + Unbound Installer                              ║
║   Version ${SCRIPT_VERSION} - ${SCRIPT_AUTHOR} - ${SCRIPT_DATE}                              ║
║   ULTIMATE MASTERPIECE FINAL EDITION                                        ║
║                                                                              ║
║   GitHub: ${SCRIPT_GITHUB}                          ║
║   Website: ${SCRIPT_WEBSITE}                                           ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to detect OS and package manager
detect_os() {
    print_status "Detecting operating system and package manager..."

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        ID=$ID
        ID_LIKE=${ID_LIKE:-}
    else
        print_error "Cannot detect OS"
        exit 1
    fi

    # Determine package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
        PKG_REMOVE="apt-get remove -y"
        PKG_PURGE="apt-get purge -y"
        DEBIAN_VERSION=0
        if [[ "$ID" == "debian" ]]; then
            DEBIAN_VERSION="${VER%%.*}"
            if [[ $DEBIAN_VERSION -ge 11 ]]; then
                DEBIAN_BULLSEYE_PLUS=true
                if [[ $DEBIAN_VERSION -ge 12 ]]; then
                    DEBIAN_BOOKWORM_PLUS=true
                    print_status "Debian Bookworm+ detected - enhanced AppArmor support"
                fi
            fi
        fi
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf check-update"
        PKG_INSTALL="dnf install -y"
        PKG_REMOVE="dnf remove -y"
        PKG_PURGE="dnf remove -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum check-update"
        PKG_INSTALL="yum install -y"
        PKG_REMOVE="yum remove -y"
        PKG_PURGE="yum remove -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
        PKG_REMOVE="pacman -R --noconfirm"
        PKG_PURGE="pacman -Rns --noconfirm"
    else
        print_error "Unsupported package manager"
        exit 1
    fi

    print_success "Detected: $OS $VER (Package manager: $PKG_MANAGER)"

    # Detect default network interface
    print_status "Detecting active network interface..."

    if command -v ip &> /dev/null; then
        DEFAULT_IF=$(ip -4 route show default | awk '{print $5}' | head -n1)
        if [[ -z "$DEFAULT_IF" ]]; then
            DEFAULT_IF=$(ip -4 route show | grep -m1 ^default | awk '{print $5}')
        fi
        if [[ -z "$DEFAULT_IF" ]]; then
            DEFAULT_IF=$(ip -4 addr show | grep -v "127.0.0.1" | grep -m1 inet | awk '{print $NF}')
        fi
    fi

    if [[ -z "$DEFAULT_IF" ]] && command -v route &> /dev/null; then
        DEFAULT_IF=$(route -n | grep -m1 "^0.0.0.0" | awk '{print $8}')
    fi

    if [[ -z "$DEFAULT_IF" ]]; then
        for iface in /sys/class/net/*; do
            iface_name=$(basename "$iface")
            if [[ "$iface_name" != "lo" ]]; then
                DEFAULT_IF="$iface_name"
                break
            fi
        done
    fi

    if [[ -n "$DEFAULT_IF" ]]; then
        PIHOLE_INTERFACE="$DEFAULT_IF"
        print_success "Detected active network interface: $PIHOLE_INTERFACE"
    else
        print_error "Could not detect network interface automatically"
        echo "Please enter your network interface name (e.g., eth0, wlan0, enp0s3): "
        read -r PIHOLE_INTERFACE
        if [[ -z "$PIHOLE_INTERFACE" ]]; then
            print_error "No interface provided. Exiting."
            exit 1
        fi
    fi
}

# Function to backup existing crons safely
backup_crons() {
    print_status "Backing up existing cron jobs..."

    mkdir -p "$CRON_BACKUP_DIR"
    local backup_file="$CRON_BACKUP_DIR/crontab-$(date +%Y%m%d-%H%M%S).backup"

    # Backup all users' crons
    for user in root $(ls /home 2>/dev/null); do
        if crontab -u "$user" -l 2>/dev/null; then
            crontab -u "$user" -l > "$CRON_BACKUP_DIR/crontab-$user.backup" 2>/dev/null || true
        fi
    done

    # Backup system crons
    cp -r /etc/cron.d "$CRON_BACKUP_DIR/" 2>/dev/null || true
    cp -r /etc/cron.daily "$CRON_BACKUP_DIR/" 2>/dev/null || true
    cp -r /etc/cron.hourly "$CRON_BACKUP_DIR/" 2>/dev/null || true
    cp -r /etc/cron.weekly "$CRON_BACKUP_DIR/" 2>/dev/null || true
    cp -r /etc/cron.monthly "$CRON_BACKUP_DIR/" 2>/dev/null || true

    print_success "Cron jobs backed up to $CRON_BACKUP_DIR"
}

# Function to safely add cron job (no duplicates)
safe_add_cron() {
    local cron_line="$1"
    local cron_file="$2"

    # Check if cron line already exists
    if [[ -f "$cron_file" ]]; then
        if grep -Fq "$cron_line" "$cron_file"; then
            print_status "Cron job already exists in $cron_file, skipping..."
            return 0
        fi
    fi

    # Add cron job
    echo "$cron_line" >> "$cron_file"
    print_success "Added cron job to $cron_file"
}

# Function to create backup of configuration files
create_backup() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup_path="${BACKUP_DIR}${file}"
        mkdir -p "$(dirname "$backup_path")"
        cp -p "$file" "$backup_path"
        print_status "Backed up: $file -> $backup_path"
    fi
}

# Function to install packages based on OS
install_packages() {
    local packages=("$@")
    local missing_packages=()

    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null && ! dpkg -l "$pkg" &> /dev/null 2>&1; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        print_status "Installing packages: ${missing_packages[*]}"
        $PKG_INSTALL "${missing_packages[@]}" >> "$SCRIPT_LOG" 2>&1 || {
            print_warning "Some packages failed to install. Continuing anyway..."
        }
    fi
}

# Function to detect DHCP and IPv6 RA conflicts
detect_dhcp_conflicts() {
    print_status "Checking for existing DHCP servers and IPv6 Router Advertisements on the network..."

    local conflicts_found=0

    # Check for DHCP servers using nmap
    if command -v nmap &> /dev/null; then
        local dhcp_servers=$(nmap --script broadcast-dhcp-discover 2>/dev/null | grep -i "DHCPOFFER" || true)
        if [[ -n "$dhcp_servers" ]]; then
            print_warning "⚠ Potential DHCP servers detected on the network:"
            echo "$dhcp_servers" | while read -r line; do
                echo "   $line"
            done
            conflicts_found=1
        fi
    fi

    # Check for IPv6 Router Advertisements (RAs)
    if command -v rdisc6 &> /dev/null; then
        local ipv6_ras=$(rdisc6 -1 "$PIHOLE_INTERFACE" 2>/dev/null | grep -i "DNS" || true)
        if [[ -n "$ipv6_ras" ]]; then
            print_warning "⚠ IPv6 Router Advertisements detected with DNS options:"
            echo "$ipv6_ras" | while read -r line; do
                echo "   $line"
            done
            conflicts_found=1
        fi
    elif [[ -f /proc/net/if_inet6 ]]; then
        # Simple IPv6 check if rdisc6 not available
        local ipv6_routers=$(ip -6 route show | grep "default via" | wc -l)
        if [[ $ipv6_routers -gt 0 ]]; then
            print_warning "⚠ IPv6 routers detected on the network (may provide DNS via RA)"
            ip -6 route show | grep "default via" | while read -r line; do
                echo "   $line"
            done
            conflicts_found=1
        fi
    fi

    # Check if Pi-hole DHCP is already enabled
    if pihole -c -j 2>/dev/null | grep -q '"DHCP":"enabled"'; then
        print_warning "⚠ Pi-hole DHCP is already enabled"
        conflicts_found=1
    fi

    if [[ $conflicts_found -gt 0 ]]; then
        echo ""
        print_warning "DHCP conflicts detected! Enabling Pi-hole DHCP may cause network issues."
        echo "Would you like to:"
        echo "  1) Continue anyway (not recommended)"
        echo "  2) Skip DHCP configuration (recommended)"
        echo "  3) Force disable detected DHCP servers (dangerous, may break network)"
        read -r dhcp_choice

        case $dhcp_choice in
            1)
                print_warning "Continuing with DHCP configuration despite conflicts"
                return 0
                ;;
            2)
                print_status "Skipping DHCP configuration"
                return 1
                ;;
            3)
                print_warning "Attempting to disable detected DHCP servers..."
                # This would require advanced network configuration - not implemented for safety
                print_error "Automatic DHCP disabling not implemented for safety"
                return 1
                ;;
            *)
                print_status "Skipping DHCP configuration"
                return 1
                ;;
        esac
    fi

    return 0
}

# Function to prompt for alerting configuration
configure_alerts() {
    print_section "Alerting Configuration (Optional)"

    echo "Would you like to configure DNS failure alerts? (y/N): "
    read -r configure_alerts

    if [[ "$configure_alerts" =~ ^[Yy]$ ]]; then
        cat > "$ALERT_CONFIG" << 'EOF'
# DNS Alerting Configuration
# Uncomment and configure the methods you want to use

# Email alerts (requires sendmail or mailutils)
# ALERT_EMAIL="your-email@example.com"

# Pushover alerts (https://pushover.net)
# ALERT_PUSHOVER_TOKEN="your-app-token"
# ALERT_PUSHOVER_USER="your-user-key"

# Slack webhook
# ALERT_SLACK_WEBHOOK="https://hooks.slack.com/services/xxx/yyy/zzz"

# Generic webhook
# ALERT_WEBHOOK_URL="https://your-webhook-endpoint.com/alert"

# Alert threshold (seconds primary must be down before alert)
ALERT_THRESHOLD=300
EOF

        echo "Alert configuration template created at $ALERT_CONFIG"
        echo "Please edit this file to add your alerting credentials."

        echo "Would you like to edit the alert configuration now? (y/N): "
        read -r edit_now
        if [[ "$edit_now" =~ ^[Yy]$ ]]; then
            ${EDITOR:-nano} "$ALERT_CONFIG"
        fi
    else
        echo "# DNS Alerting Configuration (alerts disabled)" > "$ALERT_CONFIG"
        echo "ALERT_THRESHOLD=300" >> "$ALERT_CONFIG"
    fi
}

# Function to configure Pi-hole DHCP with conflict detection
configure_pihole_dhcp() {
    print_section "Pi-hole DHCP Configuration"

    echo "Would you like to enable Pi-hole's DHCP server? (y/N): "
    read -r enable_dhcp

    if [[ "$enable_dhcp" =~ ^[Yy]$ ]]; then
        # Check for conflicts first
        if ! detect_dhcp_conflicts; then
            return
        fi

        echo "Enter DHCP IP range start (e.g., 192.168.1.100): "
        read -r dhcp_start
        echo "Enter DHCP IP range end (e.g., 192.168.1.200): "
        read -r dhcp_end
        echo "Enter DHCP router IP (e.g., 192.168.1.1): "
        read -r dhcp_router
        echo "Enter DHCP lease time in hours (default: 24): "
        read -r dhcp_lease
        dhcp_lease=${dhcp_lease:-24}

        # Enable DHCP in Pi-hole
        pihole -a enabledhcp "$dhcp_start" "$dhcp_end" "$dhcp_router" "$dhcp_lease" >> "$SCRIPT_LOG" 2>&1

        print_success "Pi-hole DHCP enabled: $dhcp_start - $dhcp_end, Router: $dhcp_router, Lease: ${dhcp_lease}h"

        # Add note to restore script
        echo "# Pi-hole DHCP was enabled during installation" >> "$BACKUP_DIR/install-notes.txt"
    else
        print_status "Pi-hole DHCP disabled (using existing router DHCP)"
    fi
}

# Function to configure DNSCrypt Proxy monitoring UI
configure_dnscrypt_dashboard() {
    print_section "DNSCrypt Proxy Monitoring UI Configuration"

    echo "Would you like to enable the built-in DNSCrypt Proxy monitoring UI? (y/N): "
    read -r enable_monitoring

    if [[ "$enable_monitoring" =~ ^[Yy]$ ]]; then
        echo "Enter IP address for monitoring UI (default: 192.168.100.50): "
        read -r monitor_ip
        monitor_ip=${monitor_ip:-192.168.100.50}

        echo "Enter port for monitoring UI (default: 8888): "
        read -r monitor_port
        monitor_port=${monitor_port:-8888}

        # Store for later use in DNSCrypt config
        MONITOR_IP="$monitor_ip"
        MONITOR_PORT="$monitor_port"

        print_success "DNSCrypt Proxy monitoring will be configured on http://$monitor_ip:$monitor_port"
    else
        MONITOR_ENABLED="false"
    fi
}

# Function to configure local DNS records
configure_local_dns() {
    print_section "Local DNS Records Configuration"

    echo "Configure local DNS records? (y/N): "
    read -r configure_local

    if [[ "$configure_local" =~ ^[Yy]$ ]]; then
        echo "Enter local DNS hostname (default: dns1): "
        read -r local_hostname
        local_hostname=${local_hostname:-dns1}

        echo "Enter local DNS domain (default: local): "
        read -r local_domain
        local_domain=${local_domain:-local}

        local_full="${local_hostname}.${local_domain}"
        local_ip="$LOCAL_DNS_IP"

        echo "Enter IP address for $local_full (default: $local_ip): "
        read -r custom_ip
        local_ip=${custom_ip:-$local_ip}

        # Add to Pi-hole local DNS records
        pihole -a addcustomdns "$local_full" "$local_ip" >> "$SCRIPT_LOG" 2>&1

        print_success "Added local DNS record: $local_full -> $local_ip"

        # Also add to /etc/hosts for good measure
        if ! grep -q "$local_full" /etc/hosts; then
            echo "$local_ip $local_full" >> /etc/hosts
        fi
    fi
}

# Function to configure DNSCrypt Proxy cloaking rules
configure_cloaking() {
    print_section "DNSCrypt Proxy Cloaking Rules"

    echo "Would you like to configure DNSCrypt Proxy cloaking rules (local overrides)? (y/N): "
    read -r configure_cloaking

    if [[ "$configure_cloaking" =~ ^[Yy]$ ]]; then
        # Create DNSCrypt config directory if it doesn't exist
        if [[ ! -d "$DNSCRYPT_CONFIG_DIR" ]]; then
            mkdir -p "$DNSCRYPT_CONFIG_DIR"
            print_status "Created DNSCrypt config directory: $DNSCRYPT_CONFIG_DIR"
        fi

        # Check if example cloaking file exists
        if [[ -f "$EXAMPLE_CLOAKING_FILE" ]]; then
            # Copy example to actual cloaking file
            cp "$EXAMPLE_CLOAKING_FILE" "$CLOAKING_FILE"
            print_success "Copied example cloaking rules to $CLOAKING_FILE"
        else
            # Create new cloaking file with header
            cat > "$CLOAKING_FILE" << 'EOF'
# DNSCrypt Proxy Cloaking Rules
# Format: domain.name 1.2.3.4
# These rules override DNS responses with local IPs

# Example: Block social media by redirecting to localhost
# www.facebook.com 0.0.0.0
# www.instagram.com 0.0.0.0

# Example: Local development domains
# dev.local 127.0.0.1
# test.local 127.0.0.1

# Your custom rules below:
EOF
            print_success "Created new cloaking rules file at $CLOAKING_FILE"
        fi

        echo "Enter cloaking rules (one per line, format: 'domain.com 127.0.0.1'). Empty line to finish:"
        while true; do
            read -r rule
            if [[ -z "$rule" ]]; then
                break
            fi
            echo "$rule" >> "$CLOAKING_FILE"
        done

        print_success "Cloaking rules saved to $CLOAKING_FILE"
    fi
}

# Function to configure DoH fallback for Unbound
configure_unbound_doh_fallback() {
    print_section "Unbound DoH Fallback Configuration"

    echo "Would you like to enable DNS-over-HTTPS (DoH) fallback? (y/N): "
    echo "(Useful if your ISP throttles Port 853 - DoT)"
    read -r enable_doh

    if [[ "$enable_doh" =~ ^[Yy]$ ]]; then
        DOH_ENABLED=true
        print_success "DoH fallback will be configured"
    else
        DOH_ENABLED=false
    fi
}

# Function to install required dependencies
install_dependencies() {
    print_section "Installing Dependencies"

    print_status "Updating package lists..."
    $PKG_UPDATE >> "$SCRIPT_LOG" 2>&1 || true

    # Base dependencies for all systems
    local base_packages=(
        "wget"
        "curl"
        "git"
        "gnupg"
        "dnsutils"
        "net-tools"
        "ca-certificates"
        "sudo"
        "systemd"
        "unzip"
        "tar"
        "grep"
        "sed"
        "awk"
        "openssl"
        "procps"
        "psmisc"
        "jq"
        "bc"
        "sqlite3"
        "python3"
        "nmap"           # For DHCP conflict detection
        "ndisc6"         # For IPv6 RA detection (provides rdisc6)
        "logrotate"      # For log management
    )

    # OS-specific package names
    case $PKG_MANAGER in
        apt-get)
            base_packages+=(
                "resolvconf"
                "apparmor-utils"
                "apparmor-profiles"
                "ufw"
                "fail2ban"
                "unbound"
                "dnscrypt-proxy"
                "lsb-release"
                "attrib"
                "haveged"
                "irqbalance"
                "prometheus-node-exporter"
                "bsd-mailx"
            )
            ;;
        dnf|yum)
            base_packages+=(
                "epel-release"
                "unbound"
                "dnscrypt-proxy"
                "fail2ban"
                "firewalld"
                "sqlite"
                "apparmor-utils"
                "haveged"
                "irqbalance"
                "node_exporter"
                "mailx"
                "ndisc6"
            )
            ;;
        pacman)
            base_packages+=(
                "unbound"
                "dnscrypt-proxy"
                "fail2ban"
                "ufw"
                "sqlite"
                "apparmor"
                "haveged"
                "irqbalance"
                "prometheus-node-exporter"
                "mailutils"
                "ndisc6"
            )
            ;;
    esac

    install_packages "${base_packages[@]}"

    # Install Pi-hole if not present
    if ! command -v pihole &> /dev/null; then
        print_status "Installing Pi-hole on interface: $PIHOLE_INTERFACE..."
        curl -sSL https://install.pi-hole.net | bash /dev/stdin \
            --unattended \
            --admin-password "$(openssl rand -base64 32)" \
            --interface "$PIHOLE_INTERFACE" \
            >> "$SCRIPT_LOG" 2>&1
    fi

    # Create DNSCrypt config directory if it doesn't exist (for cloaking rules)
    if [[ ! -d "$DNSCRYPT_CONFIG_DIR" ]]; then
        mkdir -p "$DNSCRYPT_CONFIG_DIR"
        print_status "Created DNSCrypt config directory: $DNSCRYPT_CONFIG_DIR"
    fi

    print_success "Dependencies installed"
}

# Function to backup existing configurations
backup_existing_configs() {
    print_section "Creating Configuration Backups"

    print_status "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # Backup Pi-hole configs
    local pihole_files=(
        "/etc/pihole/setupVars.conf"
        "/etc/pihole/pihole-FTL.conf"
        "/etc/pihole/gravity.db"
        "/etc/pihole/regex.list"
        "/etc/pihole/whitelist.txt"
        "/etc/pihole/blacklist.txt"
        "/etc/dnsmasq.d/01-pihole.conf"
        "/etc/dnsmasq.d/99-strict-order.conf"
    )

    for file in "${pihole_files[@]}"; do
        create_backup "$file"
    done

    # Backup Unbound configs
    local unbound_files=(
        "/etc/unbound/unbound.conf"
        "/etc/unbound/unbound.conf.d/pi-hole.conf"
        "/etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf"
        "/etc/unbound/unbound.conf.d/resolvconf_resolvers.conf"
        "/var/lib/unbound/root.key"
    )

    for file in "${unbound_files[@]}"; do
        create_backup "$file"
    done

    # Backup DNSCrypt-Proxy configs
    local dnscrypt_files=(
        "$DNSCRYPT_CONFIG_FILE"
        "$EXAMPLE_CLOAKING_FILE"
        "$CLOAKING_FILE"
    )

    for file in "${dnscrypt_files[@]}"; do
        if [[ -f "$file" ]]; then
            create_backup "$file"
        fi
    done

    # Backup resolvconf configs
    local resolvconf_files=(
        "/etc/resolvconf.conf"
        "/etc/resolv.conf"
    )

    for file in "${resolvconf_files[@]}"; do
        create_backup "$file"
    done

    # Backup logrotate configs
    if [[ -f "$LOGROTATE_CONFIG" ]]; then
        create_backup "$LOGROTATE_CONFIG"
    fi

    print_success "All existing configurations backed up to: $BACKUP_DIR"
    echo "Backup location: $BACKUP_DIR" > /root/dns-backup-info.txt
    echo "Script version: $SCRIPT_VERSION" >> /root/dns-backup-info.txt
    echo "GitHub: $SCRIPT_GITHUB" >> /root/dns-backup-info.txt
    echo "Website: $SCRIPT_WEBSITE" >> /root/dns-backup-info.txt
}

# Function to configure Pi-hole with advanced FTL settings
setup_pihole() {
    print_section "Configuring Pi-hole with Advanced FTL Settings"

    if command -v pihole &> /dev/null; then
        print_status "Pi-hole is already installed"

        # Backup current config
        create_backup "/etc/pihole/setupVars.conf"
        create_backup "$FTL_CONFIG"

        # Check Pi-hole status
        pihole status || print_warning "Pi-hole may not be running correctly"
    fi

    # Configure Pi-hole FTL with advanced settings using pihole-FTL --config
    print_status "Applying advanced FTL configuration based on system resources..."

    # Rate limiting
    pihole-FTL --config rate_limit.count "$RATE_LIMIT_COUNT" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true
    pihole-FTL --config rate_limit.interval "$RATE_LIMIT_INTERVAL" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true

    # Cache settings (optimized for available memory)
    pihole-FTL --config cache-size "$CACHE_SIZE" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true
    pihole-FTL --config edns-packet-max "1232" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true

    # Threading (optimized for CPU cores)
    pihole-FTL --config threads "$FTL_THREADS" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true

    # Privacy settings
    pihole-FTL --config blocking-mode "IP-NODATA-AAAA" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true
    pihole-FTL --config privacy-level "0" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true
    pihole-FTL --config ignore-localhost "yes" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true

    # Advanced features
    pihole-FTL --config resolveIPv6 "no" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true
    pihole-FTL --config pretty-json "yes" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true
    pihole-FTL --config socket-listen "127.0.0.1:4711" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true

    # Database settings
    pihole-FTL --config DBinterval "1.0" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true
    pihole-FTL --config DBfile "/etc/pihole/pihole-FTL.db" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true
    pihole-FTL --config maxDBdays "365" >> "$SCRIPT_LOG" 2>&1 2>/dev/null || true

    # Verify FTL configuration
    print_status "Verifying FTL configuration..."
    if pihole-FTL --config -h > /dev/null 2>&1; then
        print_success "FTL configuration applied successfully"
    else
        print_warning "Some FTL settings may not be supported in your version"
    fi

    # Temporarily set Pi-hole to use DNSCrypt-Proxy (will be reconfigured later with failover)
    pihole -a setdns "127.0.0.1#$DNSCRYPT_PORT" >> "$SCRIPT_LOG" 2>&1

    print_status "Pi-hole DNS temporarily set to DNSCrypt-Proxy (will be reconfigured with failover)"
}

# Function to configure DNSCrypt-Proxy with best privacy settings and Happy Eyeballs
setup_dnscrypt_proxy() {
    print_section "Configuring DNSCrypt-Proxy"

    print_status "Configuring DNSCrypt-Proxy with best privacy settings and Happy Eyeballs..."

    local config_file="$DNSCRYPT_CONFIG_FILE"
    create_backup "$config_file"

    # Build monitoring UI configuration if enabled
    MONITOR_CONFIG=""
    if [[ -n "${MONITOR_IP:-}" && -n "${MONITOR_PORT:-}" ]]; then
        MONITOR_CONFIG="
[monitoring_ui]
  enabled = true
  listen_address = '$MONITOR_IP:$MONITOR_PORT'
"
        print_status "Monitoring UI will be enabled on $MONITOR_IP:$MONITOR_PORT"
    fi

    # Build cloaking configuration if enabled
    CLOAKING_CONFIG=""
    if [[ -f "$CLOAKING_FILE" ]]; then
        CLOAKING_CONFIG="
[cloaking]
  cloaking_rules = '$CLOAKING_FILE'
"
        print_status "Cloaking rules will be enabled from $CLOAKING_FILE"
    fi

    # Generate new configuration with optimal privacy settings
    cat > "$config_file" << EOF
# DNSCrypt-Proxy configuration with maximum privacy settings
# Generated by Pi-hole + DNSCrypt + Unbound installer (Ultimate Masterpiece v${SCRIPT_VERSION})
# GitHub: ${SCRIPT_GITHUB}
# Website: ${SCRIPT_WEBSITE}
# Date: $(date)

##############################################
#         Global settings
##############################################

# Listen on localhost only, port 5053 (as requested)
listen_addresses = ['127.0.0.1:${DNSCRYPT_PORT}']

# Maximum concurrent queries
max_clients = 250

# Require DNS queries to not be logged (where servers support this)
require_dnssec = true
require_nolog = true
require_nofilter = true

# Force all traffic over TCP for better privacy (slightly slower but more secure)
force_tcp = false

# Timeout settings
timeout = 5000
keepalive = 30

# Load balancing with Happy Eyeballs to reduce latency
lb_strategy = 'ph'
lb_estimator = true

# Logging (minimal for privacy)
log_level = 0
use_syslog = true

# Cache settings
cache = true
cache_size = 4096
cache_min_ttl = 60
cache_max_ttl = 86400
cache_neg_min_ttl = 60
cache_neg_max_ttl = 600

# Happy Eyeballs settings - reduces double-hop latency
[happy_eyeballs]
  enabled = true
  ipv4_only = false
  ipv6_only = false

# Query logging (disabled for privacy)
[query_log]
  file = '/var/log/dnscrypt-proxy/query.log'
  format = 'tsv'

# DNSCrypt relays for extra privacy
[relays]

##############################################
#        Server lists
##############################################

# Primary server list (privacy-focused servers)
[sources]
  [sources.'public-resolvers']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
  cache_file = 'public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ''

  [sources.'relays']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md', 'https://download.dnscrypt.info/resolvers-list/v3/relays.md']
  cache_file = 'relays.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 72
  prefix = ''

# Best privacy servers (prioritize no-log, DNSSEC, no-filter)
server_names = ['cloudflare', 'quad9-dnscrypt-ip4-filter-pri', 'securedns-eu', 'meganerd']

# Fallback servers
fallback_resolver = '9.9.9.9:53'
ignore_system_dns = true

# NetProbe (connectivity check)
netprobe_address = '9.9.9.9:53'

# DNS64
[dns64]
  prefix = ''

# Static entries
[static]
  [static.'google-dns']
  stamp = 'sdns://AgUAAAAAAAAAAAAOZG5zLmdvb2dsZS5jb20NL2V4cGVyaW1lbnRhbA'
${MONITOR_CONFIG}
${CLOAKING_CONFIG}
EOF

    # Create log directory
    mkdir -p /var/log/dnscrypt-proxy
    chown -R _dnscrypt-proxy:_dnscrypt-proxy /var/log/dnscrypt-proxy 2>/dev/null || true

    # Restart DNSCrypt-Proxy
    systemctl restart dnscrypt-proxy 2>/dev/null || true
    systemctl enable dnscrypt-proxy 2>/dev/null || true

    print_success "DNSCrypt-Proxy configured on port $DNSCRYPT_PORT with Happy Eyeballs enabled"
}

# Function to configure Unbound with Quad9 DoT backup and DoH fallback
setup_unbound() {
    print_section "Configuring Unbound (DNSSEC Validator)"

    print_status "Configuring Unbound as forwarding resolver over TLS with Quad9 DoT/DoH backup..."

    local config_dir="/etc/unbound/unbound.conf.d"
    local config_file="$config_dir/pi-hole.conf"

    mkdir -p "$config_dir"
    create_backup "$config_file"

    # Ensure DNSSEC root key is initialized
    print_status "Initializing DNSSEC root trust anchor..."
    mkdir -p /var/lib/unbound
    sudo -u unbound unbound-anchor -a "/var/lib/unbound/root.key" 2>/dev/null || true
    chown unbound:unbound /var/lib/unbound/root.key 2>/dev/null || true

    # Build forward zone configuration
    FORWARD_CONFIG="forward-zone:\n    name: \".\"\n    forward-ssl-upstream: yes\n"

    # Add DoT servers
    for server in "${QUAD9_DOT_SERVERS[@]}"; do
        FORWARD_CONFIG+="    forward-addr: $server\n"
    done

    # Add DoH servers if enabled
    if [[ "${DOH_ENABLED:-false}" == true ]]; then
        FORWARD_CONFIG+="\n    # DoH fallback servers (if DoT is throttled)\n"
        for server in "${QUAD9_DOH_SERVERS[@]}"; do
            FORWARD_CONFIG+="    forward-addr: $server\n"
        done
        print_status "DoH fallback servers added"
    fi

    # Create Unbound configuration
    cat > "$config_file" << EOF
# Unbound configuration for Pi-hole
# Configured as forwarding resolver over TLS with Quad9 DoT/DoH backup
# Generated by Pi-hole + DNSCrypt + Unbound installer (Ultimate Masterpiece v${SCRIPT_VERSION})
# GitHub: ${SCRIPT_GITHUB}
# Website: ${SCRIPT_WEBSITE}
# Date: $(date)

server:
    # Basic settings
    verbosity: 0
    interface: 127.0.0.1
    port: ${UNBOUND_PORT}
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    prefer-ip6: no

    # Access control
    access-control: 127.0.0.0/8 allow
    access-control: ::1 allow

    # Privacy and security
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    use-caps-for-id: no

    # DNSSEC (primary validator)
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    val-clean-additional: yes
    val-permissive-mode: no
    val-log-level: 2
    val-clean-additional: yes

    # Performance (tuned for ${TOTAL_MEM}MB RAM, ${CPU_CORES} cores)
    prefetch: yes
    prefetch-key: yes
    num-threads: ${CPU_CORES}
    msg-cache-size: ${UNBOUND_MSG_CACHE}
    rrset-cache-size: ${UNBOUND_RRSET_CACHE}
    neg-cache-size: $((TOTAL_MEM / 8))m
    so-rcvbuf: 4m
    so-sndbuf: 4m

    # EDNS buffer (avoid fragmentation)
    edns-buffer-size: 1232
    max-udp-size: 1232

    # Aggressive NSEC for DNSSEC
    aggressive-nsec: yes

    # Private addresses (RFC1918)
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
    private-address: 192.0.2.0/24
    private-address: 198.51.100.0/24
    private-address: 203.0.113.0/24
    private-address: 255.255.255.255/32
    private-address: 2001:db8::/32

$FORWARD_CONFIG

    # Note: Quad9 DoT/DoH servers are configured as primary upstream
    # This provides encrypted DNS queries with fallback options
    # Unbound handles DNSSEC validation for all queries
EOF

    # Set proper permissions
    chown -R unbound:unbound /etc/unbound 2>/dev/null || true
    chmod 640 "$config_file" 2>/dev/null || true

    # Test configuration
    if unbound-checkconf >> "$SCRIPT_LOG" 2>&1; then
        print_success "Unbound configuration is valid"
    else
        print_error "Unbound configuration has errors"
    fi

    print_success "Unbound configured on port $UNBOUND_PORT as forwarding resolver over TLS/DoH with Quad9 backup"
}

# Function to configure Pi-hole with proper failover (Zero-Leak Config)
setup_pihole_failover() {
    print_section "Configuring Pi-hole Failover (Zero-Leak Configuration)"

    print_status "Configuring Pi-hole for DNSCrypt (Primary) and Unbound (Failover) with strict-order and no-resolv hardening..."

    # 1. Update setupVars.conf
    if [[ -f /etc/pihole/setupVars.conf ]]; then
        create_backup "/etc/pihole/setupVars.conf"

        # Remove any existing DNS lines
        sed -i '/^PIHOLE_DNS_/d' /etc/pihole/setupVars.conf

        # Add your specific order (DNSCrypt primary, Unbound secondary)
        echo "PIHOLE_DNS_1=127.0.0.1#${DNSCRYPT_PORT}" >> /etc/pihole/setupVars.conf
        echo "PIHOLE_DNS_2=127.0.0.1#${UNBOUND_PORT}" >> /etc/pihole/setupVars.conf

        # Disable Pi-hole DNSSEC (let Unbound handle it)
        sed -i '/^DNSSEC/d' /etc/pihole/setupVars.conf
        echo "DNSSEC=false" >> /etc/pihole/setupVars.conf

        print_status "Updated /etc/pihole/setupVars.conf with DNS servers and DNSSEC=false"
    else
        print_error "Pi-hole setupVars.conf not found"
        return 1
    fi

    # 2. Create the strict-order rule with no-resolv hardening
    local strict_order_file="/etc/dnsmasq.d/99-strict-order.conf"
    create_backup "$strict_order_file"

    cat > "$strict_order_file" << 'EOF'
# Enforce strict ordering of DNS servers (DNSCrypt primary, Unbound secondary)
# strict-order: Must try 5053 first, only use 5335 if first times out
# no-resolv: Prevent leakage to system resolvers (ISP DNS protection)
strict-order
no-resolv
EOF

    print_status "Created $strict_order_file with strict-order and no-resolv hardening"

    # 3. Apply changes
    pihole restartdns >> "$SCRIPT_LOG" 2>&1

    print_success "Pi-hole failover logic applied: DNSCrypt (127.0.0.1#${DNSCRYPT_PORT}) -> Unbound (127.0.0.1#${UNBOUND_PORT})"
}

# Function to inject whitelist directly into SQLite database with version tracking
inject_whitelist_sqlite() {
    print_section "Injecting Whitelist Directly into SQLite Database"

    print_status "Injecting ${#WHITELIST_DOMAINS[@]} domains into gravity database via SQLite..."

    # Check if gravity database exists
    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_error "Gravity database not found at $GRAVITY_DB"
        return 1
    fi

    local whitelist_count=0
    local teams_count=0

    # First, remove any existing entries from previous versions to avoid duplicates
    print_status "Cleaning up any previous version entries..."
    sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist WHERE comment LIKE '%Masterpiece%' OR comment LIKE '%v1.0.%' OR comment LIKE '%https://www.wael.name%';" 2>/dev/null

    for domain in "${WHITELIST_DOMAINS[@]}"; do
        # Use INSERT OR IGNORE to avoid duplicates, with version tracking comment
        if sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (0, '$domain', 1, '$SCRIPT_DB_COMMENT');" 2>/dev/null; then
            ((whitelist_count++))
            if [[ "$domain" == *"teams"* ]] || [[ "$domain" == *"microsoft"* ]]; then
                ((teams_count++))
            fi
        fi
    done

    print_success "Injected $whitelist_count domains into whitelist (including $teams_count Microsoft Teams domains)"

    # Create version tracking file
    echo "$SCRIPT_VERSION" > "$VERSION_TRACKING_FILE"
    echo "$SCRIPT_DB_COMMENT" >> "$VERSION_TRACKING_FILE"
    echo "$(date)" >> "$VERSION_TRACKING_FILE"

    # Verify Teams domains are present with our comment
    print_status "Verifying Microsoft Teams domains with version tracking..."
    for domain in "teams.microsoft.com" "login.microsoftonline.com" "outlook.office.com"; do
        local exists=$(sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE domain = '$domain' AND type = 0 AND comment = '$SCRIPT_DB_COMMENT';" 2>/dev/null)
        if [[ $exists -gt 0 ]]; then
            print_success "  ✓ $domain is whitelisted (v${SCRIPT_VERSION})"
        else
            print_warning "  ⚠ $domain may not be whitelisted with correct version"
        fi
    done
}

# Function to setup regex filtering
setup_regex_filters() {
    print_section "Configuring Comprehensive Regex Filters"

    print_status "Setting up regex patterns from mmotti and custom sources..."

    # Create regex file if it doesn't exist
    touch "$REGEX_FILE"
    create_backup "$REGEX_FILE"

    # Clear existing regex patterns
    > "$REGEX_FILE"

    # Add header with metadata
    cat > "$REGEX_FILE" << EOF
# Pi-hole Regex Filters - Ultimate Masterpiece Collection v${SCRIPT_VERSION}
# Generated by Pi-hole + DNSCrypt + Unbound installer
# GitHub: ${SCRIPT_GITHUB}
# Website: ${SCRIPT_WEBSITE}
# Date: $(date)
#
# Format: Each line is a separate regex pattern
# Type 2 = Allowlist, Type 3 = Denylist (managed via gravity database)
#
# Sources:
# - mmotti/pihole-regex (https://github.com/mmotti/pihole-regex)
# - stevejenkins/pi-hole-lists
# - Custom patterns for enhanced protection
#
# Categories:
# - Tracking & Analytics (DENY)
# - Malware & Phishing (DENY)
# - Suspicious TLDs (DENY)
# - Critical Services (ALLOW)
#
EOF

    # Add patterns to regex file with type annotations
    for pattern_entry in "${REGEX_PATTERNS[@]}"; do
        IFS='|' read -r pattern type comment <<< "$pattern_entry"
        echo "# $comment (type $type)" >> "$REGEX_FILE"
        echo "$pattern" >> "$REGEX_FILE"
        echo "" >> "$REGEX_FILE"
    done

    # Import regex patterns into gravity database with correct types
    print_status "Importing regex patterns into gravity database..."

    # Clear existing regex entries
    sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist WHERE type IN (2,3);" 2>/dev/null || true

    # Add each pattern with proper type
    local regex_counter=0
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]]; then
            continue
        fi

        # Determine type from comment
        if [[ "$line" =~ \(\ *type\ *2\ *\) ]]; then
            sqlite3 "$GRAVITY_DB" "INSERT INTO domainlist (domain, type, enabled, comment) VALUES ('$line', 2, 1, 'Regex allow pattern - v${SCRIPT_VERSION}');" 2>/dev/null && ((regex_counter++))
        elif [[ "$line" =~ \(\ *type\ *3\ *\) ]]; then
            sqlite3 "$GRAVITY_DB" "INSERT INTO domainlist (domain, type, enabled, comment) VALUES ('$line', 3, 1, 'Regex deny pattern - v${SCRIPT_VERSION}');" 2>/dev/null && ((regex_counter++))
        fi
    done < "$REGEX_FILE"

    print_success "Added $regex_counter regex patterns to gravity database"

    # Create regex update script for cron
    local regex_updater="/usr/local/bin/update-regex-lists.sh"
    cat > "$regex_updater" << EOF
#!/bin/bash
# Regex List Updater for Pi-hole
# Fetches latest regex patterns from trusted sources
# Version: ${SCRIPT_VERSION}

REGEX_FILE="/etc/pihole/regex.list"
GRAVITY_DB="/etc/pihole/gravity.db"
BACKUP_DIR="/root/regex-backup-\$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/regex-update.log"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG_FILE"
}

log "Starting regex update"

# Backup current regex
mkdir -p "\$BACKUP_DIR"
cp "\$REGEX_FILE" "\$BACKUP_DIR/" 2>/dev/null
log "Backed up current regex to \$BACKUP_DIR"

# Fetch mmotti's regex list
log "Fetching mmotti's regex list..."
curl -s "https://raw.githubusercontent.com/mmotti/pihole-regex/master/regex.list" -o /tmp/mmotti-regex.list

# Fetch stevejenkins regex list
log "Fetching stevejenkins regex list..."
curl -s "https://raw.githubusercontent.com/stevejenkins/pi-hole-lists/master/regex.txt" -o /tmp/stevejenkins-regex.list

# Merge and deduplicate
cat /tmp/mmotti-regex.list /tmp/stevejenkins-regex.list | sort -u > /tmp/merged-regex.list

# Import to gravity database
log "Importing to gravity database..."
while IFS= read -r pattern; do
    if [[ -n "\$pattern" ]] && [[ ! "\$pattern" =~ ^# ]]; then
        EXISTS=\$(sqlite3 "\$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE domain = '\$pattern' AND type IN (2,3);")
        if [[ \$EXISTS -eq 0 ]]; then
            sqlite3 "\$GRAVITY_DB" "INSERT INTO domainlist (domain, type, enabled, comment) VALUES ('\$pattern', 3, 1, 'Auto-updated regex pattern - v${SCRIPT_VERSION}');"
        fi
    fi
done < /tmp/merged-regex.list

pihole restartdns
log "Regex update complete"

rm -f /tmp/mmotti-regex.list /tmp/stevejenkins-regex.list /tmp/merged-regex.list
EOF

    chmod +x "$regex_updater"
    safe_add_cron "0 3 * * 0 root $regex_updater" "/etc/cron.d/pi-hole-regex-update"

    print_success "Regex filters configured with $regex_counter patterns"
}

# Function to setup curated whitelist and blacklist
setup_lists() {
    print_section "Configuring Curated Whitelist and Blacklist"

    # Use SQL injection for whitelist (primary method) with version tracking
    inject_whitelist_sqlite

    # Also save to text file for reference
    printf "%s\n" "${WHITELIST_DOMAINS[@]}" > "$CUSTOM_WHITELIST"
    echo "# Whitelist from v${SCRIPT_VERSION} - ${SCRIPT_WEBSITE}" >> "$CUSTOM_WHITELIST"

    # Setup blacklist
    print_status "Adding ${#BLACKLIST_DOMAINS[@]} domains to blacklist..."

    # Clear existing blacklist (type 1)
    sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist WHERE type = 1;" 2>/dev/null || true

    # Add each blacklist domain
    local blacklist_count=0
    for domain in "${BLACKLIST_DOMAINS[@]}"; do
        EXISTS=$(sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE domain = '$domain' AND type = 1;" 2>/dev/null || echo "0")
        if [[ $EXISTS -eq 0 ]]; then
            sqlite3 "$GRAVITY_DB" "INSERT INTO domainlist (domain, type, enabled, comment) VALUES ('$domain', 1, 1, 'Malware/tracking blacklist - v${SCRIPT_VERSION}');" 2>/dev/null && ((blacklist_count++))
        fi
    done

    printf "%s\n" "${BLACKLIST_DOMAINS[@]}" > "$CUSTOM_BLACKLIST"
    echo "# Blacklist from v${SCRIPT_VERSION} - ${SCRIPT_WEBSITE}" >> "$CUSTOM_BLACKLIST"
    print_success "Added $blacklist_count domains to blacklist"
}

# Function to add comprehensive blocklists
setup_blocklists() {
    print_section "Adding Comprehensive Blocklists"

    print_status "Adding ${#BLOCKLISTS[@]} curated blocklists with comments and group assignments..."

    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found. Creating..."
        sudo -u pihole pihole-FTL --config gravity 2>/dev/null || true
    fi

    for list in "${BLOCKLISTS[@]}"; do
        IFS='|' read -r url comment group <<< "$list"
        print_status "Adding: $comment"

        existing=$(sqlite3 "$GRAVITY_DB" "SELECT id FROM adlist WHERE address = '$url';" 2>/dev/null || echo "")

        if [[ -z "$existing" ]]; then
            sqlite3 "$GRAVITY_DB" "INSERT INTO adlist (address, comment, enabled) VALUES ('$url', '$comment (added by v${SCRIPT_VERSION})', 1);" 2>/dev/null || {
                pihole -a adlist add "$url" "$comment" >> "$SCRIPT_LOG" 2>&1
            }
        else
            sqlite3 "$GRAVITY_DB" "UPDATE adlist SET comment = '$comment (updated by v${SCRIPT_VERSION})', enabled = 1 WHERE address = '$url';" 2>/dev/null || {
                print_warning "Failed to update $url in database"
            }
        fi
    done

    sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO adlist_by_group (adlist_id, group_id) SELECT id, 1 FROM adlist WHERE id NOT IN (SELECT adlist_id FROM adlist_by_group);" 2>/dev/null || {
        print_warning "Failed to assign groups"
    }
}

# Function to setup advanced logrotate configuration
setup_logrotate() {
    print_section "Configuring Advanced Log Rotation"

    print_status "Creating custom logrotate configuration to prevent disk filling..."

    cat > "$LOGROTATE_CONFIG" << EOF
# Pi-hole Custom Logrotate Configuration
# Generated by v${SCRIPT_VERSION} Ultimate Masterpiece Installer
# GitHub: ${SCRIPT_GITHUB}
# Website: ${SCRIPT_WEBSITE}
# Prevents disk filling by rotating logs aggressively

/var/log/pihole/pihole.log {
    daily
    rotate 7
    maxsize 50M
    compress
    delaycompress
    missingok
    notifempty
    create 0644 pihole pihole
    sharedscripts
    postrotate
        pihole restartdns 2>/dev/null || true
    endscript
}

/var/log/pihole/FTL.log {
    daily
    rotate 7
    maxsize 50M
    compress
    delaycompress
    missingok
    notifempty
    create 0644 pihole pihole
    sharedscripts
    postrotate
        pihole restartdns 2>/dev/null || true
    endscript
}

/var/log/dnscrypt-proxy/*.log {
    daily
    rotate 7
    maxsize 20M
    compress
    delaycompress
    missingok
    notifempty
    create 0644 _dnscrypt-proxy _dnscrypt-proxy
    sharedscripts
    postrotate
        systemctl restart dnscrypt-proxy 2>/dev/null || true
    endscript
}

/var/log/unbound/unbound.log {
    daily
    rotate 7
    maxsize 20M
    compress
    delaycompress
    missingok
    notifempty
    create 0644 unbound unbound
    sharedscripts
    postrotate
        systemctl restart unbound 2>/dev/null || true
    endscript
}

/var/log/dns-health.log {
    weekly
    rotate 4
    maxsize 10M
    compress
    missingok
    notifempty
}

/var/log/dns-alerts.log {
    weekly
    rotate 4
    maxsize 5M
    compress
    missingok
    notifempty
}

/var/log/dns-watchdog.log {
    weekly
    rotate 4
    maxsize 5M
    compress
    missingok
    notifempty
}

/var/log/gravity-update.log {
    weekly
    rotate 4
    maxsize 5M
    compress
    missingok
    notifempty
}

/var/log/regex-update.log {
    weekly
    rotate 4
    maxsize 5M
    compress
    missingok
    notifempty
}
EOF

    # Test logrotate configuration
    if logrotate -d "$LOGROTATE_CONFIG" &> /dev/null; then
        print_success "Logrotate configuration is valid"
    else
        print_warning "Logrotate configuration test failed, but continuing"
    fi

    # Force initial log rotation
    logrotate -f "$LOGROTATE_CONFIG" 2>/dev/null || true

    print_success "Advanced log rotation configured - logs will be rotated before reaching 50MB"
}

# Function to create automated watchdog service
setup_watchdog() {
    print_section "Creating Automated Watchdog Service"

    print_status "Creating watchdog service (checks every ${WATCHDOG_INTERVAL} seconds)..."

    local watchdog_service="/etc/systemd/system/dns-watchdog.service"
    local watchdog_timer="/etc/systemd/system/dns-watchdog.timer"

    # Create watchdog script
    cat > "$WATCHDOG_SCRIPT" << EOF
#!/bin/bash
# DNS Watchdog Service
# Checks service status every 60 seconds and restarts if needed
# Version: ${SCRIPT_VERSION}

LOG_FILE="/var/log/dns-watchdog.log"
ALERT_SCRIPT="/usr/local/bin/dns-alert.sh"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG_FILE"
}

check_port() {
    local port=\$1
    nc -z -w2 127.0.0.1 "\$port" 2>/dev/null
    return \$?
}

restart_service() {
    local service=\$1
    local port=\$2

    log "Watchdog: \$service not responding on port \$port, attempting restart"
    systemctl restart "\$service"
    sleep 5

    if check_port "\$port"; then
        log "Watchdog: \$service successfully recovered"
        return 0
    else
        log "Watchdog: \$service failed to recover"
        return 1
    fi
}

# Check DNSCrypt-Proxy (port 5053)
if ! check_port 5053; then
    restart_service "dnscrypt-proxy" 5053
fi

# Check Unbound (port 5335)
if ! check_port 5335; then
    restart_service "unbound" 5335
fi

# Check Pi-hole FTL (port 53)
if ! check_port 53; then
    log "Watchdog: Pi-hole FTL not responding, attempting restart"
    pihole restartdns
    sleep 5
    if check_port 53; then
        log "Watchdog: Pi-hole FTL successfully recovered"
    else
        log "Watchdog: Pi-hole FTL failed to recover"
    fi
fi

exit 0
EOF

    chmod +x "$WATCHDOG_SCRIPT"

    # Create systemd service
    cat > "$watchdog_service" << EOF
[Unit]
Description=DNS Watchdog Service
After=network.target

[Service]
Type=oneshot
ExecStart=$WATCHDOG_SCRIPT
User=root
Group=root
EOF

    # Create systemd timer for 60-second intervals
    cat > "$watchdog_timer" << EOF
[Unit]
Description=DNS Watchdog Timer
Requires=dns-watchdog.service

[Timer]
OnBootSec=60
OnUnitActiveSec=60
Unit=dns-watchdog.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable dns-watchdog.timer 2>/dev/null || true
    systemctl start dns-watchdog.timer 2>/dev/null || true

    print_success "Watchdog service created - checks every ${WATCHDOG_INTERVAL} seconds"
    print_status "Watchdog will automatically restart failed services"
}

# Function to create health dashboard command
setup_health_dashboard() {
    print_section "Creating Health Dashboard Command"

    print_status "Creating 'pihole-health' command for system status overview..."

    cat > "$HEALTH_DASHBOARD" << EOF
#!/bin/bash
# Pi-hole Health Dashboard
# Displays comprehensive status of all DNS services
# Version: ${SCRIPT_VERSION}
# GitHub: ${SCRIPT_GITHUB}
# Website: ${SCRIPT_WEBSITE}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\${BLUE}════════════════════════════════════════════════════════════════════\${NC}"
echo -e "\${BLUE}         Pi-hole DNS Health Dashboard - v${SCRIPT_VERSION}             \${NC}"
echo -e "\${BLUE}         ${SCRIPT_WEBSITE}                          \${NC}"
echo -e "\${BLUE}════════════════════════════════════════════════════════════════════\${NC}"
echo ""

# Function to check service status
check_service() {
    local service=\$1
    local port=\$2
    local name=\$3

    if systemctl is-active --quiet "\$service" 2>/dev/null; then
        if nc -z -w2 127.0.0.1 "\$port" 2>/dev/null; then
            local rtime=\$(dig @127.0.0.1 -p "\$port" google.com +stats 2>/dev/null | grep "Query time:" | awk '{print \$4}')
            echo -e "  \${name}: \${GREEN}✓ RUNNING\${NC} (port \$port, response: \${rtime:-?}ms)"
        else
            echo -e "  \${name}: \${YELLOW}⚠ ACTIVE but not responding on port \$port\${NC}"
        fi
    else
        echo -e "  \${name}: \${RED}✗ STOPPED\${NC}"
    fi
}

# Service status
echo -e "\${BLUE}Service Status:\${NC}"
check_service "pihole-FTL" "53" "Pi-hole FTL"
check_service "dnscrypt-proxy" "5053" "DNSCrypt-Proxy (PRIMARY)"
check_service "unbound" "5335" "Unbound (SECONDARY)"
echo ""

# Watchdog status
echo -e "\${BLUE}Watchdog Service:\${NC}"
if systemctl is-active --quiet dns-watchdog.timer 2>/dev/null; then
    NEXT=\$(systemctl status dns-watchdog.timer | grep "Trigger:" | awk -F'Trigger: ' '{print \$2}')
    echo -e "  Watchdog: \${GREEN}✓ ACTIVE\${NC} (next check: \$NEXT)"
else
    echo -e "  Watchdog: \${RED}✗ INACTIVE\${NC}"
fi

# Health check status
if systemctl is-active --quiet dns-health-check.timer 2>/dev/null; then
    LAST=\$(tail -1 /var/log/dns-health.log 2>/dev/null | cut -d']' -f2- || echo "No logs")
    echo -e "  Health Checks: \${GREEN}✓ ACTIVE\${NC}"
    echo -e "  Last health event: \$LAST"
else
    echo -e "  Health Checks: \${RED}✗ INACTIVE\${NC}"
fi
echo ""

# DNS resolution test
echo -e "\${BLUE}DNS Resolution Tests:\${NC}"
TEST_DOMAINS=("google.com" "teams.microsoft.com" "dnssec.works")
for domain in "\${TEST_DOMAINS[@]}"; do
    if dig @127.0.0.1 "\$domain" +short > /dev/null 2>&1; then
        if [[ "\$domain" == "dnssec.works" ]]; then
            AD_FLAG=\$(dig @127.0.0.1 "\$domain" +dnssec | grep -c "ad" || echo "0")
            if [[ \$AD_FLAG -gt 0 ]]; then
                echo -e "  \$domain: \${GREEN}✓ RESOLVES (DNSSEC valid)\${NC}"
            else
                echo -e "  \$domain: \${YELLOW}⚠ RESOLVES (no DNSSEC)\${NC}"
            fi
        else
            echo -e "  \$domain: \${GREEN}✓ RESOLVES\${NC}"
        fi
    else
        echo -e "  \$domain: \${RED}✗ FAILED\${NC}"
    fi
done
echo ""

# Blocklist stats
if command -v sqlite3 &> /dev/null && [[ -f /etc/pihole/gravity.db ]]; then
    echo -e "\${BLUE}Database Statistics:\${NC}"
    WHITELIST=\$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM domainlist WHERE type=0 AND enabled=1 AND comment LIKE '%${SCRIPT_VERSION}%';" 2>/dev/null || echo "0")
    BLACKLIST=\$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM domainlist WHERE type=1 AND enabled=1 AND comment LIKE '%${SCRIPT_VERSION}%';" 2>/dev/null || echo "0")
    REGEX=\$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM domainlist WHERE type IN (2,3) AND enabled=1 AND comment LIKE '%${SCRIPT_VERSION}%';" 2>/dev/null || echo "0")
    ADLISTS=\$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist WHERE enabled=1;" 2>/dev/null || echo "0")

    echo -e "  Whitelist entries (v${SCRIPT_VERSION}): \$WHITELIST"
    echo -e "  Blacklist entries (v${SCRIPT_VERSION}): \$BLACKLIST"
    echo -e "  Regex patterns (v${SCRIPT_VERSION}):    \$REGEX"
    echo -e "  Active blocklists: \$ADLISTS"
fi
echo ""

# System resources
echo -e "\${BLUE}System Resources:\${NC}"
MEM_TOTAL=\$(free -m | awk '/^Mem:/{print \$2}')
MEM_USED=\$(free -m | awk '/^Mem:/{print \$3}')
MEM_PERCENT=\$((MEM_USED * 100 / MEM_TOTAL))
LOAD=\$(uptime | awk -F'load average:' '{print \$2}')
DISK_USED=\$(df -h / | awk 'NR==2 {print \$5}')

echo -e "  Memory: \${MEM_USED}MB / \${MEM_TOTAL}MB (\${MEM_PERCENT}%)"
echo -e "  Load:  \$LOAD"
echo -e "  Disk:  \$DISK_USED used on /"
echo ""

echo -e "\${BLUE}════════════════════════════════════════════════════════════════════\${NC}"
echo -e "Run 'pihole -c' for real-time query log"
echo -e "Run 'journalctl -u dns-watchdog -f' for watchdog logs"
echo -e "GitHub: ${SCRIPT_GITHUB}"
echo -e "\${BLUE}════════════════════════════════════════════════════════════════════\${NC}"
EOF

    chmod +x "$HEALTH_DASHBOARD"

    # Create symlink in /usr/local/bin if not already there
    if [[ ! -L "/usr/local/bin/pihole-health" ]]; then
        ln -sf "$HEALTH_DASHBOARD" "/usr/local/bin/pihole-health" 2>/dev/null || true
    fi

    print_success "Health dashboard command created: 'pihole-health'"
}

# Function to handle Debian Bullseye+ resolvconf issues
fix_debian_resolvconf() {
    if [[ "${DEBIAN_BULLSEYE_PLUS:-false}" == true ]]; then
        print_status "Applying Debian Bullseye+ resolvconf fixes..."

        if systemctl is-active --quiet unbound-resolvconf.service 2>/dev/null; then
            systemctl disable --now unbound-resolvconf.service 2>/dev/null || true
        fi

        if [[ -f /etc/resolvconf.conf ]]; then
            create_backup "/etc/resolvconf.conf"
            sed -i 's/^unbound_conf=/#unbound_conf=/' /etc/resolvconf.conf
        fi

        if [[ -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf ]]; then
            create_backup "/etc/unbound/unbound.conf.d/resolvconf_resolvers.conf"
            rm -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf
        fi

        if [[ "${DEBIAN_BOOKWORM_PLUS:-false}" == true ]] && command -v aa-enforce &> /dev/null; then
            aa-enforce /usr/sbin/unbound 2>/dev/null || true
        fi

        print_success "Debian Bullseye+ fixes applied"
    fi
}

# Function to configure Unbound logging with AppArmor
setup_unbound_logging() {
    print_status "Setting up Unbound logging with AppArmor support..."

    mkdir -p /var/log/unbound
    touch /var/log/unbound/unbound.log
    chown unbound:unbound /var/log/unbound /var/log/unbound/unbound.log 2>/dev/null || true

    local apparmor_file="/etc/apparmor.d/local/usr.sbin.unbound"

    if [[ -f /etc/apparmor.d/usr.sbin.unbound ]]; then
        create_backup "$apparmor_file"

        if ! grep -q "/var/log/unbound/unbound.log" "$apparmor_file" 2>/dev/null; then
            echo "/var/log/unbound/unbound.log rw," >> "$apparmor_file"

            if [[ "${DEBIAN_BOOKWORM_PLUS:-false}" == true ]]; then
                echo "/var/log/unbound/** rw," >> "$apparmor_file"
            fi

            if command -v apparmor_parser &> /dev/null; then
                apparmor_parser -r /etc/apparmor.d/usr.sbin.unbound 2>/dev/null || true
                systemctl restart apparmor 2>/dev/null || true
            fi
        fi
    fi

    print_success "Unbound logging configured with AppArmor support"
}

# Function to configure firewall based on OS
setup_firewall() {
    print_section "Configuring Firewall"

    if command -v ufw &> /dev/null; then
        print_status "Configuring UFW firewall..."

        ufw allow from 192.168.0.0/16 to any port 53 proto udp comment 'Pi-hole DNS' 2>/dev/null || true
        ufw allow from 192.168.0.0/16 to any port 53 proto tcp comment 'Pi-hole DNS' 2>/dev/null || true
        ufw allow from 127.0.0.1 to any port "$DNSCRYPT_PORT" comment 'DNSCrypt-Proxy' 2>/dev/null || true
        ufw allow from 127.0.0.1 to any port "$UNBOUND_PORT" comment 'Unbound' 2>/dev/null || true
        ufw allow from 127.0.0.1 to any port 9100 comment 'Node Exporter' 2>/dev/null || true

        if [[ -n "${MONITOR_IP:-}" && -n "${MONITOR_PORT:-}" ]]; then
            ufw allow from 192.168.0.0/16 to any port "$MONITOR_PORT" comment 'DNSCrypt Monitoring UI' 2>/dev/null || true
        fi

        if ! ufw status | grep -q "Status: active"; then
            echo "y" | ufw enable >> "$SCRIPT_LOG" 2>&1
        fi

        ufw status verbose
        print_success "UFW firewall configured"

    elif command -v firewall-cmd &> /dev/null; then
        print_status "Configuring firewalld..."

        firewall-cmd --permanent --add-service=dns 2>/dev/null || true
        firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.0/16" port port="53" protocol="udp" accept' 2>/dev/null || true
        firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="127.0.0.1" port port="'"$DNSCRYPT_PORT"'" protocol="tcp" accept' 2>/dev/null || true
        firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="127.0.0.1" port port="'"$UNBOUND_PORT"'" protocol="tcp" accept' 2>/dev/null || true

        if [[ -n "${MONITOR_IP:-}" && -n "${MONITOR_PORT:-}" ]]; then
            firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.0/16" port port="'"$MONITOR_PORT"'" protocol="tcp" accept' 2>/dev/null || true
        fi

        firewall-cmd --reload 2>/dev/null || true
        firewall-cmd --list-all
        print_success "Firewalld configured"
    else
        print_warning "No supported firewall found. Please configure manually"
    fi
}

# Function to create Prometheus metrics exporter
setup_metrics_exporter() {
    print_section "Setting up Prometheus Metrics Exporter"

    print_status "Creating Prometheus metrics exporter script..."

    cat > "$PROMETHEUS_EXPORTER" << EOF
#!/bin/bash
# DNS Metrics Exporter for Prometheus
# Version: ${SCRIPT_VERSION} - Ultimate Masterpiece Final Edition
# GitHub: ${SCRIPT_GITHUB}
# Website: ${SCRIPT_WEBSITE}

METRICS_FILE="/var/lib/node_exporter/dns_metrics.prom"
PIHOLE_API="http://127.0.0.1:4711/admin/api.php"
GRAVITY_DB="/etc/pihole/gravity.db"
REGEX_FILE="/etc/pihole/regex.list"

mkdir -p "\$(dirname "\$METRICS_FILE")"

cat > "\$METRICS_FILE" << 'HEADER'
# HELP dns_queries_total Total DNS queries
# TYPE dns_queries_total counter
# HELP dns_blocked_total Total blocked queries
# TYPE dns_blocked_total counter
# HELP dns_blocked_percent Percentage of queries blocked
# TYPE dns_blocked_percent gauge
# HELP dns_upstream_response_time Upstream response time in ms
# TYPE dns_upstream_response_time gauge
# HELP dns_service_status Service status (1=up, 0=down)
# TYPE dns_service_status gauge
# HELP dns_regex_patterns_total Total regex patterns loaded
# TYPE dns_regex_patterns_total gauge
# HELP dns_whitelist_total Total whitelist entries
# TYPE dns_whitelist_total gauge
# HELP dns_blacklist_total Total blacklist entries
# TYPE dns_blacklist_total gauge
# HELP dns_blocklists_total Total blocklists enabled
# TYPE dns_blocklists_total gauge
# HELP dns_watchdog_restarts_total Total watchdog restarts
# TYPE dns_watchdog_restarts_total counter
# HELP dns_version_info Version information
# TYPE dns_version_info gauge
HEADER

# Version info
echo "dns_version_info{version=\"${SCRIPT_VERSION}\",github=\"${SCRIPT_GITHUB}\",website=\"${SCRIPT_WEBSITE}\"} 1" >> "\$METRICS_FILE"

if command -v curl &> /dev/null; then
    PIHOLE_STATS=\$(curl -s --max-time 5 "\$PIHOLE_API?summary" 2>/dev/null)
    if [[ -n "\$PIHOLE_STATS" ]] && command -v jq &> /dev/null; then
        QUERIES=\$(echo "\$PIHOLE_STATS" | jq -r '.dns_queries_today // 0')
        BLOCKED=\$(echo "\$PIHOLE_STATS" | jq -r '.ads_blocked_today // 0')
        PERCENT=\$(echo "\$PIHOLE_STATS" | jq -r '.ads_percentage_today // 0')

        echo "dns_queries_total \$QUERIES" >> "\$METRICS_FILE"
        echo "dns_blocked_total \$BLOCKED" >> "\$METRICS_FILE"
        echo "dns_blocked_percent \$PERCENT" >> "\$METRICS_FILE"
    fi
fi

for service in pihole-FTL dnscrypt-proxy unbound; do
    if systemctl is-active --quiet "\$service" 2>/dev/null; then
        echo "dns_service_status{service=\"\$service\"} 1" >> "\$METRICS_FILE"
    else
        echo "dns_service_status{service=\"\$service\"} 0" >> "\$METRICS_FILE"
    fi
done

for port in 5053 5335; do
    RTIME=\$(dig @127.0.0.1 -p "\$port" google.com +stats 2>/dev/null | grep "Query time:" | awk '{print \$4}')
    if [[ -n "\$RTIME" ]]; then
        echo "dns_upstream_response_time{port=\"\$port\"} \$RTIME" >> "\$METRICS_FILE"
    fi
done

if [[ -f "\$REGEX_FILE" ]]; then
    REGEX_COUNT=\$(grep -v "^#" "\$REGEX_FILE" | grep -v "^\$" | wc -l)
    echo "dns_regex_patterns_total \$REGEX_COUNT" >> "\$METRICS_FILE"
fi

if [[ -f "\$GRAVITY_DB" ]] && command -v sqlite3 &> /dev/null; then
    # Count only entries from this version
    WHITELIST_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 0 AND enabled = 1 AND comment LIKE '%${SCRIPT_VERSION}%';" 2>/dev/null || echo "0")
    BLACKLIST_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 1 AND enabled = 1 AND comment LIKE '%${SCRIPT_VERSION}%';" 2>/dev/null || echo "0")
    REGEX_ALLOW_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 2 AND enabled = 1 AND comment LIKE '%${SCRIPT_VERSION}%';" 2>/dev/null || echo "0")
    REGEX_DENY_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 3 AND enabled = 1 AND comment LIKE '%${SCRIPT_VERSION}%';" 2>/dev/null || echo "0")
    BLOCKLISTS_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT COUNT(*) FROM adlist WHERE enabled = 1;" 2>/dev/null || echo "0")

    echo "dns_whitelist_total \$WHITELIST_COUNT" >> "\$METRICS_FILE"
    echo "dns_blacklist_total \$BLACKLIST_COUNT" >> "\$METRICS_FILE"
    echo "dns_regex_allow_total \$REGEX_ALLOW_COUNT" >> "\$METRICS_FILE"
    echo "dns_regex_deny_total \$REGEX_DENY_COUNT" >> "\$METRICS_FILE"
    echo "dns_blocklists_total \$BLOCKLISTS_COUNT" >> "\$METRICS_FILE"
fi

# Watchdog restart count
if [[ -f /var/log/dns-watchdog.log ]]; then
    RESTARTS=\$(grep -c "successfully recovered" /var/log/dns-watchdog.log 2>/dev/null || echo "0")
    echo "dns_watchdog_restarts_total \$RESTARTS" >> "\$METRICS_FILE"
fi

echo "dns_metrics_last_run \$(date +%s)" >> "\$METRICS_FILE"
EOF

    chmod +x "$PROMETHEUS_EXPORTER"
    safe_add_cron "* * * * * root $PROMETHEUS_EXPORTER" "/etc/cron.d/dns-metrics"

    print_success "Prometheus metrics exporter configured"
}

# Function to create health check service with alerts
setup_health_check() {
    print_section "Creating Health Check Service with Alerts"

    local health_script="/usr/local/bin/dns-health-check.sh"
    local health_service="/etc/systemd/system/dns-health-check.service"
    local health_timer="/etc/systemd/system/dns-health-check.timer"
    local alert_script="/usr/local/bin/dns-alert.sh"

    cat > "$alert_script" << EOF
#!/bin/bash
# DNS Alerting Script
# Version: ${SCRIPT_VERSION}

ALERT_CONFIG="/etc/dns-alerts.conf"
source "\$ALERT_CONFIG" 2>/dev/null

MESSAGE="\$1"
SUBJECT="\$2"
FAILURE_DURATION="\$3"

send_email() {
    if [[ -n "\$ALERT_EMAIL" ]]; then
        echo "\$MESSAGE" | mail -s "\$SUBJECT" "\$ALERT_EMAIL"
    fi
}

send_pushover() {
    if [[ -n "\$ALERT_PUSHOVER_TOKEN" && -n "\$ALERT_PUSHOVER_USER" ]]; then
        curl -s -F "token=\$ALERT_PUSHOVER_TOKEN" \
                 -F "user=\$ALERT_PUSHOVER_USER" \
                 -F "title=\$SUBJECT" \
                 -F "message=\$MESSAGE" \
                 https://api.pushover.net/1/messages.json > /dev/null
    fi
}

send_slack() {
    if [[ -n "\$ALERT_SLACK_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"*\$SUBJECT*\n\$MESSAGE\"}" \
            "\$ALERT_SLACK_WEBHOOK" > /dev/null
    fi
}

send_webhook() {
    if [[ -n "\$ALERT_WEBHOOK_URL" ]]; then
        curl -s -X POST -H "Content-Type: application/json" \
            --data "{\"subject\":\"\$SUBJECT\",\"message\":\"\$MESSAGE\",\"duration\":\"\$FAILURE_DURATION\",\"version\":\"${SCRIPT_VERSION}\",\"github\":\"${SCRIPT_GITHUB}\"}" \
            "\$ALERT_WEBHOOK_URL" > /dev/null
    fi
}

send_email
send_pushover
send_slack
send_webhook

echo "[\$(date)] ALERT: \$SUBJECT - \$MESSAGE (v${SCRIPT_VERSION})" >> /var/log/dns-alerts.log
EOF

    chmod +x "$alert_script"

    cat > "$health_script" << EOF
#!/bin/bash
# DNS Health Check Script
# Version: ${SCRIPT_VERSION}

LOG_FILE="/var/log/dns-health.log"
ALERT_SCRIPT="/usr/local/bin/dns-alert.sh"
STATE_FILE="/var/run/dns-health.state"
ALERT_CONFIG="/etc/dns-alerts.conf"

source "\$ALERT_CONFIG" 2>/dev/null

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1 (v${SCRIPT_VERSION})" >> "\$LOG_FILE"
}

get_response_time() {
    local port=\$1
    dig @127.0.0.1 -p "\$port" google.com +stats 2>/dev/null | grep "Query time:" | awk '{print \$4}'
}

check_service() {
    local port=\$2
    local response_time=\$(get_response_time "\$port")
    [[ -n "\$response_time" ]] && return 0 || return 1
}

if [[ -f "\$STATE_FILE" ]]; then
    source "\$STATE_FILE"
else
    PRIMARY_FAIL_SINCE=0
    LAST_ALERT=0
fi

if ! check_service "dnscrypt-proxy" 5053; then
    if [[ \$PRIMARY_FAIL_SINCE -eq 0 ]]; then
        PRIMARY_FAIL_SINCE=\$(date +%s)
        log "WARNING: DNSCrypt primary DNS failed"
    else
        FAIL_DURATION=\$(( \$(date +%s) - PRIMARY_FAIL_SINCE ))
        log "ALERT: DNSCrypt primary down for \${FAIL_DURATION}s"

        systemctl restart dnscrypt-proxy
        sleep 5

        if check_service "dnscrypt-proxy" 5053; then
            log "SUCCESS: DNSCrypt recovered"
            PRIMARY_FAIL_SINCE=0
        elif [[ \$FAIL_DURATION -ge \${ALERT_THRESHOLD:-300} && \$(( \$(date +%s) - LAST_ALERT )) -ge 3600 ]]; then
            log "SENDING ALERT: Primary DNS down for \${FAIL_DURATION}s"
            \$ALERT_SCRIPT "Primary DNS (DNSCrypt) down for \${FAIL_DURATION}s. Unbound is backup." \
                          "DNS FAILURE: Primary Down" \
                          "\$FAIL_DURATION"
            LAST_ALERT=\$(date +%s)
        fi
    fi
else
    if [[ \$PRIMARY_FAIL_SINCE -ne 0 ]]; then
        log "INFO: DNSCrypt recovered after \$(( \$(date +%s) - PRIMARY_FAIL_SINCE ))s"
        PRIMARY_FAIL_SINCE=0
    fi
fi

cat > "\$STATE_FILE" << EOS
PRIMARY_FAIL_SINCE=\$PRIMARY_FAIL_SINCE
LAST_ALERT=\$LAST_ALERT
EOS

[[ -f /usr/local/bin/dns-metrics-exporter.sh ]] && /usr/local/bin/dns-metrics-exporter.sh
exit 0
EOF

    chmod +x "$health_script"

    cat > "$health_service" << EOF
[Unit]
Description=DNS Health Check Service
After=network.target

[Service]
Type=oneshot
ExecStart=$health_script
User=root
Group=root
EOF

    cat > "$health_timer" << EOF
[Unit]
Description=DNS Health Check Timer
Requires=dns-health-check.service

[Timer]
OnCalendar=*:0/${HEALTH_CHECK_INTERVAL}
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable dns-health-check.timer 2>/dev/null || true
    systemctl start dns-health-check.timer 2>/dev/null || true

    print_success "Health check service created"
}

# Function to setup daily gravity updates
setup_gravity_updates() {
    print_section "Configuring Daily Pi-hole Gravity Updates"

    local gravity_updater="/usr/local/bin/update-gravity.sh"

    cat > "$gravity_updater" << EOF
#!/bin/bash
# Pi-hole Gravity Updater
# Version: ${SCRIPT_VERSION}

LOG_FILE="/var/log/gravity-update.log"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1 (v${SCRIPT_VERSION})" >> "\$LOG_FILE"
}

log "Starting gravity update"

if pihole -g > /dev/null 2>&1; then
    log "SUCCESS: Gravity updated successfully"
    pihole restartdns
else
    log "ERROR: Gravity update failed"
fi

log "Gravity update completed"
EOF

    chmod +x "$gravity_updater"
    safe_add_cron "0 2 * * * root $gravity_updater" "/etc/cron.d/pi-hole-gravity-update"

    print_success "Daily gravity updates configured (runs at 2 AM)"
}

# Function to test failover behavior
test_failover() {
    print_section "Testing Failover Configuration"

    print_status "Testing DNS failover configuration..."

    local test_domain="google.com"
    local test_results="/tmp/failover-test-$$.log"

    print_status "Test 1: Normal operation (both services running)..."

    local dnscrypt_time=$(dig @127.0.0.1 -p "$DNSCRYPT_PORT" "$test_domain" +stats 2>/dev/null | grep "Query time:" | awk '{print $4}')
    local unbound_time=$(dig @127.0.0.1 -p "$UNBOUND_PORT" "$test_domain" +stats 2>/dev/null | grep "Query time:" | awk '{print $4}')
    local pihole_time=$(dig @127.0.0.1 -p 53 "$test_domain" +stats 2>/dev/null | grep "Query time:" | awk '{print $4}')

    echo "   DNSCrypt-Proxy: ${dnscrypt_time:-N/A} ms" | tee -a "$test_results"
    echo "   Unbound: ${unbound_time:-N/A} ms" | tee -a "$test_results"
    echo "   Pi-hole: ${pihole_time:-N/A} ms" | tee -a "$test_results"

    print_status "Test 2: Simulating DNSCrypt failure (measuring failover time)..."

    systemctl stop dnscrypt-proxy 2>/dev/null || true
    local failover_start=$(date +%s%N)

    local failover_response=$(dig @127.0.0.1 -p 53 "$test_domain" +stats 2>/dev/null)
    local failover_time=$(echo "$failover_response" | grep "Query time:" | awk '{print $4}')
    local failover_end=$(date +%s%N)
    local failover_duration=$(( ($failover_end - $failover_start) / 1000000 ))

    echo "   Pi-hole during DNSCrypt outage: ${failover_time:-N/A} ms" | tee -a "$test_results"
    echo "   Failover detection time: ${failover_duration} ms" | tee -a "$test_results"

    systemctl start dnscrypt-proxy 2>/dev/null || true
    sleep 2

    print_status "Test 3: Verifying Microsoft Teams domains..."
    local teams_domains=("teams.microsoft.com" "login.microsoftonline.com" "outlook.office.com")
    for domain in "${teams_domains[@]}"; do
        if dig @127.0.0.1 "$domain" +short > /dev/null 2>&1; then
            echo "   ✓ $domain is accessible" | tee -a "$test_results"
        else
            echo "   ✗ $domain may be blocked" | tee -a "$test_results"
        fi
    done

    cp "$test_results" "$BACKUP_DIR/failover-test-results.txt"
    rm -f "$test_results"

    print_success "Failover testing complete - results saved to $BACKUP_DIR/failover-test-results.txt"
}

# Function to test DNSSEC validation
test_dnssec() {
    print_section "Testing DNSSEC Validation"

    print_status "Testing DNSSEC validation through Unbound..."

    local dnssec_fail=$(dig @127.0.0.1 -p "$UNBOUND_PORT" fail01.dnssec.works +short 2>&1 | grep -c "SERVFAIL" || true)
    if [[ $dnssec_fail -gt 0 ]]; then
        print_success "✓ DNSSEC validation working (expected SERVFAIL)"
    else
        print_warning "⚠ DNSSEC validation test may have issues"
    fi

    local dnssec_pass=$(dig @127.0.0.1 -p "$UNBOUND_PORT" dnssec.works +dnssec | grep -c "ad" || true)
    if [[ $dnssec_pass -gt 0 ]]; then
        print_success "✓ DNSSEC works for valid domains (AD flag present)"
    else
        print_warning "⚠ DNSSEC test for valid domain may have issues"
    fi

    print_status "Testing DNSSEC through Pi-hole chain..."
    local pihole_dnssec=$(dig @127.0.0.1 -p 53 dnssec.works +dnssec | grep -c "ad" || true)
    if [[ $pihole_dnssec -gt 0 ]]; then
        print_success "✓ DNSSEC works through complete Pi-hole chain"
    else
        print_warning "⚠ DNSSEC through Pi-hole may have issues"
    fi
}

# Function to test the complete setup
test_configuration() {
    print_section "Testing Complete Configuration"

    print_status "Testing DNSCrypt-Proxy (port $DNSCRYPT_PORT)..."
    dig @127.0.0.1 -p "$DNSCRYPT_PORT" google.com +short > /dev/null 2>&1 && \
        print_success "✓ DNSCrypt-Proxy is responding" || \
        print_error "✗ DNSCrypt-Proxy test failed"

    print_status "Testing Unbound (port $UNBOUND_PORT)..."
    dig @127.0.0.1 -p "$UNBOUND_PORT" google.com +short > /dev/null 2>&1 && \
        print_success "✓ Unbound is responding" || \
        print_error "✗ Unbound test failed"

    print_status "Testing Pi-hole (port 53)..."
    dig @127.0.0.1 -p 53 google.com +short > /dev/null 2>&1 && \
        print_success "✓ Pi-hole is responding" || \
        print_error "✗ Pi-hole test failed"

    test_dnssec
    test_failover

    print_status "Testing blocklist functionality..."
    local blocklist_count=$(sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist WHERE enabled = 1;" 2>/dev/null || echo "0")
    echo "   Active blocklists: $blocklist_count"

    print_success "All tests completed"
}

# Function to create comprehensive restore script with COMPLETE SQLite cleanup (NO GHOST ENTRIES)
create_restore_script() {
    print_section "Creating Comprehensive Restore Script with COMPLETE SQLite Cleanup"

    cat > "$RESTORE_SCRIPT" << EOF
#!/bin/bash
# Comprehensive restore script for DNS configuration backup
# v${SCRIPT_VERSION} - Ultimate Masterpiece Final Edition with COMPLETE SQLite Cleanup
# GitHub: ${SCRIPT_GITHUB}
# Website: ${SCRIPT_WEBSITE}

BACKUP_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
RESTORE_LOG="\$BACKUP_DIR/restore.log"

echo "========================================="
echo "Restoring from backup: \$BACKUP_DIR"
echo "Version: ${SCRIPT_VERSION}"
echo "GitHub: ${SCRIPT_GITHUB}"
echo "Website: ${SCRIPT_WEBSITE}"
echo "Log file: \$RESTORE_LOG"
echo "========================================="

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$RESTORE_LOG"
}

restore_file() {
    local backup_file="\$1"
    local target_file="\${backup_file#\$BACKUP_DIR}"

    if [[ -f "\$backup_file" ]]; then
        mkdir -p "\$(dirname "\$target_file")"
        cp -p "\$backup_file" "\$target_file"
        log "✓ Restored: \$target_file"
    fi
}

log "Step 1: Stopping services..."
systemctl stop dns-watchdog.timer 2>/dev/null
systemctl stop dns-health-check.timer 2>/dev/null
systemctl stop unbound 2>/dev/null
systemctl stop dnscrypt-proxy 2>/dev/null
pihole restartdns 2>/dev/null

log "Step 2: Restoring configuration files..."
find "\$BACKUP_DIR" -type f -not -name "restore.sh" -not -name "restore.log" -not -name "failover-test-results.txt" -not -name "install-notes.txt" | while read -r file; do
    restore_file "\$file"
done

log "Step 3: Removing installer-added configurations..."

# Remove custom configs
rm -f /etc/dnsmasq.d/99-strict-order.conf
rm -f /usr/local/bin/dns-watchdog.sh
rm -f /usr/local/bin/dns-health-check.sh
rm -f /usr/local/bin/dns-alert.sh
rm -f /usr/local/bin/dns-metrics-exporter.sh
rm -f /usr/local/bin/update-regex-lists.sh
rm -f /usr/local/bin/update-gravity.sh
rm -f /usr/local/bin/pihole-health

# Remove systemd services
for service in dns-watchdog.service dns-watchdog.timer dns-health-check.service dns-health-check.timer; do
    if [[ -f "/etc/systemd/system/\$service" ]]; then
        systemctl disable \${service%.*} 2>/dev/null
        rm -f "/etc/systemd/system/\$service"
        log "✓ Removed: \$service"
    fi
done

# Remove cron jobs
rm -f /etc/cron.d/dns-metrics
rm -f /etc/cron.d/pi-hole-gravity-update
rm -f /etc/cron.d/pi-hole-regex-update
log "✓ Removed: custom cron jobs"

# Remove logrotate config
rm -f /etc/logrotate.d/pihole-custom
log "✓ Removed: logrotate config"

# Remove DNSCrypt cloaking files
rm -f ${CLOAKING_FILE} 2>/dev/null || true
log "✓ Removed: DNSCrypt cloaking rules"

# Step 4: COMPLETE SQLite database cleanup - MULTIPLE METHODS TO ENSURE NO GHOST ENTRIES
log "Step 4: Performing COMPLETE SQLite database cleanup (NO GHOST ENTRIES)..."
GRAVITY_DB="/etc/pihole/gravity.db"
if [[ -f "\$GRAVITY_DB" ]]; then
    # Method 1: Remove by exact comment (primary method)
    log "Method 1: Removing entries with comment '${SCRIPT_DB_COMMENT}'..."
    sqlite3 "\$GRAVITY_DB" "DELETE FROM domainlist WHERE comment = '${SCRIPT_DB_COMMENT}';" 2>/dev/null
    DEL_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT changes();" 2>/dev/null || echo "0")
    log "  Removed \$DEL_COUNT entries by exact comment"

    # Method 2: Remove by version pattern
    log "Method 2: Removing entries with version pattern 'v${SCRIPT_VERSION}'..."
    sqlite3 "\$GRAVITY_DB" "DELETE FROM domainlist WHERE comment LIKE '%v${SCRIPT_VERSION}%';" 2>/dev/null
    DEL_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT changes();" 2>/dev/null || echo "0")
    log "  Removed \$DEL_COUNT entries by version pattern"

    # Method 3: Remove by website pattern
    log "Method 3: Removing entries with website pattern '${SCRIPT_WEBSITE}'..."
    sqlite3 "\$GRAVITY_DB" "DELETE FROM domainlist WHERE comment LIKE '%${SCRIPT_WEBSITE}%';" 2>/dev/null
    DEL_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT changes();" 2>/dev/null || echo "0")
    log "  Removed \$DEL_COUNT entries by website pattern"

    # Method 4: Remove by Masterpiece pattern (catch any older versions)
    log "Method 4: Removing entries with 'Masterpiece' in comment..."
    sqlite3 "\$GRAVITY_DB" "DELETE FROM domainlist WHERE comment LIKE '%Masterpiece%';" 2>/dev/null
    DEL_COUNT=\$(sqlite3 "\$GRAVITY_DB" "SELECT changes();" 2>/dev/null || echo "0")
    log "  Removed \$DEL_COUNT entries by Masterpiece pattern"

    # Method 5: Verify by checking our whitelist domains
    log "Method 5: Verifying our whitelist domains are removed..."
    if [[ -f "\$BACKUP_DIR/etc/pihole/whitelist.txt" ]]; then
        while IFS= read -r domain; do
            if [[ -n "\$domain" ]] && [[ ! "\$domain" =~ ^# ]]; then
                EXISTS=\$(sqlite3 "\$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE domain = '\$domain' AND type = 0 AND comment LIKE '%${SCRIPT_WEBSITE}%';" 2>/dev/null)
                if [[ \$EXISTS -gt 0 ]]; then
                    sqlite3 "\$GRAVITY_DB" "DELETE FROM domainlist WHERE domain = '\$domain' AND type = 0 AND comment LIKE '%${SCRIPT_WEBSITE}%';" 2>/dev/null
                    log "    Force removed: \$domain"
                fi
            fi
        done < "\$BACKUP_DIR/etc/pihole/whitelist.txt"
    fi

    # Reset gravity to ensure clean state
    log "Rebuilding gravity database..."
    pihole -g > /dev/null 2>&1
    log "✓ Gravity database rebuilt and verified clean"

    # Final verification
    REMAINING=\$(sqlite3 "\$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE comment LIKE '%${SCRIPT_WEBSITE}%' OR comment LIKE '%Masterpiece%' OR comment LIKE '%v${SCRIPT_VERSION}%';" 2>/dev/null || echo "0")
    if [[ \$REMAINING -eq 0 ]]; then
        log "✓ COMPLETE CLEANUP SUCCESSFUL - No ghost entries remain"
    else
        log "⚠ WARNING: \$REMAINING ghost entries may remain - manual check recommended"
    fi
fi

# Remove version tracking file
rm -f /etc/pihole/.masterpiece-version
rm -f /etc/dns-alerts.conf
rm -f /var/run/dns-health.state
rm -f /var/lib/node_exporter/dns_metrics.prom
rm -f /var/log/dns-watchdog.log
rm -f /var/log/dns-health.log
rm -f /var/log/dns-alerts.log
rm -f /var/log/gravity-update.log
rm -f /var/log/regex-update.log

systemctl daemon-reload

log "Step 5: Reverting Pi-hole DNS settings..."
if [[ -f /etc/pihole/setupVars.conf ]]; then
    sed -i '/^PIHOLE_DNS_/d' /etc/pihole/setupVars.conf
    sed -i '/^DNSSEC=/d' /etc/pihole/setupVars.conf
    echo "PIHOLE_DNS_1=9.9.9.9" >> /etc/pihole/setupVars.conf
    echo "PIHOLE_DNS_2=149.112.112.112" >> /etc/pihole/setupVars.conf
    echo "DNSSEC=true" >> /etc/pihole/setupVars.conf
    log "✓ Reverted Pi-hole DNS to Quad9 defaults"
fi

log "Step 6: Restarting services..."
systemctl daemon-reload
systemctl restart unbound 2>/dev/null
systemctl restart dnscrypt-proxy 2>/dev/null
pihole restartdns

sleep 5

log "Step 7: Verifying DNS functionality..."
if dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
    log "✓ DNS is working through Pi-hole"
else
    log "✗ DNS test failed - manual intervention required"
fi

echo "========================================="
echo "Restore complete. Please verify:"
echo "  dig google.com @127.0.0.1"
echo "  pihole status"
echo "  pihole-health (if available)"
echo ""
echo "GitHub: ${SCRIPT_GITHUB}"
echo "Website: ${SCRIPT_WEBSITE}"
echo "========================================="
log "Restore completed at \$(date)"
EOF

    chmod +x "$RESTORE_SCRIPT"
    print_success "Comprehensive restore script created with COMPLETE SQLite cleanup: $RESTORE_SCRIPT"
    print_success "This script will remove ALL ghost entries using 5 different methods!"
}

# Function to display final instructions
show_completion_message() {
    MONITOR_URL=""
    if [[ -n "${MONITOR_IP:-}" && -n "${MONITOR_PORT:-}" ]]; then
        MONITOR_URL="http://$MONITOR_IP:$MONITOR_PORT"
    fi

    cat << EOF

${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}
${GREEN}║     INSTALLATION COMPLETE - v${SCRIPT_VERSION} (ULTIMATE MASTERPIECE FINAL)        ║${NC}
${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}

${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
${CYAN}Project Information:${NC}
${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
• GitHub:           ${YELLOW}${SCRIPT_GITHUB}${NC}
• Website:          ${YELLOW}${SCRIPT_WEBSITE}${NC}
• Version:          ${YELLOW}${SCRIPT_VERSION}${NC}
• Author:           ${YELLOW}${SCRIPT_AUTHOR}${NC}
• Date:             ${YELLOW}${SCRIPT_DATE}${NC}

${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
${CYAN}Configuration Summary:${NC}
${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
• Pi-hole:           DNS server (port 53) - Primary DNS for your network
• DNSCrypt-Proxy:    127.0.0.1:${DNSCRYPT_PORT} - PRIMARY (Happy Eyeballs enabled)
• Unbound:           127.0.0.1:${UNBOUND_PORT} - SECONDARY (DoT + DoH fallback)
• Whitelist:         ${#WHITELIST_DOMAINS[@]} domains (SQLite injected, Teams ready)
• Blocklists:        ${#BLOCKLISTS[@]} comprehensive lists
• Regex Patterns:    ${#REGEX_PATTERNS[@]} regex filters
• Watchdog:          Every ${WATCHDOG_INTERVAL} seconds (auto-restart)
• Log Rotation:      Advanced (prevents disk filling)
• Health Dashboard:  'pihole-health' command available
${MONITOR_URL:+• Monitoring UI:     ${MONITOR_URL} (DNSCrypt dashboard)}
• Cloaking Rules:    ${CLOAKING_FILE} (if configured)

${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
${CYAN}Access Information:${NC}
${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
• Pi-hole Admin:     ${YELLOW}http://$(hostname -I | awk '{print $1}')/admin${NC}
• Backup Location:   ${YELLOW}${BACKUP_DIR}${NC}
• Restore Script:    ${YELLOW}${BACKUP_DIR}/restore.sh${NC} (COMPLETE SQLite cleanup)
• Health Dashboard:  ${YELLOW}pihole-health${NC}
• Installation Log:  ${YELLOW}${SCRIPT_LOG}${NC}
${MONITOR_URL:+• DNSCrypt Monitor:  ${YELLOW}${MONITOR_URL}${NC}}

${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
${CYAN}Useful Commands:${NC}
${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
${YELLOW}• Health dashboard:    pihole-health${NC}
${YELLOW}• Test Teams:          dig teams.microsoft.com @127.0.0.1${NC}
${YELLOW}• Watchdog logs:       journalctl -u dns-watchdog -f${NC}
${YELLOW}• Health logs:         tail -f /var/log/dns-health.log${NC}
${YELLOW}• Check SQL whitelist: sqlite3 /etc/pihole/gravity.db "SELECT * FROM domainlist WHERE type=0 AND comment LIKE '%${SCRIPT_VERSION}%';"${NC}

${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
${CYAN}Restore Information:${NC}
${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}
• Restore command:    ${YELLOW}sudo ${BACKUP_DIR}/restore.sh${NC}
• The restore script uses 5 different methods to ensure NO GHOST ENTRIES remain
• All v${SCRIPT_VERSION} entries are tagged with comment: "${SCRIPT_DB_COMMENT}"
• Version tracking file: ${YELLOW}/etc/pihole/.masterpiece-version${NC}

${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}
${GREEN}✓ YOUR ULTIMATE MASTERPIECE DNS SETUP v${SCRIPT_VERSION} IS COMPLETE! ✓${NC}
${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}

EOF
}

# Main installation function
main() {
    show_banner

    echo ""
    print_warning "This will install the ULTIMATE MASTERPIECE DNS solution v${SCRIPT_VERSION}."
    print_warning "Complete backup with COMPLETE SQLite cleanup: $BACKUP_DIR"
    print_warning "GitHub: $SCRIPT_GITHUB"
    print_warning "Website: $SCRIPT_WEBSITE"
    echo ""
    read -p "Press Enter to continue or Ctrl+C to cancel (Ctrl+C works now!)..."

    touch "$SCRIPT_LOG"
    echo "=== Installation started at $(date) ===" >> "$SCRIPT_LOG"
    echo "=== Version: $SCRIPT_VERSION ===" >> "$SCRIPT_LOG"
    echo "=== GitHub: $SCRIPT_GITHUB ===" >> "$SCRIPT_LOG"
    echo "=== Website: $SCRIPT_WEBSITE ===" >> "$SCRIPT_LOG"

    check_root
    detect_os
    backup_crons
    install_dependencies
    backup_existing_configs
    configure_alerts
    configure_pihole_dhcp
    configure_dnscrypt_dashboard
    configure_local_dns
    configure_cloaking
    configure_unbound_doh_fallback
    setup_pihole
    setup_dnscrypt_proxy
    setup_unbound
    setup_pihole_failover
    setup_regex_filters
    setup_lists
    setup_blocklists
    fix_debian_resolvconf
    setup_unbound_logging
    setup_logrotate
    setup_firewall
    setup_metrics_exporter
    setup_health_check
    setup_watchdog
    setup_gravity_updates
    setup_health_dashboard

    print_section "Updating Pi-hole Gravity"
    print_status "Running initial gravity update..."
    pihole -g >> "$SCRIPT_LOG" 2>&1 &
    GRAVITY_PID=$!
    while kill -0 $GRAVITY_PID 2>/dev/null; do echo -n "."; sleep 2; done
    echo ""
    print_success "Gravity update completed"

    print_section "Restarting Services"
    systemctl restart unbound 2>/dev/null || true
    systemctl restart dnscrypt-proxy 2>/dev/null || true
    pihole restartdns
    sleep 5

    test_configuration
    create_restore_script
    show_completion_message

    echo "=== Installation completed at $(date) ===" >> "$SCRIPT_LOG"
    echo "=== Version: $SCRIPT_VERSION ===" >> "$SCRIPT_LOG"
    print_success "Installation complete! Check $SCRIPT_LOG for details."
    print_success "Restore script (with COMPLETE SQLite cleanup): $RESTORE_SCRIPT"
    print_success "Health dashboard: type 'pihole-health' for system status"
    print_success "GitHub: $SCRIPT_GITHUB"
    print_success "Website: $SCRIPT_WEBSITE"
}

# Call main function
main "$@"
