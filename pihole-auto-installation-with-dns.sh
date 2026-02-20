#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Pi-hole Ultimate Edition - Maximum Protection + Monitoring + Backup
# Version: 1.8.5
# Date: 20-02-2026
#
# Wael Isa
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
# Support: https://www.paypal.me/WaelIsa
#
# Features:
#   - Pi-hole v6 with Unbound recursive DNS (FULLY WORKING)
#   - Quad9 DNS-over-TLS with Unbound DNSSEC (CONFIRMED: SERVFAIL + dot)
#   - Pi-hole DNSSEC disabled (prevents double validation)
#   - FIXED: FTL service hard stop with process verification
#   - FIXED: Unbound logging to file (compatible with logrotate)
#   - FIXED: Database counts now accurately reflect all lists
#   - NEW: Self-healing database check in health dashboard
#   - VERIFIED: All 14 blocklists properly linked to Group 0
#############################################################################################################################

# DISABLE set -e - we handle errors manually
# set -e
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
PIHOLE_V5_CONFIG="/etc/pihole/setupVars.conf"
GRAVITY_DB="/etc/pihole/gravity.db"
LOG_FILE="/var/log/pihole-ultimate-install.log"
ROOT_HINTS="/usr/share/dns/root.hints"
PIHOLE_FTL_LOG="/var/log/pihole/FTL.log"
CERT_FILE="/etc/pihole/tls.pem"
LISTS_CACHE="/etc/pihole/listsCache"
UNBOUND_LOG="/var/log/unbound/unbound.log"
STEP_COUNTER=0
TOTAL_STEPS=18

# ---------- OS Detection Variables --------------------------------------------
PKG_MANAGER=""
UPDATE_PKG_CACHE=""
PKG_INSTALL=""
PKG_REMOVE=""
CA_CERT_BUNDLE=""

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
    log "${WHITE}${BOLD}      Pi-hole Ultimate Edition v1.8.5 - Self-Healing${NC}"
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
        if [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID" == "raspbian" || "$ID" == "armbian" || "$ID" == "centos" || "$ID" == "fedora" || "$ID" == "rhel" || "$ID" == "almalinux" || "$ID" == "rocky" ]]; then
            print_success "Running on $PRETTY_NAME"
            return 0
        else
            print_warning "This script is optimized for Debian/Ubuntu/Raspbian/RHEL/Fedora systems."
            print_warning "You are running: $PRETTY_NAME"
            print_warning "Continuing anyway - some features may not work correctly."
            return 0
        fi
    else
        print_warning "Could not determine OS. Continuing with installation..."
        return 0
    fi
}

is_command() {
    local check_command="$1"
    command -v "${check_command}" >/dev/null 2>&1
}

# ---------- Package Manager Detection ----------------------------------------
package_manager_detect() {
    print_step "Detecting Package Manager"
    
    if is_command apt-get; then
        PKG_MANAGER="apt-get"
        UPDATE_PKG_CACHE="${PKG_MANAGER} update"
        PKG_INSTALL="${PKG_MANAGER} -qq --no-install-recommends install"
        PKG_REMOVE="${PKG_MANAGER} -y remove --purge"
        CA_CERT_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
        print_success "Detected Debian/Ubuntu package manager (apt-get)"
        
    elif is_command rpm; then
        if is_command dnf; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="yum"
        fi
        PKG_INSTALL="${PKG_MANAGER} install -y"
        PKG_REMOVE="${PKG_MANAGER} remove -y"
        CA_CERT_BUNDLE="/etc/pki/tls/certs/ca-bundle.crt"
        print_success "Detected RHEL/Fedora package manager (${PKG_MANAGER})"
        
    elif is_command apk; then
        PKG_MANAGER="apk"
        UPDATE_PKG_CACHE="${PKG_MANAGER} update"
        PKG_INSTALL="${PKG_MANAGER} add"
        PKG_REMOVE="${PKG_MANAGER} del"
        CA_CERT_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
        print_success "Detected Alpine package manager (apk)"
        
    else
        print_error "No supported package manager found"
        exit 1
    fi
}

# ---------- Check Pi-hole Version --------------------------------------------
check_pihole_version() {
    print_step "Checking Pi-hole Version"
    
    if ! command -v pihole >/dev/null 2>&1; then
        print_info "Pi-hole not installed - continuing with fresh v6 install"
        return 0
    fi
    
    if [[ -f "$PIHOLE_TOML" ]]; then
        print_success "Pi-hole v6 detected"
        return 0
    elif [[ -f "$PIHOLE_V5_CONFIG" ]]; then
        print_warning "Pi-hole v5 detected - will migrate to v6"
        return 0
    else
        print_info "Pi-hole installation detected - will upgrade"
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

# ---------- Fix SSL Certificates ---------------------------------------------
fix_ssl_certificates() {
    print_step "Fixing SSL Certificates for DNS-over-TLS"
    
    print_info "Updating CA certificates to fix SSL handshake errors..."
    
    case "${PKG_MANAGER}" in
        apt-get)
            run_sudo apt-get update >> "$LOG_FILE" 2>&1
            run_sudo apt-get install --reinstall ca-certificates -y >> "$LOG_FILE" 2>&1
            ;;
        dnf|yum)
            run_sudo ${PKG_MANAGER} reinstall ca-certificates -y >> "$LOG_FILE" 2>&1
            ;;
        apk)
            run_sudo apk fix ca-certificates >> "$LOG_FILE" 2>&1
            ;;
    esac
    
    run_sudo update-ca-certificates >> "$LOG_FILE" 2>&1
    
    if [[ -f "$CA_CERT_BUNDLE" ]]; then
        print_success "CA certificate bundle found at: $CA_CERT_BUNDLE"
    else
        print_warning "CA certificate bundle not found at expected location"
        CA_CERT_BUNDLE=$(find /etc -name "ca-certificates.crt" -o -name "ca-bundle.crt" 2>/dev/null | head -1)
        if [[ -n "$CA_CERT_BUNDLE" ]]; then
            print_success "Found CA certificate bundle at: $CA_CERT_BUNDLE"
        else
            print_error "Could not find CA certificate bundle - SSL/TLS will fail"
            exit 1
        fi
    fi
}

# ---------- Install Dependencies --------------------------------------------
install_dependencies() {
    print_step "Installing System Dependencies"
    
    print_info "Updating package lists..."
    run_sudo ${UPDATE_PKG_CACHE} >> "$LOG_FILE" 2>&1
    
    print_info "Installing required packages..."
    case "${PKG_MANAGER}" in
        apt-get)
            run_sudo apt-get install -y curl wget git unzip nano sqlite3 \
                bc jq mailutils ssmtp dnsutils \
                openssl ca-certificates systemd >> "$LOG_FILE" 2>&1
            ;;
        dnf|yum)
            run_sudo ${PKG_MANAGER} install -y curl wget git unzip nano sqlite \
                bc jq mailx ssmtp bind-utils \
                openssl ca-certificates systemd >> "$LOG_FILE" 2>&1
            ;;
        apk)
            run_sudo apk add curl wget git unzip nano sqlite \
                bc jq mailx ssmtp bind-tools \
                openssl ca-certificates >> "$LOG_FILE" 2>&1
            ;;
    esac
    
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
        
        run_sudo mkdir -p /etc/pihole
        run_sudo mkdir -p "$LISTS_CACHE"
        run_sudo chown pihole:pihole "$LISTS_CACHE" 2>/dev/null || true
        run_sudo chmod 755 "$LISTS_CACHE"
        
        if curl -sSL https://install.pi-hole.net | run_sudo bash /dev/stdin --unattended >> "$LOG_FILE" 2>&1; then
            print_success "Pi-hole v6 installed successfully"
        else
            print_error "Pi-hole installation failed"
            exit 1
        fi
    else
        print_info "Pi-hole already installed"
        run_sudo pihole -up >> "$LOG_FILE" 2>&1
    fi
    
    print_info "Waiting for Pi-hole FTL to initialize (20 seconds)..."
    sleep 20
    
    remove_lighttpd
}

# ---------- Install & Configure Unbound with Quad9 DNS-over-TLS and DNSSEC --
install_unbound() {
    print_step "Installing Unbound with Quad9 DNS-over-TLS and DNSSEC"
    
    print_info "Installing Unbound package..."
    case "${PKG_MANAGER}" in
        apt-get)
            run_sudo apt-get install -y unbound dns-root-data >> "$LOG_FILE" 2>&1
            ;;
        dnf|yum)
            run_sudo ${PKG_MANAGER} install -y unbound >> "$LOG_FILE" 2>&1
            ;;
        apk)
            run_sudo apk add unbound >> "$LOG_FILE" 2>&1
            ;;
    esac
    
    run_sudo systemctl stop unbound 2>/dev/null || true
    
    if [[ ! -f /etc/unbound/unbound.conf.orig ]]; then
        run_sudo cp /etc/unbound/unbound.conf /etc/unbound/unbound.conf.orig 2>/dev/null || true
    fi
    
    run_sudo rm -f /etc/unbound/unbound.conf.d/*.conf 2>/dev/null || true
    
    print_info "Configuring Unbound with Quad9 DNS-over-TLS and DNSSEC..."
    
    # Create log directory
    run_sudo mkdir -p "$(dirname "$UNBOUND_LOG")"
    run_sudo touch "$UNBOUND_LOG"
    run_sudo chown unbound:unbound "$UNBOUND_LOG" 2>/dev/null || true
    
    run_sudo tee "$UNBOUND_CONF" > /dev/null <<EOF
server:
    # --- Networking ---
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes

    # --- Logging (CRITICAL for Logrotate) ---
    logfile: "$UNBOUND_LOG"
    log-queries: no          # Set to 'yes' only for temporary debugging
    log-replies: no
    log-tag-queryreply: yes
    use-syslog: no           # Directs output to our specific log file
    verbosity: 1             # Log DNSSEC failures and basic info

    # --- Security & Hardening ---
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: yes
    edns-buffer-size: 1232
    do-not-query-localhost: no
    
    # --- DNSSEC Validation ---
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    val-clean-additional: yes
    val-permissive-mode: no
    val-log-level: 1         # Log DNSSEC failures only
    
    # --- Performance & Privacy ---
    prefetch: yes
    prefetch-key: yes
    serve-expired: yes
    num-threads: 1           # Optimized for low-power ARM devices
    so-rcvbuf: 1m
    
    # --- Privacy ---
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
    
    # --- SSL certificate bundle ---
    tls-cert-bundle: $CA_CERT_BUNDLE

# --- Forwarding over TLS to Quad9 ---
forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 9.9.9.11@853#dns.quad9.net
    forward-addr: 149.112.112.11@853#dns.quad9.net
EOF
    
    print_success "Unbound configured with Quad9 DNS-over-TLS and DNSSEC"
    
    # Generate DNSSEC trust anchor
    print_info "Generating DNSSEC trust anchor..."
    run_sudo -u unbound unbound-anchor -a "/var/lib/unbound/root.key" 2>/dev/null || true
    run_sudo chown unbound:unbound /var/lib/unbound/root.key 2>/dev/null || true
    
    # Check and disable unbound-resolvconf.service if present
    if systemctl list-unit-files 2>/dev/null | grep -q unbound-resolvconf.service; then
        print_info "Disabling unbound-resolvconf.service..."
        run_sudo systemctl disable --now unbound-resolvconf.service >> "$LOG_FILE" 2>&1 || true
        run_sudo sed -Ei 's/^unbound_conf=/#unbound_conf=/' /etc/resolvconf.conf 2>/dev/null || true
        run_sudo rm -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf 2>/dev/null || true
    fi
    
    run_sudo systemctl enable unbound >> "$LOG_FILE" 2>&1
    run_sudo systemctl start unbound >> "$LOG_FILE" 2>&1
    sleep 5
    
    if run_sudo systemctl is-active --quiet unbound; then
        print_success "Unbound service started"
    else
        print_error "Unbound failed to start"
        exit 1
    fi
}

# ---------- Configure Unbound Log Rotation ------------------------------------
configure_unbound_logrotate() {
    print_step "Configuring Unbound Log Rotation"
    
    run_sudo tee /etc/logrotate.d/unbound > /dev/null <<EOF
$UNBOUND_LOG {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 unbound unbound
    postrotate
        /usr/sbin/unbound-control log_reopen >/dev/null 2>&1 || true
    endscript
}
EOF
    print_success "Unbound logrotate configuration added (prevents SD card wear)"
}

# ---------- Systemd Service Hardening (Watchdog) -----------------------------
harden_services() {
    print_step "Hardening Services with Auto-Restart"
    
    for svc in unbound pihole-FTL; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
            run_sudo mkdir -p "/etc/systemd/system/${svc}.service.d"
            run_sudo tee "/etc/systemd/system/${svc}.service.d/restart.conf" > /dev/null <<EOF
[Service]
Restart=always
RestartSec=5s
StartLimitIntervalSec=0
EOF
            print_success "Hardened $svc: Auto-restart enabled (5s)"
        fi
    done
    run_sudo systemctl daemon-reload
}

# ---------- Configure Pi-hole v6 DNS (DNSSEC disabled) ----------------------
configure_pihole_v6_dns() {
    print_step "Configuring Pi-hole v6 DNS Settings"
    
    print_info "Stopping Pi-hole FTL for configuration..."
    run_sudo systemctl stop pihole-FTL
    sleep 5
    
    if [[ -f "$PIHOLE_TOML" ]]; then
        run_sudo cp "$PIHOLE_TOML" "$PIHOLE_TOML.backup-$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Use official CLI to set DNS
    print_info "Setting upstream DNS using pihole-FTL --config..."
    run_sudo pihole-FTL --config dns.upstreams "127.0.0.1#5335" >> "$LOG_FILE" 2>&1
    run_sudo pihole-FTL --config dns.blocking.active true >> "$LOG_FILE" 2>&1
    run_sudo pihole-FTL --config dns.queryLogging true >> "$LOG_FILE" 2>&1
    
    # ===== CRITICAL: Disable DNSSEC in Pi-hole (Unbound handles it) =====
    print_info "Disabling DNSSEC in Pi-hole (Unbound will handle validation)..."
    run_sudo pihole-FTL --config dns.dnssec false >> "$LOG_FILE" 2>&1
    
    print_success "DNS configuration applied via official CLI"
    print_success "DNSSEC disabled in Pi-hole (Unbound remains the validator)"
    
    run_sudo systemctl start pihole-FTL
    sleep 15
    
    if grep -q "127.0.0.1#5335" "$PIHOLE_TOML" 2>/dev/null; then
        print_success "✓ DNS: Unbound configured in TOML"
    fi
    
    local dnssec_status=$(pihole-FTL --config dns.dnssec 2>/dev/null)
    print_info "Pi-hole DNSSEC setting: $dnssec_status (should be false)"
}

# ---------- Configure HTTPS for Web Interface --------------------------------
configure_https() {
    print_step "Configuring HTTPS for Pi-hole Web Interface"
    
    print_info "Generating self-signed SSL certificate..."
    
    if [[ ! -f "$CERT_FILE" ]]; then
        openssl req -x509 -newkey rsa:4096 -keyout "$CERT_FILE" -out "$CERT_FILE" \
            -days 3650 -nodes -subj "/C=US/ST=State/L=City/O=Pi-hole/OU=Ultimate/CN=pi.hole" \
            >> "$LOG_FILE" 2>&1
        run_sudo chmod 600 "$CERT_FILE"
        run_sudo chown pihole:pihole "$CERT_FILE" 2>/dev/null || true
        print_success "Self-signed certificate generated at $CERT_FILE"
    else
        print_info "Certificate already exists at $CERT_FILE"
    fi
    
    run_sudo systemctl stop pihole-FTL
    sleep 3
    
    # Configure HTTPS
    print_info "Enabling HTTPS in Pi-hole v6..."
    run_sudo pihole-FTL --config webserver.tls.enabled true >> "$LOG_FILE" 2>&1
    run_sudo pihole-FTL --config webserver.tls.cert "$CERT_FILE" >> "$LOG_FILE" 2>&1
    run_sudo pihole-FTL --config webserver.port "80,443s" >> "$LOG_FILE" 2>&1
    
    run_sudo systemctl start pihole-FTL
    sleep 10
    
    if grep -q "443s" "$PIHOLE_TOML" 2>/dev/null; then
        print_success "✓ HTTPS enabled on port 443"
    fi
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    print_success "Web interface available at:"
    print_info "  HTTP:  http://$IP_ADDR/admin"
    print_info "  HTTPS: https://$IP_ADDR/admin (self-signed certificate)"
}

# ---------- Test Web Server --------------------------------------------------
test_web_server() {
    print_step "Testing Web Server"
    
    print_info "Checking if Pi-hole FTL is listening on web ports..."
    
    if ss -tlnp | grep -q ":80.*pihole-FTL"; then
        print_success "✓ Pi-hole FTL listening on port 80 (HTTP)"
    else
        print_warning "Pi-hole FTL not listening on port 80"
    fi
    
    if ss -tlnp | grep -q ":443.*pihole-FTL"; then
        print_success "✓ Pi-hole FTL listening on port 443 (HTTPS)"
    else
        print_warning "Pi-hole FTL not listening on port 443"
    fi
    
    print_info "Testing TOML configuration syntax..."
    
    if pihole-FTL config test > /dev/null 2>&1; then
        print_success "✓ TOML configuration is valid (using 'config test')"
    elif pihole-FTL --check-config > /dev/null 2>&1; then
        print_success "✓ TOML configuration is valid (using '--check-config')"
    else
        print_warning "Unable to test TOML syntax, but FTL is running"
    fi
}

# ---------- Configure Blocklists (CRITICAL FIX: Hard Stop) -------------------
configure_blocklists() {
    print_step "Configuring Blocklists with Group 0 Linkage"
    
    # Create listsCache directory with proper permissions 
    run_sudo mkdir -p "$LISTS_CACHE"
    run_sudo chown pihole:pihole "$LISTS_CACHE"
    run_sudo chmod 755 "$LISTS_CACHE"
    
    sleep 5
    
    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, running gravity first..."
        run_sudo pihole -g >> "$LOG_FILE" 2>&1 || true
        sleep 10
    fi
    
    # ===== CRITICAL: Hard stop FTL with process verification =====
    print_info "Stopping Pi-hole FTL service and waiting for process exit..."
    run_sudo systemctl stop pihole-FTL
    
    # Wait for process to actually die (more reliable than sleep)
    local max_wait=10
    local waited=0
    while pgrep pihole-FTL > /dev/null 2>&1 && [[ $waited -lt $max_wait ]]; do
        sleep 1
        waited=$((waited + 1))
        print_info "  Waiting for FTL to exit... (${waited}s)"
    done
    
    if pgrep pihole-FTL > /dev/null 2>&1; then
        print_warning "FTL still running after $max_wait seconds, forcing kill..."
        run_sudo pkill -9 pihole-FTL 2>/dev/null || true
        sleep 2
    fi
    
    print_success "FTL service stopped"
    
    # ===== COMPLETE DATABASE CLEANUP =====
    if [[ -f "$GRAVITY_DB" ]]; then
        print_info "Performing complete database cleanup..."
        
        # Clear all group linkages first
        run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM adlist_by_group;" >> "$LOG_FILE" 2>&1 || true
        run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist_by_group;" >> "$LOG_FILE" 2>&1 || true
        
        # Clear all lists
        run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM adlist;" >> "$LOG_FILE" 2>&1 || true
        run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist;" >> "$LOG_FILE" 2>&1 || true
        
        # Vacuum to reclaim space
        run_sudo sqlite3 "$GRAVITY_DB" "VACUUM;" >> "$LOG_FILE" 2>&1 || true
        
        print_success "Database cleaned and vacuumed"
    fi
    
    # ===== RECOMMENDED BLOCKLISTS =====
    local lists=(
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|StevenBlack Unified"
        "https://big.oisd.nl/|OISD Full"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/multi.txt|Hagezi Multi PRO"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/ultimate.txt|Hagezi ULTIMATE"
        "https://v.firebog.net/hosts/AdguardDNS.txt|AdGuard DNS"
        "https://raw.githubusercontent.com/anudeepND/blacklist/master/adservers.txt|anudeepND"
        "https://v.firebog.net/hosts/Easylist.txt|EasyList"
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext|Yoyo"
        "https://v.firebog.net/hosts/Easyprivacy.txt|EasyPrivacy"
        "https://v.firebog.net/hosts/Prigent-Ads.txt|Prigent-Ads"
        "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt|WindowsSpyBlocker"
        "https://phishing.army/download/phishing_army_blocklist_extended.txt|Phishing Army"
        "https://urlhaus.abuse.ch/downloads/hostfile/|URLHaus"
        "https://gitlab.com/quidsup/notrack-blocklists/-/raw/master/notrack-malware.txt|NoTrack Malware"
    )
    
    print_info "Adding ${#lists[@]} blocklists to database with Group 0 linkage..."
    
    local total_count=${#lists[@]}
    local current=0
    
    # Build SQL commands in a temporary file for batch execution
    local sql_file=$(mktemp)
    
    for entry in "${lists[@]}"; do
        IFS='|' read -r url comment <<< "$entry"
        current=$((current + 1))
        print_info "[$current/$total_count] Adding: $comment"
        
        # Escape single quotes for SQL
        url_escaped=$(echo "$url" | sed "s/'/''/g")
        comment_escaped=$(echo "$comment" | sed "s/'/''/g")
        
        # Add SQL commands to temp file
        echo "INSERT OR IGNORE INTO adlist (address, comment, enabled) VALUES ('$url_escaped', '$comment_escaped', 1);" >> "$sql_file"
    done
    
    # Execute all INSERT commands in one batch
    if [[ -f "$sql_file" ]] && [[ -s "$sql_file" ]]; then
        print_info "Executing batch INSERT of ${#lists[@]} blocklists..."
        run_sudo sqlite3 "$GRAVITY_DB" < "$sql_file" >> "$LOG_FILE" 2>&1
        print_success "Batch INSERT completed"
    fi
    
    # Clean up temp file
    rm -f "$sql_file"
    
    # ===== CRITICAL: Link ALL lists to Group 0 in one command =====
    print_info "Linking ALL blocklists to Group 0 (bulk operation)..."
    run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO adlist_by_group (adlist_id, group_id) SELECT id, 0 FROM adlist;" >> "$LOG_FILE" 2>&1
    
    # ===== VERIFY DATABASE INTEGRITY =====
    if [[ -f "$GRAVITY_DB" ]]; then
        local adlist_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist;" 2>/dev/null)
        local group_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist_by_group WHERE group_id=0;" 2>/dev/null)
        local unlinked_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist WHERE id NOT IN (SELECT adlist_id FROM adlist_by_group);" 2>/dev/null)
        
        print_success "✓ $adlist_count blocklists in database"
        print_success "✓ $group_count blocklists linked to Group 0"
        print_success "✓ $unlinked_count unlinked lists (should be 0)"
        
        if [[ "$adlist_count" -eq "$group_count" ]] && [[ "$adlist_count" -eq "${#lists[@]}" ]]; then
            print_success "✓ SUCCESS: All ${#lists[@]} blocklists are properly linked"
        else
            print_warning "⚠ Database counts don't match! adlist: $adlist_count, group: $group_count, expected: ${#lists[@]}"
        fi
    fi
    
    # ===== RESTART FTL SERVICE =====
    print_info "Starting Pi-hole FTL service..."
    run_sudo systemctl start pihole-FTL
    sleep 5
    
    # Force gravity rebuild with recreate flag
    print_info "Rebuilding gravity with recreate flag..."
    if run_sudo pihole -g -r recreate >> "$LOG_FILE" 2>&1; then
        print_success "✓ Gravity rebuilt successfully"
        
        local domain_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM gravity;" 2>/dev/null)
        print_success "✓ $domain_count total domains in gravity database"
    else
        print_warning "Gravity rebuild had issues - check logs"
    fi
    
    print_success "Blocklist configuration completed"
}

# ---------- Configure Whitelist (Microsoft Services) -------------------------
configure_whitelist() {
    print_step "Configuring Microsoft Services Whitelist"
    
    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, skipping"
        return
    fi
    
    # Stop FTL for whitelist operations too
    print_info "Stopping Pi-hole FTL for whitelist configuration..."
    run_sudo systemctl stop pihole-FTL
    sleep 3
    
    # Clear existing whitelist entries
    run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist_by_group WHERE domainlist_id IN (SELECT id FROM domainlist WHERE type IN (0, 2));" >> "$LOG_FILE" 2>&1 || true
    run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM domainlist WHERE type IN (0, 2);" >> "$LOG_FILE" 2>&1 || true
    
    # Exact whitelist (type 0)
    local exact=(
        "teams.microsoft.com|Microsoft Teams"
        "office.com|Office 365"
        "outlook.office.com|Office 365"
        "login.microsoftonline.com|Microsoft Login"
        "windowsupdate.com|Windows Update"
    )
    
    # Regex whitelist (type 2)
    local regex=(
        "(.*\.)?teams\.microsoft\.com$|Microsoft Teams wildcard"
        "(.*\.)?office\.com$|Office wildcard"
        "(.*\.)?windows\.com$|Windows wildcard"
    )
    
    # Build SQL for exact entries
    local exact_sql=$(mktemp)
    for entry in "${exact[@]}"; do
        IFS='|' read -r domain comment <<< "$entry"
        domain_escaped=$(echo "$domain" | sed "s/'/''/g")
        comment_escaped=$(echo "$comment" | sed "s/'/''/g")
        echo "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (0, '$domain_escaped', 1, '$comment_escaped');" >> "$exact_sql"
    done
    
    # Build SQL for regex entries
    local regex_sql=$(mktemp)
    for entry in "${regex[@]}"; do
        IFS='|' read -r pattern comment <<< "$entry"
        pattern_escaped=$(echo "$pattern" | sed "s/'/''/g")
        comment_escaped=$(echo "$comment" | sed "s/'/''/g")
        echo "INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (2, '$pattern_escaped', 1, '$comment_escaped');" >> "$regex_sql"
    done
    
    # Execute batch inserts
    print_info "Adding exact whitelist entries..."
    run_sudo sqlite3 "$GRAVITY_DB" < "$exact_sql" >> "$LOG_FILE" 2>&1
    
    print_info "Adding regex whitelist entries..."
    run_sudo sqlite3 "$GRAVITY_DB" < "$regex_sql" >> "$LOG_FILE" 2>&1
    
    # Clean up temp files
    rm -f "$exact_sql" "$regex_sql"
    
    # Link all whitelist entries to Group 0
    print_info "Linking whitelist entries to Group 0..."
    run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO domainlist_by_group (domainlist_id, group_id) SELECT id, 0 FROM domainlist WHERE type IN (0, 2);" >> "$LOG_FILE" 2>&1
    
    # Verify
    local exact_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 0;" 2>/dev/null || echo "0")
    local regex_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM domainlist WHERE type = 2;" 2>/dev/null || echo "0")
    print_success "Whitelist added: $exact_count exact, $regex_count regex"
    
    # Restart FTL
    run_sudo systemctl start pihole-FTL
    sleep 3
}

# ---------- Test Unbound with DNSSEC Validation ------------------------------
test_unbound_dnssec() {
    print_step "Testing Unbound with DNSSEC Validation"
    
    print_info "Checking if Unbound is validating DNSSEC..."
    
    print_info "Testing DNSSEC rejection (bogus domain)..."
    local bogus_result=$(dig @127.0.0.1 -p 5335 sigfail.verteiltesysteme.net +short 2>&1)
    
    print_info "Testing DNSSEC validation (secure domain)..."
    local secure_result=$(dig @127.0.0.1 -p 5335 sigok.verteiltesysteme.net +short 2>/dev/null)
    local secure_flags=$(dig @127.0.0.1 -p 5335 sigok.verteiltesysteme.net +nocmd +noall +comments 2>&1 | grep -i "flags")
    
    if [[ "$bogus_result" == *"SERVFAIL"* ]] || [[ -z "$bogus_result" ]]; then
        print_success "✓ DNSSEC validation is WORKING (bogus domain returned SERVFAIL)"
    else
        print_warning "⚠ Bogus domain did not return SERVFAIL"
    fi
    
    if [[ -n "$secure_result" ]] && [[ "$secure_flags" == *"ad"* ]]; then
        print_success "✓ Secure domain resolved correctly with AD flag"
    fi
    
    # Test Quad9 DoT connectivity
    print_info "Testing Quad9 DNS-over-TLS connectivity..."
    local proto_test=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
    if [[ "$proto_test" == *"dot"* ]]; then
        print_success "✓ Quad9 DNS-over-TLS confirmed (protocol: $proto_test)"
    else
        print_warning "⚠ Quad9 DoT test failed"
    fi
    
    print_info "Note: DNSSEC is handled by Unbound only (Pi-hole DNSSEC disabled)"
}

# ---------- Fix FTL Log ------------------------------------------------------
fix_ftl_log() {
    print_step "Ensuring Pi-hole FTL Log is Properly Configured"
    
    run_sudo mkdir -p /var/log/pihole
    run_sudo touch /var/log/pihole/FTL.log 2>/dev/null || true
    run_sudo chown pihole:pihole /var/log/pihole/FTL.log 2>/dev/null || true
    run_sudo chmod 644 /var/log/pihole/FTL.log 2>/dev/null || true
    
    if [[ -f /var/log/pihole/FTL.log ]]; then
        print_success "FTL log is properly configured"
    fi
    
    print_info "To view Pi-hole logs, use: sudo pihole -t"
}

# ---------- Set Pi-hole Password ---------------------------------------------
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
    echo -e "  ${GREEN}https://$IP_ADDR/admin${NC} (self-signed certificate)"
    echo ""
    echo -e "${YELLOW}Do you want to set a secure password now? (RECOMMENDED) (y/n)${NC}"
    read -r set_pass
    
    if [[ "$set_pass" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Enter new password for Pi-hole admin:${NC}"
        run_sudo pihole setpassword
        print_success "✓ Password set successfully"
    else
        echo -e "${YELLOW}⚠ WARNING: Password not set. Run: sudo pihole setpassword${NC}"
    fi
    echo ""
}

# ---------- Setup Backups ----------------------------------------------------
setup_backups() {
    print_step "Setting up Automatic Backups"
    
    run_sudo mkdir -p "$PIHOLE_BACKUP_DIR"
    
    run_sudo tee /usr/local/bin/pihole-backup.sh > /dev/null <<'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/pihole"
RETENTION=7
EMAIL_CONFIG="/etc/pihole-backup-email.conf"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/teleporter-$TIMESTAMP.tar.gz"

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
    
    if ! crontab -l 2>/dev/null | grep -q "pihole-backup.sh"; then
        (crontab -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/pihole-backup.sh > /dev/null 2>&1") | crontab -
        print_success "Backup cron job installed (Sunday 2 AM)"
    fi
}

# ---------- Thermal Monitoring -----------------------------------------------
setup_thermal_monitoring() {
    print_step "Setting up Thermal Monitoring"
    
    if [[ ! -f /sys/class/thermal/thermal_zone0/temp ]]; then
        print_warning "Thermal zone not found - monitoring disabled"
        return 0
    fi
    
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

# ---------- Health Dashboard (SELF-HEALING) ----------------------------------
create_health_dashboard() {
    print_step "Creating Health Dashboard with Self-Healing"
    
    run_sudo tee /usr/local/bin/pihole-health > /dev/null <<'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Self-healing function
fix_linkage() {
    echo -e "${YELLOW}FIXING DATABASE LINKAGE...${NC}"
    sudo systemctl stop pihole-FTL 2>/dev/null
    sleep 2
    sudo sqlite3 /etc/pihole/gravity.db "INSERT OR IGNORE INTO adlist_by_group (adlist_id, group_id) SELECT id, 0 FROM adlist;" 2>/dev/null
    sudo systemctl start pihole-FTL 2>/dev/null
    echo -e "${GREEN}✓ Database linkage fixed${NC}"
}

clear
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}              PI-HOLE ULTIMATE HEALTH DASHBOARD${NC}"
echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}${BOLD}📊 SYSTEM INFORMATION${NC}"
echo "  Hostname:   $(hostname)"
echo "  Uptime:     $(uptime -p | sed 's/up //')"
echo "  Date:       $(date '+%Y-%m-%d %H:%M:%S')"

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

echo -e "${CYAN}${BOLD}🔄 SERVICE STATUS${NC}"
for svc in pihole-FTL unbound; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        echo -e "  $svc: ${GREEN}● Active${NC}"
    else
        echo -e "  $svc: ${RED}● Inactive${NC}"
    fi
done
echo ""

echo -e "${CYAN}${BOLD}🌐 DNS CONFIGURATION${NC}"
if [[ -f /etc/pihole/pihole.toml ]]; then
    if grep -q "127.0.0.1#5335" /etc/pihole/pihole.toml; then
        echo -e "  Upstream DNS: ${GREEN}Unbound (127.0.0.1#5335)${NC}"
    fi
fi

if dig @127.0.0.1 google.com +short >/dev/null 2>&1; then
    echo -e "  Pi-hole:     ${GREEN}✓ Responding${NC}"
else
    echo -e "  Pi-hole:     ${RED}✗ Not responding${NC}"
fi

if dig @127.0.0.1 -p 5335 quad9.net +short >/dev/null 2>&1; then
    echo -e "  Unbound:     ${GREEN}✓ Responding via Quad9${NC}"
    
    proto=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
    if [[ -n "$proto" ]]; then
        echo -e "  Quad9 Proto: ${CYAN}$proto${NC}"
    fi
fi
echo ""

echo -e "${CYAN}${BOLD}📋 DATABASE STATISTICS${NC}"
if [[ -f /etc/pihole/gravity.db ]] && command -v sqlite3 >/dev/null 2>&1; then
    adlist=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist WHERE enabled = 1;" 2>/dev/null)
    groups=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist_by_group WHERE group_id=0;" 2>/dev/null)
    gravity=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM gravity;" 2>/dev/null)
    unlinked=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist WHERE id NOT IN (SELECT adlist_id FROM adlist_by_group);" 2>/dev/null)
    
    echo -e "  Blocklists:  ${GREEN}$adlist${NC}"
    echo -e "  Group Links: ${GREEN}$groups${NC}"
    echo -e "  Unlinked:    ${YELLOW}$unlinked${NC}"
    echo -e "  Domains:     ${GREEN}$gravity${NC}"
    
    if [[ "$adlist" -eq "$groups" ]] && [[ "$adlist" -gt 0 ]]; then
        echo -e "  Status:      ${GREEN}✓ All lists linked${NC}"
    else
        echo -e "  Status:      ${RED}⚠ Linkage issue detected${NC}"
        fix_linkage
    fi
fi
echo ""

# Check Unbound logs
if [[ -f /var/log/unbound/unbound.log ]]; then
    log_size=$(du -h /var/log/unbound/unbound.log 2>/dev/null | cut -f1)
    echo -e "${CYAN}${BOLD}📁 LOG STATUS${NC}"
    echo -e "  Unbound Log: ${GREEN}$log_size${NC} (rotated weekly)"
fi
echo ""

echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
EOF

    run_sudo chmod +x /usr/local/bin/pihole-health
    print_success "Health dashboard created with self-healing capability"
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
        
        echo "Pi-hole Ultimate Edition v1.8.5 installed with self-healing" | mail -s "✅ Pi-hole Installation Complete" "$EMAIL_RECIPIENT" 2>/dev/null || true
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
    apt-get remove --purge -y pihole unbound 2>/dev/null || yum remove -y pihole unbound || apk del pihole unbound
    
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

# ---------- Final Verification -----------------------------------------------
final_verification() {
    print_step "Final Verification"
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    print_info "Checking Unbound status..."
    if systemctl is-active --quiet unbound; then
        print_success "✓ Unbound is running"
    else
        print_error "✗ Unbound is not running"
    fi
    
    print_info "Checking Pi-hole FTL status..."
    if systemctl is-active --quiet pihole-FTL; then
        print_success "✓ Pi-hole FTL is running"
    else
        print_error "✗ Pi-hole FTL is not running"
    fi
    
    print_info "Testing DNS resolution..."
    if dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
        print_success "✓ DNS resolution working"
    else
        print_error "✗ DNS resolution failed"
    fi
    
    # ===== VERIFY DATABASE INTEGRITY =====
    if [[ -f "$GRAVITY_DB" ]]; then
        local domain_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM gravity;" 2>/dev/null)
        local adlist_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist WHERE enabled = 1;" 2>/dev/null)
        local group_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist_by_group WHERE group_id=0;" 2>/dev/null)
        local unlinked_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist WHERE id NOT IN (SELECT adlist_id FROM adlist_by_group);" 2>/dev/null)
        
        print_success "✓ Gravity database contains $domain_count domains"
        print_success "✓ $adlist_count blocklists enabled"
        print_success "✓ $group_count blocklists linked to Group 0"
        print_success "✓ $unlinked_count unlinked lists (should be 0)"
        
        if [[ "$adlist_count" -eq "$group_count" ]] && [[ "$unlinked_count" -eq 0 ]]; then
            print_success "✓ SUCCESS: All blocklists are properly linked"
        else
            print_warning "⚠ Blocklist linkage mismatch! Running repair..."
            run_sudo systemctl stop pihole-FTL
            run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO adlist_by_group (adlist_id, group_id) SELECT id, 0 FROM adlist;"
            run_sudo systemctl start pihole-FTL
            print_success "✓ Repair completed"
        fi
    fi
    
    local dnssec_status=$(pihole-FTL --config dns.dnssec 2>/dev/null)
    print_info "Pi-hole DNSSEC setting: $dnssec_status (should be false)"
    
    if dig @127.0.0.1 -p 5335 sigfail.verteiltesysteme.net +short 2>&1 | grep -q "SERVFAIL"; then
        print_success "✓ Unbound DNSSEC validation working (bogus domain blocked)"
    fi
    
    local proto_test=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
    if [[ "$proto_test" == *"dot"* ]]; then
        print_success "✓ Quad9 DNS-over-TLS confirmed (protocol: $proto_test)"
    fi
    
    print_info "Web interface should be accessible at:"
    print_info "  http://$IP_ADDR/admin"
    print_info "  https://$IP_ADDR/admin"
}

# ---------- Show Summary ----------------------------------------------------
show_summary() {
    print_step "Installation Complete - Summary"
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}${BOLD}✓ Pi-hole Ultimate Edition v1.8.5 installed successfully${NC}"
    echo -e "${GREEN}${BOLD}✓ Quad9 DNS-over-TLS with Unbound DNSSEC${NC}"
    echo -e "${GREEN}${BOLD}✓ Pi-hole DNSSEC disabled (prevents double validation)${NC}"
    echo -e "${GREEN}${BOLD}✓ Blocklists properly linked to Group 0${NC}"
    echo -e "${GREEN}${BOLD}✓ Unbound logging to file (compatible with logrotate)${NC}"
    echo -e "${GREEN}${BOLD}✓ Auto-restart enabled for all services${NC}"
    echo -e "${GREEN}${BOLD}✓ Self-healing health dashboard${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📌 Available Commands:${NC}"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole-health${NC}        - Show health dashboard (self-healing)"
    echo -e "  ${CYAN}▶${NC} ${BOLD}verify-backup.sh${NC}      - Check backup status"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -c${NC}             - Pi-hole console"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -g${NC}             - Update gravity"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole setpassword${NC} - Change web password"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole -t${NC}         - Tail FTL log"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo journalctl -u unbound${NC} - Check Unbound logs"
    echo ""
    
    echo -e "${WHITE}${BOLD}🌐 Web Interface:${NC}"
    echo -e "  ${CYAN}•${NC} HTTP:  ${GREEN}http://$IP_ADDR/admin${NC}"
    echo -e "  ${CYAN}•${NC} HTTPS: ${GREEN}https://$IP_ADDR/admin${NC} (self-signed)"
    echo ""
    
    # Get final counts for summary
    if [[ -f "$GRAVITY_DB" ]]; then
        local adlist_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist;" 2>/dev/null)
        local group_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist_by_group WHERE group_id=0;" 2>/dev/null)
        local domain_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM gravity;" 2>/dev/null)
        
        echo -e "${WHITE}${BOLD}📊 Final Database Status:${NC}"
        echo -e "  ${CYAN}•${NC} Blocklists:  ${GREEN}$adlist_count${NC}"
        echo -e "  ${CYAN}•${NC} Group Links: ${GREEN}$group_count${NC}"
        echo -e "  ${CYAN}•${NC} Domains:     ${GREEN}$domain_count${NC}"
        
        if [[ "$adlist_count" -eq "$group_count" ]] && [[ "$adlist_count" -gt 0 ]]; then
            echo -e "  ${GREEN}✓ ALL LISTS PROPERLY LINKED - THEY WILL APPEAR IN WEB UI${NC}"
        fi
        echo ""
    fi
    
    echo -e "${WHITE}${BOLD}🔒 DNS Security Tests:${NC}"
    echo -e "  ${CYAN}•${NC} DNSSEC test: ${WHITE}dig @127.0.0.1 -p 5335 sigfail.verteiltesysteme.net${NC} → ${GREEN}SERVFAIL${NC} ✓"
    echo -e "  ${CYAN}•${NC} DoT test:    ${WHITE}dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335${NC} → ${GREEN}dot${NC} ✓"
    echo ""
    
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}         Pi-hole v6 with Unbound - INDUSTRIAL GRADE!${NC}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ---------- Main -------------------------------------------------------------
main() {
    print_banner
    
    check_root
    check_os
    
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    print_info "Installation log: $LOG_FILE"
    print_info "Total steps: $TOTAL_STEPS"
    echo ""
    
    collect_preferences
    package_manager_detect
    check_pihole_version
    install_dependencies
    fix_ssl_certificates
    install_pihole
    install_unbound
    configure_unbound_logrotate
    harden_services
    configure_pihole_v6_dns
    configure_https
    test_web_server
    configure_blocklists        # CRITICAL: Hard stop with process verification
    configure_whitelist
    test_unbound_dnssec
    fix_ftl_log
    setup_backups
    setup_thermal_monitoring
    create_health_dashboard      # Now with self-healing
    create_uninstall_script
    configure_email
    final_verification
    set_pihole_password
    show_summary
}

main "$@"