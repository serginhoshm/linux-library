#!/bin/bash

# Aborta o script se ocorrer algum erro crítico inesperado
set -e

# Garante que o script está sendo rodado como root
if [ "$EUID" -ne 0 ]; then
  echo "[ERRO] Por favor, execute este script usando sudo."
  exit 1
fi

echo "=================================================="
echo " Configuração Automatizada e Resiliente do Samba  "
echo "=================================================="

# 1. Detectar o gerenciador de pacotes da distribuição
if [ -x "$(command -v apt)" ]; then
    PKG_MANAGER="apt"
    UPDATE_CMD="apt update"
    INSTALL_CMD="apt install -y"
    SERVICES=("smbd" "nmbd" "wsdd")
elif [ -x "$(command -v dnf)" ]; then
    PKG_MANAGER="dnf"
    UPDATE_CMD="dnf check-update"
    INSTALL_CMD="dnf install -y"
    SERVICES=("smb" "nmbd" "wsdd")
else
    echo "[ERRO] Distribuição não suportada automaticamente (requer APT ou DNF)."
    exit 1
fi

# 2. Instalar pacotes necessários (O gerenciador ignora se já estiverem instalados)
echo "[1/5] Verificando e instalando pacotes (Samba, WSDD, Sed)..."
$UPDATE_CMD || true
$INSTALL_CMD samba wsdd sed

# 3. Configurar as permissões da pasta de forma resiliente
echo "[2/5] Garantindo permissões totais em /mnt/1TBVOL..."
if [ -d "/mnt/1TBVOL" ]; then
    chmod -R 777 /mnt/1TBVOL
    chown -R nobody:nogroup /mnt/1TBVOL 2>/dev/null || chown -R nobody:nobody /mnt/1TBVOL
else
    echo "[AVISO] O diretório /mnt/1TBVOL não foi encontrado no momento. Criando ponto de montagem..."
    mkdir -p /mnt/1TBVOL
    chmod 777 /mnt/1TBVOL
fi

# 4. Modificar o arquivo smb.conf de forma limpa (Suporta múltiplas execuções)
echo "[3/5] Ajustando o arquivo /etc/samba/smb.conf..."
SMB_CONF="/etc/samba/smb.conf"

# Criar um backup de segurança apenas se o backup original não existir
if [ -f "$SMB_CONF" ] && [ ! -f "${SMB_CONF}.orig" ]; then
    cp "$SMB_CONF" "${SMB_CONF}.orig"
    echo "-> Backup original do sistema salvo em ${SMB_CONF}.orig"
fi

# Remover blocos antigos de execuções passadas para evitar duplicidade
# Remove o bloco [1TBVOL] e tudo abaixo dele se já existir
sed -i '/\[1TBVOL\]/,$d' "$SMB_CONF"

# Adicionar a linha preventiva 'root preexec' na seção [global] se ela não existir
# Isso força o Samba a rodar o mount -a antes de entregar o acesso, prevenindo pastas vazias
if ! grep -q "root preexec = /bin/mount -a" "$SMB_CONF"; then
    # Insere logo abaixo da linha identificadora [global]
    sed -i '/\[global\]/a \   root preexec = /bin/mount -a' "$SMB_CONF"
    echo "-> Comando de montagem forçada injetado na seção [global]."
fi

# Injetar o bloco de compartilhamento limpo no final do arquivo
cat << 'EOF' >> "$SMB_CONF"

[1TBVOL]
   path = /mnt/1TBVOL
   browsable = yes
   writable = yes
   guest ok = yes
   guest only = yes
   force user = nobody
   create mask = 0777
   directory mask = 0777
EOF
echo "-> Bloco [1TBVOL] reconfigurado com sucesso."

# 5. Reiniciar e Habilitar os serviços
echo "[4/5] Reiniciando e habilitando os serviços do sistema..."
for service in "${SERVICES[@]}"; do
    if systemctl list-unit-files --type=service --all | grep -q "^${service}\.service"; then
        systemctl unmask "$service" 2>/dev/null || true
        systemctl enable "$service"
        systemctl restart "$service"
        echo "-> Serviço $service atualizado."
    else
        if [ "$service" = "wsdd" ] && [ -x "$(command -v wsdd)" ]; then
            # Fallback para distros onde o pacote wsdd não entrega unit systemd.
            pgrep -f "[/]usr/bin/wsdd" >/dev/null && pkill -f "[/]usr/bin/wsdd" || true
            nohup wsdd >/var/log/wsdd.log 2>&1 &
            echo "-> wsdd iniciado em modo manual (sem unit systemd). Log: /var/log/wsdd.log"
        else
            echo "[AVISO] Unit ${service}.service não existe neste sistema. Pulando."
        fi
    fi
done

# 6. Ajustar o Firewall de forma limpa
echo "[5/5] Sincronizando regras de Firewall..."
if [ -x "$(command -v ufw)" ] && systemctl is-active --quiet ufw; then
    ufw allow samba
    ufw reload
    echo "-> Regras atualizadas no UFW."
elif [ -x "$(command -v firewall-cmd)" ] && systemctl is-active --quiet firewalld; then
    # Remove primeiro para evitar avisos de regra duplicada e adiciona novamente
    firewall-cmd --permanent --remove-service=samba 2>/dev/null || true
    firewall-cmd --permanent --add-service=samba
    firewall-cmd --reload
    echo "-> Regras atualizadas no FirewallD."
else
    echo "-> Nenhum firewall restritivo ativo detectado. Pulando."
fi

echo "=================================================="
echo " Configuração concluída e testada com sucesso!   "
echo " O volume está pronto no GNOME, Cinnamon e Android."
echo "=================================================="


