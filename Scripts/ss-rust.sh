#!/bin/bash

set -uo pipefail

VERSION="1.25.0"
INSTALL_DIR="/opt/ss-rust"
SYSTEMD_UNIT="/etc/systemd/system/ss-rust.service"
OPENRC_SCRIPT="/etc/init.d/ss-rust"
LOCK_DIR="/run/ss-rust-installer.lock"
METHOD="2022-blake3-aes-128-gcm"
ACTION="install"
PORT=""
PASSWORD=""
SERVICE_MANAGER=""
WORK_DIR=""
TRANSACTION=""
LOCK_HELD=0
WAS_RUNNING=0
START_ATTEMPTED=0
REINSTALL=0
HAD_INSTALL_DIR=0
HAD_SERVICE_DEFINITION=0
WAS_ENABLED=0

fail() {
    echo "Error: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 [install] [-p port] [-psk key]
       $0 update
       $0 uninstall
       $0 -h|--help

Install defaults to a random free port and a random 16-byte Base64 PSK.
-passwd is an alias for -psk. Options are only valid for installation.
Install replaces an existing installation and generates a new configuration.
Use update to replace only the binary and preserve the configuration.
Uninstall removes the program, configuration and service definition.
EOF
}

parse_args() {
    if [ "$#" -gt 0 ]; then
        case "$1" in
            install|update|uninstall) ACTION="$1"; shift ;;
            -h|--help) usage; exit 0 ;;
        esac
    fi
    while [ "$#" -gt 0 ]; do
        [ "$ACTION" = "install" ] || fail "$ACTION does not accept installation options"
        case "$1" in
            -p)
                [ "$#" -ge 2 ] && [ -n "$2" ] || fail "-p requires a port"
                [ -z "$PORT" ] || fail "Port specified more than once"
                [[ "$2" =~ ^[0-9]{1,5}$ ]] || fail "Invalid port: $2"
                PORT=$((10#$2))
                [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || fail "Port must be between 1 and 65535"
                shift 2
                ;;
            -psk|-passwd)
                [ "$#" -ge 2 ] && [ -n "$2" ] || fail "$1 requires a Base64 key"
                [ -z "$PASSWORD" ] || fail "PSK specified more than once"
                # Canonical Base64 for exactly 16 bytes, including its padding bits.
                [[ "$2" =~ ^[A-Za-z0-9+/]{21}[AQgw]==$ ]] || fail "PSK must encode exactly 16 bytes in Base64 (generate with: openssl rand -base64 16)"
                PASSWORD="$2"
                shift 2
                ;;
            *) fail "Unknown argument: $1 (use --help)" ;;
        esac
    done
}

get_service_manager() {
    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        SERVICE_MANAGER="systemd"
        systemctl show-environment >/dev/null 2>&1 || fail "Cannot communicate with systemd"
    elif [ -d /run/openrc ] && command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
        SERVICE_MANAGER="openrc"
    else
        fail "A running systemd or OpenRC environment is required"
    fi
}

service_action() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl "$1" ss-rust
    else
        rc-service ss-rust "$1"
    fi
}

service_running() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl is-active --quiet ss-rust
    else
        rc-service ss-rust status >/dev/null 2>&1
    fi
}

show_logs() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        journalctl -u ss-rust -n 30 --no-pager >&2 || true
    else
        tail -n 30 /var/log/ss-rust-error.log >&2 || true
    fi
}

start_and_check() {
    local attempt
    service_action restart || return 1
    # Require three consecutive running checks to catch immediate startup failures.
    for attempt in 1 2 3; do
        sleep 1
        service_running || return 1
    done
}

remove_service() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        systemctl disable ss-rust || return 1
        rm -f "$SYSTEMD_UNIT" || return 1
        systemctl daemon-reload || return 1
    else
        if rc-update show default | awk '{print $1}' | grep -qx ss-rust; then
            rc-update del ss-rust default || return 1
        fi
        rm -f "$OPENRC_SCRIPT" || return 1
    fi
}

service_definition() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        echo "$SYSTEMD_UNIT"
    else
        echo "$OPENRC_SCRIPT"
    fi
}

backup_installation() {
    local definition runlevels
    definition=$(service_definition)
    if [ -e "$INSTALL_DIR" ] || [ -L "$INSTALL_DIR" ]; then
        cp -a "$INSTALL_DIR" "$WORK_DIR/install.previous" || fail "Cannot back up existing installation"
        HAD_INSTALL_DIR=1
    fi
    if [ -e "$definition" ] || [ -L "$definition" ]; then
        cp -a "$definition" "$WORK_DIR/service.previous" || fail "Cannot back up service definition"
        HAD_SERVICE_DEFINITION=1
        if [ "$SERVICE_MANAGER" = "systemd" ]; then
            if systemctl is-enabled --quiet ss-rust; then WAS_ENABLED=1; fi
        else
            runlevels=$(rc-update show default) || fail "Cannot inspect OpenRC startup state"
            if awk '{print $1}' <<< "$runlevels" | grep -qx ss-rust; then WAS_ENABLED=1; fi
        fi
    fi
    if service_running; then
        WAS_RUNNING=1
        [ "$HAD_SERVICE_DEFINITION" -eq 1 ] || fail "Cannot replace a running service without its expected definition"
    fi
}

restore_installation() {
    local definition
    definition=$(service_definition)
    if [ "$HAD_SERVICE_DEFINITION" -eq 1 ] || [ "$START_ATTEMPTED" -eq 1 ]; then
        service_action stop || return 1
    fi
    rm -rf "$INSTALL_DIR" || return 1
    if [ "$HAD_INSTALL_DIR" -eq 1 ]; then
        cp -a "$WORK_DIR/install.previous" "$INSTALL_DIR" || return 1
    fi
    if [ "$HAD_SERVICE_DEFINITION" -eq 1 ]; then
        rm -f "$definition" || return 1
        cp -a "$WORK_DIR/service.previous" "$definition" || return 1
        if [ "$SERVICE_MANAGER" = "systemd" ]; then
            systemctl daemon-reload || return 1
            if [ "$WAS_ENABLED" -eq 1 ]; then
                systemctl enable ss-rust || return 1
            else
                systemctl disable ss-rust || return 1
            fi
        elif [ "$WAS_ENABLED" -eq 1 ]; then
            rc-update add ss-rust default || return 1
        else
            local runlevels
            runlevels=$(rc-update show default) || return 1
            if awk '{print $1}' <<< "$runlevels" | grep -qx ss-rust; then
                rc-update del ss-rust default || return 1
            fi
        fi
    elif [ -e "$definition" ] || [ -L "$definition" ]; then
        remove_service || return 1
    fi
    if [ "$WAS_RUNNING" -eq 1 ]; then
        start_and_check || { show_logs; return 1; }
    fi
    return 0
}

cleanup() {
    local status=$? keep_work=0
    trap - EXIT HUP INT TERM
    if [ "$TRANSACTION" = "reinstall" ]; then
        echo "Reinstallation failed; restoring the previous installation and configuration..." >&2
        if ! restore_installation; then
            keep_work=1
            echo "Error: Recovery incomplete. Previous files retained in $WORK_DIR" >&2
        fi
    elif [ "$TRANSACTION" = "update" ]; then
        echo "Update failed; restoring the previous binary..." >&2
        if mv -f "$WORK_DIR/ssserver.previous" "$INSTALL_DIR/ssserver"; then
            if [ "$WAS_RUNNING" -eq 1 ]; then
                start_and_check || { echo "Error: Previous binary restored, but service recovery failed" >&2; show_logs; }
            else
                service_action stop || echo "Error: Could not restore the stopped service state" >&2
            fi
        else
            keep_work=1
            echo "Error: Automatic rollback failed. Backup retained at $WORK_DIR/ssserver.previous" >&2
        fi
    elif [ "$TRANSACTION" = "install" ]; then
        echo "Installation failed; removing the incomplete installation..." >&2
        local removed=1 definition="$SYSTEMD_UNIT"
        if [ "$SERVICE_MANAGER" = "openrc" ]; then definition="$OPENRC_SCRIPT"; fi
        if [ "$START_ATTEMPTED" -eq 1 ] && ! service_action stop; then
            removed=0
        fi
        if [ "$removed" -eq 1 ] && [ -e "$definition" ] && ! remove_service; then
            removed=0
        fi
        if [ "$removed" -eq 1 ]; then
            rm -rf "$INSTALL_DIR" || echo "Error: Could not remove $INSTALL_DIR" >&2
        else
            echo "Error: Cleanup incomplete; inspect the service and $INSTALL_DIR before retrying" >&2
        fi
    fi
    if [ -n "$WORK_DIR" ] && [ "$keep_work" -eq 0 ]; then
        rm -rf "$WORK_DIR"
    fi
    if [ "$LOCK_HELD" -eq 1 ]; then
        rmdir "$LOCK_DIR" || true
    fi
    exit "$status"
}

check_installation() {
    if [ "$ACTION" = "install" ]; then
        local definition
        definition=$(service_definition)
        if [ -e "$INSTALL_DIR" ] || [ -L "$INSTALL_DIR" ] || [ -e "$definition" ] || [ -L "$definition" ]; then
            REINSTALL=1
            echo "Existing installation found; reinstalling with a new configuration."
        fi
    elif [ "$ACTION" = "update" ]; then
        [ -f "$INSTALL_DIR/ssserver" ] && [ -f "$INSTALL_DIR/config.json" ] || fail "No complete installation found"
        if [ "$SERVICE_MANAGER" = "systemd" ]; then
            [ -f "$SYSTEMD_UNIT" ] || fail "Missing systemd service definition"
        else
            [ -f "$OPENRC_SCRIPT" ] || fail "Missing OpenRC service definition"
        fi
    fi
}

select_package() {
    local arch libc="gnu"
    arch=$(uname -m) || fail "Cannot detect architecture"
    case "$arch" in
        x86_64|aarch64) ;;
        *) fail "Unsupported system architecture: $arch" ;;
    esac
    if [ -f /etc/alpine-release ]; then
        libc="musl"
    fi
    PACKAGE="shadowsocks-v$VERSION.$arch-unknown-linux-$libc.tar.xz"
}

ensure_dependencies() {
    local cmd missing=0
    local commands=(curl tar xz sha256sum)
    if [ "$ACTION" = "install" ]; then
        commands+=(openssl netstat shuf)
    fi
    for cmd in "${commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing=1
    done
    if [ "$missing" -eq 1 ]; then
        echo "Installing missing dependencies..."
        local packages=(curl tar xz ca-certificates coreutils)
        if [ "$ACTION" = "install" ]; then
            packages+=(openssl net-tools)
        fi
        if command -v apk >/dev/null 2>&1; then
            apk add --no-cache "${packages[@]}" || fail "Dependency installation failed"
        elif command -v apt-get >/dev/null 2>&1; then
            packages=(curl tar xz-utils ca-certificates coreutils)
            if [ "$ACTION" = "install" ]; then
                packages+=(openssl net-tools)
            fi
            apt-get update || fail "Package index update failed"
            apt-get install -y "${packages[@]}" || fail "Dependency installation failed"
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "${packages[@]}" || fail "Dependency installation failed"
        elif command -v yum >/dev/null 2>&1; then
            yum install -y "${packages[@]}" || fail "Dependency installation failed"
        else
            fail "Missing dependencies; supported package managers: apk/apt-get/dnf/yum"
        fi
    fi
    for cmd in "${commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || fail "Required command is unavailable: $cmd"
    done
}

port_available() {
    local sockets
    sockets=$(netstat -tuln) || fail "Cannot inspect TCP/UDP listening ports"
    ! awk -v port="$1" '$1 ~ /^(tcp|udp)/ { n=split($4,a,":"); if (a[n] == port) found=1 } END { exit !found }' <<< "$sockets"
}

prepare_config() {
    local attempt
    if [ -n "$PORT" ]; then
        # A running old service may own this port. Check again after stopping it.
        if [ "$REINSTALL" -eq 0 ] || ! service_running; then
            port_available "$PORT" || fail "Port $PORT is already in use"
        fi
    else
        for ((attempt=0; attempt<100; attempt++)); do
            PORT=$(shuf -i 1000-65535 -n 1) || fail "Cannot generate a random port"
            port_available "$PORT" && break
        done
        [ "$attempt" -lt 100 ] || fail "Cannot find a free port after 100 attempts"
    fi
    if [ -z "$PASSWORD" ]; then
        PASSWORD=$(openssl rand -base64 16) || fail "Cannot generate PSK"
    fi
}

download_server() {
    local url checksum actual version_output
    url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v$VERSION/$PACKAGE"
    echo "Downloading Shadowsocks Rust $VERSION..."
    curl -fsSL --connect-timeout 15 --max-time 120 --retry 2 -o "$WORK_DIR/$PACKAGE" "$url" || fail "Package download failed"
    curl -fsSL --connect-timeout 15 --max-time 120 --retry 2 -o "$WORK_DIR/checksum" "$url.sha256" || fail "Checksum download failed"
    read -r checksum _ < "$WORK_DIR/checksum" || fail "Cannot read checksum"
    [[ "$checksum" =~ ^[a-fA-F0-9]{64}$ ]] || fail "Invalid release checksum"
    actual=$(sha256sum "$WORK_DIR/$PACKAGE") || fail "Cannot calculate checksum"
    [ "${actual%% *}" = "$checksum" ] || fail "Package checksum mismatch"
    mkdir "$WORK_DIR/payload" || fail "Cannot create staging directory"
    # Extract only the server binary, never a configuration file from the archive.
    tar -xJf "$WORK_DIR/$PACKAGE" -C "$WORK_DIR/payload" ssserver || fail "Cannot extract ssserver"
    [ -f "$WORK_DIR/payload/ssserver" ] && [ ! -L "$WORK_DIR/payload/ssserver" ] || fail "Invalid server binary"
    chmod 755 "$WORK_DIR/payload/ssserver" || fail "Cannot set binary permissions"
    version_output=$("$WORK_DIR/payload/ssserver" --version) || fail "New binary cannot run on this system"
    [[ "$version_output" = "shadowsocks $VERSION" || "$version_output" = "shadowsocks $VERSION "* ]] || fail "Unexpected server version: $version_output"
}

write_service() {
    if [ "$SERVICE_MANAGER" = "systemd" ]; then
        cat > "$WORK_DIR/service.new" <<EOF || return 1
[Unit]
Description=Shadowsocks Rust Server
After=network.target

[Service]
Type=simple
User=root
UMask=0077
ExecStart=$INSTALL_DIR/ssserver -c $INSTALL_DIR/config.json
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        chmod 644 "$WORK_DIR/service.new" || return 1
        mv -f "$WORK_DIR/service.new" "$SYSTEMD_UNIT" || return 1
        systemctl daemon-reload || return 1
        systemctl enable ss-rust || return 1
    else
        cat > "$WORK_DIR/service.new" <<EOF || return 1
#!/sbin/openrc-run

name="Shadowsocks Rust Server"
description="Shadowsocks Rust Server"
command="$INSTALL_DIR/ssserver"
command_args="-c $INSTALL_DIR/config.json"
command_background="yes"
pidfile="/run/ss-rust.pid"
output_log="/var/log/ss-rust.log"
error_log="/var/log/ss-rust-error.log"
umask="0077"

depend() {
    need net
    after network
}
EOF
        chmod 755 "$WORK_DIR/service.new" || return 1
        mv -f "$WORK_DIR/service.new" "$OPENRC_SCRIPT" || return 1
        rc-update add ss-rust default || return 1
    fi
}

install_server() {
    cat > "$WORK_DIR/payload/config.json" <<EOF || fail "Cannot write configuration"
{
    "server": "::",
    "server_port": $PORT,
    "password": "$PASSWORD",
    "method": "$METHOD",
    "mode": "tcp_and_udp"
}
EOF
    chmod 600 "$WORK_DIR/payload/config.json" || fail "Cannot protect configuration"
    chmod 755 "$WORK_DIR/payload" || fail "Cannot set installation directory permissions"
    if [ "$REINSTALL" -eq 1 ]; then
        backup_installation
        TRANSACTION="reinstall"
        if [ "$HAD_SERVICE_DEFINITION" -eq 1 ]; then
            service_action stop || fail "Cannot stop the existing service"
        fi
    else
        TRANSACTION="install"
    fi
    port_available "$PORT" || fail "Port $PORT is already in use"
    if [ "$REINSTALL" -eq 1 ]; then
        rm -rf "$INSTALL_DIR" || fail "Cannot replace the existing installation"
    fi
    mv "$WORK_DIR/payload" "$INSTALL_DIR" || fail "Cannot install staged files"
    write_service || fail "Cannot register service"
    START_ATTEMPTED=1
    if ! start_and_check; then
        show_logs
        fail "Service startup failed"
    fi
    TRANSACTION=""
    echo "Installation completed. Service is running."
    # This address is only a convenience for node output; keep the original lookup.
    local server_ip
    server_ip=$(curl -s http://ipv4.icanhazip.com)
    echo "Node information (Surge format):"
    echo "$(hostname) = ss, $server_ip, $PORT, encrypt-method=$METHOD, password=$PASSWORD, udp-relay=true"
}

update_server() {
    chmod 600 "$INSTALL_DIR/config.json" || fail "Cannot protect configuration"
    cp -p "$INSTALL_DIR/ssserver" "$WORK_DIR/ssserver.previous" || fail "Cannot back up current binary"
    if service_running; then WAS_RUNNING=1; fi
    TRANSACTION="update"
    mv -f "$WORK_DIR/payload/ssserver" "$INSTALL_DIR/ssserver" || fail "Cannot replace binary"
    if ! start_and_check; then
        show_logs
        fail "Updated service failed to start"
    fi
    TRANSACTION=""
    echo "Update to $VERSION completed. Configuration preserved; service is running."
}

uninstall_server() {
    local definition="$SYSTEMD_UNIT"
    if [ "$SERVICE_MANAGER" = "openrc" ]; then definition="$OPENRC_SCRIPT"; fi
    if [ -e "$definition" ]; then
        service_action stop || fail "Cannot stop service; files have been preserved"
        remove_service || fail "Cannot remove service definition; program and configuration have been preserved"
    elif service_running; then
        fail "Service is running without the expected definition; refusing to remove files"
    fi
    rm -rf "$INSTALL_DIR" || fail "Cannot remove installation directory"
    echo "Shadowsocks Rust has been uninstalled."
}

check_environment() {
    [ "$EUID" -eq 0 ] || fail "Please run with root privileges"
    [ "$(uname -s)" = "Linux" ] || fail "This script supports Linux only"
    get_service_manager
}

main() {
    parse_args "$@"
    check_environment
    umask 077
    mkdir "$LOCK_DIR" 2>/dev/null || fail "Installer lock exists or cannot be created: $LOCK_DIR"
    LOCK_HELD=1
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    check_installation
    if [ "$ACTION" = "uninstall" ]; then
        uninstall_server
        return
    fi
    select_package
    ensure_dependencies
    if [ "$ACTION" = "install" ]; then prepare_config; fi
    mkdir -p "$(dirname "$INSTALL_DIR")" || fail "Cannot create installation parent directory"
    WORK_DIR=$(mktemp -d "$INSTALL_DIR.work.XXXXXX") || fail "Cannot create staging directory"
    download_server
    if [ "$ACTION" = "update" ]; then
        update_server
    else
        install_server
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
