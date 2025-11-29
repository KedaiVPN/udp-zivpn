#!/bin/bash
# - ZiVPN Remover -
clear
echo -e "Uninstalling ZiVPN and Management Scripts..."

# Stop and disable services
systemctl stop zivpn.service 1> /dev/null 2> /dev/null
systemctl disable zivpn.service 1> /dev/null 2> /dev/null

# Remove service files
rm /etc/systemd/system/zivpn.service 1> /dev/null 2> /dev/null

# Kill any running process
killall zivpn 1> /dev/null 2> /dev/null

# Stop and remove API service from pm2
pm2 stop zivpn-api 1> /dev/null 2> /dev/null
pm2 delete zivpn-api 1> /dev/null 2> /dev/null
pm2 save --force 1> /dev/null 2> /dev/null

# Remove firewall rule
iptables -D INPUT -p tcp --dport 5888 -j ACCEPT 1> /dev/null 2> /dev/null

# Remove directories, binaries, and license files
rm -rf /etc/zivpn/api 1> /dev/null 2> /dev/null
rm -f /etc/zivpn/api.auth 1> /dev/null 2> /dev/null
rm -f /usr/local/bin/zivpn_api_helper.sh 1> /dev/null 2> /dev/null
rm -f /etc/zivpn/license_checker.sh 1> /dev/null 2> /dev/null
rm -f /etc/zivpn/.license_info 1> /dev/null 2> /dev/null
rm -f /etc/zivpn/.expired 1> /dev/null 2> /dev/null
rm -rf /etc/zivpn 1> /dev/null 2> /dev/null # Finally remove the whole directory
rm -f /usr/local/bin/zivpn 1> /dev/null 2> /dev/null
rm -f /usr/local/bin/zivpn-manager 1> /dev/null 2> /dev/null
rm -f /usr/local/bin/zivpn_helper.sh 1> /dev/null 2> /dev/null


# Remove specific cron jobs
(crontab -l 2>/dev/null | grep -v "# zivpn-expiry-check") | crontab -
(crontab -l 2>/dev/null | grep -v "# zivpn-license-check") | crontab -
(crontab -l 2>/dev/null | grep -v "# zivpn-auto-backup") | crontab -


# Remove system integration from shell profiles
PROFILE_FILES=("/root/.bashrc" "/root/.bash_profile")
for PROFILE_FILE in "${PROFILE_FILES[@]}"; do
    if [ -f "$PROFILE_FILE" ]; then
        sed -i "/alias menu='\/usr\/local\/bin\/zivpn-manager'/d" "$PROFILE_FILE"
        sed -i "/\/usr\/local\/bin\/zivpn-manager/d" "$PROFILE_FILE"
    fi
done

echo "Verifying removal..."
if pgrep "zivpn" >/dev/null; then
  echo -e "Server process is still running."
else
  echo -e "Server process stopped."
fi

if [ -f "/usr/local/bin/zivpn" ] || [ -f "/usr/local/bin/zivpn-manager" ] || [ -d "/etc/zivpn" ]; then
  echo -e "Files still remaining, please check manually."
else
  echo -e "Successfully Removed All Files."
fi

echo "Cleaning Cache & Swap"
echo 3 > /proc/sys/vm/drop_caches
sysctl -w vm.drop_caches=3
swapoff -a && swapon -a
echo -e "Done."
