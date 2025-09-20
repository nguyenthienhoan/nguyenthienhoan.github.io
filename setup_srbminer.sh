#!/bin/bash

VERSION=1.1
echo "SRBMiner-MULTI mining setup script v$VERSION"
echo

# --- KHÔNG KHUYẾN NGHỊ chạy root, nhưng vẫn cho chạy ---
if [ "$(id -u)" = "0" ]; then
  echo "CẢNH BÁO: Không nên chạy script này dưới quyền root"
fi

# --- Tham số ---
WALLET="$1"
EMAIL="$2" # optional

if [ -z "$WALLET" ]; then
  echo "Cách sử dụng script:"
  echo "> setup_srbminer.sh <địa chỉ ví> [<địa chỉ email>]"
  exit 1
fi

# --- Phát hiện sudo/systemd ---
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  SUDO="sudo"
else
  SUDO=""
fi

if command -v systemctl >/dev/null 2>&1; then
  HAS_SYSTEMD=1
else
  HAS_SYSTEMD=0
fi

# --- Thư mục làm việc ---
mkdir -p "$HOME/srbminer"

CPU_THREADS=$(nproc 2>/dev/null || echo 1)
WORKER_NAME=$(hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g')
[ -z "$WORKER_NAME" ] && WORKER_NAME="worker_$(date +%s)"

echo "Host này có $CPU_THREADS luồng CPU. Worker: $WORKER_NAME"
echo "Ví Monero: $WALLET"
[ -n "$EMAIL" ] && echo "Email: $EMAIL"

echo
echo "[*] Gỡ SRBMiner cũ (nếu có)"
$SUDO systemctl stop srbminer.service 2>/dev/null
pkill -f SRBMiner-MULTI 2>/dev/null
rm -rf "$HOME/srbminer/"*

echo "[*] Lấy link latest release từ GitHub"
LATEST_URL=$(curl -s https://api.github.com/repos/doktor83/SRBMiner-Multi/releases/latest \
  | grep "browser_download_url" | grep "Linux.tar.gz" | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
  echo "LỖI: Không lấy được link release mới nhất từ GitHub."
  exit 1
fi

echo "[*] Tải SRBMiner-MULTI từ $LATEST_URL"
curl -L -o /tmp/SRBMiner-MULTI.tar.gz "$LATEST_URL" || { echo "LỖI: tải thất bại"; exit 1; }
tar -xvf /tmp/SRBMiner-MULTI.tar.gz -C "$HOME/srbminer" --strip-components=1
rm -f /tmp/SRBMiner-MULTI.tar.gz
chmod +x "$HOME/srbminer/SRBMiner-MULTI"

echo
echo "[*] Tạo script miner.sh"
cat > "$HOME/srbminer/miner.sh" <<EOL
#!/bin/bash
cd "\$(dirname "\$0")"

T=\${CPU_THREADS:-$CPU_THREADS}

./SRBMiner-MULTI \\
  --algorithm randomx \\
  --pool 13.250.25.208:39333 --wallet $WALLET --password $WORKER_NAME \\
  --cpu-threads \$T \\
  --cpu-priority 2 \\
  --disable-gpu \\
  --log-file srbminer.log
EOL

sed -i '1s|^|#!/bin/bash\n|' "$HOME/srbminer/miner.sh"
chmod +x "$HOME/srbminer/miner.sh"

echo
if [ "$HAS_SYSTEMD" -eq 1 ] && [ -n "$SUDO" ]; then
  echo "[*] Tạo systemd service"
  USER_NAME="$(whoami)"
  HOME_DIR="$HOME"

  cat > /tmp/srbminer.service <<EOL
[Unit]
Description=SRBMiner-MULTI Monero miner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER_NAME}
Group=${USER_NAME}
WorkingDirectory=${HOME_DIR}/srbminer
Environment=HOME=${HOME_DIR}
Environment=CPU_THREADS=${CPU_THREADS}
ExecStartPre=/usr/bin/sleep 5
ExecStart=${HOME_DIR}/srbminer/miner.sh
Restart=always
RestartSec=3
Nice=10
CPUWeight=1
StandardOutput=append:/var/log/srbminer.service.log
StandardError=append:/var/log/srbminer.service.log

[Install]
WantedBy=multi-user.target
EOL

  $SUDO mv /tmp/srbminer.service /etc/systemd/system/srbminer.service
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable srbminer.service
  $SUDO systemctl restart srbminer.service

  echo "OK: Đã bật service systemd: srbminer.service"
  echo "Xem log: $SUDO journalctl -u srbminer -f"
else
  echo "[*] Không có sudo/systemd -> fallback giống c3pool (.profile + chạy nền)"
  if ! grep -q 'srbminer/miner.sh' "$HOME/.profile" 2>/dev/null; then
    echo "$HOME/srbminer/miner.sh >/dev/null 2>&1" >> "$HOME/.profile"
    echo "Đã thêm autostart vào ~/.profile"
  else
    echo "Có vẻ miner.sh đã có trong ~/.profile"
  fi
  nohup "$HOME/srbminer/miner.sh" >/var/log/srbminer.out 2>&1 &
  echo "Đang chạy nền. Log: /var/log/srbminer.out  &  $HOME/srbminer/srbminer.log"
fi

echo "Hoàn tất."
