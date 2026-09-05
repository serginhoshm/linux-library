#!/usr/bin/env bash
set -euo pipefail

FTP_USER="${FTP_USER:-filmes}"
FTP_ROOT="${FTP_ROOT:-/filmes}"

# Garante que o script seja executado como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute este script como root ou usando sudo."
  exit 1
fi

echo "=================================================="
# Detectando a distribuição Linux
if [ -f /etc/debian_version ]; then
    PKG_MANAGER="apt"
    SERVICE_NAME="vsftpd"
    echo "Distribuição detectada: Linux Mint/Ubuntu"
elif [ -f /etc/fedora-release ]; then
    PKG_MANAGER="dnf"
    SERVICE_NAME="vsftpd"
    echo "Distribuição detectada: Fedora"
else
    echo "Distribuição não suportada automaticamente por este script."
    exit 1
fi
echo "=================================================="

# 1. Atualizar repositórios e instalar o vsftpd
echo "Instalando o vsftpd..."
if [ "$PKG_MANAGER" = "apt" ]; then
    apt update && apt install -y vsftpd
elif [ "$PKG_MANAGER" = "dnf" ]; then
    dnf install -y vsftpd
fi

# 2. Criar o usuário e definir uma senha sem gravá-la no script
echo "Configurando o usuário '${FTP_USER}'..."
# Verifica se o usuário já existe, se não, cria
if id "${FTP_USER}" &>/dev/null; then
    echo "O usuário '${FTP_USER}' já existe."
else
    useradd -m -s /usr/sbin/nologin "${FTP_USER}"
fi

# O PAM do vsftpd aceita apenas shells registrados, mesmo quando não permitem login interativo.
if ! grep -qxF '/usr/sbin/nologin' /etc/shells; then
    echo '/usr/sbin/nologin' >> /etc/shells
fi

if [[ -z "${FTP_PASSWORD:-}" ]]; then
    if [[ ! -t 0 ]]; then
        echo "Defina FTP_PASSWORD para uso não interativo." >&2
        exit 1
    fi
    read -r -s -p "Nova senha para ${FTP_USER}: " FTP_PASSWORD
    echo
    read -r -s -p "Confirme a senha: " FTP_PASSWORD_CONFIRM
    echo
    if [[ -z "${FTP_PASSWORD}" || "${FTP_PASSWORD}" != "${FTP_PASSWORD_CONFIRM}" ]]; then
        echo "As senhas não conferem ou estão vazias." >&2
        exit 1
    fi
fi
printf '%s:%s\n' "${FTP_USER}" "${FTP_PASSWORD}" | chpasswd
unset FTP_PASSWORD FTP_PASSWORD_CONFIRM

# 3. Criar e configurar a pasta compartilhada
echo "Configurando o diretório ${FTP_ROOT}..."
mkdir -p "${FTP_ROOT}"
chown -R "${FTP_USER}:${FTP_USER}" "${FTP_ROOT}"
chmod -R u+rwX,go-rwx "${FTP_ROOT}"

# Altera o diretório home do usuário para a pasta de filmes para facilitar o acesso direto
usermod -d "${FTP_ROOT}" "${FTP_USER}"

# 4. Configurar o vsftpd (Totalmente aberto na rede local, sem limites)
echo "Gerando arquivo de configuração /etc/vsftpd.conf..."

# Faz um backup da configuração original, se ela existir
[ -f /etc/vsftpd.conf ] && cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

cat << EOF > /etc/vsftpd.conf
# Configuração Básica do Servidor FTP
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES

# Direitos completos de leitura, escrita e exclusão
write_enable=YES
local_umask=077

# Mensagens e logs (opcional)
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES

# Conectividade e portas padrão
connect_from_port_20=YES

# Permitir que o usuário escreva no seu diretório raiz (crucial para chroot)
chroot_local_user=YES
allow_writeable_chroot=YES

# Desativar qualquer limitação de banda (0 significa ilimitado)
anon_max_rate=0
local_max_rate=0

# Garante compatibilidade com acentos e caracteres locais (UTF-8)
utf8_filesystem=YES
EOF

# 5. Ajustes específicos para o Fedora (Firewall e SELinux)
if [ "$PKG_MANAGER" = "dnf" ]; then
    echo "Ajustando políticas de SELinux e Firewall para o Fedora..."
    # Permite ao FTP gravação total no sistema (SELinux)
    setsebool -P ftpd_full_access 1 2>/dev/null || true
    
    # Abre a porta do FTP no firewall se o firewalld estiver ativo
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service=ftp
        firewall-cmd --reload
    fi
fi

# 6. Iniciar e habilitar o serviço para iniciar com o sistema
echo "Iniciando o serviço vsftpd..."
systemctl restart "$SERVICE_NAME"
systemctl enable "$SERVICE_NAME"

echo "=================================================="
echo "¡Configuração concluída com sucesso!"
echo "Usuário: ${FTP_USER}"
echo "Diretório: ${FTP_ROOT} (acesso exclusivo do usuário)"
echo "O servidor está pronto. Libere a porta 21 no firewall somente para a rede necessária."
echo "=================================================="