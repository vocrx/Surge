#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run with root privileges"
    exit 1
fi

if [ "$1" = "uninstall" ]; then
    echo "Uninstalling Snell server ..."
    systemctl stop snell
    systemctl disable snell
    rm -f /etc/systemd/system/snell.service
    systemctl daemon-reload
    rm -rf /opt/snell
    echo "Snell has been uninstalled."
    exit 0
fi

echo "Checking dependencies..."
required_packages=(wget unzip openssl curl net-tools)
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

password=$(openssl rand -base64 12)

cat >|snell-server.conf <<EOF
[snell-server]
listen = :::$port
psk = $password
ipv6 = true
EOF

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
echo -e "\nNode information (Surge format):"
echo "Proxy = snell, $server_ip, $port, psk=$password, version=4"
