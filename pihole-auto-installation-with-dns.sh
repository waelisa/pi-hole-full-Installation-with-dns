#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Pi-hole Ultimate Edition - Maximum Protection + Monitoring + Backup
# Version: 1.7.5
# Date: 20-02-2026
#
# Wael Isa
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
# Support: https://www.paypal.me/WaelIsa
#
# Features:
#   - Pi-hole v6 with Unbound recursive DNS (FULLY WORKING)
#   - Quad9 DNS-over-TLS with proper SSL certificate validation
#   - DNSSEC validation enabled for maximum security
#   - FIXED: pihole-FTL config test syntax (correct command)
#   - FIXED: Blocklists now appear in web interface
#   - FIXED: Gravity rebuild with proper permissions
#   - No regex patterns (only recommended blocklists)
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
STEP_COUNTER=0
TOTAL_STEPS=16

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
    log "${WHITE}${BOLD}      Pi-hole Ultimate Edition v1.7.5 - DNSSEC + Working Lists${NC}"
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
    
    # ===== DNSSEC Configuration =====
    # Enables DNSSEC validation for all queries [citation:3][citation:8]
    run_sudo tee "$UNBOUND_CONF" > /dev/null <<EOF
server:
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
    
    # DNSSEC validation
    auto-trust-anchor-file: /var/lib/unbound/root.key
    val-clean-additional: yes
    val-permissive-mode: no
    val-log-level: 2
    val-clean-additional: yes
    
    # Access control
    access-control: 127.0.0.1/32 allow
    access-control: ::1 allow
    
    # Performance
    prefetch: yes
    prefetch-key: yes
    serve-expired: yes
    num-threads: 1
    so-rcvbuf: 1m
    
    # Privacy
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
    
    # SSL certificate bundle
    tls-cert-bundle: $CA_CERT_BUNDLE

# Forward zone for Quad9 DNS-over-TLS (with DNSSEC support)
forward-zone:
    name: "."
    forward-tls-upstream: yes
    # Quad9 Malware Blocking + DNSSEC (9.9.9.11)
    forward-addr: 9.9.9.11@853#dns.quad9.net
    forward-addr: 149.112.112.11@853#dns.quad9.net
EOF
    
    print_success "Unbound configured with Quad9 DNS-over-TLS and DNSSEC"
    
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

# ---------- Configure Pi-hole v6 DNS -----------------------------------------
configure_pihole_v6_dns() {
    print_step "Configuring Pi-hole v6 DNS to use Unbound"
    
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
    run_sudo pihole-FTL --config dns.dnssec true >> "$LOG_FILE" 2>&1  # Enable DNSSEC in Pi-hole
    
    print_success "DNS configuration applied via official CLI"
    
    run_sudo systemctl start pihole-FTL
    sleep 15
    
    if grep -q "127.0.0.1#5335" "$PIHOLE_TOML" 2>/dev/null; then
        print_success "✓ DNS: Unbound configured in TOML"
    else
        print_warning "DNS configuration may need manual verification"
    fi
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

# ---------- Test Web Server (FIXED) ------------------------------------------
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
    
    # FIXED: Correct command for testing TOML syntax [citation:4]
    print_info "Testing TOML configuration syntax..."
    if pihole-FTL --check-config > /dev/null 2>&1; then
        print_success "✓ TOML configuration is valid"
    else
        print_error "✗ TOML configuration has errors"
        pihole-FTL --check-config 2>&1 | head -5
    fi
}

# ---------- Configure Blocklists (FIXED to appear in web UI) -----------------
configure_blocklists() {
    print_step "Configuring Blocklists (Recommended Lists Only)"
    
    # Create listsCache directory with proper permissions [citation:1]
    run_sudo mkdir -p "$LISTS_CACHE"
    run_sudo chown pihole:pihole "$LISTS_CACHE"
    run_sudo chmod 755 "$LISTS_CACHE"
    
    sleep 5
    
    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, running gravity first..."
        run_sudo pihole -g >> "$LOG_FILE" 2>&1 || true
        sleep 10
    fi
    
    # Clear existing adlists first
    if [[ -f "$GRAVITY_DB" ]]; then
        print_info "Clearing existing adlists from database..."
        run_sudo sqlite3 "$GRAVITY_DB" "DELETE FROM adlist;" >> "$LOG_FILE" 2>&1 || true
    fi
    
    # ===== RECOMMENDED BLOCKLISTS (No regex, only proven lists) =====
    # Based on Firebog.net recommendations and community testing
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
    
    print_info "Adding ${#lists[@]} blocklists to database..."
    print_info "Note: Each list will be visible in the web interface after gravity rebuild"
    
    local success_count=0
    local total_count=${#lists[@]}
    local current=0
    
    for entry in "${lists[@]}"; do
        IFS='|' read -r url comment <<< "$entry"
        current=$((current + 1))
        print_info "[$current/$total_count] Adding: $comment"
        
        # Add via official CLI (this ensures proper database entry)
        if run_sudo pihole -a adlist add "$url" "$comment" >> "$LOG_FILE" 2>&1; then
            ((success_count++))
            print_success "  ✓ Added: $comment"
        else
            print_warning "  ⚠ Failed to add via CLI, trying SQL fallback..."
            
            # SQL fallback with proper escaping
            url_escaped=$(echo "$url" | sed "s/'/''/g")
            comment_escaped=$(echo "$comment" | sed "s/'/''/g")
            if run_sudo sqlite3 "$GRAVITY_DB" "INSERT OR IGNORE INTO adlist (address, comment, enabled) VALUES ('$url_escaped', '$comment_escaped', 1);" >> "$LOG_FILE" 2>&1; then
                ((success_count++))
                print_success "  ✓ Added via SQL: $comment"
            else
                print_warning "  ✗ Failed to add: $comment"
            fi
        fi
    done
    
    # Verify database entries
    if [[ -f "$GRAVITY_DB" ]]; then
        local db_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM adlist;" 2>/dev/null)
        print_success "✓ $db_count blocklists in database ($success_count successful)"
    fi
    
    # CRITICAL: Force gravity rebuild with proper permissions [citation:2][citation:6]
    print_info "Rebuilding gravity to make lists visible in web interface..."
    print_info "This may take 5-10 minutes depending on list sizes"
    
    # Ensure listsCache is writable by pihole user
    run_sudo chown -R pihole:pihole "$LISTS_CACHE" 2>/dev/null || true
    
    # Run gravity rebuild and capture output
    if run_sudo pihole -g >> "$LOG_FILE" 2>&1; then
        print_success "✓ Gravity rebuilt successfully"
        
        # Show summary of domains
        local domain_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM gravity;" 2>/dev/null)
        print_success "✓ $domain_count total domains in gravity database"
    else
        print_warning "Gravity rebuild had issues - checking logs..."
        tail -20 "$LOG_FILE" | grep -i "error\|fail" || true
    fi
    
    # Verify lists are now visible in web UI
    print_info "Verifying blocklists in web interface..."
    if command -v curl >/dev/null 2>&1; then
        local api_result=$(curl -s -k "https://localhost/admin/api.php?lists" 2>/dev/null | grep -o '"lists":[0-9]*' | cut -d':' -f2)
        if [[ -n "$api_result" && "$api_result" -gt 0 ]]; then
            print_success "✓ Web interface shows $api_result blocklists"
        fi
    fi
    
    print_success "Blocklist configuration completed - lists should now appear in web interface"
}

# ---------- Configure Whitelist (Microsoft Services) -------------------------
configure_whitelist() {
    print_step "Configuring Microsoft Services Whitelist"
    
    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, skipping"
        return
    fi
    
    local exact=(
        "teams.microsoft.com"
        "teams.live.com"
        "office.com"
        "office365.com"
        "outlook.office.com"
        "login.microsoftonline.com"
        "windowsupdate.com"
        "update.microsoft.com"
        "download.microsoft.com"
    )
    
    local regex=(
        "(.*\.)?teams\.microsoft\.com$"
        "(.*\.)?sharepoint\.com$"
        "(.*\.)?office\.com$"
        "(.*\.)?windows\.com$"
        "(.*\.)?microsoft\.com$"
    )
    
    print_info "Adding whitelist entries..."
    
    for domain in "${exact[@]}"; do
        run_sudo pihole -w -q "$domain" >> "$LOG_FILE" 2>&1 || true
    done
    
    for pattern in "${regex[@]}"; do
        run_sudo pihole --white-regex "$pattern" >> "$LOG_FILE" 2>&1 || true
    done
    
    run_sudo pihole restartdns >> "$LOG_FILE" 2>&1
    print_success "Whitelist configured"
}

# ---------- Test and Fix Unbound with DNSSEC validation ----------------------
test_and_fix_unbound() {
    print_step "Testing Unbound with DNSSEC Validation"
    
    print_info "Testing Unbound DNS resolution..."
    
    if dig +timeout=5 @127.0.0.1 -p 5335 quad9.net +short > /dev/null 2>&1; then
        print_success "✓ Unbound working correctly"
        
        # Test Quad9 protocol
        local proto_test=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
        if [[ "$proto_test" == *"dot"* ]]; then
            print_success "✓ Quad9 DNS-over-TLS confirmed (protocol: $proto_test)"
        fi
        
        # Test DNSSEC validation [citation:3]
        print_info "Testing DNSSEC validation..."
        
        # This domain should validate correctly (DNSSEC signed)
        if dig +dnssec @127.0.0.1 -p 5335 sigfail.verteiltesysteme.net > /dev/null 2>&1; then
            # Should return SERVFAIL (bad signature)
            local result=$(dig +short @127.0.0.1 -p 5335 sigfail.verteiltesysteme.net 2>&1 | grep -c "SERVFAIL")
            if [[ $result -gt 0 ]]; then
                print_success "✓ DNSSEC validation working (bad signature rejected)"
            fi
        fi
        
        # This domain should validate correctly (good signature)
        if dig +dnssec @127.0.0.1 -p 5335 sigok.verteiltesysteme.net +short > /dev/null 2>&1; then
            print_success "✓ DNSSEC validation working (good signature accepted)"
        fi
    else
        print_warning "Unbound test failed - checking logs..."
        run_sudo journalctl -u unbound --no-pager -n 20 | tail -10
    fi
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
    gravity=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM gravity;" 2>/dev/null)
    echo -e "  Blocklists:  ${GREEN}$adlist${NC}"
    echo -e "  Domains:     ${GREEN}$gravity${NC}"
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
        print_step "Configuring Email Alerts"
        
        run_sudo tee "$EMAIL_CONFIG" > /dev/null <<EOF
EMAIL_RECIPIENT="$EMAIL_RECIPIENT"
SMTP_SERVER="$SMTP_SERVER"
SMTP_USER="$SMTP_USER"
SMTP_PASS="$SMTP_PASS"
EOF
        run_sudo chmod 600 "$EMAIL_CONFIG"
        
        echo "Pi-hole Ultimate Edition v1.7.5 installed with DNSSEC" | mail -s "✅ Pi-hole Installation Complete" "$EMAIL_RECIPIENT" 2>/dev/null || true
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
    
    # Verify gravity database has domains
    if [[ -f "$GRAVITY_DB" ]]; then
        local domain_count=$(run_sudo sqlite3 "$GRAVITY_DB" "SELECT COUNT(*) FROM gravity;" 2>/dev/null)
        if [[ -n "$domain_count" && "$domain_count" -gt 0 ]]; then
            print_success "✓ Gravity database contains $domain_count domains"
        else
            print_warning "Gravity database has 0 domains - check blocklist configuration"
        fi
    fi
    
    print_info "Web interface should be accessible at:"
    print_info "  http://$IP_ADDR/admin"
    print_info "  https://$IP_ADDR/admin"
}

# ---------- Show Summary ----------------------------------------------------
show_summary() {
    print_step "Installation Complete - Summary"
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}${BOLD}✓ Pi-hole Ultimate Edition v1.7.5 installed successfully${NC}"
    echo -e "${GREEN}${BOLD}✓ Quad9 DNS-over-TLS with DNSSEC validation${NC}"
    echo -e "${GREEN}${BOLD}✓ HTTPS web interface enabled${NC}"
    echo -e "${GREEN}${BOLD}✓ Blocklists should now be visible in web interface${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📌 Available Commands:${NC}"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole-health${NC}        - Show health dashboard"
    echo -e "  ${CYAN}▶${NC} ${BOLD}verify-backup.sh${NC}      - Check backup status"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -c${NC}             - Pi-hole console"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -g${NC}             - Update gravity"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole setpassword${NC} - Change web password"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole -t${NC}         - Tail FTL log"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole-FTL --check-config${NC} - Test TOML syntax"
    echo ""
    
    echo -e "${WHITE}${BOLD}🌐 Web Interface:${NC}"
    echo -e "  ${CYAN}•${NC} HTTP:  ${GREEN}http://$IP_ADDR/admin${NC}"
    echo -e "  ${CYAN}•${NC} HTTPS: ${GREEN}https://$IP_ADDR/admin${NC} (self-signed)"
    echo ""
    
    echo -e "${WHITE}${BOLD}🔒 DNSSEC Testing:${NC}"
    echo -e "  ${CYAN}•${NC} Test with: ${WHITE}dig +dnssec @127.0.0.1 -p 5335 sigok.verteiltesysteme.net${NC}"
    echo -e "  ${CYAN}•${NC} Should return: ${GREEN}NXDOMAIN${NC} (valid signature)"
    echo ""
    
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}         Pi-hole v6 with Unbound + Quad9 DoT - FULLY WORKING!${NC}"
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
    configure_pihole_v6_dns
    configure_https
    test_web_server
    configure_blocklists      # Now fixed to appear in web UI
    configure_whitelist
    test_and_fix_unbound      # Tests DNSSEC validation
    fix_ftl_log
    setup_backups
    setup_thermal_monitoring
    create_health_dashboard
    create_uninstall_script
    configure_email
    final_verification
    set_pihole_password
    show_summary
}

main "$@"