#!/bin/sh

set -e
random_port() {
    shuf -i 1024-65535 -n 1
}
random_psk() {
    tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 20 | head -n 1
}
generate_config() {
    PORT=${PORT:-$(random_port)}
    PSK=${PSK:-$(random_psk)}
    IPV6=${IPV6:-false}

    {
        echo "[snell-server]"
        echo "listen=:::$PORT"
        echo "psk=$PSK"
        echo "ipv6=$IPV6"
    } >/root/snell/snell.conf

    if [ -n "$DNS" ]; then
        echo "dns=$DNS" >>/root/snell/snell.conf
    fi
    if [ -n "$OBFS" ]; then
        echo "obfs=$OBFS" >>/root/snell/snell.conf
    fi
    if [ -n "$HOST" ]; then
        echo "obfs-host=$HOST" >>/root/snell/snell.conf
    fi
}
download_snell() {
    VERSION=${VERSION:-v4.1.1}
    if [ "$VERSION" = "v3.0.1" ]; then
        case "$TARGETPLATFORM" in
        "linux/amd64") SNELL_URL="https://github.com/vocrx/Surge/raw/refs/heads/main/snell-server-docker/source/snell-v3.0.1/snell-server-v3.0.1-linux-amd64.zip" ;;
        "linux/arm64") SNELL_URL="https://github.com/vocrx/Surge/raw/refs/heads/main/snell-server-docker/source/snell-v3.0.1/snell-server-v3.0.1-linux-aarch64.zip" ;;
        *) echo "不支持的平台: $TARGETPLATFORM" && exit 1 ;;
        esac
    else
        case "$TARGETPLATFORM" in
        "linux/amd64") SNELL_URL="https://dl.nssurge.com/snell/snell-server-$VERSION-linux-amd64.zip" ;;
        "linux/arm64") SNELL_URL="https://dl.nssurge.com/snell/snell-server-$VERSION-linux-aarch64.zip" ;;
        *) echo "不支持的平台: $TARGETPLATFORM" && exit 1 ;;
        esac
    fi

    wget -q -O snell.zip "$SNELL_URL" &&
        unzip -qo snell.zip -d /root/snell &&
        rm snell.zip &&
        chmod +x /root/snell/snell-server &&
        apk del wget unzip >/dev/null 2>&1 || true
}
download_snell
generate_config

[ -n "$PORT" ] && echo "PORT:$PORT" >/dev/null
[ -n "$PSK" ] && echo "PSK:$PSK" >/dev/null
[ -n "$VERSION" ] && echo "VERSION:$VERSION" >/dev/null
[ -n "$DNS" ] && echo "DNS:$DNS" >/dev/null
[ -n "$OBFS" ] && echo "OBFS:$OBFS" >/dev/null
[ -n "$HOST" ] && echo "HOST:$HOST" >/dev/null

exec /root/snell/snell-server -c /root/snell/snell.conf -l "${LOG:-notify}"
