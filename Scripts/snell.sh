#!/bin/bash

VERSION="5.0.0"

if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run with root privileges"
    exit 1
fi

update() {
    if [ ! -d "/opt/snell" ]; then
        echo "Error: Snell Server is not installed"
        exit 1
    fi

    echo "Updating Snell Server to version $VERSION..."
    cd /opt/snell

    arch=$(uname -m)
    case $arch in
    x86_64)
        package="snell-server-v$VERSION-linux-amd64.zip"
        ;;
    aarch64)
        package="snell-server-v$VERSION-linux-aarch64.zip"
        ;;
    *)
        echo "Unsupported system architecture: $arch"
        exit 1
        ;;
    esac

    rm -f snell-server
    wget -q "https://dl.nssurge.com/snell/$package"
    unzip -q "$package"
    rm -f "$package"

    systemctl restart snell
    echo "Update completed. Service restarted."
    exit 0
}

uninstall() {
    if [ -d "/opt/snell" ] || [ -f "/etc/systemd/system/snell.service" ]; then
        echo "Removing existing Snell Server installation..."
        systemctl stop snell 2>/dev/null
        systemctl disable snell 2>/dev/null
        rm -f /etc/systemd/system/snell.service
        systemctl daemon-reload
        rm -rf /opt/snell
    fi
}

if [ "$#" -eq 1 ]; then
    case "$1" in
    "uninstall")
        uninstall
        echo "Snell Server has been uninstalled."
        exit 0
        ;;
    "update")
        update
        ;;
    *)
        echo "Usage: $0 [-p port] [-psk password] [-dns dnsserver] [-v6 true/false] [update|uninstall]"
        exit 1
        ;;
    esac
fi

uninstall

echo "Checking package manager and dependencies..."
if command -v apt >/dev/null 2>&1; then
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
    echo "Error: No supported package manager found (apt/dnf/yum)"
    exit 1
fi

required_packages=(wget unzip openssl curl net-tools)

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

rm -rf /opt/snell
mkdir -p /opt/snell
cd /opt/snell

arch=$(uname -m)
case $arch in
x86_64)
    package="snell-server-v4.1.1-linux-amd64.zip"
    ;;
aarch64)
    package="snell-server-v4.1.1-linux-aarch64.zip"
    ;;
*)
    echo "Unsupported system architecture: $arch"
    exit 1
    ;;
esac

wget -q "https://dl.nssurge.com/snell/$package"
unzip -q "$package"
rm -f "$package"

port=""
password=""
dns=""
ipv6_enabled="true"

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
    -psk)
        shift
        password="$1"
        ;;
    -dns)
        shift
        dns="$1"
        ;;
    -v6)
        shift
        if [ "$1" = "true" ] || [ "$1" = "false" ]; then
            ipv6_enabled="$1"
        else
            echo "Error: IPv6 value must be true or false"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [-p port] [-psk password] [-dns dnsserver] [-v6 true/false] [update|uninstall]"
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
    password=$(openssl rand -base64 12)
fi

cat >|snell-server.conf <<EOF
[snell-server]
listen = :::$port
psk = $password
ipv6 = $ipv6_enabled
EOF

if [ ! -z "$dns" ]; then
    echo "dns = $dns" >>snell-server.conf
fi

cat >|/etc/systemd/system/snell.service <<EOF
[Unit]
Description=Snell Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/snell/snell-server -c /opt/snell/snell-server.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable snell
systemctl restart snell

server_ip=$(curl -s http://ipv4.icanhazip.com)
echo -e "Node information (Surge format):"
echo "$(hostname) = snell, $server_ip, $port, psk=$password, version=4"
