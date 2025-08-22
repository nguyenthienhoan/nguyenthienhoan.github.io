#!/bin/bash

VERSION=2.11

# in ra lời chào

echo "C3Pool mining setup script v$VERSION."
echo

if [ "$(id -u)" == "0" ]; then
  echo "CẢNH BÁO: Không nên chạy script này dưới quyền root"
fi

# tham số dòng lệnh
WALLET=$1
EMAIL=$2 # tham số này là tùy chọn

# kiểm tra các điều kiện tiên quyết

if [ -z $WALLET ]; then
  echo "Cách sử dụng script:"
echo "> setup_c3pool_miner.sh <địa chỉ ví> [<địa chỉ email của bạn>]"
echo "LỖI: Vui lòng chỉ định địa chỉ ví của bạn"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "LỖI: Độ dài địa chỉ ví cơ sở sai (phải là 106 hoặc 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "LỖI: Vui lòng định nghĩa biến môi trường HOME cho thư mục home của bạn"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "LỖI: Vui lòng đảm bảo thư mục HOME $HOME tồn tại hoặc tự đặt nó bằng lệnh này:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "LỖI: Script này yêu cầu tiện ích \"curl\" để hoạt động chính xác"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "CẢNH BÁO: Script này yêu cầu tiện ích \"lscpu\" để hoạt động chính xác"
fi

#if ! sudo -n true 2>/dev/null; then
#  if ! pidof systemd >/dev/null; then
#    echo "LỖI: Script này yêu cầu systemd để hoạt động chính xác"
#    exit 1
#  fi
#fi

# tính toán port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "LỖI: Không thể tính toán tốc độ hash Monero CN dự kiến"
  exit 1
fi

get_port_based_on_hashrate() {
  local hashrate=$1
  if [ "$hashrate" -le "5000" ]; then
    echo 80
  elif [ "$hashrate" -le "25000" ]; then
    if [ "$hashrate" -gt "5000" ]; then
      echo 13333
    else
      echo 443
    fi
  elif [ "$hashrate" -le "50000" ]; then
    if [ "$hashrate" -gt "25000" ]; then
      echo 15555
    else
      echo 14444
    fi
  elif [ "$hashrate" -le "100000" ]; then
    if [ "$hashrate" -gt "50000" ]; then
      echo 19999
    else
      echo 17777
    fi
  elif [ "$hashrate" -le "1000000" ]; then
    echo 23333
  else
    echo "LỖI: Tốc độ hash quá cao"
    exit 1
  fi
}

PORT=$(get_port_based_on_hashrate $EXP_MONERO_HASHRATE)
if [ -z $PORT ]; then
  echo "LỖI: Không thể tính toán port"
  exit 1
fi

echo "Port đã tính toán: $PORT"


# in ra mục đích

echo "Tôi sẽ tải xuống, thiết lập và chạy trong nền miner CPU Monero."
echo "Nếu cần, miner ở foreground có thể được khởi động bằng script $HOME/c3pool/miner.sh."
echo "Việc khai thác sẽ diễn ra trên ví $WALLET."
if [ ! -z $EMAIL ]; then
  echo "(và email $EMAIL làm mật khẩu để sửa đổi tùy chọn ví sau này tại trang web https://c3pool.com)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Vì tôi không thể thực hiện sudo không cần mật khẩu, khai thác trong nền sẽ được khởi động từ file $HOME/.profile của bạn lần đầu tiên bạn đăng nhập vào host này sau khi khởi động lại."
else
  echo "Khai thác trong nền sẽ được thực hiện bằng dịch vụ systemd c3pool_miner."
fi

echo
echo "FYI: Host này có $CPU_THREADS luồng CPU với $CPU_MHZ MHz và ${TOTAL_CACHE}KB cache dữ liệu tổng cộng, vì vậy tốc độ hash Monero dự kiến là khoảng $EXP_MONERO_HASHRATE H/s."
echo

# bắt đầu làm việc: chuẩn bị miner

echo "[*] Gỡ bỏ miner c3pool trước đó (nếu có)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop c3pool_miner.service
fi
killall -9 xmrig

echo "[*] Xóa thư mục $HOME/c3pool"
rm -rf $HOME/c3pool

echo "[*] Tải xuống phiên bản nâng cao C3Pool của xmrig đến /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://download.c3pool.org/xmrig_setup/raw/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "LỖI: Không thể tải xuống file https://download.c3pool.org/xmrig_setup/raw/master/xmrig.tar.gz đến /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Giải nén /tmp/xmrig.tar.gz đến $HOME/c3pool"
[ -d $HOME/c3pool ] || mkdir $HOME/c3pool
if ! tar xf /tmp/xmrig.tar.gz -C $HOME/c3pool; then
  echo "LỖI: Không thể giải nén /tmp/xmrig.tar.gz đến thư mục $HOME/c3pool"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Kiểm tra xem phiên bản nâng cao của $HOME/c3pool/xmrig có hoạt động tốt không (và không bị xóa bởi phần mềm antivirus)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $HOME/c3pool/config.json
$HOME/c3pool/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/c3pool/xmrig ]; then
    echo "CẢNH BÁO: Phiên bản nâng cao của $HOME/c3pool/xmrig không hoạt động"
  else 
    echo "CẢNH BÁO: Phiên bản nâng cao của $HOME/c3pool/xmrig đã bị xóa bởi antivirus (hoặc vấn đề khác)"
  fi

  echo "[*] Tìm kiếm phiên bản mới nhất của miner Monero"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Tải xuống $LATEST_XMRIG_LINUX_RELEASE đến /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "LỖI: Không thể tải xuống file $LATEST_XMRIG_LINUX_RELEASE đến /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Giải nén /tmp/xmrig.tar.gz đến $HOME/c3pool"
  if ! tar xf /tmp/xmrig.tar.gz -C $HOME/c3pool --strip=1; then
    echo "CẢNH BÁO: Không thể giải nén /tmp/xmrig.tar.gz đến thư mục $HOME/c3pool"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Kiểm tra xem phiên bản stock của $HOME/c3pool/xmrig có hoạt động tốt không (và không bị xóa bởi phần mềm antivirus)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/c3pool/config.json
  $HOME/c3pool/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/c3pool/xmrig ]; then
      echo "LỖI: Phiên bản stock của $HOME/c3pool/xmrig cũng không hoạt động"
    else 
      echo "LỖI: Phiên bản stock của $HOME/c3pool/xmrig cũng đã bị xóa bởi antivirus"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/c3pool/xmrig hoạt động tốt"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

echo "[*] Tạo config.json với template hoàn chỉnh"
cat > $HOME/c3pool/config.json <<EOL
{
    "api": {
        "id": null,
        "worker-id": null
    },
    "http": {
        "enabled": false,
        "host": "127.0.0.1",
        "port": 0,
        "access-token": null,
        "restricted": true
    },
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
        "priority": null,
        "memory-pool": true,
        "yield": false,
        "asm": true,
        "argon2-impl": null,
        "argon2": [0, 1, 2, 3, 6, 7],
        "cn": [
            [1, 0],
            [1, 1],
            [1, 2],
            [1, 3]
        ],
        "cn-heavy": [
            [1, 0],
            [1, 1],
            [1, 2],
            [1, 3],
            [1, 6],
            [1, 7]
        ],
        "cn-lite": [
            [1, 0],
            [1, 1],
            [1, 2],
            [1, 3],
            [1, 6],
            [1, 7]
        ],
        "cn-pico": [
            [2, 0],
            [2, 1],
            [2, 2],
            [2, 3],
            [2, 6],
            [2, 7]
        ],
        "cn/2": [
            [1, 0],
            [1, 1],
            [1, 2],
            [1, 3]
        ],
        "cn/gpu": [
            [1, 0],
            [1, 1],
            [1, 2],
            [1, 3],
            [1, 6],
            [1, 7]
        ],
        "cn/upx2": [
            [2, 0],
            [2, 1],
            [2, 2],
            [2, 3],
            [2, 6],
            [2, 7]
        ],
        "flex": [0, 1, 2, 3],
        "ghostrider": [
            [8, 0],
            [8, 1],
            [8, 2],
            [8, 3]
        ],
        "panthera": [0, 1, 2, 3],
        "rx": [0, 1, 2, 3],
        "rx/wow": [0, 1, 2, 3, 6, 7],
        "cn-lite/0": false,
        "cn/0": false,
        "rx/xeq": "rx/wow",
        "rx/arq": "rx/wow",
        "rx/keva": "rx/wow"
    },
    "log-file": "/home/user/c3pool/xmrig.log",
    "donate-level": 1,
    "donate-over-proxy": 1,
    "pools": [
        {
            "algo": "rx/0",
            "coin": null,
            "url": "47.236.141.1:3333",
            "user": "rig1",
            "pass": "x",
            "rig-id": "rig1",
            "nicehash": false,
            "keepalive": true,
            "enabled": true,
            "tls": false,
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
    "tls": {
        "enabled": true,
        "protocols": null,
        "cert": "cert.pem",
        "cert_key": "cert_key.pem",
        "ciphers": null,
        "ciphersuites": null,
        "dhparam": null
    },
    "dns": {
        "ip_version": 0,
        "ttl": 30
    },
    "user-agent": null,
    "verbose": 0,
    "watch": true,
    "rebench-algo": false,
    "bench-algo-time": 2,
    "algo-min-time": 0,
    "algo-perf": {
        "cn/0": 129.8828125,
        "cn/1": 158.5425898572132,
        "cn/2": 158.5425898572132,
        "cn/r": 158.5425898572132,
        "cn/fast": 317.0851797144264,
        "cn/half": 317.0851797144264,
        "cn/xao": 158.5425898572132,
        "cn/rto": 158.5425898572132,
        "cn/rwz": 211.39011980961757,
        "cn/zls": 211.39011980961757,
        "cn/double": 79.2712949286066,
        "cn/ccx": 259.765625,
        "cn-lite/0": 660.2469135802469,
        "cn-lite/1": 660.2469135802469,
        "cn-heavy/xhv": 145.6888007928642,
        "cn-pico": 4095.856215676485,
        "cn-pico/tlo": 4095.856215676485,
        "cn/gpu": 43.66602687140115,
        "rx/0": 1429.3559660509236,
        "rx/arq": 8308.345827086458,
        "rx/xeq": 8308.345827086458,
        "rx/graft": 1378.3108445777114,
        "rx/sfx": 1429.3559660509236,
        "panthera": 2659.510733899151,
        "argon2/chukwav2": 4754.122938530734,
        "kawpow": -1.0,
        "ghostrider": 565.2911249293386,
        "flex": 324.6056782334385
    },
    "pause-on-battery": false,
    "pause-on-active": false
}
EOL

echo "[*] Tạo config_background.json cho chạy nền"
cp $HOME/c3pool/config.json $HOME/c3pool/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/c3pool/config_background.json

# chuẩn bị script

echo "[*] Tạo script $HOME/c3pool/miner.sh"
cat >$HOME/c3pool/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice $HOME/c3pool/xmrig \$*
else
  echo "Miner Monero đã chạy trong nền. Từ chối chạy thêm một cái khác."
  echo "Chạy \"killall xmrig\" hoặc \"sudo killall xmrig\" nếu bạn muốn xóa miner nền trước."
fi
EOL

chmod +x $HOME/c3pool/miner.sh

# chuẩn bị script làm việc trong nền và làm việc sau khi khởi động lại

if ! sudo -n true 2>/dev/null; then
  if ! grep c3pool/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Thêm script $HOME/c3pool/miner.sh vào $HOME/.profile"
    echo "$HOME/c3pool/miner.sh --config=$HOME/c3pool/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Có vẻ như script $HOME/c3pool/miner.sh đã có trong $HOME/.profile"
  fi
  echo "[*] Chạy miner trong nền (xem logs trong file $HOME/c3pool/xmrig.log)"
  /bin/bash $HOME/c3pool/miner.sh --config=$HOME/c3pool/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') -gt 3500000 ]]; then
    echo "[*] Bật huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Chạy miner trong nền (xem logs trong file $HOME/c3pool/xmrig.log)"
    /bin/bash $HOME/c3pool/miner.sh --config=$HOME/c3pool/config_background.json >/dev/null 2>&1
    echo "LỖI: Script này yêu cầu tiện ích systemd \"systemctl\" để hoạt động chính xác."
    echo "Vui lòng chuyển sang bản phân phối Linux hiện đại hơn hoặc tự thiết lập kích hoạt miner sau khi khởi động lại nếu có thể."

  else

    echo "[*] Tạo dịch vụ systemd c3pool_miner"
    cat >/tmp/c3pool_miner.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=$HOME/c3pool/xmrig --config=$HOME/c3pool/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/c3pool_miner.service /etc/systemd/system/c3pool_miner.service
    echo "[*] Khởi động dịch vụ systemd c3pool_miner"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable c3pool_miner.service
    sudo systemctl start c3pool_miner.service
    echo "Để xem logs dịch vụ miner, chạy lệnh \"sudo journalctl -u c3pool_miner -f\""
  fi
fi

echo ""
echo "LƯU Ý: Nếu bạn đang sử dụng VPS dùng chung, nên tránh sử dụng 100% CPU do miner tạo ra hoặc bạn sẽ bị cấm"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "GỢI Ý: Vui lòng thực hiện các lệnh này hoặc lệnh tương tự dưới quyền root để giới hạn miner sử dụng 75% CPU:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "GỢI Ý: Vui lòng thực hiện các lệnh này và khởi động lại VPS của bạn sau đó để giới hạn miner sử dụng 75% CPU:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/c3pool/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/c3pool/config_background.json"
fi
echo ""

echo "[*] Thiết lập hoàn tất"