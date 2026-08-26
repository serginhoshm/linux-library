#!/usr/bin/env bash
set -Eeuo pipefail

SHARE_PATH="${SHARE_PATH:-/srv/share}"
SHARE_NAME="${SHARE_NAME:-publico}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute este script como root: sudo $0"
  exit 1
fi

mkdir -p "${SHARE_PATH}"
chmod 0777 "${SHARE_PATH}"

apt-get update
apt-get install -y samba wsdd

cp -n /etc/samba/smb.conf /etc/samba/smb.conf.bak 2>/dev/null || true
cat >> /etc/samba/smb.conf <<EOF

[${SHARE_NAME}]
  path = ${SHARE_PATH}
  browseable = yes
  read only = no
  guest ok = yes
  force user = nobody
  create mask = 0666
  directory mask = 0777
EOF

systemctl enable --now smbd
systemctl enable --now nmbd 2>/dev/null || true
systemctl restart smbd
systemctl restart nmbd 2>/dev/null || true

echo "Compartilhamento Samba pronto: ${SHARE_NAME} em ${SHARE_PATH}"
