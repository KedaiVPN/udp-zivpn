#!/bin/bash

# Pre-flight check
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

echo "Installing required packages..."
apt-get update
apt-get install -y unzip

echo "Creating configuration directory..."
mkdir -p /etc/zivpn

echo "Downloading and installing zivpn server..."
wget -O /tmp/zivpn.zip https://github.com/kedaivpn/udp-zivpn/raw/main/zivpn.zip
unzip -o /tmp/zivpn.zip -d /usr/local/bin/
rm /tmp/zivpn.zip
chmod +x /usr/local/bin/zivpn

echo "Creating config.json..."
cat <<EOF > /etc/zivpn/config.json
{
  "auth": {
    "mode": "password",
    "config": [
      "default_pass"
    ]
  },
  "udp": {
    "listen": ":5667"
  },
  "ssl": {
    "cert": "/etc/zivpn/zivpn.crt",
    "key": "/etc/zivpn/zivpn.key"
  }
}
EOF

echo "Generating SSL certificate..."
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

echo "Creating systemd service..."
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/zivpn -config /etc/zivpn/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "Setting up firewall rules..."
iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 6000:19999 -j DNAT --to-destination :5667

echo "Starting ZIVPN service..."
systemctl daemon-reload
systemctl enable zivpn.service
systemctl start zivpn.service

echo "Installation complete."
