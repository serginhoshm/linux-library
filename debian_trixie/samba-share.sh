#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_SHARE_PATH="${SHARE_PATH:-/srv/samba/share}"
SHARE_PATH="${SHARE_PATH:-$DEFAULT_SHARE_PATH}"
SHARE_NAME="${SHARE_NAME:-share}"
SMB_CONF="/etc/samba/smb.conf"
GUEST_USER="${GUEST_USER:-nobody}"
GUEST_GROUP="${GUEST_GROUP:-nogroup}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute este script como root: sudo $0" >&2
  exit 1
fi

if [[ ! -d "$SHARE_PATH" ]]; then
  mkdir -p "$SHARE_PATH"
fi

if id "$GUEST_USER" >/dev/null 2>&1; then
  chown "$GUEST_USER:${GUEST_GROUP:-$GUEST_USER}" "$SHARE_PATH"
else
  chown root:root "$SHARE_PATH"
fi

chmod 0777 "$SHARE_PATH"
chmod -R u+rwX,go+rwX "$SHARE_PATH"

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y samba samba-common-bin wsdd
  SERVICES=(smbd nmbd wsdd)
elif command -v dnf >/dev/null 2>&1; then
  dnf -y makecache
  dnf install -y samba wsdd
  SERVICES=(smb nmb wsdd)
elif command -v zypper >/dev/null 2>&1; then
  zypper --non-interactive install -y samba
  SERVICES=(smb nmb)
else
  echo "Distribuição não suportada automaticamente." >&2
  exit 1
fi

if [[ ! -f "$SMB_CONF" ]]; then
  echo "[ERRO] O pacote não criou $SMB_CONF." >&2
  exit 1
fi

if [[ ! -f "${SMB_CONF}.orig" ]]; then
  cp --preserve=all "$SMB_CONF" "${SMB_CONF}.orig"
fi

TEMP_CONF="$(mktemp "${SMB_CONF}.XXXXXX")"
trap 'rm -f "$TEMP_CONF"' EXIT

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

if ! grep -q '^[[:space:]]*map to guest[[:space:]]*=' "$TEMP_CONF"; then
  printf '   map to guest = Bad User\n' >> "$TEMP_CONF"
fi

if ! grep -q '^[[:space:]]*guest account[[:space:]]*=' "$TEMP_CONF"; then
  printf '   guest account = %s\n' "$GUEST_USER" >> "$TEMP_CONF"
fi

cat >> "$TEMP_CONF" <<EOF

[$SHARE_NAME]
   path = $SHARE_PATH
   browseable = yes
   read only = no
   guest ok = yes
   guest only = yes
   public = yes
   force user = $GUEST_USER
   create mask = 0666
   directory mask = 0777
EOF

testparm -s "$TEMP_CONF" >/dev/null
install -o root -g root -m 0644 "$TEMP_CONF" "$SMB_CONF"

echo "[1/4] Habilitando e reiniciando serviços Samba..."
for service in "${SERVICES[@]}"; do
  if systemctl cat "${service}.service" >/dev/null 2>&1; then
    systemctl enable --now "${service}.service" >/dev/null 2>&1 || true
    systemctl restart "${service}.service" >/dev/null 2>&1 || true
  fi
done

echo "[2/4] Sincronizando regras de firewall..."
if command -v ufw >/dev/null 2>&1 && systemctl is-active --quiet ufw; then
  ufw allow Samba >/dev/null 2>&1 || ufw allow 445/tcp >/dev/null 2>&1 || true
  echo "-> Regra Samba habilitada no UFW."
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=samba >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  echo "-> Regra Samba habilitada no firewalld."
else
  echo "-> Nenhum firewall gerenciado ativo detectado."
fi

echo "[3/4] Validando configuração..."
testparm -s "$SMB_CONF" >/dev/null

echo "[4/4] Configuração concluída."
echo "Compartilhamento público configurado em $SHARE_PATH"
echo "Acesso anônimo: guest ok = yes e map to guest = Bad User."
