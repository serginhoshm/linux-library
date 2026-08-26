#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo $USER)}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
DOWNLOAD_DIR="${REAL_HOME}/Downloads"

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y transmission-daemon transmission-cli
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y transmission-daemon transmission-cli
else
  echo "Distribuição não suportada." >&2
  exit 1
fi

mkdir -p "${DOWNLOAD_DIR}"
chown "${REAL_USER}:${REAL_USER}" "${DOWNLOAD_DIR}"
chmod 777 "${DOWNLOAD_DIR}"

SETTINGS_FILE="/etc/transmission-daemon/settings.json"
mkdir -p "$(dirname "${SETTINGS_FILE}")"
cat > "${SETTINGS_FILE}" <<EOF
{
  "download-dir": "${DOWNLOAD_DIR}",
  "rpc-enabled": true,
  "rpc-bind-address": "0.0.0.0",
  "rpc-port": 9091,
  "rpc-whitelist": "127.0.0.1,192.168.*.*",
  "rpc-whitelist-enabled": false,
  "rpc-authentication-required": false,
  "incomplete-dir-enabled": false,
  "umask": 0,
  "peer-port": 51413,
  "peer-port-random-on-start": false,
  "pex-enabled": true,
  "port-forwarding-enabled": true
}
EOF
chown debian-transmission:debian-transmission "${SETTINGS_FILE}" 2>/dev/null || true
systemctl enable --now transmission-daemon
ufw allow 9091/tcp 2>/dev/null || true

echo "Transmission pronto em http://$(hostname -I | awk '{print $1}'):9091"
