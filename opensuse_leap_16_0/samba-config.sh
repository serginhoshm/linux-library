#!/usr/bin/env bash
set -Eeuo pipefail

SHARE_DIR="${SHARE_DIR:-/srv/samba/share}"
SHARE_NAME="${SHARE_NAME:-share}"
SMB_CONF="/etc/samba/smb.conf"
GUEST_USER="${GUEST_USER:-nobody}"
GUEST_GROUP="${GUEST_GROUP:-nogroup}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute este script como root: sudo $0" >&2
  exit 1
fi

if ! command -v zypper >/dev/null 2>&1; then
  echo "Este script foi escrito para openSUSE Leap. O comando zypper não foi encontrado." >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[AVISO] Comando não encontrado: $1. Alguns passos podem ser ignorados." >&2
    return 1
  fi
}

open_firewall_for_samba() {
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=samba >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    echo "-> Regra Samba habilitada no firewalld."
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && systemctl is-active --quiet ufw; then
    ufw allow Samba >/dev/null 2>&1 || ufw allow 445/tcp >/dev/null 2>&1 || true
    echo "-> Regra Samba habilitada no UFW."
    return 0
  fi

  echo "-> Nenhum firewall gerenciado ativo detectado. Verifique as regras do firewall manualmente."
}

echo "[1/4] Instalando Samba no openSUSE..."
zypper --non-interactive install -y samba

echo "[2/4] Ajustando diretório e permissões do compartilhamento..."
mkdir -p "$SHARE_DIR"

# O compartilhamento público precisa ser gravável por usuários anônimos; o "guest account"
# do Samba deve corresponder a um usuário local que tenha acesso ao diretório.
if id "$GUEST_USER" >/dev/null 2>&1; then
  chown "$GUEST_USER:${GUEST_GROUP:-$GUEST_USER}" "$SHARE_DIR"
else
  chown root:root "$SHARE_DIR"
fi

chmod 0777 "$SHARE_DIR"
chmod -R u+rwX,go+rwX "$SHARE_DIR"

if [[ ! -f "$SMB_CONF" ]]; then
  echo "[ERRO] Arquivo de configuração do Samba não foi encontrado em $SMB_CONF" >&2
  exit 1
fi

cp --preserve=all "$SMB_CONF" "${SMB_CONF}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

TEMP_CONF="$(mktemp "${SMB_CONF}.XXXXXX")"
trap 'rm -f "$TEMP_CONF"' EXIT

# Remove o bloco gerenciado anteriormente para evitar duplicação.
awk -v section="$SHARE_NAME" '
  /^\[[^]]+\][[:space:]]*$/ {
    current = $0
    sub(/^\[/, "", current)
    sub(/\][[:space:]]*$/, "", current)
    skip = (current == section)
  }
  !skip { print }
' "$SMB_CONF" > "$TEMP_CONF"

if ! grep -q '^[[:space:]]*\[global\][[:space:]]*$' "$TEMP_CONF"; then
  printf '\n[global]\n' >> "$TEMP_CONF"
fi

# A configuração abaixo é necessária para que usuários anônimos/guest consigam se conectar.
if ! grep -q '^[[:space:]]*map to guest[[:space:]]*=' "$TEMP_CONF"; then
  printf '   map to guest = Bad User\n' >> "$TEMP_CONF"
fi

if ! grep -q '^[[:space:]]*guest account[[:space:]]*=' "$TEMP_CONF"; then
  printf '   guest account = %s\n' "$GUEST_USER" >> "$TEMP_CONF"
fi

if ! grep -q '^[[:space:]]*usershare allow guests[[:space:]]*=' "$TEMP_CONF"; then
  printf '   usershare allow guests = yes\n' >> "$TEMP_CONF"
fi

cat >> "$TEMP_CONF" <<EOF

[$SHARE_NAME]
   path = $SHARE_DIR
   browseable = yes
   read only = no
   guest ok = yes
   guest only = yes
   public = yes
   force user = $GUEST_USER
   create mask = 0666
   directory mask = 0777
EOF

# Valida a configuração antes de aplicar.
if ! require_cmd testparm; then
  echo "[AVISO] testparm não está disponível; pulando validação do smb.conf." >&2
else
  testparm -s "$TEMP_CONF" >/dev/null
fi

install -o root -g root -m 0644 "$TEMP_CONF" "$SMB_CONF"

echo "[3/4] Habilitando e reiniciando serviços Samba..."
for service in smb nmb smbd nmbd; do
  if systemctl list-unit-files --type=service --state=enabled --all 2>/dev/null | grep -q "^${service}\.service" || systemctl cat "${service}.service" >/dev/null 2>&1; then
    systemctl enable --now "${service}.service" >/dev/null 2>&1 || true
    systemctl restart "${service}.service" >/dev/null 2>&1 || true
    echo "-> Serviço $service ativo."
  fi
done

# Também cobre o caso do openSUSE usar o nome do serviço smb.service.
if systemctl cat smb.service >/dev/null 2>&1; then
  systemctl enable --now smb.service >/dev/null 2>&1 || true
  systemctl restart smb.service >/dev/null 2>&1 || true
fi

open_firewall_for_samba

if command -v smbclient >/dev/null 2>&1; then
  smbclient -L localhost -U '%' >/dev/null 2>&1 || true
fi

echo "[4/4] Configuração concluída."
echo "Compartilhamento público configurado em $SHARE_DIR"
echo "Acesso anônimo está habilitado com guest ok = yes e map to guest = Bad User."
