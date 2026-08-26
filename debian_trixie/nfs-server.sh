#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

SERVICE_NAME=""
if command -v apt-get >/dev/null 2>&1; then
  SERVICE_NAME="nfs-kernel-server"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y nfs-kernel-server avahi-daemon libnss-mdns
elif command -v dnf >/dev/null 2>&1; then
  SERVICE_NAME="nfs-server"
  dnf install -y nfs-utils avahi nss-mdns
else
  echo "Distribuição não suportada para servidor NFS neste script."
  exit 1
fi

mkdir -p /srv/nfs/shared
chown -R nobody:nogroup /srv/nfs/shared
chmod 755 /srv/nfs/shared

cat > /etc/exports <<'EOF'
/srv/nfs/shared 192.168.0.0/16(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
EOF

exportfs -ra
systemctl enable --now "${SERVICE_NAME}"
systemctl enable --now avahi-daemon >/dev/null 2>&1 || true

echo "Servidor NFS configurado em /srv/nfs/shared"
echo "Teste: showmount -e localhost"
