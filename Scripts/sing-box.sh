#!/bin/bash

VERSION="1.11.4"
BETA_VERSION="1.12.0-alpha.8"

if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run with root privileges"
    exit 1
fi

update() {
    if [ ! -d "/opt/sing-box" ]; then
        echo "Error: Sing-Box is not installed"
        exit 1
    fi

    current_version=$(/opt/sing-box/sing-box version | grep "sing-box version" | cut -d' ' -f3)

    local version_to_use="$VERSION"
    if [ "$1" = "beta" ]; then
        version_to_use="$BETA_VERSION"
        echo "Current version: $current_version"
        echo "Latest beta version: $version_to_use"
    else
        echo "Current version: $current_version"
        echo "Latest stable version: $version_to_use"
    fi

    if [ "$current_version" = "$version_to_use" ]; then
        echo "Already on the latest version"
        exit 0
    fi

    echo "Updating Sing-Box to version $version_to_use..."
    cd /opt/sing-box

    arch=$(uname -m)
    case $arch in
    x86_64)
        package="sing-box-$version_to_use-linux-amd64"
        ;;
    aarch64)
        package="sing-box-$version_to_use-linux-arm64"
        ;;
    *)
        echo "Unsupported system architecture: $arch"
        exit 1
        ;;
    esac

    rm -f sing-box
    wget -q "https://github.com/SagerNet/sing-box/releases/download/v$version_to_use/$package.tar.gz"
    tar -xzf "$package.tar.gz"
    mv "$package/sing-box" .
    rm -rf "$package" "$package.tar.gz"
    chmod +x sing-box

    systemctl restart sing-box
    echo "Update completed. Service restarted."
    exit 0
}

uninstall() {
    if [ -d "/opt/sing-box" ] || [ -f "/etc/systemd/system/sing-box.service" ]; then
        echo "Removing existing Sing-Box installation..."
        systemctl stop sing-box 2>/dev/null
        systemctl disable sing-box 2>/dev/null
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
        rm -rf /opt/sing-box
    fi
}

if [ "$#" -eq 1 ]; then
    case "$1" in
    "uninstall")
        uninstall
        echo "Sing-Box has been uninstalled."
        exit 0
        ;;
    "update")
        update
        exit 0
        ;;
    "-beta")
        use_beta=true
        version_to_use="$BETA_VERSION"
        ;;
    *)
        echo "Usage: $0 [-p port] [-k password] [-c config_file] [-beta] [update|uninstall]"
        exit 1
        ;;
    esac
elif [ "$#" -eq 2 ] && [ "$1" = "update" ] && [ "$2" = "-beta" ]; then
    update "beta"
    exit 0
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

required_packages=(wget tar openssl curl net-tools)

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

rm -rf /opt/sing-box
mkdir -p /opt/sing-box
cd /opt/sing-box

port=""
password=""
config_file=""
use_beta=false
version_to_use="$VERSION"

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
    -k)
        shift
        password="$1"
        ;;
    -c)
        shift
        input_path="$1"

        if [[ "$1" = /* ]]; then
            config_path="$1"
        else
            current_dir="$PWD"
            cd - >/dev/null

            if [ -f "$1" ]; then
                config_path="$(readlink -f "$1")"
            elif [ -f "./$1" ]; then
                config_path="$(readlink -f "./$1")"
            elif [ -f "$PWD/$1" ]; then
                config_path="$PWD/$1"
            else
                echo "Error: Configuration file '$input_path' does not exist"
                exit 1
            fi

            cd "$current_dir"
        fi

        if [ -f "$config_path" ]; then
            config_file="$config_path"
        else
            echo "Error: Configuration file '$input_path' does not exist"
            exit 1
        fi
        ;;
    -beta)
        use_beta=true
        version_to_use="$BETA_VERSION"
        ;;
    *)
        echo "Usage: $0 [-p port] [-k password] [-c config_file] [-beta] [update|uninstall]"
        exit 1
        ;;
    esac
    shift
done

arch=$(uname -m)
case $arch in
x86_64)
    package="sing-box-$version_to_use-linux-amd64"
    ;;
aarch64)
    package="sing-box-$version_to_use-linux-arm64"
    ;;
*)
    echo "Unsupported system architecture: $arch"
    exit 1
    ;;
esac

wget -q "https://github.com/SagerNet/sing-box/releases/download/v$version_to_use/$package.tar.gz"
tar -xzf "$package.tar.gz"
mv "$package/sing-box" .
rm -rf "$package" "$package.tar.gz"
chmod +x sing-box

if [ -n "$config_file" ]; then
    cp "$config_file" /opt/sing-box/config.json
else
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
        "log": {
            "disabled": true
        },
        "inbounds": [
            {
                "type": "shadowsocks",
                "listen": "::",
                "listen_port": $port,
                "method": "2022-blake3-aes-128-gcm",
                "password": "$password"
            }
        ]
    }
EOF
fi

cat >|/etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-Box Service
Documentation=https://sing-box.sagernet.org
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/sing-box/sing-box run -c /opt/sing-box/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

server_ip=$(curl -s http://ipv4.icanhazip.com)
if [ -z "$config_file" ]; then
    echo -e "Proxy information (Surge format):"
    echo "$(hostname) = ss, $server_ip, $port, encrypt-method=2022-blake3-aes-128-gcm, password=$password, udp-relay=true"
else
    echo -e "\nUsing custom configuration file: $config_file"
fi
