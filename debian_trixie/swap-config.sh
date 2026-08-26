#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Erro: Este script precisa ser executado como root (sudo)."
  exit 1
fi

if [ -z "$1" ]; then
  echo "Uso: $0 <tamanho_em_GB>"
  echo "Exemplo: $0 4"
  echo "Exemplo: $0 0"
  exit 1
fi

TAMANHO_GB=$1
SWAP_FILE="/swapfile"

if ! command -v bc &> /dev/null; then
  echo "Instalando dependência 'bc'..."
  if command -v apt-get &> /dev/null; then
    apt-get update -y && apt-get install -y bc
  elif command -v dnf &> /dev/null; then
    dnf install -y bc
  else
    yum install -y bc
  fi
fi

if [[ ! "$TAMANHO_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Erro: O argumento deve ser um número válido."
  exit 1
fi

if [ "$(echo "$TAMANHO_GB == 0" | bc -l)" -eq 1 ]; then
  echo "Desativando a swap..."
  if swapon --show | grep -q "$SWAP_FILE"; then
    swapoff "$SWAP_FILE"
  fi
  if [ -f "$SWAP_FILE" ]; then
    rm -f "$SWAP_FILE"
  fi
  sed -i "\|${SWAP_FILE}|d" /etc/fstab
  echo "Sucesso! Swap desativada e removida."
  exit 0
fi

TAMANHO_MB=$(echo "$TAMANHO_GB * 1024" | bc | cut -d'.' -f1)

echo "Preparando swap de $TAMANHO_GB GB ($TAMANHO_MB MB)..."

if swapon --show | grep -q "$SWAP_FILE"; then
  echo "Desativando swap antiga..."
  swapoff "$SWAP_FILE"
fi

if [ -f "$SWAP_FILE" ]; then
  rm -f "$SWAP_FILE"
fi

dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$TAMANHO_MB" status=progress
chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE"
swapon "$SWAP_FILE"

if ! grep -q "$SWAP_FILE" /etc/fstab; then
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

echo "Sucesso! Nova swap de $TAMANHO_GB GB ativa e configurada."
free -h
