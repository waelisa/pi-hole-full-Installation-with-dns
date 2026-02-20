#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Pi-hole Ultimate Edition - Maximum Protection + Monitoring + Backup
# Version: 1.6.5
# Date: 20-02-2026
#
# Wael Isa
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
# Support: https://www.paypal.me/WaelIsa
#
# Features:
#   - Pi-hole v6 with Unbound recursive DNS
#   - UPDATED: Working blocklists (2026 verified)
#   - FIXED: Regex patterns with proper SQL escaping
#   - FIXED: Password reset at the end
#   - All lists verified and recommended by Pi-hole community
#############################################################################################################################

set -e
set -o pipefail

# ---------- Color Definitions ------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
ORANGE='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- Configuration -----------------------------------------------------
PIHOLE_BACKUP_DIR="/var/backups/pihole"
BACKUP_RETENTION_COUNT=7
THERMAL_LOG="/var/log/thermal-monitor.log"
THERMAL_STATE="/var/lib/thermal-monitor.state"
TEMP_WARN=75
TEMP_CRIT=80
UNBOUND_CONF="/etc/unbound/unbound.conf.d/pi-hole.conf"
EMAIL_CONFIG="/etc/pihole-backup-email.conf"
PIHOLE_TOML="/etc/pihole/pihole.toml"
GRAVITY_DB="/etc/pihole/gravity.db"
LOG_FILE="/var/log/pihole-ultimate-install.log"
ROOT_HINTS="/usr/share/dns/root.hints"

# ---------- User Preferences --------------------------------------------------
EMAIL_ENABLED=false
EMAIL_RECIPIENT=""
SMTP_SERVER=""
SMTP_USER=""
SMTP_PASS=""

# ---------- Helper functions -------------------------------------------------
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

print_banner() {
    clear
    log "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    log "${WHITE}${BOLD}      Pi-hole Ultimate Edition v1.6.5 - Working Lists & Regex${NC}"
    log "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    log ""
}

print_header() {
    log "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    log "${WHITE}${BOLD}  $1${NC}"
    log "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    log "${GREEN}✓ $1${NC}"
}

print_warning() {
    log "${YELLOW}⚠ $1${NC}"
}

print_error() {
    log "${RED}✗ $1${NC}"
}

print_info() {
    log "${CYAN}ℹ $1${NC}"
}

run_sudo() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
        print_error "This script requires root privileges. Please run with sudo or as root."
        exit 1
    fi
}

check_os() {
    print_info "Checking operating system compatibility..."

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID" == "raspbian" || "$ID" == "armbian" ]]; then
            print_success "Running on $PRETTY_NAME"
            return 0
        else
            print_warning "This script is optimized for Debian/Ubuntu/Raspbian systems."
            print_warning "You are running: $PRETTY_NAME"
            print_warning "Continuing anyway - some features may not work correctly."
            return 0
        fi
    else
        print_warning "Could not determine OS. Continuing with installation..."
        return 0
    fi
}

# ---------- Collect User Preferences -----------------------------------------
collect_preferences() {
    print_header "Configuration Collection"

    echo -e "${YELLOW}Do you want to enable email alerts? (y/n)${NC}"
    read -r enable_email
    if [[ "$enable_email" =~ ^[Yy]$ ]]; then
        EMAIL_ENABLED=true
        echo -e "${CYAN}Enter recipient email address:${NC}"
        read -r EMAIL_RECIPIENT
        echo -e "${CYAN}Enter SMTP server (e.g., smtp.gmail.com:587):${NC}"
        read -r SMTP_SERVER
        echo -e "${CYAN}Enter SMTP user (leave empty if not required):${NC}"
        read -r SMTP_USER
        echo -e "${CYAN}Enter SMTP password (leave empty if not required):${NC}"
        read -rs SMTP_PASS
        echo ""
        print_success "Email configuration saved"
    else
        print_info "Email alerts disabled"
    fi
}

# ---------- Install Dependencies --------------------------------------------
install_dependencies() {
    print_header "Installing System Dependencies"

    print_info "Updating package lists..."
    run_sudo apt-get update >> "$LOG_FILE" 2>&1

    print_info "Installing required packages..."
    run_sudo apt-get install -y curl wget git unzip nano sqlite3 \
        bc jq mailutils ssmtp dnsutils \
        openssl ca-certificates systemd >> "$LOG_FILE" 2>&1

    print_success "Dependencies installed"
}

# ---------- Remove lighttpd if present ---------------------------------------
remove_lighttpd() {
    if dpkg -l | grep -q lighttpd 2>/dev/null; then
        print_info "Removing lighttpd (Pi-hole v6 uses embedded web server)..."
        run_sudo systemctl stop lighttpd 2>/dev/null || true
        run_sudo systemctl disable lighttpd 2>/dev/null || true
        run_sudo apt-get remove --purge -y lighttpd >> "$LOG_FILE" 2>&1
        print_success "lighttpd removed"
    fi
}

# ---------- Install Pi-hole v6 ----------------------------------------------
install_pihole() {
    print_header "Installing Pi-hole v6"

    if ! command -v pihole >/dev/null 2>&1; then
        print_info "Downloading and installing Pi-hole v6..."

        # Create directory structure
        run_sudo mkdir -p /etc/pihole

        # Run installer
        if curl -sSL https://install.pi-hole.net | run_sudo bash /dev/stdin --unattended >> "$LOG_FILE" 2>&1; then
            print_success "Pi-hole v6 installed successfully"
        else
            print_error "Pi-hole installation failed"
            exit 1
        fi
    else
        print_info "Pi-hole already installed"
        # Ensure it's v6
        run_sudo pihole -up >> "$LOG_FILE" 2>&1
    fi

    # Wait for FTL to start
    print_info "Waiting for Pi-hole FTL to initialize..."
    sleep 10

    # Remove lighttpd if present
    remove_lighttpd
}

# ---------- Set Pi-hole Password --------------------------------------------
set_pihole_password() {
    print_header "Setting Pi-hole Admin Password"

    print_info "You can set a password for the Pi-hole web interface."
    echo -e "${YELLOW}Do you want to set a custom password now? (y/n)${NC}"
    echo -e "${CYAN}Note: If you skip, you can set it later with: sudo pihole setpassword${NC}"
    read -r set_pass

    if [[ "$set_pass" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Enter new password for Pi-hole admin:${NC}"
        run_sudo pihole setpassword
        print_success "Password set successfully"
    else
        print_info "Skipping password setup. Default password is empty."
        print_info "To set password later: sudo pihole setpassword"
    fi
}

# ---------- Install & Configure Unbound --------------------------------------
install_unbound() {
    print_header "Installing Unbound Recursive DNS"

    print_info "Installing Unbound package..."
    run_sudo apt-get install -y unbound dns-root-data >> "$LOG_FILE" 2>&1

    run_sudo systemctl stop unbound 2>/dev/null || true

    # Backup original config
    if [[ ! -f /etc/unbound/unbound.conf.orig ]]; then
        run_sudo cp /etc/unbound/unbound.conf /etc/unbound/unbound.conf.orig 2>/dev/null || true
    fi

    # Clear existing configs
    run_sudo rm -f /etc/unbound/unbound.conf.d/*.conf 2>/dev/null || true

    print_info "Configuring Unbound..."
    run_sudo tee "$UNBOUND_CONF" > /dev/null <<EOF
server:
    interface: 127.0.0.1
    interface: ::1
    port: 5335
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes

    access-control: 127.0.0.0/8 allow
    access-control: ::1/128 allow
    access-control: 192.168.0.0/16 allow
    access-control: 172.16.0.0/12 allow
    access-control: 10.0.0.0/8 allow

    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    qname-minimisation: yes

    root-hints: $ROOT_HINTS
    auto-trust-anchor-file: /var/lib/unbound/root.key

    cache-min-ttl: 3600
    cache-max-ttl: 86400
    prefetch: yes
    num-threads: 2
EOF

    # Download root hints
    if [[ ! -f "$ROOT_HINTS" ]]; then
        run_sudo mkdir -p /usr/share/dns
        run_sudo curl -o "$ROOT_HINTS" https://www.internic.net/domain/named.cache >> "$LOG_FILE" 2>&1 || true
    fi

    # Fix permissions
    if [[ -f /var/lib/unbound/root.key ]]; then
        run_sudo chown unbound:unbound /var/lib/unbound/root.key 2>/dev/null || true
        run_sudo chmod 644 /var/lib/unbound/root.key 2>/dev/null || true
    fi

    # Start Unbound
    run_sudo systemctl enable unbound >> "$LOG_FILE" 2>&1
    run_sudo systemctl start unbound >> "$LOG_FILE" 2>&1
    sleep 3

    if run_sudo systemctl is-active --quiet unbound; then
        print_success "Unbound service started"
    else
        print_error "Unbound failed to start"
        exit 1
    fi
}

# ---------- Configure Pi-hole v6 DNS (DIRECT TOML MANIPULATION) ------------
configure_pihole_v6_dns() {
    print_header "Configuring Pi-hole v6 DNS (Direct TOML Edit)"

    print_info "Stopping Pi-hole FTL for configuration..."
    run_sudo systemctl stop pihole-FTL
    sleep 3

    # BACKUP and EDIT TOML directly
    if [[ -f "$PIHOLE_TOML" ]]; then
        print_info "Backing up original TOML..."
        run_sudo cp "$PIHOLE_TOML" "$PIHOLE_TOML.backup"

        print_info "Setting DNS upstream to Unbound in TOML..."

        # Create a completely new TOML with proper format
        run_sudo tee "$PIHOLE_TOML" > /dev/null <<'EOF'
# Pi-hole v6 configuration file
[dns]
upstreams = ["127.0.0.1#5335"]
blocking.active = true
queryLogging = true

[webserver]
port = 80
api.password = ""

[database]
maxDBdays = 365
EOF

        print_success "TOML configuration updated with Unbound upstream"

        # Show the config
        print_info "New TOML configuration:"
        run_sudo cat "$PIHOLE_TOML" | while read line; do
            print_info "  $line"
        done
    else
        print_error "TOML file not found!"
        exit 1
    fi

    # Start FTL
    print_info "Starting Pi-hole FTL..."
    run_sudo systemctl start pihole-FTL
    sleep 10

    # Test resolution
    if dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
        print_success "Pi-hole DNS resolution working"
    else
        print_warning "Pi-hole DNS test failed"
    fi

    if dig @127.0.0.1 -p 5335 google.com +short > /dev/null 2>&1; then
        print_success "Unbound DNS resolution working"
    else
        print_error "Unbound DNS test failed"
        exit 1
    fi
}

# ---------- Configure Blocklists (2026 UPDATED WORKING LISTS) ---------------
configure_blocklists() {
    print_header "Configuring Blocklists (2026 UPDATED WORKING LISTS)"

    # Wait for database to be created
    sleep 5

    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, running gravity first..."
        run_sudo pihole -g >> "$LOG_FILE" 2>&1
        sleep 5
    fi

    if [[ -f "$GRAVITY_DB" ]]; then
        print_info "Clearing existing adlists from database..."
        run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM adlist;" >> "$LOG_FILE" 2>&1 || true
    fi

    # ===== 2026 VERIFIED WORKING BLOCKLISTS =====
    # Sources: Firebog.net (Ticked lists), Hagezi, OISD, and community recommendations
    # All URLs tested and working as of February 2026
    local lists=(
        # === HAGEZI BLOCKLISTS (Highly Recommended) ===
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/multi.txt|Hagezi Multi PRO - Extended protection"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/ultimate.txt|Hagezi ULTIMATE - Maximum protection"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/tif.txt|Hagezi TIF - Threat Intelligence Feeds"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/fake.txt|Hagezi FAKE - Fake/Scam sites"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/popupads.txt|Hagezi PopupAds - Popup ads"

        # === OISD - Most Comprehensive Balanced List ===
        "https://big.oisd.nl/|OISD Full - Balanced protection"

        # === FIREBOG TICKED LISTS (Safe/Recommended) ===
        "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt|KADhosts"
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Spam/hosts|add.Spam"
        "https://v.firebog.net/hosts/static/w3kbl.txt|w3kbl"
        "https://adaway.org/hosts.txt|AdAway"
        "https://v.firebog.net/hosts/AdguardDNS.txt|AdGuard DNS"
        "https://v.firebog.net/hosts/Admiral.txt|Admiral"
        "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt|anudeepND"
        "https://v.firebog.net/hosts/Easylist.txt|EasyList"
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext|Yoyo"
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/UncheckyAds/hosts|UncheckyAds"
        "https://raw.githubusercontent.com/bigdargon/hostsVN/master/hosts|bigdargon"
        "https://v.firebog.net/hosts/Easyprivacy.txt|EasyPrivacy"
        "https://v.firebog.net/hosts/Prigent-Ads.txt|Prigent-Ads"
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.2o7Net/hosts|2o7Net"
        "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt|WindowsSpyBlocker"
        "https://hostfiles.frogeye.fr/firstparty-trackers-hosts.txt|FirstParty Trackers"
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt|DandelionSprout"
        "https://v.firebog.net/hosts/Prigent-Crypto.txt|Prigent-Crypto"
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Risk/hosts|add.Risk"
        "https://phishing.army/download/phishing_army_blocklist_extended.txt|Phishing Army"
        "https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt|NoTrack"
        "https://raw.githubusercontent.com/Spam404/lists/master/main-blacklist.txt|Spam404"
        "https://raw.githubusercontent.com/AssoEchap/stalkerware-indicators/master/generated/hosts|Stalkerware"
        "https://urlhaus.abuse.ch/downloads/hostfile/|URLHaus"
        "https://lists.cyberhost.uk/malware.txt|Cyberhost UK"

        # === STEVEN BLACK (Base List) ===
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts|StevenBlack Unified"

        # === SPANISH/EUROPEAN LISTS ===
        "https://easylist-downloads.adblockplus.org/easylistspanish.txt|EasyList Spanish"
        "https://raw.githubusercontent.com/gioxx/xfiles/master/filtri.txt|gioxx Italian/Spanish"
    )

    print_info "Adding ${#lists[@]} blocklists to database (2026 verified sources)..."

    local success_count=0
    for entry in "${lists[@]}"; do
        IFS='|' read -r url comment <<< "$entry"
        print_info "Adding: $comment"

        # Direct SQLite insertion with proper escaping
        if [[ -f "$GRAVITY_DB" ]]; then
            # Escape single quotes in URL and comment
            url_escaped=$(echo "$url" | sed "s/'/''/g")
            comment_escaped=$(echo "$comment" | sed "s/'/''/g")
            if run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO adlist (address, comment, enabled) VALUES ('$url_escaped', '$comment_escaped', 1);" >> "$LOG_FILE" 2>&1; then
                ((success_count++))
            else
                print_warning "Failed to add: $comment"
            fi
        fi
    done

    # Verify insertion
    if [[ -f "$GRAVITY_DB" ]]; then
        local count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist;" 2>/dev/null)
        print_success "$count blocklists added to database ($success_count new)"
    fi

    # CRITICAL: Rebuild gravity
    print_info "Rebuilding gravity (this will take a few minutes)..."
    run_sudo pihole -g >> "$LOG_FILE" 2>&1

    print_success "Gravity rebuilt - blocklists now active"
}

# ---------- Configure Regex Patterns (FIXED SQL ESCAPING) -------------------
configure_regex() {
    print_header "Configuring Regex Patterns (FIXED SQL Escaping)"

    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, skipping regex configuration"
        return
    fi

    print_info "Clearing existing regex patterns from database..."
    run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist WHERE type = 3;" >> "$LOG_FILE" 2>&1 || true

    # ===== REGEX PATTERNS (with proper SQL escaping) =====
    # All special characters are escaped for SQLite
    local patterns=(
        "(^|\.)bit\.ly$|URL shorteners"
        "(^|\.)tinyurl\.com$|URL shorteners"
        "(^|\.)goo\.gl$|Google URL shortener"
        "(^|\.)ow\.ly$|URL shortener"
        "(^|\.)malware[a-zA-Z0-9-]*\.|Generic malware"
        "(^|\.)phish[a-zA-Z0-9-]*\.|Generic phishing"
        "(^|\.)ransom[a-zA-Z0-9-]*\.|Generic ransomware"
        "(^|\.)cryptolocker\.|CryptoLocker"
        "(^|\.)paypal-secure\.|Fake PayPal"
        "(^|\.)apple-id\.|Fake Apple ID"
        "(^|\.)amazon-login\.|Fake Amazon"
        "(^|\.)bankofamerica-verify\.|Fake banking"
        "(^|\.)google-analytics\.com$|Google Analytics"
        "(^|\.)googletagmanager\.com$|Google Tag Manager"
        "(^|\.)doubleclick\.net$|DoubleClick"
        "(^|\.)googleadservices\.com$|Google Ads"
        "(^|\.)coin-hive\.com$|CoinHive"
        "(^|\.)telemetry\.|Telemetry"
        "(^|\.)diagnostics\.|Diagnostics"
        "(^|\.)data-?collector\.|Data collector"
        "(^|\.)spy\.|Spyware"
        "^adserver[0-9]*\.|Ad servers"
        "^ads[0-9]*\.|Ad servers"
        "^track\.|Tracking"
    )

    print_info "Adding ${#patterns[@]} regex patterns to database with proper escaping..."

    local success_count=0
    for entry in "${patterns[@]}"; do
        IFS='|' read -r pattern comment <<< "$entry"

        # CRITICAL: Properly escape single quotes for SQLite
        # Replace ' with '' in both pattern and comment
        pattern_escaped=$(echo "$pattern" | sed "s/'/''/g")
        comment_escaped=$(echo "$comment" | sed "s/'/''/g")

        # Direct SQLite insertion - type 3 is regex blacklist
        if [[ -f "$GRAVITY_DB" ]]; then
            if run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (3, '$pattern_escaped', 1, '$comment_escaped');" >> "$LOG_FILE" 2>&1; then
                ((success_count++))
            else
                print_warning "Failed to add pattern: $comment"
            fi
        fi
    done

    # Verify
    if [[ -f "$GRAVITY_DB" ]]; then
        local count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 3;" 2>/dev/null)
        print_success "$count regex patterns added to database ($success_count new)"
    fi

    # Reload lists
    run_sudo pihole restartdns reload-lists >> "$LOG_FILE" 2>&1 || run_sudo pihole restartdns >> "$LOG_FILE" 2>&1
}

# ---------- Configure Whitelist ----------------------------------------------
configure_whitelist() {
    print_header "Configuring Microsoft Services Whitelist"

    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, skipping whitelist configuration"
        return
    fi

    print_info "Clearing existing whitelist entries from database..."
    run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist WHERE type IN (0, 2);" >> "$LOG_FILE" 2>&1 || true

    # Exact whitelist (type 0)
    local exact=(
        "teams.microsoft.com|Microsoft Teams"
        "teams.live.com|Microsoft Teams"
        "teams.events.data.microsoft.com|Microsoft Teams"
        "statics.teams.cdn.office.net|Microsoft Teams"
        "config.teams.microsoft.com|Microsoft Teams"
        "teams.cloud.microsoft|Microsoft Teams"
        "teams.office.com|Microsoft Teams"
        "office.com|Office 365"
        "office365.com|Office 365"
        "outlook.office.com|Office 365"
        "outlook.office365.com|Office 365"
        "mail.office365.com|Office 365"
        "login.microsoftonline.com|Microsoft Login"
        "login.microsoft.com|Microsoft Login"
        "account.live.com|Microsoft Account"
        "account.microsoft.com|Microsoft Account"
        "windows.com|Windows"
        "windows.net|Windows"
        "windowsupdate.com|Windows Update"
        "update.microsoft.com|Windows Update"
        "download.microsoft.com|Microsoft Download"
        "delivery.mp.microsoft.com|Microsoft Delivery"
    )

    # Regex whitelist (type 2)
    local regex=(
        "(.*\.)?teams\.microsoft\.com$|Microsoft Teams wildcard"
        "(.*\.)?sharepoint\.com$|SharePoint"
        "(.*\.)?sfbassets\.com$|Skype for Business"
        "(.*\.)?skype\.com$|Skype"
        "(.*\.)?office\.com$|Office wildcard"
        "(.*\.)?office365\.com$|Office 365 wildcard"
        "(.*\.)?microsoftonline\.com$|Microsoft Login wildcard"
        "(.*\.)?live\.com$|Live wildcard"
        "(.*\.)?outlook\.com$|Outlook wildcard"
        "(.*\.)?windows\.com$|Windows wildcard"
        "(.*\.)?windows\.net$|Windows wildcard"
        "(.*\.)?azure\.com$|Azure"
        "(.*\.)?azure\.net$|Azure"
        "(.*\.)?microsoft365\.com$|Microsoft 365"
    )

    print_info "Adding exact whitelist entries..."
    local exact_success=0
    for entry in "${exact[@]}"; do
        IFS='|' read -r domain comment <<< "$entry"
        if [[ -f "$GRAVITY_DB" ]]; then
            domain_escaped=$(echo "$domain" | sed "s/'/''/g")
            comment_escaped=$(echo "$comment" | sed "s/'/''/g")
            if run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (0, '$domain_escaped', 1, '$comment_escaped');" >> "$LOG_FILE" 2>&1; then
                ((exact_success++))
            fi
        fi
    done

    print_info "Adding regex whitelist entries..."
    local regex_success=0
    for entry in "${regex[@]}"; do
        IFS='|' read -r pattern comment <<< "$entry"
        if [[ -f "$GRAVITY_DB" ]]; then
            pattern_escaped=$(echo "$pattern" | sed "s/'/''/g")
            comment_escaped=$(echo "$comment" | sed "s/'/''/g")
            if run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (2, '$pattern_escaped', 1, '$comment_escaped');" >> "$LOG_FILE" 2>&1; then
                ((regex_success++))
            fi
        fi
    done

    # Verify
    if [[ -f "$GRAVITY_DB" ]]; then
        local exact_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 0;" 2>/dev/null)
        local regex_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 2;" 2>/dev/null)
        print_success "Whitelist added: $exact_count exact, $regex_count regex"
    fi

    run_sudo pihole restartdns >> "$LOG_FILE" 2>&1
}

# ---------- Verify Everything Works -----------------------------------------
verify_installation() {
    print_header "Verifying Installation"

    print_info "Checking Pi-hole DNS configuration..."
    if [[ -f "$PIHOLE_TOML" ]]; then
        if grep -q "127.0.0.1#5335" "$PIHOLE_TOML"; then
            print_success "✓ DNS: Unbound configured in TOML"
        else
            print_error "✗ DNS: Unbound NOT found in TOML"
        fi
    fi

    print_info "Checking database contents..."
    if [[ -f "$GRAVITY_DB" ]] && command -v sqlite3 >/dev/null 2>&1; then
        local adlist_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist;" 2>/dev/null)
        local regex_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 3;" 2>/dev/null)
        local whitelist_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 0;" 2>/dev/null)
        local regex_whitelist_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 2;" 2>/dev/null)

        print_success "✓ Database: $adlist_count blocklists"
        print_success "✓ Database: $regex_count regex blacklist patterns"
        print_success "✓ Database: $whitelist_count exact whitelist entries"
        print_success "✓ Database: $regex_whitelist_count regex whitelist entries"
    fi

    print_info "Testing DNS resolution..."
    if dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
        print_success "✓ Pi-hole responding on port 53"
    else
        print_error "✗ Pi-hole not responding"
    fi

    if dig @127.0.0.1 -p 5335 google.com +short > /dev/null 2>&1; then
        print_success "✓ Unbound responding on port 5335"
    else
        print_error "✗ Unbound not responding"
    fi
}

# ---------- Setup Backups ----------------------------------------------------
setup_backups() {
    print_header "Setting up Automatic Backups"

    run_sudo mkdir -p "$PIHOLE_BACKUP_DIR"

    # Backup script
    run_sudo tee /usr/local/bin/pihole-backup.sh > /dev/null <<'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/pihole"
RETENTION=7
EMAIL_CONFIG="/etc/pihole-backup-email.conf"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/teleporter-$TIMESTAMP.tar.gz"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

send_email() {
    if [[ -f "$EMAIL_CONFIG" ]]; then
        source "$EMAIL_CONFIG"
        if [[ -n "$EMAIL_RECIPIENT" ]] && command -v mail >/dev/null 2>&1; then
            echo -e "$2" | mail -s "$1" "$EMAIL_RECIPIENT"
        fi
    fi
}

echo -e "${YELLOW}Starting Pi-hole backup...${NC}"

if pihole -a -t "$BACKUP_FILE" >/dev/null 2>&1; then
    echo -e "${GREEN}Backup created: $BACKUP_FILE${NC}"

    # Rotate old backups
    mapfile -t backups < <(ls -1t "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null)
    count=${#backups[@]}

    if [[ $count -gt $RETENTION ]]; then
        echo -e "${YELLOW}Rotating backups...${NC}"
        for ((i=$RETENTION; i<$count; i++)); do
            rm -f "${backups[$i]}"
        done
    fi

    send_email "✅ Pi-hole Backup Success" "Backup completed successfully."
    echo -e "${GREEN}Backup process completed${NC}"
else
    echo -e "${RED}Backup creation failed!${NC}"
    send_email "❌ Pi-hole Backup Failed" "Backup creation failed at $(date)."
    exit 1
fi
EOF

    run_sudo chmod +x /usr/local/bin/pihole-backup.sh

    # Cron job
    if ! crontab -l 2>/dev/null | grep -q "pihole-backup.sh"; then
        (crontab -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/pihole-backup.sh > /dev/null 2>&1") | crontab -
        print_success "Backup cron job installed (Sunday 2 AM)"
    fi
}

# ---------- Backup Verification Script ---------------------------------------
create_verification_script() {
    run_sudo tee /usr/local/bin/verify-backup.sh > /dev/null <<'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

BACKUP_DIR="/var/backups/pihole"
RETENTION=7

echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}           Pi-hole Backup Verification Report${NC}"
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo -e "${RED}✗ ERROR: Backup directory does not exist.${NC}"
    exit 1
fi

mapfile -t backups < <(ls -1 "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null | sort)
count=${#backups[@]}

if [[ $count -eq 0 ]]; then
    echo -e "${RED}⚠ No backups found.${NC}"
    exit 0
fi

echo -e "Number of backups: ${GREEN}$count${NC}"
echo ""

failed=0
for b in "${backups[@]}"; do
    size=$(du -h "$b" | cut -f1)
    date=$(stat -c %y "$b" | cut -d. -f1)

    if tar -tzf "$b" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $(basename "$b") [${size}] (${date})"
    else
        echo -e "${RED}✗ CORRUPT${NC} $(basename "$b") [${size}] (${date})"
        failed=$((failed + 1))
    fi
done

echo ""
if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}✓ All backups verified successfully${NC}"
else
    echo -e "${RED}✗ $failed backup(s) are corrupt${NC}"
fi

echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
EOF

    run_sudo chmod +x /usr/local/bin/verify-backup.sh
    print_success "Verification script created"
}

# ---------- Thermal Monitoring -----------------------------------------------
setup_thermal_monitoring() {
    print_header "Setting up Thermal Monitoring"

    if [[ ! -f /sys/class/thermal/thermal_zone0/temp ]]; then
        print_warning "Thermal zone not found - monitoring disabled"
        return 0
    fi

    # Monitoring script
    run_sudo tee /usr/local/bin/thermal-monitor.sh > /dev/null <<'EOF'
#!/bin/bash
TEMP_FILE="/sys/class/thermal/thermal_zone0/temp"
LOG_FILE="/var/log/thermal-monitor.log"
STATE_FILE="/var/lib/thermal-monitor.state"
WARN=75
CRIT=80
EMAIL_CONFIG="/etc/pihole-backup-email.conf"

send_alert() {
    local level="$1"
    local temp="$2"
    local now=$(date +%s)
    local last_alert=0

    [[ -f "$STATE_FILE" ]] && last_alert=$(cat "$STATE_FILE")

    if (( now - last_alert > 1800 )); then
        echo "$now" > "$STATE_FILE"
        if [[ -f "$EMAIL_CONFIG" ]]; then
            source "$EMAIL_CONFIG"
            [[ -n "$EMAIL_RECIPIENT" ]] && echo "Temperature reached ${temp}°C" | mail -s "Pi-hole Thermal Alert [$level]" "$EMAIL_RECIPIENT"
        fi
    fi
}

if [[ ! -f "$TEMP_FILE" ]]; then
    exit 0
fi

temp=$(($(cat "$TEMP_FILE")/1000))
echo "$(date) - Temperature: ${temp}°C" >> "$LOG_FILE"

if [[ $temp -ge $CRIT ]]; then
    send_alert "CRITICAL" "$temp"
elif [[ $temp -ge $WARN ]]; then
    send_alert "WARNING" "$temp"
fi
EOF

    run_sudo chmod +x /usr/local/bin/thermal-monitor.sh

    # Systemd timer
    run_sudo tee /etc/systemd/system/thermal-monitor.service > /dev/null <<EOF
[Unit]
Description=Thermal monitoring for Pi-hole

[Service]
Type=oneshot
ExecStart=/usr/local/bin/thermal-monitor.sh
User=root
EOF

    run_sudo tee /etc/systemd/system/thermal-monitor.timer > /dev/null <<EOF
[Unit]
Description=Run thermal monitor every 5 minutes

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    run_sudo systemctl daemon-reload
    run_sudo systemctl enable thermal-monitor.timer >> "$LOG_FILE" 2>&1
    run_sudo systemctl start thermal-monitor.timer >> "$LOG_FILE" 2>&1
    print_success "Thermal monitoring started"
}

# ---------- Health Dashboard -------------------------------------------------
create_health_dashboard() {
    print_header "Creating Health Dashboard"

    run_sudo tee /usr/local/bin/pihole-health > /dev/null <<'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}              PI-HOLE ULTIMATE HEALTH DASHBOARD${NC}"
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# System Info
echo -e "${CYAN}${BOLD}📊 SYSTEM INFORMATION${NC}"
echo "  Hostname:   $(hostname)"
echo "  Uptime:     $(uptime -p | sed 's/up //')"
echo "  Date:       $(date '+%Y-%m-%d %H:%M:%S')"

# CPU Temp
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    temp=$(($(cat /sys/class/thermal/thermal_zone0/temp)/1000))
    if [[ $temp -ge 80 ]]; then
        color=$RED
    elif [[ $temp -ge 75 ]]; then
        color=$YELLOW
    else
        color=$GREEN
    fi
    echo -e "  CPU Temp:   ${color}${temp}°C${NC}"
fi
echo ""

# Services
echo -e "${CYAN}${BOLD}🔄 SERVICE STATUS${NC}"
for svc in pihole-FTL unbound; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        echo -e "  $svc: ${GREEN}● Active${NC}"
    else
        echo -e "  $svc: ${RED}● Inactive${NC}"
    fi
done
echo ""

# DNS Configuration
echo -e "${CYAN}${BOLD}🌐 DNS CONFIGURATION${NC}"
if [[ -f /etc/pihole/pihole.toml ]]; then
    if grep -q "127.0.0.1#5335" /etc/pihole/pihole.toml; then
        echo -e "  Upstream DNS: ${GREEN}Unbound (127.0.0.1#5335)${NC}"
    else
        echo -e "  Upstream DNS: ${RED}Not configured correctly${NC}"
    fi
fi

# Test DNS
if dig @127.0.0.1 google.com +short >/dev/null 2>&1; then
    echo -e "  Pi-hole:     ${GREEN}✓ Responding${NC}"
else
    echo -e "  Pi-hole:     ${RED}✗ Not responding${NC}"
fi

if dig @127.0.0.1 -p 5335 google.com +short >/dev/null 2>&1; then
    echo -e "  Unbound:     ${GREEN}✓ Responding${NC}"
else
    echo -e "  Unbound:     ${RED}✗ Not responding${NC}"
fi
echo ""

# Database Stats
echo -e "${CYAN}${BOLD}📋 DATABASE STATISTICS${NC}"
if [[ -f /etc/pihole/gravity.db ]] && command -v sqlite3 >/dev/null 2>&1; then
    adlist=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist WHERE enabled = 1;" 2>/dev/null)
    regex=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM domainlist WHERE type = 3 AND enabled = 1;" 2>/dev/null)
    whitelist=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM domainlist WHERE type = 0 AND enabled = 1;" 2>/dev/null)
    regex_whitelist=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM domainlist WHERE type = 2 AND enabled = 1;" 2>/dev/null)

    echo -e "  Blocklists:      ${GREEN}$adlist${NC}"
    echo -e "  Regex Blacklist: ${GREEN}$regex${NC}"
    echo -e "  Whitelist:       ${GREEN}$whitelist${NC}"
    echo -e "  Regex Whitelist: ${GREEN}$regex_whitelist${NC}"
fi
echo ""

echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
EOF

    run_sudo chmod +x /usr/local/bin/pihole-health
    print_success "Health dashboard created"
}

# ---------- Configure Email --------------------------------------------------
configure_email() {
    if [[ "$EMAIL_ENABLED" == "true" ]]; then
        print_header "Configuring Email Alerts"

        run_sudo tee "$EMAIL_CONFIG" > /dev/null <<EOF
EMAIL_RECIPIENT="$EMAIL_RECIPIENT"
SMTP_SERVER="$SMTP_SERVER"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
EOF
        run_sudo chmod 600 "$EMAIL_CONFIG"

        run_sudo apt-get install -y mailutils ssmtp >> "$LOG_FILE" 2>&1

        if [[ -n "$SMTP_SERVER" && -n "$SMTP_USER" ]]; then
            run_sudo tee /etc/ssmtp/ssmtp.conf > /dev/null <<EOF
root=$EMAIL_RECIPIENT
mailhub=$SMTP_SERVER
AuthUser=$SMTP_USER
AuthPass=$SMTP_PASS
UseSTARTTLS=YES
UseTLS=YES
EOF
        fi

        # Test email
        echo "Pi-hole Ultimate Edition v1.6.5 installed successfully" | mail -s "✅ Pi-hole Installation Complete" "$EMAIL_RECIPIENT" 2>/dev/null || true
        print_success "Email configured"
    fi
}

# ---------- Uninstall Script ------------------------------------------------
create_uninstall_script() {
    run_sudo tee /usr/local/bin/uninstall-pihole-ultimate.sh > /dev/null <<'EOF'
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}This will uninstall Pi-hole Ultimate Edition${NC}"
echo -e "${YELLOW}Are you sure? (y/N)${NC}"
read -r confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Stopping services...${NC}"
    systemctl stop pihole-FTL unbound 2>/dev/null

    echo -e "${YELLOW}Removing packages...${NC}"
    apt-get remove --purge -y pihole unbound 2>/dev/null

    echo -e "${YELLOW}Removing configuration...${NC}"
    rm -rf /etc/pihole /etc/unbound /var/backups/pihole /usr/local/bin/pihole-*

    echo -e "${GREEN}Uninstall complete${NC}"
else
    echo -e "${GREEN}Uninstall cancelled${NC}"
fi
EOF
    run_sudo chmod +x /usr/local/bin/uninstall-pihole-ultimate.sh
}

# ---------- Show Summary ----------------------------------------------------
show_summary() {
    print_header "Installation Complete"

    IP_ADDR=$(hostname -I | awk '{print $1}')

    echo -e "${GREEN}${BOLD}✓ Pi-hole Ultimate Edition v1.6.5 installed successfully${NC}"
    echo ""

    echo -e "${WHITE}${BOLD}📌 Commands:${NC}"
    echo -e "  ${CYAN}▶${NC} pihole-health        - Show health dashboard"
    echo -e "  ${CYAN}▶${NC} verify-backup.sh     - Check backup status"
    echo -e "  ${CYAN}▶${NC} pihole -c            - Pi-hole console"
    echo -e "  ${CYAN}▶${NC} pihole -g            - Update gravity"
    echo -e "  ${CYAN}▶${NC} sudo pihole setpassword - Change web password"
    echo ""

    echo -e "${WHITE}${BOLD}🌐 Web Interface:${NC}"
    echo -e "  ${CYAN}•${NC} URL: ${GREEN}http://$IP_ADDR/admin${NC}"
    echo -e "  ${CYAN}•${NC} Default password: ${YELLOW}(empty)${NC}"
    echo -e "  ${CYAN}•${NC} To set password: ${YELLOW}sudo pihole setpassword${NC}"
    echo ""

    # Final verification
    verify_installation

    echo -e "${YELLOW}${BOLD}⚠ RECOMMENDED NEXT STEPS:${NC}"
    echo -e "  1. Set a secure password: ${CYAN}sudo pihole setpassword${NC}"
    echo -e "  2. Access web interface: ${CYAN}http://$IP_ADDR/admin${NC}"
    echo -e "  3. Check Lists > Adlists to see all ${GREEN}$adlist_count blocklists${NC}"
    echo -e "  4. Check Domains > Regex to see all ${GREEN}$regex_count regex patterns${NC}"
    echo ""

    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}         Pi-hole v6 with Unbound - Ready to use!${NC}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
}

# ---------- Main -------------------------------------------------------------
main() {
    print_banner

    check_root
    check_os

    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    print_info "Installation log: $LOG_FILE"

    collect_preferences
    install_dependencies
    install_pihole
    install_unbound
    configure_pihole_v6_dns
    configure_blocklists
    configure_regex
    configure_whitelist
    set_pihole_password
    setup_backups
    create_verification_script
    setup_thermal_monitoring
    create_health_dashboard
    create_uninstall_script
    configure_email

    show_summary
}

main "$@"
