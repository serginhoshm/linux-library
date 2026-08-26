#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

echo "[1/3] Instalando dependências do cliente NFS..."
sudo zypper install -y nfs-client
systemctl enable --now rpcbind
systemctl enable --now rpc-statd 2>/dev/null || true

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
