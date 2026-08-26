#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

echo "[1/3] Instalando vsftpd..."
sudo zypper install -y vsftpd

if ! id "filmes" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash filmes
fi

echo "filmes:filmes123*" | chpasswd 2>/dev/null || true
mkdir -p /filmes
chown -R filmes:filmes /filmes
chmod -R 777 /filmes
usermod -d /filmes filmes

cat > /etc/vsftpd.conf <<'EOF'
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=000
chroot_local_user=YES
allow_writeable_chroot=YES
EOF

systemctl enable --now vsftpd

echo "Servidor FTP pronto. Usuário: filmes | Senha: filmes123* | Diretório: /filmes"
