#!/bin/bash
#
# Skrip Perbaikan untuk Instalasi zivpn
# --------------------------------------------------
# Skrip ini akan memeriksa dan memperbaiki instalasi zivpn yang rusak dengan
# memastikan semua file yang diperlukan ada, layanan berjalan, dan
# firewall dikonfigurasi dengan benar.
#
# Jalankan skrip ini di server Anda dengan perintah:
#   wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/repair.sh
#   chmod +x repair.sh
#   sudo ./repair.sh
#

echo "===== Memulai Proses Perbaikan zivpn ====="

# Langkah 1: Pastikan file biner zivpn ada dan dapat dieksekusi
if [ ! -f "/usr/local/bin/zivpn" ]; then
    echo "[LANGKAH 1] File biner zivpn tidak ditemukan. Mengunduh..."
    wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
    chmod +x /usr/local/bin/zivpn
    echo "[LANGKAH 1] File biner zivpn berhasil diunduh dan diatur."
else
    echo "[LANGKAH 1] File biner zivpn sudah ada."
fi

# Langkah 2: Pastikan direktori dan file konfigurasi ada
if [ ! -d "/etc/zivpn" ]; then
    echo "[LANGKAH 2] Direktori /etc/zivpn tidak ditemukan. Membuat..."
    mkdir -p /etc/zivpn
else
    echo "[LANGKAH 2] Direktori /etc/zivpn sudah ada."
fi

if [ ! -f "/etc/zivpn/config.json" ]; then
    echo "[LANGKAH 2] File config.json tidak ditemukan. Mengunduh..."
    wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O /etc/zivpn/config.json
else
    echo "[LANGKAH 2] File config.json sudah ada."
fi

if [ ! -f "/etc/zivpn/zivpn.crt" ] || [ ! -f "/etc/zivpn/zivpn.key" ]; then
    echo "[LANGKAH 2] File sertifikat SSL tidak ditemukan. Membuat..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=California/L=Los Angeles/O=Example Corp/OU=IT Department/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"
else
    echo "[LANGKAH 2] File sertifikat SSL sudah ada."
fi
echo "[LANGKAH 2] Konfigurasi selesai diperiksa."

# Langkah 3: Pastikan layanan systemd ada dan berjalan
SERVICE_FILE="/etc/systemd/system/zivpn.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo "[LANGKAH 3] File layanan systemd tidak ditemukan. Membuat..."
    cat <<EOF > $SERVICE_FILE
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
    echo "[LANGKAH 3] Memuat ulang daemon systemd..."
    systemctl daemon-reload
    echo "[LANGKAH 3] Mengaktifkan layanan zivpn..."
    systemctl enable zivpn.service
else
    echo "[LANGKAH 3] File layanan systemd sudah ada."
fi

echo "[LANGKAH 3] Memulai ulang layanan zivpn..."
systemctl restart zivpn.service

# Beri waktu sejenak untuk layanan stabil
sleep 3

# Cek status akhir
if systemctl is-active --quiet zivpn.service; then
    echo "[LANGKAH 3] Layanan zivpn berhasil dimulai dan sedang berjalan."
else
    echo "[PERINGATAN] Layanan zivpn gagal dimulai. Silakan periksa log dengan 'journalctl -u zivpn.service'."
fi

# Langkah 4: Pastikan aturan firewall iptables ada
# Cari nama interface default
IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$IFACE" ]; then
    echo "[KESALAHAN] Tidak dapat menemukan interface jaringan default. Aturan firewall tidak dapat ditambahkan."
else
    # Cek apakah aturan sudah ada
    if ! iptables -t nat -C PREROUTING -i $IFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null; then
        echo "[LANGKAH 4] Aturan firewall iptables tidak ditemukan. Menambahkan..."
        iptables -t nat -A PREROUTING -i $IFACE -p udp --dport 6000:19999 -j DNAT --to-destination :5667
        echo "[LANGKAH 4] Aturan firewall berhasil ditambahkan untuk interface '$IFACE'."
    else
        echo "[LANGKAH 4] Aturan firewall iptables sudah ada."
    fi
fi

echo "===== Proses Perbaikan Selesai ====="
echo "Silakan coba hubungkan kembali klien VPN Anda."
