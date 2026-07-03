#!/bin/bash

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
    echo "Distribuição detectada: Debian/Ubuntu"
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

# 2. Criar o usuário 'filmes' com a senha 'filmes123*'
echo "Configurando o usuário 'filmes'..."
# Verifica se o usuário já existe, se não, cria
if id "filmes" &>/dev/null; then
    echo "O usuário 'filmes' ya existe."
else
    useradd -m -s /bin/bash filmes
fi
# Define a senha de forma não-interativa
echo "filmes:filmes123*" | chpasswd 2>/dev/null || echo -e "filmes123*\nfilmes123*" | passwd filmes

# 3. Criar e configurar a pasta compartilhada /filmes
echo "Configurando o diretório /filmes con direitos completos..."
mkdir -p /filmes
chown -R filmes:filmes /filmes
chmod -R 777 /filmes

# Altera o diretório home do usuário para a pasta de filmes para facilitar o acesso direto
usermod -d /filmes filmes

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
local_umask=000

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
systemctl restart $SERVICE_NAME
systemctl enable $SERVICE_NAME

echo "=================================================="
echo "¡Configuração concluída com sucesso!"
echo "Usuário: filmes"
echo "Senha: filmes123*"
echo "Diretório: /filmes (Permissões 777)"
echo "O servidor está pronto e aberto na sua rede local."
echo "=================================================="