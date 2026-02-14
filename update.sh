#!/bin/bash
# Zivpn Update Script
# This script applies the fix for the license detection issue on existing VPS instances.
# Run this as root.

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo or run as root user." >&2
  exit 1
fi

echo "--- Updating Zivpn Components ---"

# 1. Update zivpn_helper.sh
echo "Updating zivpn_helper.sh..."
wget -O /usr/local/bin/zivpn_helper.sh https://raw.githubusercontent.com/kedaivpn/udp-zivpn/main/zivpn_helper.sh
if [ $? -ne 0 ]; then
    echo "Warning: Failed to download zivpn_helper.sh from main repo. Skipping."
else
    chmod +x /usr/local/bin/zivpn_helper.sh
    echo "zivpn_helper.sh updated."
fi

# 2. Update zivpn-manager (install.sh)
echo "Updating zivpn-manager..."
wget -O /usr/local/bin/zivpn-manager https://raw.githubusercontent.com/kedaivpn/udp-zivpn/main/install.sh
if [ $? -ne 0 ]; then
    echo "Warning: Failed to download install.sh from main repo. Skipping."
else
    chmod +x /usr/local/bin/zivpn-manager
    echo "zivpn-manager updated."
fi

# 3. Regenerate license_checker.sh with robust IP detection
echo "Regenerating license_checker.sh..."

cat <<'EOF' > /etc/zivpn/license_checker.sh
#!/bin/bash
# Zivpn License Checker
# This script is run by a cron job to periodically check the license status.

# --- Configuration ---
LICENSE_URL="https://raw.githubusercontent.com/kedaivpn/izin/main/licence"
LICENSE_INFO_FILE="/etc/zivpn/.license_info"
EXPIRED_LOCK_FILE="/etc/zivpn/.expired"
TELEGRAM_CONF="/etc/zivpn/telegram.conf"
LOG_FILE="/var/log/zivpn_license.log"

# --- Logging ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# --- Helper Functions ---
function get_public_ip() {
    local ip=""
    # List of services to try
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
        "https://checkip.amazonaws.com"
    )

    for service in "${services[@]}"; do
        # Use curl with timeout, silence output, follow redirects
        ip=$(curl -s --max-time 3 "$service" | tr -d '[:space:]')
        
        # Check if the retrieved string is a valid IPv4 address
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    return 1
}

function get_host() {
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null || echo "")
    if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
        local ip
        ip=$(get_public_ip)
        if [ -n "$ip" ]; then
            echo "$ip"
        else
            curl -s ifconfig.me
        fi
    else
        echo "$CERT_CN"
    fi
}

function get_isp() {
    curl -s ipinfo.io | jq -r '.org // "N/A"'
}


# --- Telegram Notification Function ---
send_telegram_message() {
    local message="$1"
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        log "Telegram config not found, skipping notification."
        return
    fi
    
    source "$TELEGRAM_CONF"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
        curl -s -X POST "$api_url" -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${message}" -d "parse_mode=Markdown" > /dev/null
        log "Simple telegram notification sent."
    else
        log "Telegram config found but token or chat ID is missing."
    fi
}

# --- Main Logic ---
log "Starting license check..."

# 1. Get Server IP
SERVER_IP=$(get_public_ip)
if [ -z "$SERVER_IP" ]; then
    log "Error: Failed to retrieve server IP. Exiting."
    exit 1
fi

# 2. Get Local License Info
if [ ! -f "$LICENSE_INFO_FILE" ]; then
    log "Error: Local license info file not found. Exiting."
    exit 1
fi
source "$LICENSE_INFO_FILE" # This loads CLIENT_NAME and EXPIRY_DATE

# 3. Fetch Remote License Data
license_data=$(curl -s "$LICENSE_URL")
if [ $? -ne 0 ] || [ -z "$license_data" ]; then
    log "Error: Failed to connect to license server. Exiting."
    exit 1
fi

# 4. Check License Status from Remote
license_entry=$(echo "$license_data" | grep -w "$SERVER_IP")

if [ -z "$license_entry" ]; then
    # IP not found in remote list (Revoked)
    if [ ! -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has been REVOKED."
        systemctl stop zivpn.service
        touch "$EXPIRED_LOCK_FILE"
        local MSG="Notifikasi Otomatis: Lisensi untuk Klien \`${CLIENT_NAME}\` dengan IP \`${SERVER_IP}\` telah dicabut (REVOKED). Layanan zivpn telah dihentikan."
        send_telegram_message "$MSG"
    fi
    exit 0
fi

# 5. IP Found, Check for Expiry or Renewal
client_name_remote=$(echo "$license_entry" | awk '{print $1}')
expiry_date_remote=$(echo "$license_entry" | awk '{print $2}')
expiry_timestamp_remote=$(date -d "$expiry_date_remote" +%s)
current_timestamp=$(date +%s)

# Update local license info file with the latest from server
if [ "$expiry_date_remote" != "$EXPIRY_DATE" ]; then
    log "Remote license has a different expiry date (${expiry_date_remote}). Updating local file."
    echo "CLIENT_NAME=${client_name_remote}" > "$LICENSE_INFO_FILE"
    echo "EXPIRY_DATE=${expiry_date_remote}" >> "$LICENSE_INFO_FILE"
    CLIENT_NAME=$client_name_remote
    EXPIRY_DATE=$expiry_date_remote
fi

if [ "$expiry_timestamp_remote" -le "$current_timestamp" ]; then
    # License is EXPIRED
    if [ ! -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has EXPIRED."
        systemctl stop zivpn.service
        touch "$EXPIRED_LOCK_FILE"
        local host
        host=$(get_host)
        local isp
        isp=$(get_isp)
        log "Sending rich expiry notification via helper script..."
        /usr/local/bin/zivpn_helper.sh expiry-notification "$host" "$SERVER_IP" "$CLIENT_NAME" "$isp" "$EXPIRY_DATE"
    fi
else
    # License is ACTIVE (potentially renewed)
    if [ -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has been RENEWED/ACTIVATED."
        rm "$EXPIRED_LOCK_FILE"
        systemctl start zivpn.service
        local host
        host=$(get_host)
        local isp
        isp=$(get_isp)
        log "Sending rich renewed notification via helper script..."
        /usr/local/bin/zivpn_helper.sh renewed-notification "$host" "$SERVER_IP" "$CLIENT_NAME" "$isp" "$expiry_timestamp_remote"
    else
        log "License is active and valid. No action needed."
    fi
fi

log "License check finished."
exit 0
EOF

chmod +x /etc/zivpn/license_checker.sh
echo "license_checker.sh updated."

# 4. Remove .expired lock file if present (to force re-check)
if [ -f "/etc/zivpn/.expired" ]; then
    echo "Removing .expired lock file to trigger re-check..."
    rm "/etc/zivpn/.expired"
fi

# 5. Restart service
echo "Restarting zivpn service..."
systemctl restart zivpn.service

# 6. Run license check immediately
echo "Running immediate license check..."
/etc/zivpn/license_checker.sh

# 7. Ensure auto-start in .bashrc
echo "Configuring auto-start in .bashrc..."
PROFILE_FILE="/root/.bashrc"
ALIAS_CMD="alias menu='/usr/local/bin/zivpn-manager'"
AUTORUN_CMD="if [[ \$- == *i* ]]; then /usr/local/bin/zivpn-manager; fi"

if [ -f "$PROFILE_FILE" ]; then
    # Add alias if missing
    grep -qF "$ALIAS_CMD" "$PROFILE_FILE" || echo "$ALIAS_CMD" >> "$PROFILE_FILE"
    
    # Add auto-run if missing
    if ! grep -qF "if [[ \$- == *i* ]]; then /usr/local/bin/zivpn-manager; fi" "$PROFILE_FILE"; then
        echo "" >> "$PROFILE_FILE"
        echo "$AUTORUN_CMD" >> "$PROFILE_FILE"
        echo "Auto-start added to $PROFILE_FILE"
    else
        echo "Auto-start already present in $PROFILE_FILE"
    fi
else
    echo "Warning: $PROFILE_FILE not found. Auto-start could not be configured."
fi

# 8. Ensure .bash_profile or .profile sources .bashrc
echo "Checking login shell configuration..."
LOGIN_SCRIPTS=("/root/.bash_profile" "/root/.profile")

for script in "${LOGIN_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo "Found login script: $script"
        if grep -q "\.bashrc" "$script"; then
            echo "$script already sources .bashrc"
        else
            echo "Appending .bashrc source to $script"
            echo "" >> "$script"
            echo "if [ -f ~/.bashrc ]; then . ~/.bashrc; fi" >> "$script"
        fi
    fi
done

echo "--- Update Complete ---"
echo "Please logout and login again to verify the auto-start functionality."
