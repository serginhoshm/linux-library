#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

echo "Instalando o vsftpd..."
sudo dnf install -y vsftpd

if ! id "filmes" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash filmes
fi

echo "filmes:filmes123*" | chpasswd 2>/dev/null || echo -e "filmes123*\nfilmes123*" | passwd filmes

mkdir -p /filmes
chown -R filmes:filmes /filmes
chmod -R 777 /filmes
usermod -d /filmes filmes

cat > /etc/vsftpd.conf <<'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=000
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
utf8_filesystem=YES
EOF

setsebool -P ftpd_full_access 1 2>/dev/null || true
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=ftp
  firewall-cmd --reload
fi

systemctl enable --now vsftpd

echo "Servidor FTP pronto. Usuário: filmes | Senha: filmes123* | Diretório: /filmes"
