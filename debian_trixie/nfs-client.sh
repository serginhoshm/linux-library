#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

echo "[1/3] Instalando dependências do cliente NFS..."
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y nfs-common nmap avahi-daemon libnss-mdns
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y nfs-utils nmap avahi nss-mdns
else
  echo "Distribuição não suportada para cliente NFS neste script."
  exit 1
fi

systemctl enable --now avahi-daemon >/dev/null 2>&1 || true

echo "[2/3] Detectando rede local..."
DEFAULT_IFACE="$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}' || true)"
if [[ -n "${DEFAULT_IFACE}" ]]; then
  CIDR="$(ip -o -f inet addr show dev "${DEFAULT_IFACE}" 2>/dev/null | awk 'NR==1 {print $4}' || true)"
  echo "Rede detectada: ${CIDR:-'não identificada'}"
else
  echo "Não foi possível detectar a interface padrão."
fi

echo "[3/3] Cliente NFS pronto."
echo "Teste: showmount -e <ip-do-servidor>"
