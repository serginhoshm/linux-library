#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Erro: Este script precisa ser executado como root (sudo)."
  exit 1
fi

if [ -z "$1" ]; then
  echo "Uso: $0 <tamanho_em_GB>"
  exit 1
fi

TAMANHO_GB=$1
SWAP_FILE="/swapfile"

if [[ ! "$TAMANHO_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Erro: O argumento deve ser um número válido."
  exit 1
fi

if [ "$(echo "$TAMANHO_GB == 0" | bc -l)" -eq 1 ]; then
  if swapon --show | grep -q "$SWAP_FILE"; then
    swapoff "$SWAP_FILE"
  fi
  rm -f "$SWAP_FILE"
  sed -i "\|${SWAP_FILE}|d" /etc/fstab
  echo "Sucesso! Swap removida."
  exit 0
fi

TAMANHO_MB=$(echo "$TAMANHO_GB * 1024" | bc | cut -d'.' -f1)
if swapon --show | grep -q "$SWAP_FILE"; then
  swapoff "$SWAP_FILE"
fi
rm -f "$SWAP_FILE"

dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$TAMANHO_MB" status=progress
chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE"
swapon "$SWAP_FILE"

if ! grep -q "$SWAP_FILE" /etc/fstab; then
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

echo "Swap configurada com sucesso."
free -h
