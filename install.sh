#!/bin/bash
# Zivpn UDP Module Manager
# This script installs the base Zivpn service and then sets up an advanced management interface.

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo or run as root user." >&2
  exit 1
fi

# --- Utility Functions ---
function restart_zivpn() {
    echo "Restarting ZIVPN service..."
    systemctl restart zivpn.service
    echo "Service restarted."
}

# --- Core Logic Functions ---
function create_account() {
    echo "--- Create New Account ---"
    read -p "Enter new password: " password
    if [ -z "$password" ]; then
        echo "Password cannot be empty."
        return
    fi

    read -p "Enter active period (in days): " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo "Invalid number of days."
        return
    fi

    local db_file="/etc/zivpn/users.db"
    if grep -q "^${password}:" "$db_file"; then
        echo "Password '${password}' already exists."
        return
    fi

    local expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}" >> "$db_file"
    echo "User '${password}' added, expires in $days day(s)."

    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    
    # --- Display Account Information ---
    # Get host information
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    if [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    # Format expiry date
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y")
    
    clear
    echo "🔹Informasi Akun zivpn Anda🔹"
    echo "┌─────────────────────"
    echo "│ Host: $HOST"
    echo "│ Pass: $password"
    echo "│ Expire: $EXPIRE_FORMATTED"
    echo "└─────────────────────"
    echo "♨ᵗᵉʳⁱᵐᵃᵏᵃˢⁱʰ ᵗᵉˡᵃʰ ᵐᵉⁿᵍᵍᵘⁿᵃᵏᵃⁿ ˡᵃʸᵃⁿᵃⁿ ᵏᵃᵐⁱ♨"
    
    restart_zivpn
}

function delete_account() {
    echo "--- Delete Account ---"
    read -p "Enter password to delete: " password
    if [ -z "$password" ]; then
        echo "Password cannot be empty."
        return
    fi

    local db_file="/etc/zivpn/users.db"
    if [ ! -f "$db_file" ]; then
        echo "User database not found."
        return
    fi

    if ! grep -q "^${password}:" "$db_file"; then
        echo "Password '${password}' not found."
        return
    fi

    sed -i "/^${password}:/d" "$db_file"
    echo "User '${password}' removed from database."

    jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    echo "Configuration updated."
    restart_zivpn
}

function change_domain() {
    echo "--- Change Domain ---"
    read -p "Enter the new domain name for the SSL certificate: " domain
    if [ -z "$domain" ]; then
        echo "Domain name cannot be empty."
        return
    fi

    echo "Generating new certificate for domain '${domain}'..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=${domain}" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

    echo "New certificate generated."
    restart_zivpn
}

function list_accounts() {
    echo "--- Active Accounts ---"
    local db_file="/etc/zivpn/users.db"

    if [ ! -f "$db_file" ] || [ ! -s "$db_file" ]; then
        echo "No accounts found."
        return
    fi

    local current_date=$(date +%s)
    printf "%-20s | %s\n" "Password" "Expires in (days)"
    echo "------------------------------------------"
    while IFS=':' read -r password expiry_date; do
        if [[ -n "$password" ]]; then
            local remaining_seconds=$((expiry_date - current_date))
            if [ $remaining_seconds -gt 0 ]; then
                local remaining_days=$((remaining_seconds / 86400))
                printf "%-20s | %s days\n" "$password" "$remaining_days"
            else
                printf "%-20s | Expired\n" "$password"
            fi
        fi
    done < "$db_file"
    echo "------------------------------------------"
}

function show_menu() {
    clear
    echo "ZIVPN Account Manager"
    echo "---------------------"
    echo "1. Create Account"
    echo "2. Delete Account"
    echo "3. Change Domain"
    echo "4. List Accounts"
    echo "5. Exit"
    echo "---------------------"
    read -p "Enter your choice [1-5]: " choice

    case $choice in
        1) create_account ;;
        2) delete_account ;;
        3) change_domain ;;
        4) list_accounts ;;
        5) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
}

# --- Main Installation and Setup Logic ---
function run_setup() {
    # --- Run Base Installation ---
    echo "--- Starting Base Installation ---"
    wget -O zi.sh https://raw.githubusercontent.com/kedaivpn/udp-zivpn/main/zi.sh
    if [ $? -ne 0 ]; then
        echo "Failed to download the base installer. Aborting."
        exit 1
    fi
    chmod +x zi.sh
    ./zi.sh
    if [ $? -ne 0 ]; then
        echo "Base installation script failed. Aborting."
        exit 1
    fi
    rm zi.sh
    echo "--- Base Installation Complete ---"

    # --- Setting up Advanced Management ---
    echo "--- Setting up Advanced Management ---"

    if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
        echo "Installing dependencies (jq, curl)..."
        apt-get update && apt-get install -y jq curl
    fi

    echo "Clearing initial password(s) set during base installation..."
    jq '.auth.config = []' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    touch /etc/zivpn/users.db

    RANDOM_PASS="zivpn$(shuf -i 10000-99999 -n 1)"
    EXPIRY_DATE=$(date -d "+1 day" +%s)

    echo "Creating a temporary initial account..."
    echo "${RANDOM_PASS}:${EXPIRY_DATE}" >> /etc/zivpn/users.db
    jq --arg pass "$RANDOM_PASS" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    echo "Setting up daily expiry check cron job..."
    cat <<'EOF' > /etc/zivpn/expire_check.sh
#!/bin/bash
DB_FILE="/etc/zivpn/users.db"
CONFIG_FILE="/etc/zivpn/config.json"
TMP_DB_FILE="${DB_FILE}.tmp"
CURRENT_DATE=$(date +%s)
USERS_REMOVED=false
if [ ! -f "$DB_FILE" ]; then exit 0; fi
> "$TMP_DB_FILE"
while IFS=':' read -r password expiry_date; do
    if [[ -n "$password" ]]; then
        if [ "$expiry_date" -le "$CURRENT_DATE" ]; then
            echo "User '${password}' has expired. Removing."
            jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            USERS_REMOVED=true
        else
            echo "${password}:${expiry_date}" >> "$TMP_DB_FILE"
        fi
    fi
done < "$DB_FILE"
mv "$TMP_DB_FILE" "$DB_FILE"
if [ "$USERS_REMOVED" = true ]; then
    echo "Restarting zivpn service due to user removal."
    systemctl restart zivpn.service
fi
exit 0
EOF

    chmod +x /etc/zivpn/expire_check.sh
    CRON_JOB="0 0 * * * /etc/zivpn/expire_check.sh"
    (crontab -l 2>/dev/null | grep -Fq "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

    restart_zivpn

    # --- System Integration ---
    echo "--- Integrating management script into the system ---"
    cp "$0" /usr/local/bin/zivpn-manager
    chmod +x /usr/local/bin/zivpn-manager

    PROFILE_FILE="/root/.bashrc"
    if [ -f "/root/.bash_profile" ]; then
        PROFILE_FILE="/root/.bash_profile"
    fi

    ALIAS_CMD="alias menu='/usr/local/bin/zivpn-manager'"
    AUTORUN_CMD="/usr/local/bin/zivpn-manager"

    # Add alias and autorun command if they don't exist
    grep -qF "$ALIAS_CMD" "$PROFILE_FILE" || echo "$ALIAS_CMD" >> "$PROFILE_FILE"
    grep -qF "$AUTORUN_CMD" "$PROFILE_FILE" || echo "$AUTORUN_CMD" >> "$PROFILE_FILE"

    echo "The 'menu' command is now available."
    echo "The management menu will now open automatically on login."
    
    echo "-----------------------------------------------------"
    echo "Advanced management setup complete."
    echo "A temporary account has been created to ensure service starts correctly:"
    echo "Password: ${RANDOM_PASS}"
    echo "Expires in: 24 hours"
    echo "Please use the menu to create your permanent account(s)."
    echo "-----------------------------------------------------"
    read -p "Press Enter to continue to the management menu..."
}

# --- Main Script ---
if [ ! -f "/etc/systemd/system/zivpn.service" ]; then
    run_setup
fi

while true; do
    show_menu
    read -p "Press Enter to return to the menu..."
done
