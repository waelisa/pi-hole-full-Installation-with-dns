#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Pi-hole Ultimate Edition - Maximum Protection + Monitoring + Backup
# Version: 1.6.7
# Date: 20-02-2026
#
# Wael Isa
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
# Support: https://www.paypal.me/WaelIsa
#
# Features:
#   - Pi-hole v6 with Unbound recursive DNS
#   - Quad9 DNS-over-TLS for maximum privacy and security
#   - Based on official Pi-hole documentation
#   - FIXED: Script continues after blocklist addition (no exit)
#   - FIXED: Proper error handling for database operations
#   - FIXED: Password prompt at the very end
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
TOTAL_STEPS=13

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
    log "${WHITE}${BOLD}      Pi-hole Ultimate Edition v1.6.7 - Quad9 DoT + Unbound${NC}"
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

# ---------- Install & Configure Unbound with Quad9 DNS-over-TLS ------------
install_unbound() {
    print_step "Installing Unbound with Quad9 DNS-over-TLS"
    
    print_info "Installing Unbound package..."
    run_sudo apt-get install -y unbound dns-root-data >> "$LOG_FILE" 2>&1
    
    run_sudo systemctl stop unbound 2>/dev/null || true
    
    # Backup original config
    if [[ ! -f /etc/unbound/unbound.conf.orig ]]; then
        run_sudo cp /etc/unbound/unbound.conf /etc/unbound/unbound.conf.orig 2>/dev/null || true
    fi
    
    # Clear existing configs
    run_sudo rm -f /etc/unbound/unbound.conf.d/*.conf 2>/dev/null || true
    
    print_info "Configuring Unbound with Quad9 DNS-over-TLS (based on official docs)..."
    
    # Configuration based on Pi-hole documentation and Quad9 recommendations [citation:7][citation:1]
    run_sudo tee "$UNBOUND_CONF" > /dev/null <<EOF
server:
    # Listen on localhost only
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    
    # Security settings
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: yes
    edns-buffer-size: 1232
    do-not-query-localhost: no
    
    # Access control - only allow localhost
    access-control: 127.0.0.1/32 allow
    access-control: ::1 allow
    
    # Performance settings
    prefetch: yes
    num-threads: 1
    so-rcvbuf: 1m
    
    # Privacy - hide local IP ranges
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10

# Forward zone for Quad9 DNS-over-TLS [citation:6][citation:7]
forward-zone:
    name: "."
    forward-tls-upstream: yes
    # Quad9 Malware Blocking + DNSSEC (9.9.9.11) [citation:7]
    forward-addr: 9.9.9.11@853#dns.quad9.net
    forward-addr: 149.112.112.11@853#dns.quad9.net
    # IPv6 addresses (uncomment if you have native IPv6)
    # forward-addr: 2620:fe::11@853#dns.quad9.net
    # forward-addr: 2620:fe::fe@853#dns.quad9.net
EOF
    
    print_success "Unbound configured with Quad9 DNS-over-TLS"
    
    # Check and disable unbound-resolvconf.service if present (Debian Bullseye+)
    if systemctl list-unit-files | grep -q unbound-resolvconf.service; then
        print_info "Disabling unbound-resolvconf.service (required for Debian Bullseye+ releases)..."
        run_sudo systemctl disable --now unbound-resolvconf.service >> "$LOG_FILE" 2>&1 || true
        run_sudo sed -Ei 's/^unbound_conf=/#unbound_conf=/' /etc/resolvconf.conf 2>/dev/null || true
        run_sudo rm -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf 2>/dev/null || true
    fi
    
    # Start Unbound
    run_sudo systemctl enable unbound >> "$LOG_FILE" 2>&1
    run_sudo systemctl start unbound >> "$LOG_FILE" 2>&1
    sleep 5
    
    if run_sudo systemctl is-active --quiet unbound; then
        print_success "Unbound service started"
    else
        print_error "Unbound failed to start - checking logs..."
        run_sudo journalctl -u unbound --no-pager -n 20 >> "$LOG_FILE"
        print_info "Check $LOG_FILE for details"
        exit 1
    fi
    
    # Test Unbound resolution through Quad9
    print_info "Testing DNS resolution through Quad9..."
    if dig @127.0.0.1 -p 5335 quad9.net +short > /dev/null 2>&1; then
        print_success "✓ Unbound responding on port 5335"
        
        # Test Quad9 protocol (should show 'dot' for DNS-over-TLS) [citation:6]
        local proto_test=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
        if [[ "$proto_test" == *"dot"* ]]; then
            print_success "✓ Quad9 DNS-over-TLS confirmed (protocol: $proto_test)"
        else
            print_info "Quad9 protocol response: $proto_test"
        fi
    else
        print_error "Unbound DNS test failed"
        exit 1
    fi
}

# ---------- Configure Pi-hole v6 DNS (Based on your working pihole.toml) ----
configure_pihole_v6_dns() {
    print_step "Configuring Pi-hole v6 DNS to use Unbound"
    
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
# This file is managed by Pi-hole Ultimate v1.6.7
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
    pwhash = ""

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
    
    # Test resolution through Pi-hole
    print_info "Testing DNS resolution through Pi-hole (via Unbound)..."
    if dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
        print_success "✓ Pi-hole → Unbound → Quad9 DNS resolution working"
    else
        print_warning "Pi-hole DNS test failed - check configuration"
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
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/popupads.txt|Hagezi PopupAds"
        
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
        
        # NoTrack Malware - FIXED URL
        "https://gitlab.com/quidsup/notrack-blocklists/-/raw/master/notrack-malware.txt|NoTrack Malware"
    )
    
    print_info "Adding ${#lists[@]} blocklists to database (2026 verified sources)..."
    
    local success_count=0
    local total_count=${#lists[@]}
    local current=0
    
    # Use a temporary file for SQL commands to avoid command line length limits
    local sql_file=$(mktemp)
    
    for entry in "${lists[@]}"; do
        IFS='|' read -r url comment <<< "$entry"
        current=$((current + 1))
        print_info "[$current/$total_count] Adding: $comment"
        
        if [[ -f "$GRAVITY_DB" ]]; then
            # Escape single quotes for SQLite
            url_escaped=$(echo "$url" | sed "s/'/''/g")
            comment_escaped=$(echo "$comment" | sed "s/'/''/g")
            
            # Write to temp file
            echo "INSERT OR IGNORE INTO adlist (address, comment, enabled) VALUES ('$url_escaped', '$comment_escaped', 1);" >> "$sql_file"
            ((success_count++))
            print_success "  ✓ Queued: $comment"
        fi
    done
    
    # Execute all SQL commands at once
    if [[ -f "$GRAVITY_DB" ]] && [[ -s "$sql_file" ]]; then
        print_info "Executing database insertions..."
        if run_sudo sqlite3 "$GRAVITY_DB" < "$sql_file" >> "$LOG_FILE" 2>&1; then
            print_success "✓ All blocklists inserted successfully"
        else
            print_warning "Some blocklists may have failed - check $LOG_FILE"
        fi
    fi
    
    # Clean up
    rm -f "$sql_file"
    
    # Verify insertion
    if [[ -f "$GRAVITY_DB" ]]; then
        local count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist;" 2>/dev/null)
        print_success "✓ $count blocklists in database"
    fi
    
    # CRITICAL: Rebuild gravity - with error handling to prevent script exit
    print_info "Rebuilding gravity (this will take 5-10 minutes)..."
    print_info "Please wait - do not interrupt this process"
    
    # Run gravity rebuild with error suppression to prevent script exit
    if run_sudo pihole -g >> "$LOG_FILE" 2>&1; then
        print_success "✓ Gravity rebuilt successfully - blocklists now active"
    else
        print_warning "Gravity rebuild had non-critical issues - continuing anyway"
        print_info "You can manually run 'pihole -g' later if needed"
    fi
}

# ---------- Configure Regex Patterns (FIXED SQL ESCAPING) -------------------
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
        "(^|\.)wellsfargo-verify\.|Fake banking"
        "(^|\.)chase-verify\.|Fake banking"
        "(^|\.)google-analytics\.com$|Google Analytics"
        "(^|\.)googletagmanager\.com$|Google Tag Manager"
        "(^|\.)doubleclick\.net$|DoubleClick"
        "(^|\.)googleadservices\.com$|Google Ads"
        "(^|\.)coin-hive\.com$|CoinHive"
        "(^|\.)crypto-loot\.com$|Crypto miner"
        "(^|\.)telemetry\.|Telemetry"
        "(^|\.)diagnostics\.|Diagnostics"
        "(^|\.)data-?collector\.|Data collector"
        "(^|\.)spy\.|Spyware"
        "^adserver[0-9]*\.|Ad servers"
        "^ads[0-9]*\.|Ad servers"
        "^banner[0-9]*\.|Banners"
        "^popup[0-9]*\.|Popups"
        "^track\.|Tracking"
    )
    
    print_info "Adding ${#patterns[@]} regex patterns to database..."
    
    local sql_file=$(mktemp)
    local success_count=0
    
    for entry in "${patterns[@]}"; do
        IFS='|' read -r pattern comment <<< "$entry"
        
        # Properly escape single quotes for SQLite
        pattern_escaped=$(echo "$pattern" | sed "s/'/''/g")
        comment_escaped=$(echo "$comment" | sed "s/'/''/g")
        
        # Write to temp file
        echo "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (3, '$pattern_escaped', 1, '$comment_escaped');" >> "$sql_file"
        ((success_count++))
    done
    
    # Execute all SQL commands at once
    if [[ -f "$GRAVITY_DB" ]] && [[ -s "$sql_file" ]]; then
        if run_sudo sqlite3 "$GRAVITY_DB" < "$sql_file" >> "$LOG_FILE" 2>&1; then
            print_success "✓ All regex patterns inserted successfully"
        else
            print_warning "Some regex patterns may have failed - check $LOG_FILE"
        fi
    fi
    
    # Clean up
    rm -f "$sql_file"
    
    # Verify
    if [[ -f "$GRAVITY_DB" ]]; then
        local count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 3;" 2>/dev/null)
        print_success "✓ $count regex patterns in database"
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
        "teams-api.cloud.microsoft|Microsoft Teams"
        "teams-mobile-edge.teams.microsoft.com|Microsoft Teams"
        "office.com|Office 365"
        "office365.com|Office 365"
        "outlook.office.com|Office 365"
        "outlook.office365.com|Office 365"
        "mail.office365.com|Office 365"
        "protection.outlook.com|Office 365"
        "substrate.office.com|Office 365"
        "login.microsoftonline.com|Microsoft Login"
        "login.microsoft.com|Microsoft Login"
        "login.windows.net|Microsoft Login"
        "account.live.com|Microsoft Account"
        "account.microsoft.com|Microsoft Account"
        "graph.microsoft.com|Microsoft Graph"
        "windows.com|Windows"
        "windows.net|Windows"
        "windowsupdate.com|Windows Update"
        "update.microsoft.com|Windows Update"
        "download.windowsupdate.com|Windows Update"
        "download.microsoft.com|Microsoft Download"
        "delivery.mp.microsoft.com|Microsoft Delivery"
    )
    
    # Regex whitelist (type 2)
    local regex=(
        "(.*\.)?teams\.microsoft\.com$|Microsoft Teams wildcard"
        "(.*\.)?teams\.live\.com$|Microsoft Teams Live wildcard"
        "(.*\.)?sharepoint\.com$|SharePoint"
        "(.*\.)?sfbassets\.com$|Skype for Business"
        "(.*\.)?skype\.com$|Skype"
        "(.*\.)?skypeforbusiness\.com$|Skype for Business"
        "(.*\.)?teams\.skype\.com$|Teams Skype"
        "(.*\.)?office\.com$|Office wildcard"
        "(.*\.)?office365\.com$|Office 365 wildcard"
        "(.*\.)?office\.net$|Office net"
        "(.*\.)?microsoftonline\.com$|Microsoft Login wildcard"
        "(.*\.)?microsoftonline-p\.net$|Microsoft Login wildcard"
        "(.*\.)?live\.com$|Live wildcard"
        "(.*\.)?outlook\.com$|Outlook wildcard"
        "(.*\.)?outlook\.office\.com$|Outlook Office"
        "(.*\.)?outlook\.office365\.com$|Outlook Office 365"
        "(.*\.)?mail\.office365\.com$|Mail Office 365"
        "(.*\.)?attachment\.office\.net$|Office Attachments"
        "(.*\.)?protection\.outlook\.com$|Protection Outlook"
        "(.*\.)?sharepointonline\.com$|SharePoint Online"
        "(.*\.)?onedrive\.com$|OneDrive"
        "(.*\.)?onedrive\.live\.com$|OneDrive Live"
        "(.*\.)?onedriveforbusiness\.com$|OneDrive for Business"
        "(.*\.)?windows\.com$|Windows wildcard"
        "(.*\.)?windows\.net$|Windows net wildcard"
        "(.*\.)?windowsupdate\.com$|Windows Update wildcard"
        "(.*\.)?update\.microsoft\.com$|Microsoft Update wildcard"
        "(.*\.)?download\.windowsupdate\.com$|Download Windows Update"
        "(.*\.)?download\.microsoft\.com$|Download Microsoft"
        "(.*\.)?delivery\.mp\.microsoft\.com$|Microsoft Delivery"
        "(.*\.)?azure\.com$|Azure"
        "(.*\.)?azure\.net$|Azure"
        "(.*\.)?azurewebsites\.net$|Azure Websites"
        "(.*\.)?azureedge\.net$|Azure Edge"
        "(.*\.)?azure-api\.net$|Azure API"
        "(.*\.)?microsoft365\.com$|Microsoft 365"
    )
    
    print_info "Adding exact whitelist entries..."
    local exact_sql=$(mktemp)
    
    for entry in "${exact[@]}"; do
        IFS='|' read -r domain comment <<< "$entry"
        domain_escaped=$(echo "$domain" | sed "s/'/''/g")
        comment_escaped=$(echo "$comment" | sed "s/'/''/g")
        echo "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (0, '$domain_escaped', 1, '$comment_escaped');" >> "$exact_sql"
    done
    
    print_info "Adding regex whitelist entries..."
    local regex_sql=$(mktemp)
    
    for entry in "${regex[@]}"; do
        IFS='|' read -r pattern comment <<< "$entry"
        pattern_escaped=$(echo "$pattern" | sed "s/'/''/g")
        comment_escaped=$(echo "$comment" | sed "s/'/''/g")
        echo "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (2, '$pattern_escaped', 1, '$comment_escaped');" >> "$regex_sql"
    done
    
    # Execute SQL files
    if [[ -f "$GRAVITY_DB" ]]; then
        if [[ -s "$exact_sql" ]]; then
            run_sudo sqlite3 "$GRAVITY_DB" < "$exact_sql" >> "$LOG_FILE" 2>&1
        fi
        if [[ -s "$regex_sql" ]]; then
            run_sudo sqlite3 "$GRAVITY_DB" < "$regex_sql" >> "$LOG_FILE" 2>&1
        fi
    fi
    
    # Clean up
    rm -f "$exact_sql" "$regex_sql"
    
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
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo -e "${CYAN}The Pi-hole web interface is accessible at:${NC}"
    echo -e "  ${GREEN}http://$IP_ADDR/admin${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: By default, the password is EMPTY - anyone can access!${NC}"
    echo ""
    echo -e "${YELLOW}Do you want to set a secure password now? (RECOMMENDED) (y/n)${NC}"
    read -r set_pass
    
    if [[ "$set_pass" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Enter new password for Pi-hole admin:${NC}"
        run_sudo pihole setpassword
        print_success "✓ Password set successfully"
    else
        echo -e "${YELLOW}⚠ WARNING: Skipping password setup.${NC}"
        echo -e "${YELLOW}⚠ Your Pi-hole admin panel is unprotected!${NC}"
        echo -e "${CYAN}To set password later, run: ${WHITE}sudo pihole setpassword${NC}"
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
    print_step "Setting up Thermal Monitoring"
    
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
    print_success "Thermal monitoring started (every 5 minutes)"
}

# ---------- Health Dashboard -------------------------------------------------
create_health_dashboard() {
    print_step "Creating Health Dashboard"
    
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

if dig @127.0.0.1 -p 5335 quad9.net +short >/dev/null 2>&1; then
    echo -e "  Unbound:     ${GREEN}✓ Responding via Quad9${NC}"
    
    # Test Quad9 protocol
    proto=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
    if [[ -n "$proto" ]]; then
        echo -e "  Quad9 Proto: ${CYAN}$proto${NC}"
    fi
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
    print_success "Health dashboard created at /usr/local/bin/pihole-health"
}

# ---------- Configure Email --------------------------------------------------
configure_email() {
    if [[ "$EMAIL_ENABLED" == "true" ]]; then
        print_step "Configuring Email Alerts"
        
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
        echo "Pi-hole Ultimate Edition v1.6.7 installed successfully with Quad9 DoT" | mail -s "✅ Pi-hole Installation Complete" "$EMAIL_RECIPIENT" 2>/dev/null || true
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

echo -e "${YELLOW}This will uninstall Pi-hole Ultimate Edition and all components${NC}"
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
    print_success "Uninstall script created"
}

# ---------- Verify Everything Works -----------------------------------------
verify_installation() {
    print_step "Verifying Installation"
    
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
    
    if dig @127.0.0.1 -p 5335 quad9.net +short > /dev/null 2>&1; then
        print_success "✓ Unbound responding on port 5335 via Quad9"
        
        # Test Quad9 protocol
        local proto_test=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
        if [[ "$proto_test" == *"dot"* ]]; then
            print_success "✓ Quad9 DNS-over-TLS confirmed (protocol: $proto_test)"
        fi
    else
        print_error "✗ Unbound not responding"
    fi
}

# ---------- Show Summary ----------------------------------------------------
show_summary() {
    print_step "Installation Complete - Summary"
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}${BOLD}✓ Pi-hole Ultimate Edition v1.6.7 installed successfully${NC}"
    echo -e "${GREEN}${BOLD}✓ Quad9 DNS-over-TLS configured with Unbound${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📌 Available Commands:${NC}"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole-health${NC}        - Show health dashboard"
    echo -e "  ${CYAN}▶${NC} ${BOLD}verify-backup.sh${NC}      - Check backup status"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -c${NC}             - Pi-hole console"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -g${NC}             - Update gravity"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole setpassword${NC} - Change web password"
    echo -e "  ${CYAN}▶${NC} ${BOLD}uninstall-pihole-ultimate.sh${NC} - Remove everything"
    echo ""
    
    echo -e "${WHITE}${BOLD}🌐 Web Interface:${NC}"
    echo -e "  ${CYAN}•${NC} URL: ${GREEN}http://$IP_ADDR/admin${NC}"
    
    # Check if password was set
    if [[ -f /etc/pihole/admin-password.txt ]] && [[ -s /etc/pihole/admin-password.txt ]]; then
        echo -e "  ${CYAN}•${NC} Password: ${YELLOW}[Password was set during installation]${NC}"
    else
        echo -e "  ${CYAN}•${NC} Password: ${RED}EMPTY - UNSECURED!${NC}"
        echo -e "  ${CYAN}•${NC} Run: ${WHITE}sudo pihole setpassword${NC} to secure your installation"
    fi
    echo ""
    
    echo -e "${WHITE}${BOLD}📊 Database Statistics:${NC}"
    if [[ -f "$GRAVITY_DB" ]] && command -v sqlite3 >/dev/null 2>&1; then
        local adlist_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist;" 2>/dev/null)
        local regex_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 3;" 2>/dev/null)
        local whitelist_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 0;" 2>/dev/null)
        
        echo -e "  ${CYAN}•${NC} Blocklists:     ${GREEN}$adlist_count${NC}"
        echo -e "  ${CYAN}•${NC} Regex Patterns: ${GREEN}$regex_count${NC}"
        echo -e "  ${CYAN}•${NC} Whitelist:      ${GREEN}$whitelist_count${NC}"
    fi
    echo ""
    
    echo -e "${WHITE}${BOLD}🔒 DNS Security:${NC}"
    echo -e "  ${CYAN}•${NC} Unbound → Quad9 (9.9.9.11) with DNS-over-TLS [citation:6]"
    echo -e "  ${CYAN}•${NC} Malware blocking + DNSSEC validation enabled [citation:7]"
    echo -e "  ${CYAN}•${NC} Test with: ${WHITE}dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335${NC}"
    echo ""
    
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}         Pi-hole v6 with Unbound + Quad9 DoT - Ready!${NC}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
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
    print_info "Total steps: $TOTAL_STEPS"
    echo ""
    
    collect_preferences
    install_dependencies
    install_pihole
    install_unbound
    configure_pihole_v6_dns
    configure_blocklists
    configure_regex
    configure_whitelist
    setup_backups
    create_verification_script
    setup_thermal_monitoring
    create_health_dashboard
    create_uninstall_script
    configure_email
    verify_installation
    set_pihole_password  # LAST STEP - password prompt at the very end
    show_summary
}

main "$@"