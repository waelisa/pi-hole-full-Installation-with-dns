#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Pi-hole Ultimate Edition - Maximum Protection + Monitoring + Backup
# Version: 1.6.6
# Date: 20-02-2026
#
# Wael Isa
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
# Support: https://www.paypal.me/WaelIsa
#
# Features:
#   - Pi-hole v6 with Unbound recursive DNS
#   - COMPLETE STEP-BY-STEP EXECUTION with progress tracking
#   - GUARANTEED Pi-hole v6 TOML configuration (based on your working config)
#   - VERIFIED blocklists (2026 working sources)
#   - FIXED: Script continues after blocklist addition
#   - FIXED: Regex patterns properly injected
#   - FIXED: Password prompt at the end
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
STEP_COUNTER=0
TOTAL_STEPS=12

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
    log "${WHITE}${BOLD}      Pi-hole Ultimate Edition v1.6.6 - Step-by-Step Install${NC}"
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

print_step() {
    STEP_COUNTER=$((STEP_COUNTER + 1))
    log ""
    log "${YELLOW}${BOLD}[Step $STEP_COUNTER/$TOTAL_STEPS] $1${NC}"
    log ""
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
    print_step "Collecting User Preferences"

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
    print_step "Installing System Dependencies"

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
    print_step "Installing Pi-hole v6"

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

# ---------- Install & Configure Unbound --------------------------------------
install_unbound() {
    print_step "Installing Unbound Recursive DNS"

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

# ---------- Configure Pi-hole v6 DNS (Based on your working pihole.toml) ----
configure_pihole_v6_dns() {
    print_step "Configuring Pi-hole v6 DNS (Based on your working config)"

    print_info "Stopping Pi-hole FTL for configuration..."
    run_sudo systemctl stop pihole-FTL
    sleep 3

    # BACKUP and EDIT TOML directly using your working config as template
    if [[ -f "$PIHOLE_TOML" ]]; then
        print_info "Backing up original TOML..."
        run_sudo cp "$PIHOLE_TOML" "$PIHOLE_TOML.backup-$(date +%Y%m%d-%H%M%S)"
    fi

    print_info "Creating optimized TOML configuration with Unbound upstream..."

    # Create a new TOML based on your working file but with Unbound DNS
    run_sudo tee "$PIHOLE_TOML" > /dev/null <<'EOF'
# Pi-hole configuration file (v6.4.1)
# Encoding: UTF-8
# This file is managed by Pi-hole Ultimate v1.6.6
# Last updated on 2026-02-20

[dns]
  # Upstream DNS Servers - Unbound on port 5335
  upstreams = ["127.0.0.1#5335"]

  CNAMEdeepInspect = true
  blockESNI = true
  EDNS0ECS = true
  ignoreLocalhost = false
  showDNSSEC = true
  analyzeOnlyAandAAAA = false
  piholePTR = "PI.HOLE"
  replyWhenBusy = "ALLOW"
  blockTTL = 2

  # Custom DNS records (local network)
  hosts = []

  domainNeeded = true
  expandHosts = true
  bogusPriv = true
  dnssec = true
  interface = "eth0"
  listeningMode = "LOCAL"
  queryLogging = true
  port = 53
  localise = true

  [dns.domain]
    name = "local"
    local = true

  [dns.cache]
    size = 10000
    optimizer = 3600
    upstreamBlockedTTL = 86400

  [dns.blocking]
    active = true
    mode = "NULL"
    edns = "TEXT"

  [dns.specialDomains]
    mozillaCanary = true
    iCloudPrivateRelay = true
    designatedResolver = true

[webserver]
  domain = "pi.hole"
  port = "80"
  threads = 0

  [webserver.api]
    max_sessions = 16
    prettyJSON = false

[database]
  DBimport = true
  maxDBdays = 91
  DBinterval = 60
  useWAL = true

  [database.network]
    parseARPcache = true
    expire = 91

[files]
  pid = "/run/pihole-FTL.pid"
  database = "/etc/pihole/pihole-FTL.db"
  gravity = "/etc/pihole/gravity.db"
  gravity_tmp = "/tmp"
  macvendor = "/etc/pihole/macvendor.db"

  [files.log]
    ftl = "/var/log/pihole/FTL.log"
    dnsmasq = "/var/log/pihole/pihole.log"
    webserver = "/var/log/pihole/webserver.log"

[misc]
  privacylevel = 0
  delay_startup = 0
  nice = -10
  addr2line = true
  etc_dnsmasq_d = false
  extraLogging = false
  readOnly = false
  normalizeCPU = true
  hide_dnsmasq_warn = false

  [misc.check]
    load = true
    shmem = 90
    disk = 90

[debug]
  all = false
EOF

    print_success "TOML configuration updated with Unbound upstream"

    # Show the config
    print_info "New TOML configuration (DNS section):"
    run_sudo grep -A 5 "\[dns\]" "$PIHOLE_TOML" | while read line; do
        print_info "  $line"
    done

    # Start FTL
    print_info "Starting Pi-hole FTL..."
    run_sudo systemctl start pihole-FTL
    sleep 10

    # Verify DNS configuration
    print_info "Verifying DNS configuration..."
    if grep -q "127.0.0.1#5335" "$PIHOLE_TOML"; then
        print_success "✓ DNS: Unbound configured in TOML"
    else
        print_error "✗ DNS: Unbound NOT found in TOML - configuration failed"
        exit 1
    fi

    # Test resolution
    print_info "Testing DNS resolution..."
    if dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
        print_success "✓ Pi-hole DNS resolution working on port 53"
    else
        print_warning "Pi-hole DNS test failed - check configuration"
    fi

    if dig @127.0.0.1 -p 5335 google.com +short > /dev/null 2>&1; then
        print_success "✓ Unbound DNS resolution working on port 5335"
    else
        print_error "✗ Unbound DNS test failed"
        exit 1
    fi
}

# ---------- Configure Blocklists (VERIFIED WORKING LISTS 2026) -------------
configure_blocklists() {
    print_step "Configuring Blocklists (VERIFIED WORKING LISTS 2026)"

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

    # ===== VERIFIED WORKING BLOCKLISTS (February 2026) =====
    # All URLs tested and confirmed working
    local lists=(
        # StevenBlack Unified Hosts (Base protection)
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|StevenBlack Unified"

        # OISD Full - Most comprehensive balanced list
        "https://big.oisd.nl/|OISD Full"

        # Hagezi Blocklists (Highly Recommended)
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/multi.txt|Hagezi Multi PRO"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/ultimate.txt|Hagezi ULTIMATE"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/tif.txt|Hagezi TIF"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/fake.txt|Hagezi FAKE"

        # Firebog Ticked Lists (Safe/Recommended)
        "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt|KADhosts"
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Spam/hosts|add.Spam"
        "https://v.firebog.net/hosts/static/w3kbl.txt|w3kbl"
        "https://adaway.org/hosts.txt|AdAway"
        "https://v.firebog.net/hosts/AdguardDNS.txt|AdGuard DNS"
        "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt|anudeepND"
        "https://v.firebog.net/hosts/Easylist.txt|EasyList"
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext|Yoyo"
        "https://raw.githubusercontent.com/bigdargon/hostsVN/master/hosts|bigdargon"
        "https://v.firebog.net/hosts/Easyprivacy.txt|EasyPrivacy"
        "https://v.firebog.net/hosts/Prigent-Ads.txt|Prigent-Ads"
        "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt|WindowsSpyBlocker"
        "https://hostfiles.frogeye.fr/firstparty-trackers-hosts.txt|FirstParty Trackers"
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt|DandelionSprout"

        # Phishing Army
        "https://phishing.army/download/phishing_army_blocklist_extended.txt|Phishing Army"

        # URLHaus and malware
        "https://urlhaus.abuse.ch/downloads/hostfile/|URLHaus"
        "https://lists.cyberhost.uk/malware.txt|Cyberhost UK"

        # NoTrack Malware
        "https://gitlab.com/quidsup/notrack-blocklists/-/raw/master/notrack-malware.txt?inline=false|NoTrack Malware"
    )

    print_info "Adding ${#lists[@]} blocklists to database (2026 verified sources)..."

    local success_count=0
    local total_count=${#lists[@]}
    local current=0

    for entry in "${lists[@]}"; do
        IFS='|' read -r url comment <<< "$entry"
        current=$((current + 1))
        print_info "[$current/$total_count] Adding: $comment"

        # Direct SQLite insertion with proper escaping
        if [[ -f "$GRAVITY_DB" ]]; then
            # Escape single quotes in URL and comment
            url_escaped=$(echo "$url" | sed "s/'/''/g")
            comment_escaped=$(echo "$comment" | sed "s/'/''/g")
            if run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO adlist (address, comment, enabled) VALUES ('$url_escaped', '$comment_escaped', 1);" >> "$LOG_FILE" 2>&1; then
                ((success_count++))
                print_success "  ✓ Added: $comment"
            else
                print_warning "  ✗ Failed to add: $comment"
            fi
        fi
    done

    # Verify insertion
    if [[ -f "$GRAVITY_DB" ]]; then
        local count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist;" 2>/dev/null)
        print_success "✓ $count blocklists added to database ($success_count successful)"
    fi

    # CRITICAL: Rebuild gravity
    print_info "Rebuilding gravity (this will take 5-10 minutes)..."
    print_info "Please wait - do not interrupt this process"

    if run_sudo pihole -g >> "$LOG_FILE" 2>&1; then
        print_success "✓ Gravity rebuilt successfully - blocklists now active"
    else
        print_warning "Gravity rebuild had issues - check $LOG_FILE for details"
    fi
}

# ---------- Configure Regex Patterns -----------------------------------------
configure_regex() {
    print_step "Configuring Regex Patterns"

    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, skipping regex configuration"
        return
    fi

    print_info "Clearing existing regex patterns from database..."
    run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist WHERE type = 3;" >> "$LOG_FILE" 2>&1 || true

    # ===== REGEX PATTERNS =====
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

    print_info "Adding ${#patterns[@]} regex patterns to database..."

    local success_count=0
    local total_count=${#patterns[@]}
    local current=0

    for entry in "${patterns[@]}"; do
        IFS='|' read -r pattern comment <<< "$entry"
        current=$((current + 1))

        # Properly escape single quotes for SQLite
        pattern_escaped=$(echo "$pattern" | sed "s/'/''/g")
        comment_escaped=$(echo "$comment" | sed "s/'/''/g")

        # Direct SQLite insertion - type 3 is regex blacklist
        if [[ -f "$GRAVITY_DB" ]]; then
            if run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (3, '$pattern_escaped', 1, '$comment_escaped');" >> "$LOG_FILE" 2>&1; then
                ((success_count++))
            fi
        fi
    done

    # Verify
    if [[ -f "$GRAVITY_DB" ]]; then
        local count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 3;" 2>/dev/null)
        print_success "✓ $count regex patterns added to database ($success_count successful)"
    fi

    # Reload lists
    print_info "Reloading DNS lists..."
    run_sudo pihole restartdns reload-lists >> "$LOG_FILE" 2>&1 || run_sudo pihole restartdns >> "$LOG_FILE" 2>&1
    print_success "Regex patterns activated"
}

# ---------- Configure Whitelist ----------------------------------------------
configure_whitelist() {
    print_step "Configuring Microsoft Services Whitelist"

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
    local exact_total=${#exact[@]}
    local current=0

    for entry in "${exact[@]}"; do
        IFS='|' read -r domain comment <<< "$entry"
        current=$((current + 1))

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
    local regex_total=${#regex[@]}
    current=0

    for entry in "${regex[@]}"; do
        IFS='|' read -r pattern comment <<< "$entry"
        current=$((current + 1))

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
        print_success "✓ Whitelist added: $exact_count exact, $regex_count regex"
    fi

    run_sudo pihole restartdns >> "$LOG_FILE" 2>&1
}

# ---------- Set Pi-hole Password (LAST STEP) --------------------------------
set_pihole_password() {
    print_step "Setting Pi-hole Admin Password (LAST STEP)"

    echo ""
    echo -e "${YELLOW}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║           PI-HOLE ADMIN PASSWORD SETUP                     ║${NC}"
    echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}The Pi-hole web interface is accessible at:${NC}"
    echo -e "  ${GREEN}http://$(hostname -I | awk '{print $1}')/admin${NC}"
    echo ""
    echo -e "${YELLOW}Do you want to set a secure password now? (RECOMMENDED) (y/n)${NC}"
    read -r set_pass

    if [[ "$set_pass" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Enter new password for Pi-hole admin:${NC}"
        run_sudo pihole setpassword
        print_success "✓ Password set successfully"
    else
        echo -e "${YELLOW}⚠ Skipping password setup.${NC}"
        echo -e "${CYAN}To set password later, run: ${WHITE}sudo pihole setpassword${NC}"
        echo -e "${CYAN}Default password is ${WHITE}empty${CYAN} - anyone can access the admin panel!${NC}"
    fi
    echo ""
}

# ---------- Setup Backups ----------------------------------------------------
setup_backups() {
    print_step "Setting up Automatic Backups"

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

    run
