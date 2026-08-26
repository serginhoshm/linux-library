#!/usr/bin/env bash
set -euo pipefail

PORTS=(
  "32400/tcp"
  "32469/tcp"
  "1900/udp"
  "5353/udp"
  "32410-32414/udp"
)

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

detect_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
    echo "ufw"
  elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    echo "firewalld"
  elif command -v nft >/dev/null 2>&1; then
    echo "nft"
  else
    echo "none"
  fi
}

configure_firewall() {
  local fw
  fw="$(detect_firewall)"

  if [[ "${fw}" == "none" ]]; then
    echo "Nenhum firewall padrão detectado. Verifique manualmente." >&2
    exit 1
  fi

  echo "[1/4] Firewall detectado: ${fw}"

  case "${fw}" in
    ufw)
      echo "[2/4] Abrindo portas do Plex no UFW..."
      ufw allow 32400/tcp comment 'Plex Media Server' >/dev/null
      ufw allow 32469/tcp comment 'Plex DLNA/Remote' >/dev/null
      ufw allow 1900/udp comment 'Plex DLNA' >/dev/null
      ufw allow 5353/udp comment 'Plex Bonjour' >/dev/null
      ufw allow 32410:32414/udp comment 'Plex GDM/Media' >/dev/null
      ufw reload >/dev/null
      ;;
    firewalld)
      echo "[2/4] Abrindo portas do Plex no firewalld..."
      for port in 32400/tcp 32469/tcp 1900/udp 5353/udp; do
        firewall-cmd --permanent --add-port="${port}" >/dev/null 2>&1 || true
      done
      firewall-cmd --permanent --add-port=32410-32414/udp >/dev/null 2>&1 || true
      firewall-cmd --reload >/dev/null
      ;;
    nft)
      echo "[2/4] Abrindo portas do Plex no nftables..."
      nft list table inet filter >/dev/null 2>&1 || nft add table inet filter
      nft list chain inet filter input >/dev/null 2>&1 || nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }'
      for rule in \
        'tcp dport 32400 accept' \
        'tcp dport 32469 accept' \
        'udp dport 1900 accept' \
        'udp dport 5353 accept' \
        'udp dport 32410-32414 accept'; do
        nft add rule inet filter input ${rule} >/dev/null 2>&1 || true
      done
      ;;
  esac

  echo "[3/4] Validando regras..."
  case "${fw}" in
    ufw)
      ufw status verbose | grep -E '32400|32469|1900|5353|32410' || true
      ;;
    firewalld)
      firewall-cmd --list-ports | grep -E '32400|32469|1900|5353|32410' || true
      ;;
    nft)
      nft list ruleset | grep -E '32400|32469|1900|5353|32410' || true
      ;;
  esac

  echo "[4/4] Concluído."
  echo "Portas do Plex abertas: 32400/tcp, 32469/tcp, 1900/udp, 5353/udp, 32410-32414/udp."
}

test_firewall() {
  local fw
  fw="$(detect_firewall)"

  echo "[1/3] Firewall detectado: ${fw}"
  echo "[2/3] Verificando portas do Plex..."

  case "${fw}" in
    ufw)
      ufw status verbose | grep -E '32400|32469|1900|5353|32410' || echo 'Nenhuma regra do Plex encontrada no UFW.'
      ;;
    firewalld)
      firewall-cmd --list-ports | grep -E '32400|32469|1900|5353|32410' || echo 'Nenhuma regra do Plex encontrada no firewalld.'
      ;;
    nft)
      nft list ruleset | grep -E '32400|32469|1900|5353|32410' || echo 'Nenhuma regra do Plex encontrada no nftables.'
      ;;
    *)
      echo "Nenhum firewall detectado."
      ;;
  esac

  echo "[3/3] Verificando escuta local..."
  ss -lntup 2>/dev/null | grep -E ':32400|:32469|:1900|:5353|:32410|:32411|:32412|:32413|:32414' || echo 'Nenhuma porta do Plex ouvindo localmente.'
}

show_menu() {
  echo "========================================="
  echo " Plex Media Server - Firewall Helper "
  echo "========================================="
  echo "1) Configurar portas do Plex"
  echo "2) Testar firewall e portas"
  echo "3) Sair"
  echo "========================================="
  read -r -p "Escolha uma opção [1-3]: " choice

  case "${choice}" in
    1)
      configure_firewall
      ;;
    2)
      test_firewall
      ;;
    3)
      echo "Saindo..."
      exit 0
      ;;
    *)
      echo "Opção inválida."
      exit 1
      ;;
  esac
}

show_menu
