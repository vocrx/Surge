#!/bin/bash

VERSION="1.21.2"

get_service_manager() {
    if command -v systemctl >/dev/null 2>&1; then
        echo "systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        echo "openrc"
    else
        echo "unknown"
    fi
}

SERVICE_MANAGER=$(get_service_manager)

if [ "$SERVICE_MANAGER" = "unknown" ]; then
    echo "Error: No supported service manager found"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run with root privileges"
    exit 1
fi

is_alpine() {
    if [ -f /etc/alpine-release ]; then
        return 0
    else
        return 1
    fi
}

update() {
    if [ ! -d "/opt/ss-rust" ]; then
        echo "Error: Shadowsocks Rust is not installed"
        exit 1
    fi

    echo "Updating Shadowsocks Rust to version $VERSION..."
    cd /opt/ss-rust

    arch=$(uname -m)
    if is_alpine; then
        case $arch in
        x86_64)
            package="shadowsocks-v$VERSION.x86_64-unknown-linux-musl.tar.xz"
            ;;
        aarch64)
            package="shadowsocks-v$VERSION.aarch64-unknown-linux-musl.tar.xz"
            ;;
        *)
            echo "Unsupported system architecture: $arch"
            exit 1
            ;;
        esac
    else
        case $arch in
        x86_64)
            package="shadowsocks-v$VERSION.x86_64-unknown-linux-gnu.tar.xz"
            ;;
        aarch64)
            package="shadowsocks-v$VERSION.aarch64-unknown-linux-gnu.tar.xz"
            ;;
        *)
            echo "Unsupported system architecture: $arch"
            exit 1
            ;;
        esac
    fi
    rm -f ssserver
    wget -q "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v$VERSION/$package"
    tar -xf "$package"
    rm -f "$package" sslocal ssmanager ssservice ssurl

    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl restart ss-rust
    else
        rc-service ss-rust restart
    fi
    echo "Update completed. Service restarted."
    exit 0
}

uninstall() {
    if [ -d "/opt/ss-rust" ] || [ -f "/etc/systemd/system/ss-rust.service" ] || [ -f "/etc/init.d/ss-rust" ]; then
        echo "Removing existing Shadowsocks Rust installation..."
        if [ "$SERVICE_MANAGER" = "systemd" ]; then
            systemctl stop ss-rust 2>/dev/null
            systemctl disable ss-rust 2>/dev/null
            rm -f /etc/systemd/system/ss-rust.service
            systemctl daemon-reload
        else
            rc-service ss-rust stop 2>/dev/null
            rc-update del ss-rust default 2>/dev/null
            rm -f /etc/init.d/ss-rust
        fi
        rm -rf /opt/ss-rust
    fi
}

if [ "$#" -eq 1 ]; then
    case "$1" in
    "uninstall")
        uninstall
        echo "Shadowsocks Rust has been uninstalled."
        exit 0
        ;;
    "update")
        update
        ;;
    *)
        echo "Usage: $0 [-p port] [-psk password] [update|uninstall]"
        exit 1
        ;;
    esac
fi

uninstall

echo "Checking package manager and dependencies..."
if command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
    check_package() {
        apk info -e "$1" >/dev/null 2>&1
    }
    install_packages() {
        apk add --no-cache "$@" >/dev/null 2>&1
    }
elif command -v apt >/dev/null 2>&1; then
    PKG_MANAGER="apt"
    check_package() {
        dpkg -l "$1" 2>/dev/null | grep -q "^ii"
    }
    install_packages() {
        apt update >/dev/null 2>&1
        apt install -y "$@" >/dev/null 2>&1
    }
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    check_package() {
        rpm -q "$1" >/dev/null 2>&1
    }
    install_packages() {
        dnf install -y "$@" >/dev/null 2>&1
    }
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
    check_package() {
        rpm -q "$1" >/dev/null 2>&1
    }
    install_packages() {
        yum install -y "$@" >/dev/null 2>&1
    }
else
    echo "Error: No supported package manager found (apk/apt/dnf/yum)"
    exit 1
fi

if [ "$PKG_MANAGER" = "apk" ]; then
    required_packages=(wget tar openssl curl net-tools xz bash)
else
    required_packages=(wget tar openssl curl net-tools xz-utils)
fi

missing_packages=()

for package in "${required_packages[@]}"; do
    if ! check_package "$package"; then
        missing_packages+=("$package")
    fi
done

if [ ${#missing_packages[@]} -ne 0 ]; then
    echo "Installing required packages: ${missing_packages[*]}"
    if ! install_packages "${missing_packages[@]}"; then
        echo "Error: Failed to install required packages"
        exit 1
    fi
else
    echo "All dependencies are already installed"
fi

rm -rf /opt/ss-rust
mkdir -p /opt/ss-rust
cd /opt/ss-rust

arch=$(uname -m)
if is_alpine; then
    case $arch in
    x86_64)
        package="shadowsocks-v$VERSION.x86_64-unknown-linux-musl.tar.xz"
        ;;
    aarch64)
        package="shadowsocks-v$VERSION.aarch64-unknown-linux-musl.tar.xz"
        ;;
    *)
        echo "Unsupported system architecture: $arch"
        exit 1
        ;;
    esac
else
    case $arch in
    x86_64)
        package="shadowsocks-v$VERSION.x86_64-unknown-linux-gnu.tar.xz"
        ;;
    aarch64)
        package="shadowsocks-v$VERSION.aarch64-unknown-linux-gnu.tar.xz"
        ;;
    *)
        echo "Unsupported system architecture: $arch"
        exit 1
        ;;
    esac
fi

wget -q "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v$VERSION/$package"
tar -xf "$package"
rm -f "$package" sslocal ssmanager ssservice ssurl

port=""
password=""

while [ "$#" -gt 0 ]; do
    case "$1" in
    -p)
        shift
        if [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; then
            if ! netstat -tuln | grep -q ":$1 "; then
                port="$1"
            else
                echo "Error: Port $1 is already in use"
                exit 1
            fi
        else
            echo "Error: Invalid port number"
            exit 1
        fi
        ;;
    -passwd)
        shift
        password="$1"
        ;;
    *)
        echo "Usage: $0 [-p port] [-psk password] [update|uninstall]"
        exit 1
        ;;
    esac
    shift
done

if [ -z "$port" ]; then
    while true; do
        port=$(shuf -i 1000-65535 -n 1)
        if ! netstat -tuln | grep -q ":$port "; then
            break
        fi
    done
fi

if [ -z "$password" ]; then
    password=$(openssl rand -base64 16)
fi

cat >|config.json <<EOF
{
    "server": "::",
    "server_port": $port,
    "password": "$password",
    "method": "2022-blake3-aes-128-gcm",
    "mode": "tcp_and_udp"
}
EOF

if [ "$SERVICE_MANAGER" = "systemd" ]; then
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
else
    cat >|/etc/init.d/ss-rust <<EOF
#!/sbin/openrc-run

name="Shadowsocks Rust Server"
description="Shadowsocks Rust Server"
command="/opt/ss-rust/ssserver"
command_args="-c /opt/ss-rust/config.json"
command_background="yes"
pidfile="/run/ss-rust.pid"
output_log="/var/log/ss-rust.log"
error_log="/var/log/ss-rust-error.log"

depend() {
    need net
    after network
}
EOF
    chmod +x /etc/init.d/ss-rust
    rc-update add ss-rust default
    rc-service ss-rust restart
fi

server_ip=$(curl -s http://ipv4.icanhazip.com)
echo -e "Node information (Surge format):"
echo "$(hostname) = ss, $server_ip, $port, encrypt-method=2022-blake3-aes-128-gcm, password=$password, udp-relay=true"
