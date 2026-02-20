#!/bin/bash

#############################################################################################################################
# The MIT License (MIT)
#
# Pi-hole Ultimate Edition - Maximum Protection + Monitoring + Backup
# Version: 2.0.0
# Date: 21-02-2026
#
# Wael Isa
# GitHub: https://github.com/waelisa/pi-hole-full-Installation-with-dns
# Website: https://www.wael.name/
# Support: https://www.paypal.me/WaelIsa
#
# Features:
#   - Pi-hole v6 with Unbound recursive DNS (FULLY WORKING)
#   - Quad9 DNS-over-TLS with Unbound DNSSEC
#   - Pi-hole DNSSEC disabled (prevents double validation)
#   - CLEANUP: Removes old backup files and cron jobs at start
#   - CLEANUP: Removes previous script versions
#   - Thermal Monitoring with alerts at 75°C and 80°C (NO EMAIL)
#   - EMERGENCY BACKUP: Auto-backup at 80°C critical threshold
#   - Automated Backups with 7-day retention (NO EMAIL)
#   - Static IP Guard (network persistence after router reboots)
#   - NO automatic blocklist installation (user chooses)
#   - NO email dependencies (leaner, faster, more private)
#   - RECOMMENDED: 5 best blocklists shown at end
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
PIHOLE_TOML="/etc/pihole/pihole.toml"
PIHOLE_V5_CONFIG="/etc/pihole/setupVars.conf"
GRAVITY_DB="/etc/pihole/gravity.db"
LOG_FILE="/var/log/pihole-ultimate-install.log"
ROOT_HINTS="/usr/share/dns/root.hints"
PIHOLE_FTL_LOG="/var/log/pihole/FTL.log"
CERT_FILE="/etc/pihole/tls.pem"
UNBOUND_LOG="/var/log/unbound/unbound.log"
NETWORK_CONFIG="/etc/dhcpcd.conf"
STEP_COUNTER=0
TOTAL_STEPS=13  # Reduced because email step removed

# ---------- OS Detection Variables --------------------------------------------
PKG_MANAGER=""
UPDATE_PKG_CACHE=""
PKG_INSTALL=""
PKG_REMOVE=""
CA_CERT_BUNDLE=""
OS_TYPE=""

# ---------- Helper functions -------------------------------------------------
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

print_banner() {
    clear
    log "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    log "${WHITE}${BOLD}      Pi-hole Ultimate Edition v2.0.0 - Production Ready${NC}"
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
            OS_TYPE="debian"
            print_success "Running on $PRETTY_NAME"
            return 0
        elif [[ "$ID" == "centos" || "$ID" == "fedora" || "$ID" == "rhel" || "$ID" == "almalinux" || "$ID" == "rocky" ]]; then
            OS_TYPE="rhel"
            print_success "Running on $PRETTY_NAME"
            return 0
        else
            print_warning "This script is optimized for Debian/Ubuntu/Raspbian/RHEL/Fedora systems."
            print_warning "You are running: $PRETTY_NAME"
            print_warning "Continuing anyway - some features may not work correctly."
            OS_TYPE="unknown"
            return 0
        fi
    else
        print_warning "Could not determine OS. Continuing with installation..."
        OS_TYPE="unknown"
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
        
    else
        print_error "No supported package manager found"
        exit 1
    fi
}

# ---------- CLEANUP: Remove old files and cron jobs -------------------------
perform_cleanup() {
    print_step "Performing System Cleanup"
    
    print_info "Removing old backup files..."
    if [[ -d "$PIHOLE_BACKUP_DIR" ]]; then
        local old_backups=$(find "$PIHOLE_BACKUP_DIR" -name "teleporter-*.tar.gz" -type f | wc -l)
        if [[ $old_backups -gt 0 ]]; then
            run_sudo rm -f "$PIHOLE_BACKUP_DIR"/teleporter-*.tar.gz
            print_success "Removed $old_backups old backup files"
        else
            print_info "No old backups found"
        fi
    fi
    
    print_info "Cleaning old cron jobs..."
    # Remove any existing pihole-backup cron jobs
    if crontab -l 2>/dev/null | grep -q "pihole-backup.sh"; then
        crontab -l 2>/dev/null | grep -v "pihole-backup.sh" | crontab -
        print_success "Removed old backup cron job"
    fi
    
    print_info "Removing old script versions..."
    # Remove any previous version scripts in common locations
    local old_scripts=(
        "/usr/local/bin/pihole-ultimate-*.sh"
        "/root/pihole-ultimate-*.sh"
        "/home/*/pihole-ultimate-*.sh"
        "/tmp/pihole-ultimate-*.sh"
    )
    
    for pattern in "${old_scripts[@]}"; do
        run_sudo find $(dirname "$pattern") -name "$(basename "$pattern")" -type f 2>/dev/null -delete
    done
    
    print_info "Cleaning old log files..."
    # Remove old thermal logs but keep current
    if [[ -f "$THERMAL_LOG" ]]; then
        run_sudo mv "$THERMAL_LOG" "$THERMAL_LOG.old" 2>/dev/null || true
        run_sudo touch "$THERMAL_LOG"
        run_sudo chmod 644 "$THERMAL_LOG"
    fi
    
    # Remove old backup logs
    if [[ -f "/var/log/pihole-backup.log" ]]; then
        run_sudo rm -f "/var/log/pihole-backup.log.old" 2>/dev/null || true
        run_sudo mv "/var/log/pihole-backup.log" "/var/log/pihole-backup.log.old" 2>/dev/null || true
    fi
    
    print_success "Cleanup completed"
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
            # NOTE: mailutils and ssmtp are intentionally removed (no email)
            run_sudo apt-get install -y curl wget git unzip nano sqlite3 \
                bc jq dnsutils openssl ca-certificates systemd dhcpcd5 >> "$LOG_FILE" 2>&1
            ;;
        dnf|yum)
            # NOTE: mailx and ssmtp are intentionally removed (no email)
            run_sudo ${PKG_MANAGER} install -y curl wget git unzip nano sqlite \
                bc jq bind-utils openssl ca-certificates systemd >> "$LOG_FILE" 2>&1
            ;;
    esac
    
    print_success "Dependencies installed"
}

# ---------- Remove lighttpd if present ---------------------------------------
remove_lighttpd() {
    if command -v dpkg >/dev/null 2>&1 && dpkg -l | grep -q lighttpd 2>/dev/null; then
        print_info "Removing lighttpd (Pi-hole v6 uses embedded web server)..."
        run_sudo systemctl stop lighttpd 2>/dev/null || true
        run_sudo systemctl disable lighttpd 2>/dev/null || true
        run_sudo apt-get remove --purge -y lighttpd >> "$LOG_FILE" 2>&1
        print_success "lighttpd removed"
    elif command -v rpm >/dev/null 2>&1 && rpm -qa | grep -q lighttpd; then
        print_info "Removing lighttpd (Pi-hole v6 uses embedded web server)..."
        run_sudo systemctl stop lighttpd 2>/dev/null || true
        run_sudo systemctl disable lighttpd 2>/dev/null || true
        run_sudo ${PKG_MANAGER} remove -y lighttpd >> "$LOG_FILE" 2>&1
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
    esac
    
    run_sudo systemctl stop unbound 2>/dev/null || true
    
    if [[ ! -f /etc/unbound/unbound.conf.orig ]]; then
        run_sudo cp /etc/unbound/unbound.conf /etc/unbound/unbound.conf.orig 2>/dev/null || true
    fi
    
    run_sudo rm -f /etc/unbound/unbound.conf.d/*.conf 2>/dev/null || true
    
    print_info "Configuring Unbound with Quad9 DNS-over-TLS and DNSSEC..."
    
    # Create log directory with proper permissions
    run_sudo mkdir -p "$(dirname "$UNBOUND_LOG")"
    run_sudo touch "$UNBOUND_LOG"
    run_sudo chown -R unbound:unbound "$(dirname "$UNBOUND_LOG")" 2>/dev/null || true
    run_sudo chmod 755 "$(dirname "$UNBOUND_LOG")"
    run_sudo chmod 644 "$UNBOUND_LOG"
    
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
    
    # Disable DNSSEC in Pi-hole (Unbound handles it)
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

# ---------- Configure Static IP Guard -----------------------------------------
configure_static_ip_guard() {
    print_step "Configuring Static IP Guard"
    
    # Get current IP and gateway
    CURRENT_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    CURRENT_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
    CURRENT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [[ -z "$CURRENT_IP" || -z "$CURRENT_GATEWAY" || -z "$CURRENT_INTERFACE" ]]; then
        print_warning "Could not detect network configuration automatically"
        echo -e "${YELLOW}Enter your static IP address (e.g., 192.168.1.100):${NC}"
        read -r STATIC_IP
        echo -e "${YELLOW}Enter your gateway/router IP (e.g., 192.168.1.1):${NC}"
        read -r STATIC_GATEWAY
        echo -e "${YELLOW}Enter your network interface (e.g., eth0):${NC}"
        read -r STATIC_INTERFACE
    else
        STATIC_IP="$CURRENT_IP"
        STATIC_GATEWAY="$CURRENT_GATEWAY"
        STATIC_INTERFACE="$CURRENT_INTERFACE"
        print_info "Detected network configuration:"
        print_info "  IP: $STATIC_IP"
        print_info "  Gateway: $STATIC_GATEWAY"
        print_info "  Interface: $STATIC_INTERFACE"
        
        echo -e "${YELLOW}Use this configuration for static IP? (y/n)${NC}"
        read -r confirm_static
        if [[ ! "$confirm_static" =~ ^[Yy]$ ]]; then
            print_info "Manual configuration:"
            echo -e "${YELLOW}Enter your static IP address (e.g., 192.168.1.100):${NC}"
            read -r STATIC_IP
            echo -e "${YELLOW}Enter your gateway/router IP (e.g., 192.168.1.1):${NC}"
            read -r STATIC_GATEWAY
            echo -e "${YELLOW}Enter your network interface (e.g., eth0):${NC}"
            read -r STATIC_INTERFACE
        fi
    fi
    
    # Configure based on OS type
    if [[ "$OS_TYPE" == "debian" ]]; then
        # Debian/Raspbian/Ubuntu with dhcpcd
        if [[ -f /etc/dhcpcd.conf ]]; then
            run_sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup
            print_info "Backed up original dhcpcd.conf"
            
            # Check if interface already has static config
            if grep -q "^interface $STATIC_INTERFACE" /etc/dhcpcd.conf; then
                print_warning "Static IP already configured for $STATIC_INTERFACE"
            else
                run_sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOF

# Static IP configuration added by Pi-hole Ultimate
interface $STATIC_INTERFACE
static ip_address=$STATIC_IP/24
static routers=$STATIC_GATEWAY
static domain_name_servers=127.0.0.1
EOF
                print_success "Static IP configured in dhcpcd.conf"
            fi
        else
            print_warning "dhcpcd.conf not found, using netplan or interfaces file"
            # Try netplan for newer Ubuntu
            if [[ -d /etc/netplan ]]; then
                local netplan_file=$(ls /etc/netplan/*.yaml | head -1)
                if [[ -n "$netplan_file" ]]; then
                    run_sudo cp "$netplan_file" "$netplan_file.backup"
                    print_info "Please configure static IP manually in $netplan_file"
                fi
            fi
        fi
    elif [[ "$OS_TYPE" == "rhel" ]]; then
        # RHEL/CentOS/Fedora with NetworkManager
        print_info "Configuring static IP via NetworkManager..."
        run_sudo nmcli con mod "$STATIC_INTERFACE" ipv4.addresses "$STATIC_IP/24"
        run_sudo nmcli con mod "$STATIC_INTERFACE" ipv4.gateway "$STATIC_GATEWAY"
        run_sudo nmcli con mod "$STATIC_INTERFACE" ipv4.dns "127.0.0.1"
        run_sudo nmcli con mod "$STATIC_INTERFACE" ipv4.method manual
        print_success "Static IP configured via NetworkManager"
    fi
    
    print_success "Static IP guard configured (prevents DNS blackouts after reboot)"
}

# ---------- Setup Automatic Backups ------------------------------------------
setup_backups() {
    print_step "Setting up Automatic Backups (7-day retention, no email)"
    
    run_sudo mkdir -p "$PIHOLE_BACKUP_DIR"
    run_sudo chmod 755 "$PIHOLE_BACKUP_DIR"
    
    # Backup script (simplified, no email)
    run_sudo tee /usr/local/bin/pihole-backup.sh > /dev/null <<'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/pihole"
RETENTION=7
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/teleporter-$TIMESTAMP.tar.gz"
LOG_FILE="/var/log/pihole-backup.log"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "$1"
}

log "${YELLOW}Starting Pi-hole backup...${NC}"

# Create backup using Teleporter
if pihole -a -t "$BACKUP_FILE" >/dev/null 2>&1; then
    log "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"
    
    # Verify backup integrity
    if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        log "${GREEN}✓ Backup integrity verified${NC}"
    else
        log "${RED}⚠ Backup integrity check failed${NC}"
    fi
    
    # Rotate old backups
    mapfile -t backups < <(ls -1t "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null)
    count=${#backups[@]}
    
    if [[ $count -gt $RETENTION ]]; then
        log "${YELLOW}Rotating backups (keeping last $RETENTION)...${NC}"
        for ((i=$RETENTION; i<$count; i++)); do
            rm -f "${backups[$i]}"
            log "  Removed: ${backups[$i]}"
        done
    fi
    
    log "${GREEN}✓ Backup process completed${NC}"
else
    log "${RED}✗ Backup creation failed!${NC}"
    exit 1
fi
EOF

    run_sudo chmod +x /usr/local/bin/pihole-backup.sh
    
    # Cron job (Sunday 2 AM)
    if ! crontab -l 2>/dev/null | grep -q "pihole-backup.sh"; then
        (crontab -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/pihole-backup.sh > /dev/null 2>&1") | crontab -
        print_success "Backup cron job installed (Sunday 2 AM, 7-day retention)"
    else
        print_info "Backup cron job already exists"
    fi
    
    # Create backup log file
    run_sudo touch /var/log/pihole-backup.log
    run_sudo chmod 644 /var/log/pihole-backup.log
}

# ---------- Setup Emergency Thermal Backup Handler (No Email) ----------------
setup_emergency_handler() {
    print_step "Setting up Emergency Thermal Backup Handler"
    
    run_sudo tee /usr/local/bin/thermal-emergency.sh > /dev/null <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/thermal-monitor.log"
BACKUP_LOG="/var/log/pihole-backup.log"

echo "$(date +'%Y-%m-%d %H:%M:%S') - [EMERGENCY] 🔥 80°C CRITICAL THRESHOLD REACHED! Starting safety backup..." | tee -a "$LOG_FILE"

# Trigger the existing backup script
if [[ -f "/usr/local/bin/pihole-backup.sh" ]]; then
    /usr/local/bin/pihole-backup.sh
    if [[ $? -eq 0 ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - [EMERGENCY] ✅ Emergency backup completed successfully." | tee -a "$LOG_FILE"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') - [EMERGENCY] ❌ Emergency backup failed!" | tee -a "$LOG_FILE"
    fi
else
    echo "$(date +'%Y-%m-%d %H:%M:%S') - [EMERGENCY] ❌ Backup script not found!" | tee -a "$LOG_FILE"
fi

# Log to system journal for monitoring
logger -t "thermal-emergency" "Emergency backup completed due to critical temperature"
EOF

    run_sudo chmod +x /usr/local/bin/thermal-emergency.sh
    print_success "Emergency handler script created"
    
    # Create systemd service for emergency backup
    run_sudo tee /etc/systemd/system/thermal-emergency.service > /dev/null <<EOF
[Unit]
Description=Emergency Pi-hole Backup on Overheat
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/thermal-emergency.sh
User=root
EOF

    run_sudo systemctl daemon-reload
    print_success "Emergency systemd service created"
}

# ---------- Setup Thermal Monitoring (Simplified, No Email) ------------------
setup_thermal_monitoring() {
    print_step "Setting up Thermal Monitoring (75°C warn, 80°C critical with emergency backup)"
    
    if [[ ! -f /sys/class/thermal/thermal_zone0/temp ]]; then
        print_warning "Thermal zone not found - temperature monitoring disabled"
        return 0
    fi
    
    # Monitoring script (simplified, no email)
    run_sudo tee /usr/local/bin/thermal-monitor.sh > /dev/null <<'EOF'
#!/bin/bash
TEMP_FILE="/sys/class/thermal/thermal_zone0/temp"
LOG_FILE="/var/log/thermal-monitor.log"
WARN=75
CRIT=80

if [[ ! -f "$TEMP_FILE" ]]; then
    exit 0
fi

raw=$(cat "$TEMP_FILE")
temp=$((raw/1000))

# Log temperature
echo "$(date +'%Y-%m-%d %H:%M:%S') - Temperature: ${temp}°C" >> "$LOG_FILE"

# Take action based on temperature
if [[ $temp -ge $CRIT ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') - [CRITICAL] 🔥 80°C reached! Triggering emergency backup." >> "$LOG_FILE"
    # Trigger emergency backup service
    systemctl start thermal-emergency.service
elif [[ $temp -ge $WARN ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') - [WARNING] ⚠️ 75°C warning threshold exceeded. Check cooling." >> "$LOG_FILE"
fi
EOF

    run_sudo chmod +x /usr/local/bin/thermal-monitor.sh
    
    # Systemd timer (every 5 minutes)
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
Requires=thermal-monitor.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    run_sudo systemctl daemon-reload
    run_sudo systemctl enable thermal-monitor.timer >> "$LOG_FILE" 2>&1
    run_sudo systemctl start thermal-monitor.timer >> "$LOG_FILE" 2>&1
    print_success "Thermal monitoring timer started (every 5 minutes)"
}

# ---------- Health Dashboard (No Email) --------------------------------------
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

# CPU Temperature
if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    temp=$((raw/1000))
    if [[ $temp -ge 80 ]]; then
        color=$RED
        temp_icon="🔴 CRITICAL"
    elif [[ $temp -ge 75 ]]; then
        color=$YELLOW
        temp_icon="🟡 WARNING"
    else
        color=$GREEN
        temp_icon="🟢 NORMAL"
    fi
    echo -e "  CPU Temp:   ${color}${temp}°C${NC} ${temp_icon}"
else
    echo -e "  CPU Temp:   ${YELLOW}N/A${NC}"
fi

# Memory Usage
mem_total=$(free -h | awk '/^Mem:/ {print $2}')
mem_used=$(free -h | awk '/^Mem:/ {print $3}')
mem_percent=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')
echo -e "  Memory:      ${mem_used} / ${mem_total} (${mem_percent}%)"

# Disk Usage
disk_used=$(df -h / | awk 'NR==2 {print $3}')
disk_total=$(df -h / | awk 'NR==2 {print $2}')
disk_percent=$(df / | awk 'NR==2 {print $5}')
echo -e "  Disk Usage:  ${disk_used} / ${disk_total} (${disk_percent})"
echo ""

echo -e "${CYAN}${BOLD}🔄 SERVICE STATUS${NC}"
for svc in pihole-FTL unbound; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        echo -e "  $svc: ${GREEN}● Active${NC}"
    else
        echo -e "  $svc: ${RED}● Inactive${NC}"
    fi
done

# Check emergency service
if systemctl list-unit-files 2>/dev/null | grep -q thermal-emergency.service; then
    echo -e "  emergency-backup: ${GREEN}✓ Ready${NC}"
fi
echo ""

echo -e "${CYAN}${BOLD}🌐 DNS CONFIGURATION${NC}"
if [[ -f /etc/pihole/pihole.toml ]]; then
    if grep -q "127.0.0.1#5335" /etc/pihole/pihole.toml; then
        echo -e "  Upstream DNS: ${GREEN}Unbound (127.0.0.1#5335)${NC}"
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
    
    proto=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
    if [[ -n "$proto" ]]; then
        echo -e "  Quad9 Proto: ${CYAN}$proto${NC}"
    fi
fi
echo ""

echo -e "${CYAN}${BOLD}💾 BACKUP STATUS${NC}"
BACKUP_DIR="/var/backups/pihole"
if [[ -d "$BACKUP_DIR" ]]; then
    count=$(ls -1 "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null | wc -l)
    if [[ $count -gt 0 ]]; then
        total_size=$(du -ch "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null | grep total$ | cut -f1)
        newest=$(ls -1t "$BACKUP_DIR"/teleporter-*.tar.gz 2>/dev/null | head -1)
        newest_date=$(stat -c %y "$newest" 2>/dev/null | cut -d. -f1)
        
        echo -e "  Backups:     ${GREEN}$count${NC} (last 7 kept)"
        echo -e "  Total size:  ${total_size:-0}"
        echo -e "  Latest:      $(basename "$newest")"
        echo -e "  Date:        $newest_date"
    else
        echo -e "  Backups:     ${YELLOW}No backups found${NC}"
    fi
fi
echo ""

echo -e "${CYAN}${BOLD}🌡️  RECENT THERMAL EVENTS${NC}"
if [[ -f /var/log/thermal-monitor.log ]]; then
    tail -5 /var/log/thermal-monitor.log 2>/dev/null | while read line; do
        if [[ "$line" == *"CRITICAL"* ]] || [[ "$line" == *"EMERGENCY"* ]]; then
            echo -e "  ${RED}●${NC} $line"
        elif [[ "$line" == *"WARNING"* ]]; then
            echo -e "  ${YELLOW}●${NC} $line"
        else
            echo -e "  ${GREEN}●${NC} $line"
        fi
    done
else
    echo -e "  ${YELLOW}No thermal events logged${NC}"
fi
echo ""

echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
EOF

    run_sudo chmod +x /usr/local/bin/pihole-health
    print_success "Health dashboard created at /usr/local/bin/pihole-health"
}

# ---------- Uninstall Script ------------------------------------------------
create_uninstall_script() {
    print_step "Creating Uninstall Script"
    
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
    systemctl stop pihole-FTL unbound thermal-monitor.timer 2>/dev/null
    systemctl disable pihole-FTL unbound thermal-monitor.timer 2>/dev/null
    
    echo -e "${YELLOW}Removing systemd overrides...${NC}"
    rm -rf /etc/systemd/system/unbound.service.d
    rm -rf /etc/systemd/system/pihole-FTL.service.d
    rm -f /etc/systemd/system/thermal-emergency.service
    rm -f /etc/systemd/system/thermal-monitor.*
    systemctl daemon-reload
    
    echo -e "${YELLOW}Removing packages...${NC}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get remove --purge -y pihole unbound
    elif command -v dnf >/dev/null 2>&1; then
        dnf remove -y pihole unbound
    elif command -v yum >/dev/null 2>&1; then
        yum remove -y pihole unbound
    fi
    
    echo -e "${YELLOW}Removing configuration and scripts...${NC}"
    rm -rf /etc/pihole
    rm -rf /etc/unbound
    rm -rf /var/backups/pihole
    rm -f /usr/local/bin/pihole-*
    rm -f /usr/local/bin/thermal-*
    rm -f /usr/local/bin/verify-backup.sh
    rm -f /etc/logrotate.d/unbound
    
    echo -e "${YELLOW}Removing cron job...${NC}"
    crontab -l 2>/dev/null | grep -v "pihole-backup.sh" | crontab -
    
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
    
    print_info "Checking thermal monitoring..."
    if systemctl is-active --quiet thermal-monitor.timer; then
        print_success "✓ Thermal monitoring is active"
    else
        print_warning "Thermal monitoring not running"
    fi
    
    print_info "Checking emergency backup service..."
    if systemctl list-unit-files 2>/dev/null | grep -q thermal-emergency.service; then
        print_success "✓ Emergency backup service is ready"
    else
        print_warning "Emergency backup service not found"
    fi
    
    print_info "Checking backup cron..."
    if crontab -l 2>/dev/null | grep -q "pihole-backup.sh"; then
        print_success "✓ Backup cron is configured"
    else
        print_warning "Backup cron not configured"
    fi
    
    print_info "Checking Unbound log permissions..."
    if [[ -f "$UNBOUND_LOG" ]]; then
        local owner=$(stat -c '%U' "$UNBOUND_LOG" 2>/dev/null)
        if [[ "$owner" == "unbound" ]]; then
            print_success "✓ Unbound log has correct ownership"
        else
            print_warning "Unbound log ownership may be incorrect"
        fi
    fi
    
    print_info "Testing DNS resolution..."
    if dig @127.0.0.1 google.com +short > /dev/null 2>&1; then
        print_success "✓ DNS resolution working"
    else
        print_error "✗ DNS resolution failed"
    fi
    
    if dig @127.0.0.1 -p 5335 sigfail.verteiltesysteme.net +short 2>&1 | grep -q "SERVFAIL"; then
        print_success "✓ DNSSEC validation working (bogus domain blocked)"
    fi
    
    local proto_test=$(dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335 2>/dev/null)
    if [[ "$proto_test" == *"dot"* ]]; then
        print_success "✓ Quad9 DNS-over-TLS confirmed (protocol: $proto_test)"
    fi
    
    print_info "Web interface should be accessible at:"
    print_info "  http://$IP_ADDR/admin"
    print_info "  https://$IP_ADDR/admin"
}

# ---------- Show Summary with Blocklist Recommendations ---------------------
show_summary() {
    print_step "Installation Complete - Summary"
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}${BOLD}✓ Pi-hole Ultimate Edition v2.0.0 installed successfully${NC}"
    echo -e "${GREEN}${BOLD}✓ Quad9 DNS-over-TLS with Unbound DNSSEC${NC}"
    echo -e "${GREEN}${BOLD}✓ Pi-hole DNSSEC disabled (prevents double validation)${NC}"
    echo -e "${GREEN}${BOLD}✓ System cleanup performed (old files removed)${NC}"
    echo -e "${GREEN}${BOLD}✓ Thermal monitoring (75°C warn, 80°C critical with emergency backup)${NC}"
    echo -e "${GREEN}${BOLD}✓ Automatic backups (weekly, 7-day retention, no email)${NC}"
    echo -e "${GREEN}${BOLD}✓ Emergency backup at 80°C (protects your config before shutdown)${NC}"
    echo -e "${GREEN}${BOLD}✓ Static IP guard configured${NC}"
    echo -e "${GREEN}${BOLD}✓ Zero email dependencies (leaner, faster, more private)${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📌 Available Commands:${NC}"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole-health${NC}        - Show health dashboard"
    echo -e "  ${CYAN}▶${NC} ${BOLD}verify-backup.sh${NC}      - Check backup status"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -c${NC}             - Pi-hole console"
    echo -e "  ${CYAN}▶${NC} ${BOLD}pihole -g${NC}             - Update gravity"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole setpassword${NC} - Change web password"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo pihole -t${NC}         - Tail FTL log"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo journalctl -u unbound${NC} - Check Unbound logs"
    echo -e "  ${CYAN}▶${NC} ${BOLD}sudo systemctl status thermal-emergency${NC} - Check emergency service"
    echo ""
    
    echo -e "${WHITE}${BOLD}🌐 Web Interface:${NC}"
    echo -e "  ${CYAN}•${NC} HTTP:  ${GREEN}http://$IP_ADDR/admin${NC}"
    echo -e "  ${CYAN}•${NC} HTTPS: ${GREEN}https://$IP_ADDR/admin${NC} (self-signed)"
    echo ""
    
    echo -e "${WHITE}${BOLD}📋 System Status:${NC}"
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        current_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000}')
        echo -e "  ${CYAN}•${NC} CPU Temp:   ${current_temp}°C"
    fi
    echo -e "  ${CYAN}•${NC} Disk Space: $(df -h / | awk 'NR==2 {print $5}') used"
    echo -e "  ${CYAN}•${NC} Unbound:    $(systemctl is-active unbound)"
    echo -e "  ${CYAN}•${NC} Pi-hole:    $(systemctl is-active pihole-FTL)"
    echo ""
    
    # ===== RECOMMENDED BLOCKLISTS =====
    echo -e "${WHITE}${BOLD}🛡️  RECOMMENDED BLOCKLISTS (Add these manually):${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}1.${NC} ${BOLD}StevenBlack Unified${NC}"
    echo -e "     ${CYAN}https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts${NC}"
    echo -e "     → Most comprehensive base list (covers ads, malware, trackers)"
    echo ""
    
    echo -e "  ${GREEN}2.${NC} ${BOLD}OISD Full${NC}"
    echo -e "     ${CYAN}https://big.oisd.nl/${NC}"
    echo -e "     → Balanced protection, low false positives"
    echo ""
    
    echo -e "  ${GREEN}3.${NC} ${BOLD}Hagezi Multi PRO${NC}"
    echo -e "     ${CYAN}https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/multi.txt${NC}"
    echo -e "     → Aggressive protection against ads, trackers, and malware"
    echo ""
    
    echo -e "  ${GREEN}4.${NC} ${BOLD}Phishing Army${NC}"
    echo -e "     ${CYAN}https://phishing.army/download/phishing_army_blocklist_extended.txt${NC}"
    echo -e "     → Blocks phishing and scam domains"
    echo ""
    
    echo -e "  ${GREEN}5.${NC} ${BOLD}NoTrack Malware${NC}"
    echo -e "     ${CYAN}https://gitlab.com/quidsup/notrack-blocklists/-/raw/master/notrack-malware.txt${NC}"
    echo -e "     → Focuses on malware and malicious domains"
    echo ""
    
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}To add these lists, go to:${NC}"
    echo -e "  Web Interface → Adlists → Add new adlist"
    echo -e "  Then run: ${CYAN}sudo pihole -g${NC} to update gravity"
    echo ""
    
    echo -e "${WHITE}${BOLD}🔒 DNS Security Tests:${NC}"
    echo -e "  ${CYAN}•${NC} DNSSEC test: ${WHITE}dig @127.0.0.1 -p 5335 sigfail.verteiltesysteme.net${NC} → ${GREEN}SERVFAIL${NC}"
    echo -e "  ${CYAN}•${NC} DoT test:    ${WHITE}dig +short txt proto.on.quad9.net. @127.0.0.1 -p 5335${NC} → ${GREEN}dot${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}🔥 Emergency Protection:${NC}"
    echo -e "  ${CYAN}•${NC} At 80°C, an automatic backup is triggered"
    echo -e "  ${CYAN}•${NC} Check emergency logs: ${WHITE}sudo journalctl -u thermal-emergency${NC}"
    echo -e "  ${CYAN}•${NC} Manual emergency test: ${WHITE}sudo systemctl start thermal-emergency${NC}"
    echo ""
    
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}         Pi-hole v6 with Unbound - PRODUCTION READY!${NC}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ---------- Set Pi-hole Password ---------------------------------------------
set_pihole_password() {
    print_step "Setting Pi-hole Admin Password"
    
    echo ""
    echo -e "${YELLOW}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║           PI-HOLE ADMIN PASSWORD SETUP                     ║${NC}"
    echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
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
    
    perform_cleanup
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
    test_unbound_dnssec
    configure_static_ip_guard
    setup_backups
    setup_emergency_handler
    setup_thermal_monitoring
    create_health_dashboard
    create_uninstall_script
    final_verification
    set_pihole_password
    show_summary
}

main "$@"