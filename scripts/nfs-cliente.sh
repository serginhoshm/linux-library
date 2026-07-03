#!/bin/bash

#sudo mount -t nfs <IP_DESTE_SERVIDOR>:/home/sergio85/Public /pasta/local/do/cliente

# --- PARÂMETROS FLEXÍVEIS ---
# Coloque aqui o IP do seu servidor NFS doméstico
SERVER_IP="192.168.1.200"

# O caminho da pasta do servidor que você deseja montar
# (O script anterior usou /home/usuario/Public - mude para o caminho correto do servidor)
REMOTE_DIR="/home/sergio85/Public"

# Onde essa pasta vai aparecer NESTE computador cliente
LOCAL_MOUNT_POINT="/mnt/sergio-vnt-nfs"
# ----------------------------

# Garante que o script está rodando com sudo
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute este script usando sudo: sudo $0"
  exit 1
fi

echo "=== Configurando Cliente NFS Doméstico ==="
echo "Tentando conectar a: ${SERVER_IP}:${REMOTE_DIR}"
echo "Ponto de montagem local: ${LOCAL_MOUNT_POINT}"
echo "----------------------------------------"

# 1. Detecta a distro e instala o cliente NFS necessário
if [ -f /etc/debian_version ]; then
    echo "Sistema baseado em Debian/Ubuntu detectado. Garantindo pacotes nfs-common..."
    apt update && apt install -y nfs-common
elif [ -f /etc/fedora-release ] || [ -f /etc/redhat-release ]; then
    echo "Sistema baseado em Fedora/RHEL detectado. Garantindo pacotes nfs-utils..."
    dnf install -y nfs-utils
else
    echo "Distribuição não mapeada automaticamente. Certifique-se de ter o cliente NFS instalado."
fi

# 2. Cria o ponto de montagem se não existir
if [ ! -d "$LOCAL_MOUNT_POINT" ]; then
    echo "Criando o diretório local $LOCAL_MOUNT_POINT..."
    mkdir -p "$LOCAL_MOUNT_POINT"
fi

# 3. Testa a montagem temporária imediata
echo "Testando a conexão e montando o diretório..."
# Opções recomendadas para redes domésticas (timeout curto caso o servidor esteja desligado)
MOUNT_OPTS="rw,soft,timeo=50,retrans=2"

mount -t nfs -o $MOUNT_OPTS "${SERVER_IP}:${REMOTE_DIR}" "$LOCAL_MOUNT_POINT"

if [ $? -eq 0 ]; then
    echo "🎉 Sucesso! A pasta foi montada temporariamente em $LOCAL_MOUNT_POINT"
    ls -la "$LOCAL_MOUNT_POINT"
else
    echo "❌ Erro ao tentar montar. Verifique o IP do servidor, o caminho da pasta ou o firewall."
    exit 1
fi

# 4. Oferece a opção de automatizar a montagem na inicialização (/etc/fstab)
echo "----------------------------------------"
read -p "Deseja que esta pasta seja montada automaticamente sempre que o PC ligar? (s/N): " RESPOSTA

if [[ "$RESPOSTA" =~ ^[Ss]$ ]]; then
    FSTAB_LINE="${SERVER_IP}:${REMOTE_DIR} ${LOCAL_MOUNT_POINT} nfs ${MOUNT_OPTS},_netdev 0 0"
    
    # Verifica se a linha já não existe para evitar duplicatas
    if grep -q "${SERVER_IP}:${REMOTE_DIR}" /etc/fstab; then
        echo "Esta montagem já estava configurada no seu /etc/fstab."
    else
        echo "Adicionando configuração ao /etc/fstab..."
        echo "$FSTAB_LINE" >> /etc/fstab
        echo "Configuração permanente concluída!"
    fi
else
    echo "Montagem mantida apenas para esta sessão (vai sumir ao reiniciar)."
fi

echo "=== Configuração do Cliente Concluída ==="