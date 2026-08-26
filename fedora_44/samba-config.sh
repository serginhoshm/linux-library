#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

echo "[1/4] Atualizando a lista de pacotes..."
sudo dnf makecache --refresh

echo "[2/4] Instalando Samba..."
sudo dnf install -y samba samba-common

echo "[3/4] Ajustando usuário do Samba..."
sudo usermod -aG sambashare "${SUDO_USER:-$USER}" 2>/dev/null || true
sudo smbpasswd -a "${SUDO_USER:-$USER}" || true

echo "[4/4] Reiniciando serviços..."
systemctl enable --now smb
systemctl restart smb

echo "Configuração concluída. Faça logout e login novamente para aplicar o grupo." 
