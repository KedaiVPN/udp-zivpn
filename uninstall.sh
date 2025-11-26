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

# Remove directories and binaries
rm -rf /etc/zivpn 1> /dev/null 2> /dev/null
rm /usr/local/bin/zivpn 1> /dev/null 2> /dev/null
rm /usr/local/bin/zivpn-manager 1> /dev/null 2> /dev/null

# Remove cron job
(crontab -l 2>/dev/null | grep -v "/etc/zivpn/expire_check.sh") | crontab -

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
