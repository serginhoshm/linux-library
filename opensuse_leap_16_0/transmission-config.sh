#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

if command -v zypper >/dev/null 2>&1; then
  zypper install -y transmission
else
  echo "Distribuição não suportada."
  exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo $USER)}"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
DOWNLOAD_DIR="${REAL_HOME}/Downloads"
mkdir -p "${DOWNLOAD_DIR}"
chown "${REAL_USER}:${REAL_USER}" "${DOWNLOAD_DIR}"
chmod 777 "${DOWNLOAD_DIR}"

cat > /etc/transmission/settings.json <<EOF
{
  "download-dir": "${DOWNLOAD_DIR}",
  "rpc-enabled": true,
  "rpc-bind-address": "0.0.0.0",
  "rpc-port": 9091,
  "rpc-whitelist": "127.0.0.1,192.168.*.*",
  "rpc-whitelist-enabled": false,
  "rpc-authentication-required": false,
  "umask": 0
}
EOF

systemctl enable --now transmission

ufw allow 9091/tcp 2>/dev/null || true

echo "Transmission pronto em http://$(hostname -I | awk '{print $1}'):9091"
