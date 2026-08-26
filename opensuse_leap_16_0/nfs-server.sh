#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

echo "[1/3] Instalando servidor NFS..."
sudo zypper install -y nfs-kernel-server

mkdir -p /srv/nfs/shared
chown -R nobody:nogroup /srv/nfs/shared
chmod 755 /srv/nfs/shared

cat > /etc/exports <<'EOF'
/srv/nfs/shared 192.168.0.0/16(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
EOF

exportfs -ra
systemctl enable --now nfs-server

echo "Servidor NFS configurado em /srv/nfs/shared"
