#!/bin/bash
# Zivpn UDP Module Manager
# This script installs the base Zivpn service and then sets up an advanced management interface.

# --- UI Definitions ---
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD_WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Box drawing characters
TL='╔'
TR='╗'
BL='╚'
BR='╝'
H='═'
V='║'

# --- UI Helper Functions ---
# Draw a neatly aligned menu box; safe with colored output.
function draw_menu() {
    local title="$1"
    shift
    local items=("$@")

    # Remove ANSI sequences for length calculations (if any)
    local clean_title
    clean_title=$(echo -ne "$title" | sed -r 's/\x1B\[[0-9;]*[mK]//g')
    local title_len=${#clean_title}

    # Determine longest item visible length (we'll display "N) text")
    local max_item_len=0
    for item in "${items[@]}"; do
        # build visible representation like "1) Text here"
        local num=$(echo "$item" | awk '{print $1}')
        local text=$(echo "$item" | cut -d' ' -f2-)
        local visible="  ${num}) ${text}"
        local visible_len=${#visible}
        if (( visible_len > max_item_len )); then
            max_item_len=$visible_len
        fi
    done

    # compute width: allow some padding, minimum 50 chars inner width
    local inner_width=$(( max_item_len + 6 ))
    (( inner_width < 50 )) && inner_width=50

    # Top border
    printf "${YELLOW}%s" "${TL}"
    for ((i=0;i<inner_width;i++)); do printf "%s" "$H"; done
    printf "%s${NC}\n" "${TR}"

    # Title line (centered)
    local pad_left=$(( (inner_width - title_len) / 2 ))
    (( pad_left < 0 )) && pad_left=0
    local pad_right=$(( inner_width - title_len - pad_left ))
    printf "${YELLOW}${V}${NC}"
    printf "%*s" $pad_left ""
    printf "${BOLD_WHITE}%s${NC}" "$title"
    printf "%*s" $pad_right ""
    printf "${YELLOW}${V}${NC}\n"

    # Empty separator line
    printf "${YELLOW}${V}${NC}"
    printf "%-${inner_width}s" ""
    printf "${YELLOW}${V}${NC}\n"

    # Items
    for item in "${items[@]}"; do
        local num=$(echo "$item" | awk '{print $1}')
        local text=$(echo "$item" | cut -d' ' -f2-)
        local line="  ${RED}${num})${NC} ${BOLD_WHITE}${text}${NC}"
        # Print item padded to inner_width
        printf "${YELLOW}${V}${NC} %-*s ${YELLOW}${V}${NC}\n" "$inner_width" "$line"
    done

    # Empty separator line
    printf "${YELLOW}${V}${NC}"
    printf "%-${inner_width}s" ""
    printf "${YELLOW}${V}${NC}\n"

    # Bottom border
    printf "${YELLOW}%s" "${BL}"
    for ((i=0;i<inner_width;i++)); do printf "%s" "$H"; done
    printf "%s${NC}\n" "${BR}"
}

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
function create_manual_account() {
    echo "--- Create New Zivpn Account ---"
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

    local expiry_date
    expiry_date=$(date -d "+$days days" +%s)
    echo "${password}:${expiry_date}" >> "$db_file"
    
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    local HOST
    if [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
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

function create_trial_account() {
    echo "--- Create Trial Zivpn Account ---"
    read -p "Enter active period (in minutes): " minutes
    if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
        echo "Invalid number of minutes."
        return
    fi

    local password="trial$(shuf -i 10000-99999 -n 1)"
    local db_file="/etc/zivpn/users.db"

    local expiry_date
    expiry_date=$(date -d "+$minutes minutes" +%s)
    echo "${password}:${expiry_date}" >> "$db_file"
    
    jq --arg pass "$password" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json
    
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    local HOST
    if [ "$CERT_CN" == "zivpn" ]; then
        HOST=$(curl -s ifconfig.me)
    else
        HOST=$CERT_CN
    fi

    local EXPIRE_FORMATTED
    EXPIRE_FORMATTED=$(date -d "@$expiry_date" +"%d %B %Y %H:%M:%S")
    
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

function renew_account() {
    echo "--- Renew Account ---"
    read -p "Enter password to renew: " password
    if [ -z "$password" ]; then
        echo "Password cannot be empty."
        return
    fi

    read -p "Enter number of days to extend: " days
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid number of days. Please enter a positive number."
        return
    fi

    local db_file="/etc/zivpn/users.db"
    local user_line
    user_line=$(grep "^${password}:" "$db_file")

    if [ -z "$user_line" ]; then
        echo "Account '${password}' not found or has expired."
        return
    fi

    local current_expiry_date
    current_expiry_date=$(echo "$user_line" | cut -d: -f2)

    if ! [[ "$current_expiry_date" =~ ^[0-9]+$ ]]; then
        echo "Error: Corrupted database entry for user '$password'. Cannot renew."
        return
    fi
    
    local seconds_to_add=$((days * 86400))
    local new_expiry_date=$((current_expiry_date + seconds_to_add))
    
    sed -i "s/^${password}:.*/${password}:${new_expiry_date}/" "$db_file"

    local new_expiry_formatted
    new_expiry_formatted=$(date -d "@$new_expiry_date" +"%d %B %Y")
    echo "Account '${password}' has been renewed. New expiry date: ${new_expiry_formatted}."
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

    local current_date
    current_date=$(date +%s)
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

function setup_auto_backup() {
    echo "--- Configure Auto Backup ---"
    if [ ! -f "/etc/zivpn/telegram.conf" ]; then
        echo "Telegram is not configured. Please run a manual backup once to set it up."
        return
    fi

    read -p "Enter backup interval in hours (e.g., 6, 12, 24). Enter 0 to disable: " interval
    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        echo "Invalid input. Please enter a number."
        return
    fi

    (crontab -l 2>/dev/null | grep -v "# zivpn-auto-backup") | crontab -

    if [ "$interval" -gt 0 ]; then
        local cron_schedule="0 */${interval} * * *"
        (crontab -l 2>/dev/null; echo "${cron_schedule} /usr/local/bin/zivpn_helper.sh backup >/dev/null 2>&1 # zivpn-auto-backup") | crontab -
        echo "Auto backup scheduled to run every ${interval} hour(s)."
    else
        echo "Auto backup has been disabled."
    fi
}

function create_account() {
    clear
    local title="Create Account"
    local items=("1 Create Zivpn (Manual)" "2 Trial Zivpn (Auto)" "0 Back to Main Menu")
    draw_menu "$title" "${items[@]}"
    
    read -p "Enter your choice [0-2]: " choice

    case $choice in
        1) create_manual_account ;;
        2) create_trial_account ;;
        0) return ;;
        *) echo "Invalid option." ;;
    esac
}

function show_backup_menu() {
    clear
    local title="Backup / Restore"
    local items=("1 Backup Data" "2 Restore Data" "3 Auto Backup" "0 Back to Main Menu")
    draw_menu "$title" "${items[@]}"
    
    read -p "Enter your choice [0-3]: " choice
    
    case $choice in
        1) /usr/local/bin/zivpn_helper.sh backup ;;
        2) /usr/local/bin/zivpn_helper.sh restore ;;
        3) setup_auto_backup ;;
        0) return ;;
        *) echo "Invalid option." ;;
    esac
}

function show_menu() {
    clear
    figlet "ZIVPN" | lolcat
    
    local title="KEDAI SSH"
    local items=("1 Create Account" "2 Renew Account" "3 Delete Account" "4 Change Domain" "5 List Accounts" "6 Backup / Restore" "0 Exit")
    draw_menu "$title" "${items[@]}"
    
    read -p "Enter your choice [0-6]: " choice

    case $choice in
        1) create_account ;;
        2) renew_account ;;
        3) delete_account ;;
        4) change_domain ;;
        5) list_accounts ;;
        6) show_backup_menu ;;
        0) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
}

# --- Main Installation and Setup Logic ---
function run_setup() {
    # --- Run Base Installation ---
    echo "--- Starting Base Installation ---"
    wget -O zi.sh https://raw.githubusercontent.com/kedaivpn/udp-zivpn/main/zi.sh
    if [ $? -ne 0 ]; then echo "Failed to download base installer. Aborting."; exit 1; fi
    chmod +x zi.sh
    ./zi.sh
    if [ $? -ne 0 ]; then echo "Base installation script failed. Aborting."; exit 1; fi
    rm zi.sh
    echo "--- Base Installation Complete ---"

    # --- Setting up Advanced Management ---
    echo "--- Setting up Advanced Management ---"

    if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null || ! command -v zip &> /dev/null || ! command -v figlet &> /dev/null || ! command -v lolcat &> /dev/null; then
        echo "Installing dependencies (jq, curl, zip, figlet, lolcat)..."
        apt-get update && apt-get install -y jq curl zip figlet lolcat
    fi
    
    # Download helper script from repository
    echo "Downloading helper script..."
    wget -O /usr/local/bin/zivpn_helper.sh https://raw.githubusercontent.com/kedaivpn/udp-zivpn/main/zivpn_helper.sh
    if [ $? -ne 0 ]; then
        echo "Failed to download helper script. Aborting."
        exit 1
    fi
    chmod +x /usr/local/bin/zivpn_helper.sh

    echo "Clearing initial password(s) set during base installation..."
    jq '.auth.config = []' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    touch /etc/zivpn/users.db

    RANDOM_PASS="zivpn$(shuf -i 10000-99999 -n 1)"
    EXPIRY_DATE=$(date -d "+1 day" +%s)

    echo "Creating a temporary initial account..."
    echo "${RANDOM_PASS}:${EXPIRY_DATE}" >> /etc/zivpn/users.db
    jq --arg pass "$RANDOM_PASS" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    echo "Setting up expiry check cron job..."
    cat <<'EOF' > /etc/zivpn/expire_check.sh
#!/bin/bash
DB_FILE="/etc/zivpn/users.db"
CONFIG_FILE="/etc/zivpn/config.json"
TMP_DB_FILE="${DB_FILE}.tmp"
CURRENT_DATE=$(date +%s)
SERVICE_RESTART_NEEDED=false

if [ ! -f "$DB_FILE" ]; then exit 0; fi
> "$TMP_DB_FILE"

while IFS=':' read -r password expiry_date; do
    if [[ -z "$password" ]]; then continue; fi

    if [ "$expiry_date" -le "$CURRENT_DATE" ]; then
        echo "User '${password}' has expired. Deleting permanently."
        jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        SERVICE_RESTART_NEEDED=true
    else
        echo "${password}:${expiry_date}" >> "$TMP_DB_FILE"
    fi
done < "$DB_FILE"

mv "$TMP_DB_FILE" "$DB_FILE"

if [ "$SERVICE_RESTART_NEEDED" = true ]; then
    echo "Restarting zivpn service due to user removal."
    systemctl restart zivpn.service
fi
exit 0
EOF
    chmod +x /etc/zivpn/expire_check.sh
    CRON_JOB_EXPIRY="* * * * * /etc/zivpn/expire_check.sh # zivpn-expiry-check"
    (crontab -l 2>/dev/null | grep -v "# zivpn-expiry-check") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_JOB_EXPIRY") | crontab -

    restart_zivpn

    # --- System Integration ---
    echo "--- Integrating management script into the system ---"
    cp "$0" /usr/local/bin/zivpn-manager
    chmod +x /usr/local/bin/zivpn-manager

    PROFILE_FILE="/root/.bashrc"
    if [ -f "/root/.bash_profile" ]; then PROFILE_FILE="/root/.bash_profile"; fi
    
    ALIAS_CMD="alias menu='/usr/local/bin/zivpn-manager'"
    AUTORUN_CMD="/usr/local/bin/zivpn-manager"

    grep -qF "$ALIAS_CMD" "$PROFILE_FILE" || echo "$ALIAS_CMD" >> "$PROFILE_FILE"
    grep -qF "$AUTORUN_CMD" "$PROFILE_FILE" || echo "$AUTORUN_CMD" >> "$PROFILE_FILE"

    echo "The 'menu' command is now available."
    echo "The management menu will now open automatically on login."
    
    echo "-----------------------------------------------------"
    echo "Advanced management setup complete."
    echo "Password for temporary account (expires 24h): ${RANDOM_PASS}"
    echo "-----------------------------------------------------"
    read -p "Press Enter to continue to the management menu..."
}

# --- Main Script ---
function main() {
    if [ ! -f "/etc/systemd/system/zivpn.service" ]; then
        run_setup
    fi

    while true; do
        show_menu
        read -p "Press Enter to return to the menu..."
    done
}

# Execute main function only when script is run directly, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
