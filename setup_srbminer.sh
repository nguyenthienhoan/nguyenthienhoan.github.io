#!/bin/bash

VERSION=1.0
echo "SRBMiner-MULTI mining setup script v$VERSION"
echo

if [ "$(id -u)" == "0" ]; then
  echo "CẢNH BÁO: Không nên chạy script này dưới quyền root"
fi

# Tham số
WALLET=$1
EMAIL=$2 # tùy chọn

if [ -z "$WALLET" ]; then
  echo "Cách sử dụng script:"
  echo "> setup_srbminer.sh <địa chỉ ví> [<địa chỉ email>]"
  exit 1
fi

if [ ! -d $HOME/srbminer ]; then
  mkdir -p $HOME/srbminer
fi

CPU_THREADS=$(nproc)
WORKER_NAME=$(hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g')
[ -z "$WORKER_NAME" ] && WORKER_NAME="worker_$(date +%s)"

echo "Host này có $CPU_THREADS luồng CPU. Worker: $WORKER_NAME"
echo "Ví Monero: $WALLET"
[ ! -z "$EMAIL" ] && echo "Email: $EMAIL"

echo
echo "[*] Gỡ bỏ SRBMiner cũ (nếu có)"
sudo systemctl stop srbminer.service 2>/dev/null
killall -9 SRBMiner-MULTI 2>/dev/null
rm -rf $HOME/srbminer/*

echo "[*] Lấy link latest release từ GitHub"
LATEST_URL=$(curl -s https://api.github.com/repos/doktor83/SRBMiner-Multi/releases/latest \
  | grep "browser_download_url" \
  | grep "Linux.tar.gz" \
  | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
  echo "LỖI: Không lấy được link release mới nhất từ GitHub."
  exit 1
fi

echo "[*] Tải SRBMiner-MULTI từ $LATEST_URL"
wget -O /tmp/SRBMiner-MULTI.tar.gz "$LATEST_URL"
tar -xvf /tmp/SRBMiner-MULTI.tar.gz -C $HOME/srbminer --strip-components=1
rm /tmp/SRBMiner-MULTI.tar.gz

echo
echo "[*] Tạo script miner.sh"
cat > $HOME/srbminer/miner.sh <<EOL
#!/bin/bash
cd \$(dirname \$0)

./SRBMiner-MULTI \\
  --algorithm randomx \\
  --pool 13.250.25.208:3333 \\
  --wallet $WALLET \\
  --password $WORKER_NAME \\
  --cpu-threads 4 \\
  --cpu-priority 2 \\
  --disable-gpu \\
  --log-file srbminer.log
EOL

chmod +x "$HOME/srbminer/miner.sh"

echo
echo "[*] Tạo systemd service"
cat > /tmp/srbminer.service <<EOL
[Unit]
Description=SRBMiner-MULTI Monero miner
After=network.target

[Service]
ExecStart=$HOME/srbminer/miner.sh
WorkingDirectory=$HOME/srbminer
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL

$SUDO mv /tmp/srbminer.service /etc/systemd/system/srbminer.service
$SUDO systemctl daemon-reload
$SUDO systemctl enable srbminer.service
$SUDO systemctl restart srbminer.service

echo "OK: Đã bật service systemd: srbminer.service"
echo "Xem log: $SUDO journalctl -u srbminer -f"

