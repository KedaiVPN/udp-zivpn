#!/bin/bash
# ZIVPN Helper Script for Backup and Restore

# --- Configuration ---
CONFIG_DIR="/etc/zivpn"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"
BACKUP_FILES=("config.json" "users.db")

# --- Helper Functions ---
function get_host() {
    local CERT_CN
    CERT_CN=$(openssl x509 -in "${CONFIG_DIR}/zivpn.crt" -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p')
    if [ "$CERT_CN" == "zivpn" ]; then
        curl -s ifconfig.me
    else
        echo "$CERT_CN"
    fi
}

function send_telegram_message() {
    local message="$1"
    # URL Encode the message
    local encoded_message
    encoded_message=$(printf %s "$message" | jq -s -R -r @uri)
    curl -s -o /dev/null "https://api.telegram.org/bot${API_KEY}/sendMessage?chat_id=${CHAT_ID}&text=${encoded_message}"
}

# --- Core Functions ---
function handle_backup() {
    echo "--- Starting Backup Process ---"

    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo "Telegram credentials not found. Please configure them first."
        read -p "Enter your Bot API Key: " api_key
        read -p "Enter your Telegram Chat ID (get it from @userinfobot): " chat_id

        if [ -z "$api_key" ] || [ -z "$chat_id" ]; then
            echo "API Key and Chat ID cannot be empty. Aborting."
            exit 1
        fi

        echo "API_KEY=${api_key}" > "$TELEGRAM_CONF"
        echo "CHAT_ID=${chat_id}" >> "$TELEGRAM_CONF"
        chmod 600 "$TELEGRAM_CONF"
        echo "Credentials saved to $TELEGRAM_CONF"
    fi

    # shellcheck source=/etc/zivpn/telegram.conf
    source "$TELEGRAM_CONF"

    local backup_filename="zivpn_backup_$(date +%Y%m%d-%H%M%S).zip"
    local temp_backup_path="/tmp/${backup_filename}"

    echo "Creating backup archive..."
    zip "$temp_backup_path" -j "$CONFIG_DIR/config.json" "$CONFIG_DIR/users.db" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to create backup archive. Aborting."
        rm -f "$temp_backup_path"
        exit 1
    fi

    echo "Sending backup to Telegram..."
    local response
    response=$(curl -s -F "chat_id=${CHAT_ID}" -F "document=@${temp_backup_path}" "https://api.telegram.org/bot${API_KEY}/sendDocument")

    local file_id
    file_id=$(echo "$response" | jq -r '.result.document.file_id')

    if [ -z "$file_id" ] || [ "$file_id" == "null" ]; then
        echo "Failed to upload backup to Telegram. Please check your API Key and Chat ID."
        echo "Telegram API response: $response"
        rm -f "$temp_backup_path"
        exit 1
    fi

    echo "Backup sent successfully. Sending details..."
    local host
    host=$(get_host)
    local current_date
    current_date=$(date +"%d %B %Y")

    local backup_message
    backup_message=$(cat <<EOF
◇━━━━━━━━━━━━━━◇
   ⚠️Backup ZIVPN⚠️   
◇━━━━━━━━━━━━━━◇ 
HOST  : ${host}
Tanggal : ${current_date}
Id file    :  ${file_id}
◇━━━━━━━━━━━━━━◇
Silahkan copy id file nya untuk restore
EOF
)
    send_telegram_message "$backup_message"

    rm -f "$temp_backup_path"
    echo "Backup process complete."
}

function handle_restore() {
    echo "--- Starting Restore Process ---"

    if [ ! -f "$TELEGRAM_CONF" ]; then
        echo "Telegram credentials not found. Cannot perform restore."
        echo "Please run the backup function at least once to configure."
        exit 1
    fi

    # shellcheck source=/etc/zivpn/telegram.conf
    source "$TELEGRAM_CONF"

    read -p "Enter the File ID for the backup you want to restore: " file_id
    if [ -z "$file_id" ]; then
        echo "File ID cannot be empty. Aborting."
        exit 1
    fi

    read -p "WARNING: This will overwrite current user data. Are you sure? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Restore cancelled."
        exit 0
    fi

    echo "Fetching file information from Telegram..."
    local response
    response=$(curl -s "https://api.telegram.org/bot${API_KEY}/getFile?file_id=${file_id}")
    
    local file_path
    file_path=$(echo "$response" | jq -r '.result.file_path')

    if [ -z "$file_path" ] || [ "$file_path" == "null" ]; then
        echo "Failed to get file path from Telegram. Is the File ID correct?"
        echo "Telegram API response: $response"
        exit 1
    fi

    local download_url="https://api.telegram.org/file/bot${API_KEY}/${file_path}"
    local temp_restore_path="/tmp/restore_$(basename "$file_path")"

    echo "Downloading backup file..."
    curl -s -o "$temp_restore_path" "$download_url"
    if [ $? -ne 0 ]; then
        echo "Failed to download backup file. Aborting."
        rm -f "$temp_restore_path"
        exit 1
    fi

    echo "Extracting and restoring data..."
    unzip -o "$temp_restore_path" -d "$CONFIG_DIR"
    if [ $? -ne 0 ]; then
        echo "Failed to extract backup archive. Aborting."
        rm -f "$temp_restore_path"
        exit 1
    fi

    rm -f "$temp_restore_path"
    
    echo "Restarting ZIVPN service to apply changes..."
    systemctl restart zivpn.service

    echo "Restore complete! User data has been restored from backup."
}

# --- Main Script Logic ---
case "$1" in
    backup)
        handle_backup
        ;;
    restore)
        handle_restore
        ;;
    *)
        echo "Usage: $0 {backup|restore}"
        exit 1
        ;;
esac
