#!/bin/bash

# --- PARÂMETROS FLEXÍVEIS ---
# Define a faixa da rede local (ajuste se a sua casa usar outra faixa, ex: 192.168.0.0/24)
ALLOWED_NET="192.168.1.0/24"

# Detecta dinamicamente o usuário atual, UID, GID e a pasta Public
REAL_USER=$(logname 2>/dev/null || echo $USER)
USER_HOME=$(eval echo ~$REAL_USER)
SHARE_DIR="${USER_HOME}/Public"
USER_UID=$(id -u $REAL_USER)
USER_GID=$(id -g $REAL_USER)

# Opções do NFS para evitar bloqueios do root e mapear tudo para o seu usuário
# rw: Leitura e escrita
# sync: Garante integridade dos dados
# all_squash: Mapeia TODO mundo para o usuário anônimo
# anonuid/anongid: Define o usuário anônimo como o seu usuário atual
NFS_OPTS="rw,sync,all_squash,anonuid=${USER_UID},anongid=${USER_GID},no_subtree_check"
# ----------------------------

# Garante que o script está rodando com sudo (necessário para instalar e mexer no /etc/exports)
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute este script usando sudo: sudo $0"
  exit 1
fi

echo "=== Configurando Servidor NFS Doméstico ==="
echo "Usuário real detectado: $REAL_USER (UID: $USER_UID / GID: $USER_GID)"

# 1. Garante que a pasta compartilhada existe e tem as permissões corretas
if [ ! -d "$SHARE_DIR" ]; then
    echo "Criando a pasta $SHARE_DIR..."
    mkdir -p "$SHARE_DIR"
    chown -R $REAL_USER:$REAL_USER "$SHARE_DIR"
    chmod 755 "$SHARE_DIR"
fi
echo "Pasta para compartilhamento: $SHARE_DIR"

# 2. Detecta a distro e instala o servidor NFS
if [ -f /etc/debian_version ]; then
    echo "Sistema baseado en Debian/Ubuntu detectado. Instalando nfs-kernel-server..."
    apt update && apt install -y nfs-kernel-server
    SERVICE_NAME="nfs-kernel-server"
elif [ -f /etc/fedora-release ] || [ -f /etc/redhat-release ]; then
    echo "Sistema baseado em Fedora/RHEL detectado. Instalando nfs-utils..."
    dnf install -y nfs-utils
    SERVICE_NAME="nfs-server"
else
    echo "Distribuição não suportada automaticamente pelo script. Instale o servidor NFS manualmente."
    exit 1
fi

# 3. Configura o arquivo /etc/exports sem duplicar linhas antigas
EXPORT_LINE="${SHARE_DIR} ${ALLOWED_NET}(${NFS_OPTS})"

# Remove configurações antigas dessa mesma pasta para evitar sujeira
sed -i "\|${SHARE_DIR}|d" /etc/exports

# Adiciona a nova configuração
echo "$EXPORT_LINE" >> /etc/exports
echo "Configuração adicionada ao /etc/exports com sucesso!"

# 4. Ajusta o Firewall automaticamente se estiver ativo
if systemctl is-active --quiet ufw; then
    echo "Ajustando regras no UFW..."
    ufw allow from $ALLOWED_NET to any port nfs
elif systemctl is-active --quiet firewalld; then
    echo "Ajustando regras no Firewalld (zona home)..."
    firewall-cmd --permanent --zone=home --add-service=nfs
    firewall-cmd --reload
fi

# 5. Reinicia e habilita o serviço do NFS
echo "Reiniciando o serviço NFS..."
systemctl enable --now $SERVICE_NAME
exportfs -arv

echo "============================================="
echo "Configuração concluída!"
echo "Para montar este compartilhamento em outro Linux da sua casa, use:"
echo "sudo mount -t nfs <IP_DESTE_SERVIDOR>:${SHARE_DIR} /pasta/local/do/cliente"
echo "============================================="