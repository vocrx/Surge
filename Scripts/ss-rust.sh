#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run with root privileges"
    exit 1
fi

if [ "$1" = "uninstall" ]; then
    echo "Uninstalling Shadowsocks Rust ..."
    systemctl stop ss-rust
    systemctl disable ss-rust
    rm -f /etc/systemd/system/ss-rust.service
    systemctl daemon-reload
    rm -rf /opt/ss-rust
    echo "Shadowsocks Rust has been uninstalled."
    exit 0
fi

# Check and install required packages
echo "Checking dependencies..."
required_packages=(wget tar openssl curl net-tools)
missing_packages=()

for package in "${required_packages[@]}"; do
    if ! dpkg -s "$package" >/dev/null 2>&1; then
        missing_packages+=("$package")
    fi
done

if [ ${#missing_packages[@]} -ne 0 ]; then
    echo "Installing required packages: ${missing_packages[*]}"
    apt update >/dev/null 2>&1
    apt install -y "${missing_packages[@]}" >/dev/null 2>&1
else
    echo "All dependencies are already installed"
fi

# 强制删除并重新创建目录
rm -rf /opt/ss-rust
mkdir -p /opt/ss-rust
cd /opt/ss-rust

# 检测系统架构
arch=$(uname -m)
case $arch in
x86_64)
    package="shadowsocks-v1.21.2.x86_64-unknown-linux-gnu.tar.xz"
    ;;
aarch64)
    package="shadowsocks-v1.21.2.aarch64-unknown-linux-gnu.tar.xz"
    ;;
*)
    echo "Unsupported system architecture: $arch"
    exit 1
    ;;
esac

# 下载对应架构的包
wget -q "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.21.2/$package"
tar -xf "$package"
rm -f "$package" sslocal ssmanager ssservice ssurl

while true; do

    read -p "Please enter port number (1-65535, press Enter for random port): " port

    if [ -z "$port" ]; then
        while true; do
            port=$(shuf -i 1000-65535 -n 1)
            if ! netstat -tuln | grep -q ":$port "; then
                echo "Using random port: $port"
                break
            fi
        done
        break
    else
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            echo "Error: Please enter a valid port number between 1-65535"
            continue
        fi

        if netstat -tuln | grep -q ":$port "; then
            echo "Error: Port $port is already in use, please try another"
            continue
        fi
        break
    fi
done

password=$(openssl rand -base64 16)

# 使用 >| 强制覆盖配置文件
cat >|config.json <<EOF
{
    "server": "::",
    "server_port": $port,
    "password": "$password",
    "method": "2022-blake3-aes-128-gcm",
    "mode": "tcp_and_udp"
}
EOF

cat >|/etc/systemd/system/ss-rust.service <<EOF
[Unit]
Description=Shadowsocks Rust Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/ss-rust/ssserver -c /opt/ss-rust/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ss-rust
systemctl restart ss-rust

server_ip=$(curl -s http://ipv4.icanhazip.com)
echo -e "\nNode information (Surge format):"
echo "Proxy = ss, $server_ip, $port, encrypt-method=2022-blake3-aes-128-gcm, password=$password, udp-relay=true"
