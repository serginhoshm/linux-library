#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute este script como root: sudo $0"
  exit 1
fi

echo "[1/4] Instalando Samba no openSUSE..."
sudo zypper install -y samba

echo "[2/4] Ajustando permissões do compartilhamento..."
mkdir -p /srv/samba/share
chmod -R 0777 /srv/samba/share

echo "[3/4] Habilitando serviço Samba..."
systemctl enable --now smb

cat >> /etc/samba/smb.conf <<'EOF'

[share]
  path = /srv/samba/share
  browseable = yes
  read only = no
  guest ok = yes
  force user = nobody
  create mask = 0666
  directory mask = 0777
EOF

systemctl restart smb

echo "[4/4] Configuração concluída."
