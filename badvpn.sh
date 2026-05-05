#!/bin/bash
# Script Instalasi BadVPN UDPGW
# Port: 7000, 7100, 7200, 7300

echo "--- Memulai Instalasi BadVPN UDPGW ---"

# 1. Menginstal dependensi yang diperlukan
echo "Menginstal dependensi (cmake, make, gcc, unzip)..."
apt-get update -y
apt-get install -y cmake make gcc build-essential unzip wget

# 2. Mengunduh dan mengkompilasi BadVPN
echo "Mengunduh source code BadVPN..."
cd /root
wget -O badvpn.zip https://github.com/ambrop72/badvpn/archive/master.zip
unzip -o badvpn.zip
cd badvpn-master
mkdir -p build
cd build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make install

# 3. Membuat systemd service untuk port 7000, 7100, 7200, 7300
PORTS=(7000 7100 7200 7300)

for PORT in "${PORTS[@]}"; do
    echo "Membuat service untuk BadVPN di port $PORT..."
    cat <<EOF > /etc/systemd/system/badvpn${PORT}.service
[Unit]
Description=BadVPN UDPGW Service Port ${PORT}
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:${PORT} --max-clients 500
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable dan start service
    systemctl daemon-reload
    systemctl enable badvpn${PORT}.service
    systemctl start badvpn${PORT}.service
done

# Membersihkan file instalasi
cd /root
rm -rf badvpn-master badvpn.zip

echo "--- Instalasi BadVPN UDPGW Selesai ---"
