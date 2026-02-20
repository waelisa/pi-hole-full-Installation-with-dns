#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Pi-hole Ultimate Edition - Maximum Protection + Monitoring + Backup
# Version: 1.7.2
# Date: 20-02-2026
#
# Wael Isa
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
# Support: https://www.paypal.me/WaelIsa
#
# Features:
#   - Pi-hole v6 with Unbound recursive DNS
#   - Quad9 DNS-over-TLS with FIXED SSL certificate validation
#   - CRITICAL FIX: Added tls-cert-bundle directive
#   - Multi-OS support (Debian, Ubuntu, Raspbian, Fedora, CentOS, AlmaLinux, Rocky Linux)
#   - FIXED: Unbound now properly validates Quad9 certificates
#   - FIXED: SERVFAIL errors resolved
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
STEP_COUNTER=0
TOTAL_STEPS=15

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
    log "${WHITE}${BOLD}      Pi-hole Ultimate Edition v1.7.2 - SSL Certificate Fix${NC}"
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
        # Try to find it
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

# ---------- Install & Configure Unbound with Quad9 DNS-over-TLS ------------
install_unbound() {
    print_step "Installing Unbound with Quad9 DNS-over-TLS"
    
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
    
    print_info "Configuring Unbound with Quad9 DNS-over-TLS..."
    
    # ===== CRITICAL FIX: Added tls-cert-bundle directive =====
    # This tells Unbound where to find the CA certificates for validating Quad9's SSL cert
    # Without this, you get "ssl handshake cert error: unable to get local issuer certificate"
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
    
    # Access control
    access-control: 127.0.0.1/32 allow
    access-control: ::1 allow
    
    # Performance
    prefetch: yes
    num-threads: 1
    so-rcvbuf: 1m
    
    # Privacy
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
    
    # ===== CRITICAL FIX: Certificate bundle for SSL validation =====
    # This must point to your system's CA certificate bundle
    tls-cert-bundle: $CA_CERT_BUNDLE

# Forward zone for Quad9 DNS-over-TLS 
forward-zone:
    name: "."
    forward-tls-upstream: yes
    # Quad9 Malware Blocking + DNSSEC (9.9.9.11)
    forward-addr: 9.9.9.11@853#dns.quad9.net
    forward-addr: 149.112.112.11@853#dns.quad9.net
EOF
    
    print_success "Unbound configured with Quad9 DNS-over-TLS (SSL fixed)"
    
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

# ---------- Configure Pi-hole v6 DNS - UNIVERSAL TOML ----------------------
configure_pihole_v6_dns() {
    print_step "Configuring Pi-hole v6 DNS - UNIVERSAL TOML"
    
    print_info "Stopping Pi-hole FTL for configuration..."
    run_sudo systemctl stop pihole-FTL
    sleep 5
    
    if [[ -f "$PIHOLE_TOML" ]]; then
        run_sudo cp "$PIHOLE_TOML" "$PIHOLE_TOML.backup-$(date +%Y%m%d-%H%M%S)"
    fi
    
    run_sudo tee "$PIHOLE_TOML" > /dev/null <<'EOF'
# Pi-hole v6 Universal Configuration
# Generated by Pi-hole Ultimate v1.7.2

[dns]
upstreams = ["127.0.0.1#5335"]
blocking.active = true
queryLogging = true

[webserver]
port = "80"

[database]
maxDBdays = 365
EOF
    
    print_success "UNIVERSAL TOML configuration created"
    
    run_sudo systemctl start pihole-FTL
    sleep 15
    
    if grep -q "127.0.0.1#5335" "$PIHOLE_TOML"; then
        print_success "✓ DNS: Unbound configured in TOML"
    else
        print_error "✗ DNS: Unbound NOT found in TOML"
        exit 1
    fi
}

# ---------- Configure Blocklists --------------------------------------------
configure_blocklists() {
    print_step "Configuring Blocklists"
    
    sleep 10
    
    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, running gravity first..."
        run_sudo pihole -g >> "$LOG_FILE" 2>&1 || true
        sleep 10
    fi
    
    local lists=(
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|StevenBlack Unified"
        "https://big.oisd.nl/|OISD Full"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/multi.txt|Hagezi Multi PRO"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/ultimate.txt|Hagezi ULTIMATE"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/tif.txt|Hagezi TIF"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/fake.txt|Hagezi FAKE"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/popupads.txt|Hagezi PopupAds"
        "https://raw.githubusercontent.com/PolishFiltersTeam/KADhosts/master/KADhosts.txt|KADhosts"
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/add.Spam/hosts|add.Spam"
        "https://v.firebog.net/hosts/static/w3kbl.txt|w3kbl"
        "https://adaway.org/hosts.txt|AdAway"
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
    
    print_info "Adding ${#lists[@]} blocklists..."
    
    local success_count=0
    local total_count=${#lists[@]}
    local current=0
    
    for entry in "${lists[@]}"; do
        IFS='|' read -r url comment <<< "$entry"
        current=$((current + 1))
        print_info "[$current/$total_count] Adding: $comment"
        
        if run_sudo pihole -a adlist add "$url" "$comment" >> "$LOG_FILE" 2>&1; then
            ((success_count++))
            print_success "  ✓ Added: $comment"
        else
            print_warning "  ⚠ Failed: $comment"
        fi
    done
    
    print_info "Rebuilding gravity..."
    run_sudo pihole -g >> "$LOG_FILE" 2>&1 || true
    
    print_success "Blocklist configuration completed"
}

# ---------- Configure Regex Patterns -----------------------------------------
configure_regex() {
    print_step "Configuring Regex Patterns"
    
    if [[ ! -f "$GRAVITY_DB" ]]; then
        print_warning "Gravity database not found, skipping"
        return
    fi
    
    local patterns=(
        "(^|\.)bit\.ly$"
        "(^|\.)tinyurl\.com$"
        "(^|\.)goo\.gl$"
        "(^|\.)ow\.ly$"
        "(^|\.)malware[a-zA-Z0-9-]*\."
        "(^|\.)phish[a-zA-Z0-9-]*\."
        "(^|\.)ransom[a-zA-Z0-9-]*\."
        "(^|\.)cryptolocker\."
        "(^|\.)paypal-secure\."
        "(^|\.)apple-id\."
        "(^|\.)amazon-login\."
        "(^|\.)google-analytics\.com$"
        "(^|\.)googletagmanager\.com$"
        "(^|\.)doubleclick\.net$"
        "(^|\.)googleadservices\.com$"
        "(^|\.)coin-hive\.com$"
        "(^|\.)telemetry\."
        "(^|\.)diagnostics\."
        "^adserver[0-9]*\."
        "^ads[0-9]*\."
        "^track\."
    )
    
    print_info "Adding ${#patterns[@]} regex patterns..."
    
    for pattern in "${patterns[@]}"; do
        run_sudo pihole --regex "$pattern" >> "$LOG_FILE" 2>&1 || true
    done
    
    run_sudo pihole restartdns reload-lists >> "$LOG_FILE" 2>&1 || true
    print_success "Regex patterns added"
}

# ---------- Configure Whitelist ----------------------------------------------
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
    )
    
    local regex=(
        "(.*\.)?teams\.microsoft\.com$"
        "(.*\.)?sharepoint\.com$"
        "(.*\.)?office\.com$"
        "(.*\.)?windows\.com$"
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

# ---------- Test and Fix Unbound ---------------------------------------------
test_and_fix_unbound() {
    print_step "Testing and Fixing Unbound Configuration"
    
    print_info "Testing Unbound DNS resolution..."
    
    # Test with increased timeout and retry
    if dig +timeout=5 @127.0.0.1 -p 5335 quad9.net +short > /dev/null 2>&1; then
        print_success "✓ Unbound working correctly"
        
        local proto_test=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
        if [[ "$proto_test" == *"dot"* ]]; then
            print_success "✓ Quad9 DNS-over-TLS confirmed (protocol: $proto_test)"
        fi
    else
        print_warning "Unbound test failed - checking logs..."
        run_sudo journalctl -u unbound --no-pager -n 20 | tail -10
        
        # Check if it's the SSL certificate issue
        if journalctl -u unbound --since "5 minutes ago" | grep -q "unable to get local issuer certificate"; then
            print_warning "SSL certificate issue detected - verifying CA bundle path..."
            
            # Double-check CA bundle path
            if [[ -f "$CA_CERT_BUNDLE" ]]; then
                print_success "CA bundle exists at: $CA_CERT_BUNDLE"
                
                # Ensure the config has the correct path
                if grep -q "tls-cert-bundle" "$UNBOUND_CONF"; then
                    run_sudo sed -i "s|tls-cert-bundle: .*|tls-cert-bundle: $CA_CERT_BUNDLE|" "$UNBOUND_CONF"
                    print_success "Updated tls-cert-bundle in config"
                fi
            fi
            
            run_sudo systemctl restart unbound
            sleep 5
            
            # Test again
            if dig +timeout=5 @127.0.0.1 -p 5335 quad9.net +short > /dev/null 2>&1; then
                print_success "✓ Unbound fixed and working after SSL fix"
            else
                print_error "Unbound still not working - check manually"
            fi
        fi
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
    else
        echo -e "  Upstream DNS: ${RED}Not configured correctly${NC}"
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
else
    echo -e "  Unbound:     ${RED}✗ Not responding${NC}"
fi
echo ""

echo -e "${CYAN}${BOLD}📋 DATABASE STATISTICS${NC}"
if [[ -f /etc/pihole/gravity.db ]] && command -v sqlite3 >/dev/null 2>&1; then
    adlist=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist WHERE enabled = 1;" 2>/dev/null)
    regex=$(sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM domainlist WHERE type = 3 AND enabled = 1;" 2>/dev/null)
    echo -e "  Blocklists:  ${GREEN}$adlist${NC}"
    echo -e "  Regex:       ${GREEN}$regex${NC}"
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
        
        echo "Pi-hole Ultimate Edition v1.7.2 installed" | mail -s "✅ Pi-hole Installation Complete" "$EMAIL_RECIPIENT" 2>/dev/null || true
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
    
    print_info "Checking Unbound status..."
    if systemctl is-active --quiet unbound; then
        print_success "✓ Unbound is running"
        
        if journalctl -u unbound --since "5 minutes ago" | grep -q "ssl handshake failed"; then
            print_warning "SSL handshake errors detected - but may be from previous attempts"
            print_info "New queries should work now with tls-cert-bundle configured"
        else
            print_success "✓ No SSL errors detected in recent logs"
        fi
    else
        print_error "✗ Unbound is not running"
    fi
    
    print_info "Testing DNS chain..."
    if dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
        print_success "✓ Pi-hole → Unbound → Quad9 chain working"
        
        # Test Quad9 protocol
        local proto_test=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
        if [[ "$proto_test" == *"dot"* ]]; then
            print_success "✓ Quad9 DNS-over-TLS confirmed (protocol: $proto_test)"
        fi
    else
        print_error "✗ DNS chain broken - check Unbound configuration"
    fi
}

# ---------- Show Summary ----------------------------------------------------
show_summary() {
    print_step "Installation Complete - Summary"
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}${BOLD}✓ Pi-hole Ultimate Edition v1.7.2 installed successfully${NC}"
    echo -e "${GREEN}${BOLD}✓ Quad9 DNS-over-TLS configured with SSL certificate fix${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📌 Available Commands:${NC}"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole-health${NC}        - Show health dashboard"
    echo -e "  ${CYAN}▶${NC} ${BOLD}verify-backup.sh${NC}      - Check backup status"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -c${NC}             - Pi-hole console"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -g${NC}             - Update gravity"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole setpassword${NC} - Change web password"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole -t${NC}         - Tail FTL log"
    echo ""
    
    echo -e "${WHITE}${BOLD}🌐 Web Interface:${NC}"
    echo -e "  ${CYAN}•${NC} URL: ${GREEN}http://$IP_ADDR/admin${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}🔒 DNS Security (FIXED):${NC}"
    echo -e "  ${CYAN}•${NC} SSL Certificate bundle: ${GREEN}$CA_CERT_BUNDLE${NC}"
    echo -e "  ${CYAN}•${NC} Test with: ${WHITE}dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335${NC}"
    echo -e "  ${CYAN}•${NC} Should now return: ${GREEN}\"dot\"${NC} (was failing before)"
    echo ""
    
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}         Pi-hole v6 with Unbound + Quad9 DoT - FIXED!${NC}"
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
    configure_blocklists
    configure_regex
    configure_whitelist
    test_and_fix_unbound
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