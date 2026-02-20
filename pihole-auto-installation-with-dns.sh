#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Pi-hole Ultimate Edition - Maximum Protection + Monitoring + Backup
# Version: 1.5.9
# Date: 20-02-2026
#
# Wael Isa
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
# Support: https://www.paypal.me/WaelIsa
#
# Features:
#   - Pi-hole with Unbound recursive DNS
#   - Maximum ad/tracker blocking with premium blocklists
#   - Sophisticated regex patterns for malware/phishing
#   - Comprehensive whitelist for Microsoft Teams, Office 365, Windows
#   - Thermal monitoring with email alerts
#   - Automatic backups with retention management
#   - Professional health dashboard with color coding
#   - Fixed: Wildcard whitelist using regex entries
#   - Fixed: Unbound root key permissions
#   - Fixed: Better error handling and logging
#   - New: Automatic root hints updater (monthly cron)
#   - New: Pre-installation configuration collection
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
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------- Configuration -----------------------------------------------------
PIHOLE_BACKUP_DIR="/var/backups/pihole"
BACKUP_RETENTION_COUNT=7
THERMAL_LOG="/var/log/thermal-monitor.log"
THERMAL_STATE="/var/lib/thermal-monitor.state"
ALERT_COOLDOWN_SECONDS=1800  # 30 minutes (reduced from 1 hour for critical alerts)
TEMP_WARN=75
TEMP_CRIT=80
UNBOUND_CONF="/etc/unbound/unbound.conf.d/pi-hole.conf"
EMAIL_CONFIG="/etc/pihole-backup-email.conf"
REGEX_FILE="/etc/pihole/regex.list"
WHITELIST_FILE="/etc/pihole/whitelist.txt"
WHITELIST_REGEX_FILE="/etc/pihole/whitelist-regex.txt"
BLOCKLIST_DIR="/etc/pihole/adlists.list"
SETUP_VARS="/etc/pihole/setupVars.conf"
LOG_FILE="/var/log/pihole-ultimate-install.log"
ROOT_HINTS="/usr/share/dns/root.hints"

# ---------- User Preferences (collected at start) ----------------------------
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
    log "${CYAN}${BOLD}"
    log "██████╗ ██╗      ██████╗ ██╗     ███████╗"
    log "██╔══██╗██║     ██╔═══██╗██║     ██╔════╝"
    log "██████╔╝██║     ██║   ██║██║     █████╗  "
    log "██╔═══╝ ██║     ██║   ██║██║     ██╔══╝  "
    log "██║     ███████╗╚██████╔╝███████╗███████╗"
    log "╚═╝     ╚══════╝ ╚═════╝ ╚══════╝╚══════╝"
    log "${NC}"
    log "${WHITE}${BOLD}        Ultimate Edition v1.5.9 - Maximum Protection${NC}"
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_os() {
    print_info "Checking operating system compatibility..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "debian" && "$ID" != "ubuntu" && "$ID" != "raspbian" ]]; then
            print_warning "This script is designed for Debian/Ubuntu/Raspbian systems."
            print_warning "Continuing anyway - some features may not work correctly."
        else
            print_success "Running on $PRETTY_NAME"
        fi
    fi
}

send_email() {
    local subject="$1"
    local body="$2"
    if [[ -f "$EMAIL_CONFIG" ]]; then
        source "$EMAIL_CONFIG"
        if [[ -n "$EMAIL_RECIPIENT" ]] && command -v mail >/dev/null 2>&1; then
            echo "$body" | mail -s "$subject" "$EMAIL_RECIPIENT" 2>/dev/null || print_warning "Failed to send email"
        fi
    fi
}

run_command() {
    local cmd="$1"
    local error_msg="$2"

    print_info "Running: $cmd"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        print_error "$error_msg"
        print_info "Check $LOG_FILE for details"
        return 1
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

    # Create Pi-hole setup vars if not exists
    if [[ ! -f "$SETUP_VARS" ]]; then
        mkdir -p /etc/pihole
        cat > "$SETUP_VARS" <<EOF
PIHOLE_INTERFACE=eth0
IPV4_ADDRESS=0.0.0.0
IPV6_ADDRESS=
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
BLOCKING_ENABLED=true
WEBPASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "pihole")
EOF
        print_success "Created Pi-hole setup variables"
    fi
}

# ---------- Install Dependencies --------------------------------------------
install_dependencies() {
    print_header "Installing System Dependencies"

    print_info "Updating package lists..."
    apt-get update >> "$LOG_FILE" 2>&1

    print_info "Installing required packages..."
    apt-get install -y curl wget git unzip nano \
        bc jq mailutils ssmtp \
        openssl ca-certificates \
        systemd >> "$LOG_FILE" 2>&1

    print_success "Dependencies installed"
}

# ---------- Install Pi-hole --------------------------------------------------
install_pihole() {
    print_header "Installing Pi-hole"

    if ! command -v pihole >/dev/null 2>&1; then
        print_info "Downloading and installing Pi-hole..."

        # Create unattended setup config
        cat > /etc/pihole/unattended.conf <<EOF
PIHOLE_INTERFACE=eth0
PIHOLE_DNS_1=127.0.0.1#5335
PIHOLE_DNS_2=127.0.0.1#5335
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
BLOCKING_ENABLED=true
EOF

        # Run installer with error handling
        if curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended >> "$LOG_FILE" 2>&1; then
            print_success "Pi-hole installed successfully"
        else
            print_error "Pi-hole installation failed"
            print_info "Check $LOG_FILE for details"
            exit 1
        fi
    else
        print_info "Pi-hole already installed, skipping."
    fi

    # Set random password if not set
    if [[ -z $(pihole -a -p -s 2>/dev/null) ]]; then
        local password=$(openssl rand -base64 12)
        echo "pihole -a -p $password" | bash >> "$LOG_FILE" 2>&1
        print_info "Pi-hole web password: $password"
        echo "$password" > /etc/pihole/admin-password.txt
        chmod 600 /etc/pihole/admin-password.txt
    fi
}

# ---------- Install & Configure Unbound --------------------------------------
install_unbound() {
    print_header "Installing Unbound Recursive DNS"

    print_info "Installing Unbound package..."
    apt-get install -y unbound dns-root-data >> "$LOG_FILE" 2>&1

    # Backup original config
    if [[ ! -f /etc/unbound/unbound.conf.orig ]]; then
        cp /etc/unbound/unbound.conf /etc/unbound/unbound.conf.orig
        print_info "Original Unbound config backed up"
    fi

    print_info "Configuring Unbound for recursive DNS..."
    cat > "$UNBOUND_CONF" <<EOF
server:
    # Listen only on localhost
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes

    # Allow queries from local network
    access-control: 127.0.0.0/8 allow
    access-control: 192.168.0.0/16 allow
    access-control: 172.16.0.0/12 allow
    access-control: 10.0.0.0/8 allow

    # Recursive DNS with root hints
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: no
    cache-min-ttl: 3600
    cache-max-ttl: 86400
    prefetch: yes
    num-threads: 2
    msg-cache-size: 50m
    rrset-cache-size: 100m
    neg-cache-size: 5m
    so-rcvbuf: 1m

    # Root hints (updated automatically)
    root-hints: $ROOT_HINTS

    # Security
    hide-http-user-agent: yes
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes

    # DNSSEC
    auto-trust-anchor-file: /var/lib/unbound/root.key
    val-clean-additional: yes
    val-permissive-mode: no
    val-log-level: 2

remote-control:
    control-enable: no
EOF
    print_success "Unbound configured"

    # Download root hints if missing
    if [[ ! -f "$ROOT_HINTS" ]]; then
        mkdir -p /usr/share/dns
        print_info "Downloading root hints..."
        if curl -o "$ROOT_HINTS" https://www.internic.net/domain/named.cache >> "$LOG_FILE" 2>&1; then
            print_success "Root hints downloaded"
        else
            print_warning "Failed to download root hints, using package default"
        fi
    fi

    # Fix permissions for root.key
    if [[ -f /var/lib/unbound/root.key ]]; then
        chown unbound:unbound /var/lib/unbound/root.key
        chmod 644 /var/lib/unbound/root.key
    fi

    # Create monthly root hints updater
    cat > /etc/cron.monthly/update-root-hints <<'EOF'
#!/bin/bash
ROOT_HINTS="/usr/share/dns/root.hints"
TEMP_HINTS="${ROOT_HINTS}.new"
curl -o "$TEMP_HINTS" https://www.internic.net/domain/named.cache 2>/dev/null
if [[ $? -eq 0 && -s "$TEMP_HINTS" ]]; then
    mv "$TEMP_HINTS" "$ROOT_HINTS"
    systemctl restart unbound
fi
EOF
    chmod +x /etc/cron.monthly/update-root-hints
    print_success "Monthly root hints updater created"

    systemctl enable unbound >> "$LOG_FILE" 2>&1
    systemctl restart unbound >> "$LOG_FILE" 2>&1

    if systemctl is-active --quiet unbound; then
        print_success "Unbound service started"
    else
        print_error "Unbound failed to start"
        journalctl -u unbound --no-pager -n 20 >> "$LOG_FILE"
        exit 1
    fi

    # Point Pi-hole to Unbound
    print_info "Configuring Pi-hole to use Unbound..."
    pihole -a setdns 127.0.0.1#5335 >> "$LOG_FILE" 2>&1
    pihole -a setconditionallogging false >> "$LOG_FILE" 2>&1
    print_success "Pi-hole DNS set to Unbound (127.0.0.1#5335)"
}

# ---------- Maximum Blocklists -----------------------------------------------
configure_blocklists() {
    print_header "Configuring Maximum Ad/Tracker Blocklists"

    print_info "Adding premium blocklists for maximum protection..."

    # Backup existing adlists
    if [[ -f "$BLOCKLIST_DIR" ]]; then
        cp "$BLOCKLIST_DIR" "$BLOCKLIST_DIR.backup"
        print_info "Existing adlists backed up"
    fi

    # Comprehensive blocklists with verification
    cat > "$BLOCKLIST_DIR" <<'EOF'
# OISD Full - Most comprehensive balanced blocklist
https://big.oisd.nl/

# Hagezi - Ultimate protection list
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/multi.txt

# 1Hosts Pro - Maximum protection
https://raw.githubusercontent.com/badmojr/1Hosts/master/Pro/hosts.txt

# NoTracking - Blocks tracking and analytics
https://raw.githubusercontent.com/notracking/hosts-blocklists/master/hostnames.txt

# EasyList - Standard ad blocking
https://easylist.to/easylist/easylist.txt

# EasyPrivacy - Privacy protection
https://easylist.to/easylist/easyprivacy.txt

# AdGuard DNS filter
https://adguardteam.github.io/AdGuardSDNSFilter/Files/filter.txt

# WindowsSpyBlocker - Blocks Windows telemetry
https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt

# GoodbyeAds - Comprehensive ad blocking
https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Hosts/GoodbyeAds.txt

# Phishing Army - Blocks phishing domains
https://phishing.army/download/phishing_army_blocklist_extended.txt

# D3Hosts - Blocks malware and ads
https://raw.githubusercontent.com/d3ward/d3host/master/hosts

# URLVir - Malware protection
https://raw.githubusercontent.com/URLVir/URLVir-List/main/urlvir-domains.txt

# Ransomware Tracker
https://ransomwaretracker.abuse.ch/downloads/RW_DOMBL.txt

# CoinBlocker - Cryptominer blocking
https://gitlab.com/ZeroDot1/CoinBlockerLists/raw/master/hosts_browser

# Scam Blocklist
https://raw.githubusercontent.com/ShadowWhisperer/BlockLists/master/Lists/Scam

# Tracking Aggressive
https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/TrackingFilter/sections/tracking_servers.txt

# The Big List of Hacked Malware Web Sites
https://raw.githubusercontent.com/mitchellkrogza/The-Big-List-of-Hacked-Malware-Web-Sites/master/hosts

# NoCoin - Cryptocurrency mining blocklist
https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/nocoin.txt

# StevenBlack Unified hosts
https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn/hosts
EOF

    # Count and validate blocklists
    list_count=$(grep -v '^#' "$BLOCKLIST_DIR" | grep -v '^$' | wc -l)
    print_success "$list_count premium blocklists added"

    # Update gravity with progress indication
    print_info "Updating Pi-hole gravity with new blocklists (this may take a few minutes)..."
    if pihole -g >> "$LOG_FILE" 2>&1; then
        print_success "Gravity updated successfully"
    else
        print_error "Gravity update failed"
        print_info "Check $LOG_FILE for details"
    fi
}

# ---------- Regex Patterns ---------------------------------------------------
configure_regex() {
    print_header "Configuring Sophisticated Regex Patterns"

    print_info "Adding advanced regex patterns for malware/phishing protection..."

    cat > "$REGEX_FILE" <<'EOF'
# === MALWARE & PHISHING PATTERNS ===
(^|\.)bit\.ly$                                      # URL shorteners (phishing risk)
(^|\.)tinyurl\.com$                                 # URL shorteners
(^|\.)goo\.gl$                                      # Google URL shortener
(^|\.)ow\.ly$                                       # URL shortener
(^|\.)malware[a-zA-Z0-9-]*\.                        # Generic malware domains
(^|\.)phish[a-zA-Z0-9-]*\.                          # Generic phishing domains
(^|\.)ransom[a-zA-Z0-9-]*\.                         # Generic ransomware domains
(^|\.)cryptolocker\.                                # CryptoLocker
(^|\.)paypal-secure\.                               # Fake PayPal
(^|\.)apple-id\.                                    # Fake Apple ID
(^|\.)amazon-login\.                                # Fake Amazon login
(^|\.)bankofamerica-verify\.                        # Fake banking
(^|\.)wellsfargo-verify\.                           # Fake banking
(^|\.)chase-verify\.                                # Fake banking
(^|\.)dhl-parcel\.                                  # Fake shipping
(^|\.)fedex-delivery\.                              # Fake shipping
(^|\.)ups-delivery\.                                # Fake shipping
(^|\.)usps-delivery\.                               # Fake shipping

# === TRACKING & ANALYTICS ===
(^|\.)google-analytics\.com$                        # Google Analytics
(^|\.)googletagmanager\.com$                        # Google Tag Manager
(^|\.)facebook\.com\/tr\/?                          # Facebook Pixel
(^|\.)connect\.facebook\.net$                       # Facebook tracking
(^|\.)ads?\.                                        # Generic ad servers
(^|\.)analytics?\.                                  # Generic analytics
(^|\.)track(ing)?\.                                 # Generic tracking
(^|\.)metrics?\.                                    # Generic metrics
(^|\.)pixel\.                                        # Tracking pixels

# === AD SERVERS ===
^adserver[0-9]*\.                                   # Ad servers
^ads[0-9]*\.                                        # Ad servers
^banner[0-9]*\.                                     # Banners
^popup[0-9]*\.                                      # Popups
^click[0-9]*\.                                      # Click tracking
^track\.                                            # Tracking
(^|\.)doubleclick\.net$                             # Google DoubleClick
(^|\.)googleadservices\.com$                        # Google Ads

# === CRYPTO MINING ===
(^|\.)coin-hive\.com$                               # CoinHive miner
(^|\.)crypto-loot\.com$                             # Crypto miner
(^|\.)minr\.                                        # Minr miner
(^|\.)coinhive\.                                    # Coinhive miner
(^|\.)mining\.                                      # Mining domains

# === TELEMETRY & SPYING ===
(^|\.)telemetry\.                                   # Telemetry endpoints
(^|\.)diagnostics\.                                 # Diagnostics
(^|\.)data-?collector\.                             # Data collection
(^|\.)spy\.                                         # Spyware
(^|\.)beacon\.                                      # Beacons

# === FAKE UPDATES & SCAMS ===
(^|\.)update-(service|software)\.                   # Fake updates
(^|\.)security-(scan|alert)\.                       # Fake security alerts
(^|\.)antivirus-(pro|scan)\.                        # Fake AV
(^|\.)system-(scan|check)\.                         # Fake system scans
(^|\.)pc-(repair|fix)\.                             # Fake PC repairs

# === ADULT & UNWANTED CONTENT ===
(^|\.)xxx|adult|porn|sex|escort                     # Adult content
(^|\.)gambling|casino|poker|bet                     # Gambling
(^|\.)dating|single|match                           # Dating sites
EOF

    # Count regex patterns
    regex_count=$(grep -v '^#' "$REGEX_FILE" | grep -v '^$' | wc -l)
    print_success "$regex_count regex patterns configured"

    # Add regex to Pi-hole
    print_info "Applying regex patterns..."
    pihole restartdns >> "$LOG_FILE" 2>&1
    print_success "Regex patterns active"
}

# ---------- Microsoft Services Whitelist ------------------------------------
configure_whitelist() {
    print_header "Configuring Microsoft Services Whitelist"

    print_info "Adding comprehensive whitelist for Microsoft Teams, Office 365, Windows..."

    # Standard whitelist entries (exact domains)
    cat > "$WHITELIST_FILE" <<'EOF'
# === MICROSOFT TEAMS (Exact Domains) ===
teams.microsoft.com
teams.live.com
teams.events.data.microsoft.com
statics.teams.cdn.office.net
config.teams.microsoft.com
teams.cloud.microsoft
teams.office.com
teams-api.cloud.microsoft
teams-mobile-edge.teams.microsoft.com
teams.live.com
teams.events.data.microsoft.com
statics.teams.cdn.office.net
config.teams.microsoft.com

# === OFFICE 365 (Exact Domains) ===
office.com
office365.com
outlook.office.com
outlook.office365.com
mail.office365.com
protection.outlook.com
substrate.office.com
officeclient.microsoft.com
officecdn.microsoft.com
login.microsoftonline.com
login.microsoft.com
login.windows.net
account.live.com
account.microsoft.com
graph.microsoft.com

# === WINDOWS SERVICES (Exact Domains) ===
windows.com
windows.net
windowsupdate.com
update.microsoft.com
download.windowsupdate.com
download.microsoft.com
stats.update.microsoft.com
delivery.mp.microsoft.com
displaycatalog.mp.microsoft.com
purchase.mp.microsoft.com
licensing.mp.microsoft.com
settings-win.data.microsoft.com
settings.data.microsoft.com
notify.windows.com
wns.windows.com
dsp.mp.microsoft.com
EOF

    # Regex whitelist entries (wildcard domains) - CORRECTED APPROACH
    cat > "$WHITELIST_REGEX_FILE" <<'EOF'
# === MICROSOFT TEAMS (Wildcard - Regex Format) ===
(.*\.)?teams\.microsoft\.com$
(.*\.)?teams\.live\.com$
(.*\.)?sharepoint\.com$
(.*\.)?sfbassets\.com$
(.*\.)?skype\.com$
(.*\.)?skypeforbusiness\.com$
(.*\.)?teams\.skype\.com$
(.*\.)?cloud\.microsoft$

# === OFFICE 365 (Wildcard - Regex Format) ===
(.*\.)?office\.com$
(.*\.)?office365\.com$
(.*\.)?office\.net$
(.*\.)?officeppe\.com$
(.*\.)?officeconfig\.msocdn\.com$
(.*\.)?officehome\.msocdn\.com$
(.*\.)?microsoftonline\.com$
(.*\.)?microsoftonline-p\.net$
(.*\.)?msidentity\.com$
(.*\.)?msauth\.net$
(.*\.)?msauthimages\.net$
(.*\.)?live\.com$
(.*\.)?outlook\.com$
(.*\.)?outlook\.office\.com$
(.*\.)?outlook\.office365\.com$
(.*\.)?mail\.office365\.com$
(.*\.)?attachment\.office\.net$
(.*\.)?protection\.outlook\.com$
(.*\.)?sharepointonline\.com$
(.*\.)?spoppe\.com$
(.*\.)?onedrive\.com$
(.*\.)?onedrive\.live\.com$
(.*\.)?onedriveforbusiness\.com$

# === WINDOWS SERVICES (Wildcard - Regex Format) ===
(.*\.)?windows\.com$
(.*\.)?windows\.net$
(.*\.)?windowsupdate\.com$
(.*\.)?update\.microsoft\.com$
(.*\.)?download\.windowsupdate\.com$
(.*\.)?download\.microsoft\.com$
(.*\.)?delivery\.mp\.microsoft\.com$
(.*\.)?geo-prod\.do\.dsp\.mp\.microsoft\.com$
(.*\.)?displaycatalog\.mp\.microsoft\.com$
(.*\.)?purchase\.mp\.microsoft\.com$
(.*\.)?licensing\.mp\.microsoft\.com$
(.*\.)?settings-win\.data\.microsoft\.com$
(.*\.)?settings\.data\.microsoft\.com$
(.*\.)?wns\.windows\.com$
(.*\.)?dsp\.mp\.microsoft\.com$
(.*\.)?dl\.delivery\.mp\.microsoft\.com$

# === MICROSOFT 365 APPS (Wildcard - Regex Format) ===
(.*\.)?microsoft365\.com$
(.*\.)?microsoft-365\.com$
(.*\.)?azure\.com$
(.*\.)?azure\.net$
(.*\.)?azurewebsites\.net$
(.*\.)?azureedge\.net$
(.*\.)?azure-api\.net$
(.*\.)?azurecr\.io$
(.*\.)?azurefd\.net$
(.*\.)?trafficmanager\.net$
(.*\.)?cloudapp\.azure\.com$
EOF

    # Count entries
    wl_count=$(grep -v '^#' "$WHITELIST_FILE" | grep -v '^$' | wc -l)
    regex_wl_count=$(grep -v '^#' "$WHITELIST_REGEX_FILE" | grep -v '^$' | wc -l)
    total_wl=$((wl_count + regex_wl_count))
    print_success "$total_wl Microsoft domains whitelisted ($wl_count exact, $regex_wl_count wildcard regex)"

    # Apply standard whitelist
    print_info "Applying exact domain whitelist..."
    while IFS= read -r domain; do
        # Skip comments and empty lines
        [[ "$domain" =~ ^#.*$ || -z "$domain" ]] && continue
        pihole -w -q "$domain" >> "$LOG_FILE" 2>&1 || print_warning "Failed to whitelist $domain"
    done < "$WHITELIST_FILE"

    # Apply regex whitelist (CORRECT METHOD)
    print_info "Applying wildcard regex whitelist..."
    while IFS= read -r regex; do
        # Skip comments and empty lines
        [[ "$regex" =~ ^#.*$ || -z "$regex" ]] && continue
        pihole --white-regex "$regex" >> "$LOG_FILE" 2>&1 || print_warning "Failed to whitelist regex $regex"
    done < "$WHITELIST_REGEX_FILE"

    print_success "Whitelist applied successfully"
    pihole restartdns >> "$LOG_FILE" 2>&1
}

# ---------- Setup Backups ----------------------------------------------------
setup_backups() {
    print_header "Setting up Automatic Backups"

    print_info "Creating backup directory: $PIHOLE_BACKUP_DIR"
    mkdir -p "$PIHOLE_BACKUP_DIR"

    # Backup script
    print_info "Creating backup script..."
    cat > /usr/local/bin/pihole-backup.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/pihole"
RETENTION=7
EMAIL_CONFIG="/etc/pihole-backup-email.conf"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/teleporter-$TIMESTAMP.tar.gz"
LOG_FILE="/var/log/pihole-backup.log"

# Color output for manual runs
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

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "$1"
}

log "${YELLOW}Starting Pi-hole backup...${NC}"

# Create backup
if pihole -a -t "$BACKUP_FILE" >/dev/null 2>&1; then
    log "${GREEN}Backup created: $BACKUP_FILE${NC}"

    # Verify backup integrity
    if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        log "${GREEN}Backup integrity verified${NC}"
    else
        log "${RED}Backup integrity check failed${NC}"
        send_email "⚠ Pi-hole Backup Warning" "Backup created but integrity check failed at $(date)."
    fi

    # Rotate old backups
    mapfile -t backups < <(ls -1t "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null)
    count=${#backups[@]}

    if [[ $count -gt $RETENTION ]]; then
        log "${YELLOW}Rotating backups (keeping last $RETENTION)...${NC}"
        for ((i=$RETENTION; i<$count; i++)); do
            rm -f "${backups[$i]}"
            log "Removed old backup: ${backups[$i]}"
        done
    fi

    send_email "✅ Pi-hole Backup Success" "Backup completed successfully.\nFile: $BACKUP_FILE\nRetention: $RETENTION\nDate: $(date)"
    log "${GREEN}Backup process completed successfully${NC}"
else
    log "${RED}Backup creation failed!${NC}"
    send_email "❌ Pi-hole Backup Failed" "Backup creation failed at $(date)."
    exit 1
fi
EOF

    chmod +x /usr/local/bin/pihole-backup.sh
    print_success "Backup script created at /usr/local/bin/pihole-backup.sh"

    # Cron job (Sunday 2 AM)
    if ! crontab -l 2>/dev/null | grep -q "pihole-backup.sh"; then
        (crontab -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/pihole-backup.sh > /dev/null 2>&1") | crontab -
        print_success "Backup cron job installed (Sunday 2 AM)"
    else
        print_info "Backup cron job already exists"
    fi

    # Create backup log file
    touch /var/log/pihole-backup.log
    chmod 644 /var/log/pihole-backup.log
}

# ---------- Backup Verification Script ---------------------------------------
create_verification_script() {
    print_header "Creating Backup Verification Script"

    cat > /usr/local/bin/verify-backup.sh <<'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

BACKUP_DIR="/var/backups/pihole"
RETENTION=7

clear
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
total_size=$(du -ch "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null | grep total$ | cut -f1)

echo -e "${BOLD}Backup Directory:${NC} $BACKUP_DIR"
echo ""

if [[ $count -eq 0 ]]; then
    echo -e "${RED}⚠ No backups found.${NC}"
    exit 0
fi

echo -e "${BOLD}Backup Summary:${NC}"
echo -e "  Number of backups: ${GREEN}$count${NC}"
if [[ $count -gt $RETENTION ]]; then
    echo -e "  ${YELLOW}⚠ WARNING: More than $RETENTION backups exist (retention limit)${NC}"
fi
echo -e "  Total size: ${GREEN}${total_size:-0}${NC}"
echo ""

echo -e "${BOLD}Backup Details:${NC}"
oldest="${backups[0]}"
newest="${backups[-1]}"
echo -e "  Oldest backup: $(basename "$oldest") ($(stat -c %y "$oldest" | cut -d. -f1))"
echo -e "  Newest backup: $(basename "$newest") ($(stat -c %y "$newest" | cut -d. -f1))"
echo ""

echo -e "${BOLD}Backup Files:${NC}"
failed=0
for b in "${backups[@]}"; do
    size=$(du -h "$b" | cut -f1)
    date=$(stat -c %y "$b" | cut -d. -f1)

    # Verify integrity
    if tar -tzf "$b" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $(basename "$b")  [${YELLOW}$size${NC}]  (${date})"
    else
        echo -e "  ${RED}✗ CORRUPT${NC} $(basename "$b")  [${YELLOW}$size${NC}]  (${date})"
        failed=$((failed + 1))
    fi
done

echo ""
if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}✓ All backups verified successfully${NC}"
else
    echo -e "${RED}✗ $failed backup(s) are corrupt${NC}"
fi

echo ""
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
EOF

    chmod +x /usr/local/bin/verify-backup.sh
    print_success "Verification script created at /usr/local/bin/verify-backup.sh"
}

# ---------- Thermal Monitoring -----------------------------------------------
setup_thermal_monitoring() {
    print_header "Setting up Thermal Monitoring"

    print_info "Configuring CPU temperature monitoring..."

    # Check if thermal zone exists
    if [[ ! -f /sys/class/thermal/thermal_zone0/temp ]]; then
        print_warning "Thermal zone not found - temperature monitoring disabled"
        return 0
    fi

    # Monitoring script
    cat > /usr/local/bin/thermal-monitor.sh <<'EOF'
#!/bin/bash
TEMP_FILE="/sys/class/thermal/thermal_zone0/temp"
LOG_FILE="/var/log/thermal-monitor.log"
STATE_FILE="/var/lib/thermal-monitor.state"
WARN=75
CRIT=80
COOLDOWN=1800  # 30 minutes
CRIT_COOLDOWN=300  # 5 minutes for critical alerts
EMAIL_CONFIG="/etc/pihole-backup-email.conf"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

send_alert() {
    local level="$1"
    local temp="$2"
    local now=$(date +%s)
    local last_alert=0
    local cooldown=$COOLDOWN

    # Shorter cooldown for critical alerts
    [[ "$level" == "CRITICAL" ]] && cooldown=$CRIT_COOLDOWN

    if [[ -f "$STATE_FILE" ]]; then
        last_alert=$(cat "$STATE_FILE")
    fi

    if (( now - last_alert > cooldown )); then
        echo "$now" > "$STATE_FILE"
        send_email "🔴 Pi-hole Thermal Alert [$level]" "Temperature reached ${temp}°C at $(date)."
    fi
}

send_email() {
    if [[ -f "$EMAIL_CONFIG" ]]; then
        source "$EMAIL_CONFIG"
        if [[ -n "$EMAIL_RECIPIENT" ]] && command -v mail >/dev/null 2>&1; then
            echo -e "$2" | mail -s "$1" "$EMAIL_RECIPIENT"
        fi
    fi
}

if [[ ! -f "$TEMP_FILE" ]]; then
    echo "$(date): Thermal zone not available." >> "$LOG_FILE"
    exit 0
fi

raw=$(cat "$TEMP_FILE")
temp=$((raw/1000))

# Color output for log
if [[ $temp -ge $CRIT ]]; then
    color=$RED
    level="CRITICAL"
elif [[ $temp -ge $WARN ]]; then
    color=$YELLOW
    level="WARNING"
else
    color=$GREEN
    level="NORMAL"
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') - Temperature: ${color}${temp}°C${NC} [$level]" >> "$LOG_FILE"

if [[ $temp -ge $CRIT ]]; then
    send_alert "CRITICAL" "$temp"
elif [[ $temp -ge $WARN ]]; then
    send_alert "WARNING" "$temp"
fi
EOF

    chmod +x /usr/local/bin/thermal-monitor.sh
    print_success "Thermal monitoring script created"

    # Systemd timer (every 5 minutes)
    cat > /etc/systemd/system/thermal-monitor.service <<EOF
[Unit]
Description=Thermal monitoring for Pi-hole
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/thermal-monitor.sh
User=root
EOF

    cat > /etc/systemd/system/thermal-monitor.timer <<EOF
[Unit]
Description=Run thermal monitor every 5 minutes
Requires=thermal-monitor.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable thermal-monitor.timer >> "$LOG_FILE" 2>&1
    systemctl start thermal-monitor.timer >> "$LOG_FILE" 2>&1
    print_success "Thermal monitoring timer started (every 5 minutes)"

    # Create state file
    touch "$THERMAL_STATE"
    chmod 644 "$THERMAL_STATE"
}

# ---------- Enhanced Health Dashboard ----------------------------------------
create_health_dashboard() {
    print_header "Creating Professional Health Dashboard"

    cat > /usr/local/bin/pihole-health <<'EOF'
#!/bin/bash
# Pi-hole Ultimate Health Dashboard

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}${BOLD}                    PI-HOLE ULTIMATE HEALTH DASHBOARD${NC}"
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# === SYSTEM INFORMATION ===
echo -e "${CYAN}${BOLD}📊 SYSTEM INFORMATION${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

# Hostname and Uptime
hostname=$(hostname)
uptime_info=$(uptime -p | sed 's/up //')
echo -e " ${BOLD}Hostname:${NC}     $hostname"
echo -e " ${BOLD}Uptime:${NC}       $uptime_info"
echo -e " ${BOLD}Date/Time:${NC}    $(date '+%Y-%m-%d %H:%M:%S')"

# CPU Temperature
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    temp=$((raw/1000))
    if [[ $temp -ge 80 ]]; then
        temp_color=$RED
        temp_icon="🔴 CRITICAL"
    elif [[ $temp -ge 75 ]]; then
        temp_color=$YELLOW
        temp_icon="🟡 WARNING"
    else
        temp_color=$GREEN
        temp_icon="🟢 NORMAL"
    fi
    echo -e " ${BOLD}CPU Temp:${NC}      ${temp_color}${temp}°C${NC} ${temp_icon}"
else
    echo -e " ${BOLD}CPU Temp:${NC}      ${YELLOW}N/A${NC}"
fi

# Memory Usage
if command -v free >/dev/null 2>&1; then
    mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    mem_percent=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')
    if (( $(echo "$mem_percent > 90" | bc -l 2>/dev/null) )); then
        mem_color=$RED
    elif (( $(echo "$mem_percent > 75" | bc -l 2>/dev/null) )); then
        mem_color=$YELLOW
    else
        mem_color=$GREEN
    fi
    echo -e " ${BOLD}Memory:${NC}       ${mem_color}${mem_used} / ${mem_total} (${mem_percent}%)${NC}"
fi

# Disk Usage
if command -v df >/dev/null 2>&1; then
    disk_used=$(df -h / | awk 'NR==2 {print $3}')
    disk_total=$(df -h / | awk 'NR==2 {print $2}')
    disk_percent=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_percent -ge 90 ]]; then
        disk_color=$RED
    elif [[ $disk_percent -ge 75 ]]; then
        disk_color=$YELLOW
    else
        disk_color=$GREEN
    fi
    echo -e " ${BOLD}Disk Usage:${NC}    ${disk_color}${disk_used} / ${disk_total} (${disk_percent}%)${NC}"
fi

# Load Average
loadavg=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
echo -e " ${BOLD}Load Avg:${NC}      $loadavg"
echo ""

# === SERVICE STATUS ===
echo -e "${CYAN}${BOLD}🔄 SERVICE STATUS${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

# Pi-hole FTL
if systemctl is-active --quiet pihole-FTL 2>/dev/null; then
    echo -e " ${BOLD}Pi-hole FTL:${NC}   ${GREEN}● Active${NC} ${GREEN}✓${NC}"
else
    echo -e " ${BOLD}Pi-hole FTL:${NC}   ${RED}● Inactive${NC} ${RED}✗${NC}"
fi

# Unbound
if systemctl is-active --quiet unbound 2>/dev/null; then
    echo -e " ${BOLD}Unbound DNS:${NC}   ${GREEN}● Active${NC} ${GREEN}✓${NC}"
else
    echo -e " ${BOLD}Unbound DNS:${NC}   ${RED}● Inactive${NC} ${RED}✗${NC}"
fi

# Thermal Monitor
if systemctl is-active --quiet thermal-monitor.timer 2>/dev/null; then
    echo -e " ${BOLD}Thermal Monitor:${NC} ${GREEN}● Active${NC} ${GREEN}✓${NC}"
else
    echo -e " ${BOLD}Thermal Monitor:${NC} ${RED}● Inactive${NC} ${RED}✗${NC}"
fi

# Backup Cron
if crontab -l 2>/dev/null | grep -q "pihole-backup"; then
    echo -e " ${BOLD}Backup Cron:${NC}    ${GREEN}● Configured${NC} ${GREEN}✓${NC}"
else
    echo -e " ${BOLD}Backup Cron:${NC}    ${YELLOW}● Not configured${NC} ${YELLOW}⚠${NC}"
fi
echo ""

# === BLOCKING STATISTICS ===
echo -e "${CYAN}${BOLD}🛡️  BLOCKING STATISTICS${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

if command -v pihole >/dev/null 2>&1; then
    # Get Pi-hole stats
    if pihole -c -j >/dev/null 2>&1; then
        domains_blocked=$(pihole -c -j 2>/dev/null | grep -o '"domains_being_blocked":[0-9]*' | cut -d: -f2)
        queries_today=$(pihole -c -j 2>/dev/null | grep -o '"dns_queries_today":[0-9]*' | cut -d: -f2)
        blocked_today=$(pihole -c -j 2>/dev/null | grep -o '"ads_blocked_today":[0-9]*' | cut -d: -f2)
        percentage=$(pihole -c -j 2>/dev/null | grep -o '"ads_percentage_today":[0-9.]*' | cut -d: -f2)

        echo -e " ${BOLD}Domains Blocked:${NC} ${YELLOW}${domains_blocked:-N/A}${NC}"
        echo -e " ${BOLD}Queries Today:${NC}   ${YELLOW}${queries_today:-N/A}${NC}"
        echo -e " ${BOLD}Blocked Today:${NC}   ${RED}${blocked_today:-N/A}${NC}"
        echo -e " ${BOLD}Block Rate:${NC}      ${percentage:-N/A}%"
    else
        echo -e " ${YELLOW}Pi-hole API not responding${NC}"
    fi
else
    echo -e " ${YELLOW}Pi-hole not installed${NC}"
fi
echo ""

# === BACKUP STATUS ===
echo -e "${CYAN}${BOLD}💾 BACKUP STATUS${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

BACKUP_DIR="/var/backups/pihole"
RETENTION=7

if [[ -d "$BACKUP_DIR" ]]; then
    count=$(ls -1 "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null | wc -l)
    if [[ $count -gt 0 ]]; then
        total_size=$(du -ch "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null | grep total$ | cut -f1)
        newest=$(ls -1t "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null | head -1)
        if [[ -f "$newest" ]]; then
            newest_date=$(stat -c %y "$newest" 2>/dev/null | cut -d. -f1)
            newest_size=$(du -h "$newest" 2>/dev/null | cut -f1)

            echo -e " ${BOLD}Backup Count:${NC}   $count"
            echo -e " ${BOLD}Total Size:${NC}     $total_size"
            echo -e " ${BOLD}Latest Backup:${NC}  $(basename "$newest")"
            echo -e " ${BOLD}Latest Date:${NC}    $newest_date"
            echo -e " ${BOLD}Latest Size:${NC}    $newest_size"

            if [[ $count -gt $RETENTION ]]; then
                echo -e " ${YELLOW}⚠ Warning: Backup count exceeds retention limit ($RETENTION)${NC}"
            elif [[ $count -eq $RETENTION ]]; then
                echo -e " ${GREEN}✓ Backup retention policy satisfied${NC}"
            fi
        fi
    else
        echo -e " ${YELLOW}⚠ No backups found${NC}"
    fi
else
    echo -e " ${YELLOW}⚠ Backup directory not found${NC}"
fi
echo ""

# === RECENT THERMAL EVENTS ===
echo -e "${CYAN}${BOLD}🌡️  RECENT THERMAL EVENTS${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

if [[ -f /var/log/thermal-monitor.log ]]; then
    tail -5 /var/log/thermal-monitor.log 2>/dev/null | while read line; do
        if [[ "$line" == *"CRITICAL"* ]]; then
            echo -e " ${RED}●${NC} $line"
        elif [[ "$line" == *"WARNING"* ]]; then
            echo -e " ${YELLOW}●${NC} $line"
        else
            echo -e " ${GREEN}●${NC} $line"
        fi
    done
else
    echo -e " ${YELLOW}No thermal events logged${NC}"
fi
echo ""

# === FILTERING CONFIGURATION ===
echo -e "${CYAN}${BOLD}📋 FILTERING CONFIGURATION${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

# Count whitelist entries
if [[ -f /etc/pihole/whitelist.txt ]]; then
    wl_count=$(grep -v '^#' /etc/pihole/whitelist.txt | grep -v '^$' | wc -l)
    echo -e " ${BOLD}Whitelist Entries:${NC} ${GREEN}$wl_count${NC}"
fi

# Count regex whitelist entries
if [[ -f /etc/pihole/whitelist-regex.txt ]]; then
    wl_regex_count=$(grep -v '^#' /etc/pihole/whitelist-regex.txt | grep -v '^$' | wc -l)
    echo -e " ${BOLD}Regex Whitelist:${NC}   ${GREEN}$wl_regex_count${NC}"
fi

# Count regex blacklist entries
if [[ -f /etc/pihole/regex.list ]]; then
    regex_count=$(grep -v '^#' /etc/pihole/regex.list | grep -v '^$' | wc -l)
    echo -e " ${BOLD}Regex Patterns:${NC}   ${GREEN}$regex_count${NC}"
fi

# Count adlists
if [[ -f /etc/pihole/adlists.list ]]; then
    adlist_count=$(grep -v '^#' /etc/pihole/adlists.list | grep -v '^$' | wc -l)
    echo -e " ${BOLD}Active Blocklists:${NC} ${GREEN}$adlist_count${NC}"
fi

echo ""
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}${BOLD}              System Report - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
EOF

    chmod +x /usr/local/bin/pihole-health
    print_success "Enhanced health dashboard created at /usr/local/bin/pihole-health"
}

# ---------- Configure Email Alerts ------------------------------------------
configure_email() {
    if [[ "$EMAIL_ENABLED" == "true" ]]; then
        print_header "Configuring Email Alerts"

        # Write config file
        cat > "$EMAIL_CONFIG" <<EOF
EMAIL_RECIPIENT="$EMAIL_RECIPIENT"
SMTP_SERVER="$SMTP_SERVER"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
EOF
        chmod 600 "$EMAIL_CONFIG"

        print_success "Email configuration saved"

        # Install mailutils and configure ssmtp if needed
        print_info "Installing email utilities..."
        apt-get install -y mailutils ssmtp >> "$LOG_FILE" 2>&1

        if [[ -n "$SMTP_SERVER" && -n "$SMTP_USER" ]]; then
            cat > /etc/ssmtp/ssmtp.conf <<EOF
root=$EMAIL_RECIPIENT
mailhub=$SMTP_SERVER
AuthUser=$SMTP_USER
AuthPass=$SMTP_PASS
UseSTARTTLS=YES
UseTLS=YES
EOF
            print_success "SMTP configured"
        fi

        # Send test email
        print_info "Sending test email..."
        if echo "Pi-hole Ultimate Edition v1.5.9 installed successfully" | mail -s "✅ Pi-hole Installation Complete" "$EMAIL_RECIPIENT" 2>/dev/null; then
            print_success "Test email sent"
        else
            print_warning "Test email failed - check SMTP settings"
        fi
    else
        print_info "Email alerts disabled"
        rm -f "$EMAIL_CONFIG" 2>/dev/null || true
    fi
}

# ---------- Create Uninstall Script -----------------------------------------
create_uninstall_script() {
    cat > /usr/local/bin/uninstall-pihole-ultimate.sh <<'EOF'
#!/bin/bash
# Pi-hole Ultimate Edition Uninstaller

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}This will uninstall Pi-hole Ultimate Edition and all components${NC}"
echo -e "${YELLOW}Are you sure? (y/N)${NC}"
read -r confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Stopping services...${NC}"
    systemctl stop pihole-FTL unbound thermal-monitor.timer 2>/dev/null

    echo -e "${YELLOW}Disabling services...${NC}"
    systemctl disable pihole-FTL unbound thermal-monitor.timer 2>/dev/null

    echo -e "${YELLOW}Removing packages...${NC}"
    apt-get remove --purge -y pihole unbound 2>/dev/null

    echo -e "${YELLOW}Removing configuration...${NC}"
    rm -rf /etc/pihole /etc/unbound /var/backups/pihole /usr/local/bin/pihole-*

    echo -e "${GREEN}Uninstall complete${NC}"
else
    echo -e "${GREEN}Uninstall cancelled${NC}"
fi
EOF
    chmod +x /usr/local/bin/uninstall-pihole-ultimate.sh
}

# ---------- Final Summary ----------------------------------------------------
show_summary() {
    print_header "Installation Complete - Summary"

    # Get IP address
    IP_ADDR=$(hostname -I | awk '{print $1}')

    echo -e "${GREEN}${BOLD}✓ Pi-hole Ultimate Edition v1.5.9 installed successfully${NC}"
    echo ""

    echo -e "${WHITE}${BOLD}📌 Quick Start Commands:${NC}"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole-health${NC}        - Show health dashboard"
    echo -e "  ${CYAN}▶${NC} ${BOLD}verify-backup.sh${NC}      - Check backup status"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -c${NC}             - Show Pi-hole console"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -g${NC}             - Update gravity"
    echo -e "  ${CYAN}▶${NC} ${BOLD}uninstall-pihole-ultimate.sh${NC} - Remove everything"
    echo ""

    echo -e "${WHITE}${BOLD}📁 Important Files:${NC}"
    echo -e "  ${CYAN}•${NC} Blocklists:    ${YELLOW}/etc/pihole/adlists.list${NC}"
    echo -e "  ${CYAN}•${NC} Regex Patterns: ${YELLOW}/etc/pihole/regex.list${NC}"
    echo -e "  ${CYAN}•${NC} Whitelist:      ${YELLOW}/etc/pihole/whitelist.txt${NC}"
    echo -e "  ${CYAN}•${NC} Regex Whitelist: ${YELLOW}/etc/pihole/whitelist-regex.txt${NC}"
    echo -e "  ${CYAN}•${NC} Backups:        ${YELLOW}/var/backups/pihole/${NC}"
    echo -e "  ${CYAN}•${NC} Thermal Log:    ${YELLOW}/var/log/thermal-monitor.log${NC}"
    echo -e "  ${CYAN}•${NC} Installation Log: ${YELLOW}$LOG_FILE${NC}"
    echo ""

    echo -e "${WHITE}${BOLD}🌐 Web Interface:${NC}"
    echo -e "  ${CYAN}•${NC} URL:           ${GREEN}http://$IP_ADDR/admin${NC}"
    if [[ -f /etc/pihole/admin-password.txt ]]; then
        echo -e "  ${CYAN}•${NC} Password:      ${YELLOW}$(cat /etc/pihole/admin-password.txt)${NC}"
    fi
    echo ""

    echo -e "${WHITE}${BOLD}🔄 Services:${NC}"
    echo -e "  ${CYAN}•${NC} Pi-hole FTL:    ${GREEN}active${NC}"
    echo -e "  ${CYAN}•${NC} Unbound DNS:    ${GREEN}active${NC} (127.0.0.1#5335)"
    echo -e "  ${CYAN}•${NC} Thermal Monitor:${GREEN}active${NC} (every 5 minutes)"
    echo -e "  ${CYAN}•${NC} Backup Cron:    ${GREEN}active${NC} (Sunday 2 AM)"
    echo ""

    echo -e "${WHITE}${BOLD}📊 Statistics:${NC}"
    echo -e "  ${CYAN}•${NC} Blocklists:     ${GREEN}$(grep -v '^#' "$BLOCKLIST_DIR" | grep -v '^$' | wc -l)${NC} premium lists"
    echo -e "  ${CYAN}•${NC} Regex Patterns: ${GREEN}$(grep -v '^#' "$REGEX_FILE" | grep -v '^$' | wc -l)${NC} sophisticated rules"
    echo -e "  ${CYAN}•${NC} Whitelist:      ${GREEN}$(grep -v '^#' "$WHITELIST_FILE" | grep -v '^$' | wc -l)${NC} exact domains"
    echo -e "  ${CYAN}•${NC} Regex Whitelist: ${GREEN}$(grep -v '^#' "$WHITELIST_REGEX_FILE" | grep -v '^$' | wc -l)${NC} wildcard patterns"
    echo -e "  ${CYAN}•${NC} Backup Policy:  ${GREEN}Last 7 backups${NC} retained"
    echo ""

    if [[ "$EMAIL_ENABLED" == "true" ]]; then
        echo -e "${GREEN}✓ Email alerts configured for: $EMAIL_RECIPIENT${NC}"
    else
        echo -e "${YELLOW}⚠ Email alerts disabled${NC}"
    fi
    echo ""

    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}              Thank you for choosing Pi-hole Ultimate!${NC}"
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

    # Collect user preferences first
    collect_preferences

    # Start installation
    install_dependencies
    install_pihole
    install_unbound
    configure_blocklists
    configure_regex
    configure_whitelist
    setup_backups
    create_verification_script
    setup_thermal_monitoring
    create_health_dashboard
    create_uninstall_script
    configure_email

    show_summary
}

main "$@"
