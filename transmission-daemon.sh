#!/usr/bin/env bash

set -euo pipefail

REAL_USER=""
REAL_HOME=""
DOWNLOAD_DIR=""
SERVICE_NAME="transmission-daemon"
TRANSMISSION_USER=""
TRANSMISSION_GROUP=""
SETTINGS_FILE=""
LOCAL_NET=""
SERVER_IP=""

banner() {
    cat <<'EOF'
============================================================
 Transmission Daemon - Configuracao automatizada
------------------------------------------------------------
 Este script vai:
 - instalar transmission-daemon e cliente CLI
 - salvar downloads em ~/Downloads do usuario corrente
 - sobrescrever settings.json em toda execucao
 - liberar permissoes completas nos arquivos baixados
 - expor o RPC/Web UI na rede local pela porta 9091
============================================================
EOF
}

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "Execute como root: sudo $0"
        exit 1
    fi
}

detect_real_user() {
    if [[ -n "${SUDO_USER:-}" ]] && id "${SUDO_USER}" >/dev/null 2>&1; then
        REAL_USER="${SUDO_USER}"
    elif logname >/dev/null 2>&1 && id "$(logname)" >/dev/null 2>&1; then
        REAL_USER="$(logname)"
    else
        REAL_USER="root"
    fi

    REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
    if [[ -z "${REAL_HOME}" ]]; then
        echo "Nao foi possivel detectar o home do usuario ${REAL_USER}."
        exit 1
    fi

    DOWNLOAD_DIR="${REAL_HOME}/Downloads"
    echo "[Pre-config] Usuario alvo: ${REAL_USER}"
    echo "[Pre-config] Pasta de downloads: ${DOWNLOAD_DIR}"
}

install_packages() {
    echo "[1/7] Instalando Transmission daemon e cliente CLI..."

    if [[ -f /etc/debian_version ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt update
        apt install -y transmission-daemon transmission-cli
    elif [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
        dnf install -y transmission-daemon transmission-cli
    else
        echo "Distribuicao nao suportada automaticamente. Requer Debian/Ubuntu/Zorin/LMDE ou Fedora/RHEL-like."
        exit 1
    fi
}

detect_local_network() {
    local default_dev cidr ip_addr prefix a b c d ip_int mask_int net_int

    default_dev="$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')"

    if [[ -n "${default_dev}" ]]; then
        cidr="$(ip -o -f inet addr show dev "${default_dev}" 2>/dev/null | awk 'NR==1 {print $4}')"
    else
        cidr=""
    fi

    if [[ -z "${cidr}" ]]; then
        cidr="$(ip -o -f inet addr show scope global 2>/dev/null | awk 'NR==1 {print $4}')"
    fi

    if [[ -z "${cidr}" ]]; then
        LOCAL_NET=""
        SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
        echo "[Pre-config] Rede local nao detectada automaticamente. Firewall sera aberto para a porta 9091."
        return
    fi

    ip_addr="${cidr%/*}"
    prefix="${cidr#*/}"
    SERVER_IP="${ip_addr}"
    IFS=. read -r a b c d <<<"${ip_addr}"

    if [[ "${prefix}" -eq 0 ]]; then
        mask_int=0
    else
        mask_int=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    fi

    ip_int=$(( (a << 24) + (b << 16) + (c << 8) + d ))
    net_int=$(( ip_int & mask_int ))
    LOCAL_NET="$(( (net_int >> 24) & 255 )).$(( (net_int >> 16) & 255 )).$(( (net_int >> 8) & 255 )).$(( net_int & 255 ))/${prefix}"

    echo "[Pre-config] Rede local detectada: ${LOCAL_NET}"
}

prepare_download_dir() {
    echo "[2/7] Preparando pasta de downloads com permissoes abertas..."
    mkdir -p "${DOWNLOAD_DIR}"
    chown "${REAL_USER}:${REAL_USER}" "${DOWNLOAD_DIR}"
    chmod 777 "${DOWNLOAD_DIR}"
    chmod -R a+rwX "${DOWNLOAD_DIR}"
}

detect_service() {
    echo "[3/7] Detectando servico e usuario do Transmission..."

    if systemctl list-unit-files --type=service --all | grep -q '^transmission-daemon\.service'; then
        SERVICE_NAME="transmission-daemon"
    elif systemctl list-unit-files --type=service --all | grep -q '^transmission\.service'; then
        SERVICE_NAME="transmission"
    else
        SERVICE_NAME="transmission-daemon"
    fi

    TRANSMISSION_USER="$(systemctl show "${SERVICE_NAME}" -p User --value 2>/dev/null || true)"
    if [[ -z "${TRANSMISSION_USER}" ]]; then
        if id debian-transmission >/dev/null 2>&1; then
            TRANSMISSION_USER="debian-transmission"
        elif id transmission >/dev/null 2>&1; then
            TRANSMISSION_USER="transmission"
        else
            TRANSMISSION_USER="${REAL_USER}"
        fi
    fi

    TRANSMISSION_GROUP="$(id -gn "${TRANSMISSION_USER}" 2>/dev/null || echo "${TRANSMISSION_USER}")"

    echo "-> Servico: ${SERVICE_NAME}.service"
    echo "-> Usuario do servico: ${TRANSMISSION_USER}:${TRANSMISSION_GROUP}"
}

stop_service() {
    echo "[4/7] Parando o servico antes de reescrever a configuracao..."
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
}

detect_settings_file() {
    local candidates=()
    local candidate

    echo "[5/7] Localizando settings.json..."

    candidates+=("/etc/transmission-daemon/settings.json")
    candidates+=("/var/lib/transmission/.config/transmission-daemon/settings.json")
    candidates+=("/var/lib/transmission-daemon/.config/transmission-daemon/settings.json")

    if [[ "${TRANSMISSION_USER}" != "root" ]]; then
        local service_home
        service_home="$(getent passwd "${TRANSMISSION_USER}" | cut -d: -f6 || true)"
        if [[ -n "${service_home}" ]]; then
            candidates+=("${service_home}/.config/transmission-daemon/settings.json")
        fi
    fi

    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}" ]]; then
            SETTINGS_FILE="${candidate}"
            break
        fi
    done

    if [[ -z "${SETTINGS_FILE}" ]]; then
        if [[ -d /etc/transmission-daemon ]] || [[ -f /etc/debian_version ]]; then
            SETTINGS_FILE="/etc/transmission-daemon/settings.json"
        else
            SETTINGS_FILE="/var/lib/transmission/.config/transmission-daemon/settings.json"
        fi
    fi

    mkdir -p "$(dirname "${SETTINGS_FILE}")"
    echo "-> Configuracao alvo: ${SETTINGS_FILE}"
}

write_settings() {
    echo "[6/7] Sobrescrevendo configuracao do Transmission..."

    if [[ -f "${SETTINGS_FILE}" && ! -f "${SETTINGS_FILE}.orig" ]]; then
        cp "${SETTINGS_FILE}" "${SETTINGS_FILE}.orig"
        echo "-> Backup original salvo em ${SETTINGS_FILE}.orig"
    fi

    cat > "${SETTINGS_FILE}" <<EOF
{
    "alt-speed-down": 50,
    "alt-speed-enabled": false,
    "alt-speed-time-begin": 540,
    "alt-speed-time-day": 127,
    "alt-speed-time-enabled": false,
    "alt-speed-time-end": 1020,
    "alt-speed-up": 50,
    "bind-address-ipv4": "0.0.0.0",
    "bind-address-ipv6": "::",
    "blocklist-enabled": false,
    "blocklist-url": "http://www.example.com/blocklist",
    "cache-size-mb": 4,
    "dht-enabled": true,
    "download-dir": "${DOWNLOAD_DIR}",
    "download-limit": 100,
    "download-limit-enabled": false,
    "download-queue-enabled": true,
    "download-queue-size": 5,
    "encryption": 1,
    "idle-seeding-limit": 30,
    "idle-seeding-limit-enabled": false,
    "incomplete-dir": "${DOWNLOAD_DIR}",
    "incomplete-dir-enabled": false,
    "lpd-enabled": false,
    "message-level": 2,
    "peer-congestion-algorithm": "",
    "peer-id-ttl-hours": 6,
    "peer-limit-global": 200,
    "peer-limit-per-torrent": 50,
    "peer-port": 51413,
    "peer-port-random-high": 65535,
    "peer-port-random-low": 49152,
    "peer-port-random-on-start": false,
    "peer-socket-tos": "default",
    "pex-enabled": true,
    "port-forwarding-enabled": true,
    "preallocation": 1,
    "prefetch-enabled": true,
    "queue-stalled-enabled": true,
    "queue-stalled-minutes": 30,
    "ratio-limit": 2,
    "ratio-limit-enabled": false,
    "rename-partial-files": true,
    "rpc-authentication-required": false,
    "rpc-bind-address": "0.0.0.0",
    "rpc-enabled": true,
    "rpc-host-whitelist": "",
    "rpc-host-whitelist-enabled": false,
    "rpc-password": "",
    "rpc-port": 9091,
    "rpc-url": "/transmission/",
    "rpc-username": "",
    "rpc-whitelist": "127.0.0.1,192.168.*.*,10.*.*.*,172.16.*.*,172.17.*.*,172.18.*.*,172.19.*.*,172.20.*.*,172.21.*.*,172.22.*.*,172.23.*.*,172.24.*.*,172.25.*.*,172.26.*.*,172.27.*.*,172.28.*.*,172.29.*.*,172.30.*.*,172.31.*.*",
    "rpc-whitelist-enabled": false,
    "scrape-paused-torrents-enabled": true,
    "script-torrent-done-enabled": false,
    "script-torrent-done-filename": "",
    "seed-queue-enabled": false,
    "seed-queue-size": 10,
    "speed-limit-down": 100,
    "speed-limit-down-enabled": false,
    "speed-limit-up": 100,
    "speed-limit-up-enabled": false,
    "start-added-torrents": true,
    "trash-original-torrent-files": false,
    "umask": 0,
    "upload-limit": 100,
    "upload-limit-enabled": false,
    "upload-slots-per-torrent": 14,
    "utp-enabled": true
}
EOF

    chown "${TRANSMISSION_USER}:${TRANSMISSION_GROUP}" "${SETTINGS_FILE}" 2>/dev/null || true
    chmod 644 "${SETTINGS_FILE}"
    chown -R "${TRANSMISSION_USER}:${TRANSMISSION_GROUP}" "$(dirname "${SETTINGS_FILE}")" 2>/dev/null || true
}

configure_firewall() {
    echo "[7/7] Ajustando firewall para RPC/Web UI na porta 9091..."

    if command -v ufw >/dev/null 2>&1 && systemctl is-active --quiet ufw; then
        if [[ -n "${LOCAL_NET}" ]]; then
            ufw allow from "${LOCAL_NET}" to any port 9091 proto tcp
            echo "-> UFW liberado para ${LOCAL_NET} na porta 9091/tcp."
        else
            ufw allow 9091/tcp
            echo "-> UFW liberado para a porta 9091/tcp."
        fi
        ufw reload
    elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=9091/tcp
        firewall-cmd --reload
        echo "-> FirewallD liberado para a porta 9091/tcp."
    else
        echo "-> Nenhum firewall restritivo ativo detectado. Pulando."
    fi
}

start_service() {
    echo "[Final] Habilitando e reiniciando ${SERVICE_NAME}.service..."
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl restart "${SERVICE_NAME}"
}

validate_cli() {
    echo "[Final] Validando cliente CLI..."

    if transmission-remote 127.0.0.1:9091 -l >/dev/null 2>&1; then
        echo "-> transmission-remote conectou no daemon local com sucesso."
    else
        echo "[AVISO] transmission-remote nao conseguiu conectar em 127.0.0.1:9091."
        echo "        Verifique: systemctl status ${SERVICE_NAME}"
        echo "        Configuracao: ${SETTINGS_FILE}"
    fi
}

print_summary() {
    local host_ref

    if [[ -n "${SERVER_IP}" ]]; then
        host_ref="${SERVER_IP}"
    else
        host_ref="$(hostname -f 2>/dev/null || hostname)"
    fi

    cat <<EOF
============================================================
 Configuracao concluida.
------------------------------------------------------------
 Downloads: ${DOWNLOAD_DIR}
 Permissoes: pasta 777 e umask 000 para novos arquivos
 Cliente CLI: transmission-remote 127.0.0.1:9091 -l
 Web UI/RPC: http://${host_ref}:9091
 Configuracao: ${SETTINGS_FILE}

 AVISO: o RPC esta sem senha e aceitando conexoes de rede.
 Use apenas em uma LAN domestica/confiavel.
============================================================
EOF
}

main() {
    banner
    check_root
    detect_real_user
    install_packages
    detect_local_network
    prepare_download_dir
    detect_service
    stop_service
    detect_settings_file
    write_settings
    configure_firewall
    start_service
    validate_cli
    print_summary
}

main "$@"