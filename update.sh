#!/bin/bash
# Zivpn Update Script
# This script applies the update for the backup filename format.
# Run this as root.

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo or run as root user." >&2
  exit 1
fi

echo "--- Updating Zivpn Components ---"

# 1. Update zivpn_helper.sh (Contains the backup filename fix)
echo "Updating zivpn_helper.sh..."
wget -O /usr/local/bin/zivpn_helper.sh https://raw.githubusercontent.com/kedaivpn/udp-zivpn/main/zivpn_helper.sh
if [ $? -ne 0 ]; then
    echo "Warning: Failed to download zivpn_helper.sh from main repo. Skipping."
else
    chmod +x /usr/local/bin/zivpn_helper.sh
    echo "zivpn_helper.sh updated successfully."
fi

echo "--- Update Complete ---"
echo "Backup filename format has been updated to use domain/IP."
