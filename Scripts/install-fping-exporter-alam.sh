#!/bin/bash

PING_PERIOD=15
PING_COUNT=15

while [[ $# -gt 0 ]]; do
    case "$1" in
    -p)
        if [[ "$2" =~ ^[0-9]+$ ]]; then
            PING_PERIOD="$2"
            shift 2
        else
            echo "错误：-p 参数必须是数字" >&2
            exit 1
        fi
        ;;
    -c)
        if [[ "$2" =~ ^[0-9]+$ ]]; then
            PING_COUNT="$2"
            shift 2
        else
            echo "错误：-c 参数必须是数字" >&2
            exit 1
        fi
        ;;
    *)
        echo "未知参数: $1" >&2
        exit 1
        ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "此脚本必须以 root 权限运行"
    exit 1
fi

systemctl stop fping-exporter 2>/dev/null
systemctl disable fping-exporter 2>/dev/null

apt update >/dev/null 2>&1
apt install -y fping >/dev/null 2>&1

rm -rf /root/fping-exporter
mkdir -p /root/fping-exporter

wget -q https://github.com/midori01/fping-exporter/releases/download/v1.0.2/fping-exporter-linux-amd64 -O /root/fping-exporter/fping-exporter-linux-amd64

chmod +x /root/fping-exporter/fping-exporter-linux-amd64

cat >/etc/systemd/system/fping-exporter.service <<EOL
[Unit]
Description=Fping Exporter
After=network.target

[Service]
Type=simple
ExecStart=/root/fping-exporter/fping-exporter-linux-amd64 -f /usr/sbin/fping -p $PING_PERIOD -c $PING_COUNT
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable fping-exporter
systemctl start fping-exporter
systemctl status fping-exporter
