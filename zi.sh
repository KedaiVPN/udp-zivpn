#!/bin/bash
# Zivpn UDP Module installer and manager
# Creator Zahid Islam

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
    # Check if input is a number
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo "Invalid number of days."
        return
    fi

    # Database file
    local db_file="/etc/zivpn/users.db"
    touch "$db_file" # Ensure the file exists

    # Check if password already exists
    if grep -q "^${password}:" "$db_file"; then
        echo "Password '${password}' already exists."
        return
    fi

    # Calculate expiry date (seconds since epoch)
    local expiry_date=$(date -d "+$days days" +%s)

    # Save to user database
    echo "${password}:${expiry_date}" >> "$db_file"
    echo "User '${password}' added, expires in $days day(s)."

    # Add password to config.json using jq
    # Read, add the new password, and write back
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    echo "Configuration updated."
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

    # Check if the database file exists
    if [ ! -f "$db_file" ]; then
        echo "User database not found. No users to delete."
        return
    fi

    # Check if password exists in db
    if ! grep -q "^${password}:" "$db_file"; then
        echo "Password '${password}' not found."
        return
    fi

    # Remove from user database
    sed -i "/^${password}:/d" "$db_file"
    echo "User '${password}' removed from database."

    # Remove password from config.json using jq
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

function install_zivpn() {
    echo -e "Updating server and installing dependencies (jq)..."
    sudo apt-get update && apt-get upgrade -y && sudo apt-get install -y jq
    systemctl stop zivpn.service 1> /dev/null 2> /dev/null
    echo -e "Downloading UDP Service"
    wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn 1> /dev/null 2> /dev/null
    chmod +x /usr/local/bin/zivpn
    mkdir /etc/zivpn 1> /dev/null 2> /dev/null
    wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O /etc/zivpn/config.json 1> /dev/null 2> /dev/null

    echo "Generating cert files:"
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
    sysctl -w net.core.rmem_max=16777216 1> /dev/null 2> /dev/null
    sysctl -w net.core.wmem_max=16777216 1> /dev/null 2> /dev/null
    cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    # Initialize config with an empty password list and create the user database
    jq '.auth.config = []' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    touch /etc/zivpn/users.db

    systemctl enable zivpn.service
    systemctl start zivpn.service
    iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    ufw allow 6000:19999/udp
    ufw allow 5667/udp

    # Setup the daily expiry check cron job
    cat <<'EOF' > /etc/zivpn/expire_check.sh
#!/bin/bash
DB_FILE="/etc/zivpn/users.db"
CONFIG_FILE="/etc/zivpn/config.json"
TMP_DB_FILE="${DB_FILE}.tmp"
CURRENT_DATE=$(date +%s)
USERS_REMOVED=false

if [ ! -f "$DB_FILE" ]; then
    exit 0
fi

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
    # Add cron job only if it doesn't already exist
    CRON_JOB="0 0 * * * /etc/zivpn/expire_check.sh"
    (crontab -l 2>/dev/null | grep -Fq "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

    rm zi.* 1> /dev/null 2> /dev/null
    echo -e "ZIVPN UDP Installed and expiry check cron job created."
    echo -e "\nInstallation complete. Please use the menu to create your first account."
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

# --- Main Script ---
if [ ! -f "/etc/systemd/system/zivpn.service" ]; then
    install_zivpn
fi

while true; do
    show_menu
    read -p "Press Enter to return to the menu..."
done
