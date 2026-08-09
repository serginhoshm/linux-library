#!/usr/bin/env bash

set -Eeuo pipefail

DEFAULT_SHARE_PATH="/mnt/1TBVOL"
SHARE_PATH_WAS_SET="${SHARE_PATH+x}"
SHARE_PATH="${SHARE_PATH:-$DEFAULT_SHARE_PATH}"
SHARE_NAME="${SHARE_NAME:-}"
SMB_CONF="/etc/samba/smb.conf"

if [[ $EUID -ne 0 ]]; then
    echo "[ERRO] Execute este script usando sudo." >&2
    exit 1
fi

if [[ -z $SHARE_PATH_WAS_SET ]] && { [[ ! -d $SHARE_PATH ]] || ! mountpoint --quiet "$SHARE_PATH"; }; then
    echo "[AVISO] O volume padrão $DEFAULT_SHARE_PATH não foi encontrado ou não está montado."

    if [[ ! -t 0 ]]; then
        echo "[ERRO] Não há terminal interativo. Defina SHARE_PATH com um diretório existente." >&2
        exit 1
    fi

    while true; do
        read -r -p "Informe o caminho absoluto da pasta a compartilhar: " SHARE_PATH

        if [[ $SHARE_PATH == /* ]] && [[ -d $SHARE_PATH ]] && [[ $SHARE_PATH != / ]]; then
            break
        fi

        echo "[ERRO] Informe um diretório absoluto existente, diferente de /." >&2
    done
fi

if [[ $SHARE_PATH != /* ]] || [[ ! -d $SHARE_PATH ]] || [[ $SHARE_PATH == / ]]; then
    echo "[ERRO] SHARE_PATH deve ser um diretório absoluto existente: $SHARE_PATH" >&2
    exit 1
fi

SHARE_PATH="$(realpath -e -- "$SHARE_PATH")"
SHARE_NAME="${SHARE_NAME:-$(basename -- "$SHARE_PATH")}"

if [[ -z $SHARE_NAME ]] || [[ $SHARE_NAME == *'['* ]] || [[ $SHARE_NAME == *']'* ]] ||
   [[ $SHARE_NAME == */* ]] || [[ $SHARE_NAME == *\\* ]]; then
    echo "[ERRO] Nome de compartilhamento inválido: $SHARE_NAME" >&2
    exit 1
fi

echo "=================================================="
echo " Configuração do Samba: [$SHARE_NAME]"
echo " Caminho: $SHARE_PATH"
echo "=================================================="

if command -v apt-get >/dev/null; then
    PACKAGES=(samba wsdd2)
    SERVICES=(smbd nmbd wsdd2)
    apt-get update
    apt-get install -y "${PACKAGES[@]}"
elif command -v dnf >/dev/null; then
    PACKAGES=(samba wsdd)
    SERVICES=(smb nmb wsdd)
    dnf -y makecache
    dnf install -y "${PACKAGES[@]}"
else
    echo "[ERRO] Distribuição não suportada automaticamente (requer APT ou DNF)." >&2
    exit 1
fi

echo "[1/4] Ajustando acesso ao diretório compartilhado..."
# O compartilhamento é público; não altere recursivamente arquivos já existentes.
chmod 0777 "$SHARE_PATH"

echo "[2/4] Gerando e validando $SMB_CONF..."
if [[ ! -f $SMB_CONF ]]; then
    echo "[ERRO] O pacote não criou $SMB_CONF." >&2
    exit 1
fi

if [[ ! -f ${SMB_CONF}.orig ]]; then
    cp --preserve=all "$SMB_CONF" "${SMB_CONF}.orig"
    echo "-> Configuração original salva em ${SMB_CONF}.orig"
fi

TEMP_CONF="$(mktemp "${SMB_CONF}.XXXXXX")"
trap 'rm -f "$TEMP_CONF"' EXIT

# Remove somente a seção gerenciada, preservando compartilhamentos posteriores.
awk -v section="$SHARE_NAME" '
    /^\[[^]]+\][[:space:]]*$/ {
        current = $0
        sub(/^\[/, "", current)
        sub(/\][[:space:]]*$/, "", current)
        skip = (current == section)
    }
    !skip { print }
' "$SMB_CONF" > "$TEMP_CONF"

# Remove uma diretiva insegura criada por versões anteriores deste script.
sed -i '/^[[:space:]]*root preexec = \/bin\/mount -a[[:space:]]*$/d' "$TEMP_CONF"

if grep -q '^[[:space:]]*map to guest[[:space:]]*=' "$TEMP_CONF"; then
    sed -i 's/^[[:space:]]*map to guest[[:space:]]*=.*/   map to guest = Bad User/' "$TEMP_CONF"
else
    sed -i '/^[[:space:]]*\[global\][[:space:]]*$/a\   map to guest = Bad User' "$TEMP_CONF"
fi

cat >> "$TEMP_CONF" <<EOF

[$SHARE_NAME]
   path = $SHARE_PATH
   browsable = yes
   read only = no
   guest ok = yes
   guest only = yes
   force user = nobody
   create mask = 0666
   directory mask = 0777
EOF

testparm -s "$TEMP_CONF" >/dev/null
install -o root -g root -m 0644 "$TEMP_CONF" "$SMB_CONF"
echo "-> Configuração validada e aplicada."

echo "[3/4] Habilitando e reiniciando serviços..."
for service in "${SERVICES[@]}"; do
    if systemctl cat "${service}.service" >/dev/null 2>&1; then
        systemctl unmask "${service}.service" >/dev/null 2>&1 || true
        systemctl enable --now "${service}.service"
        systemctl restart "${service}.service"
        echo "-> Serviço $service ativo."
    else
        echo "[AVISO] Unit ${service}.service não existe; verifique o pacote instalado."
    fi
done

echo "[4/4] Sincronizando regras de firewall..."
if command -v ufw >/dev/null && systemctl is-active --quiet ufw; then
    ufw allow Samba
    echo "-> Regra Samba habilitada no UFW."
elif command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=samba
    firewall-cmd --reload
    echo "-> Regra Samba habilitada no firewalld."
else
    echo "-> UFW e firewalld não estão ativos."
fi

testparm -s "$SMB_CONF" >/dev/null
systemctl --quiet is-active "${SERVICES[0]}.service"

echo "=================================================="
echo " Compartilhamento //$HOSTNAME/$SHARE_NAME pronto."
echo " AVISO: acesso de convidado com escrita está ativo."
echo "=================================================="


