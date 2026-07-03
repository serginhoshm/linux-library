#!/bin/bash

# Verificar se o script está sendo executado como root
if [ "$EUID" -ne 0 ]; then
  echo "Erro: Este script precisa ser executado como root (sudo)."
  exit 1
fi

# Verificar se o argumento foi passado
if [ -z "$1" ]; then
  echo "Uso: $0 <tamanho_em_GB>"
  echo "Exemplo: $0 4"
  echo "Exemplo: $0 0   (para desativar)"
  exit 1
fi

TAMANHO_GB=$1
SWAP_FILE="/swapfile"

# Garantir que o utilitário 'bc' esteja instalado
if ! command -v bc &> /dev/null; then
  echo "Instalando dependência 'bc'..."
  if command -v apt-get &> /dev/null; then
    apt-get update -y && apt-get install -y bc
  elif command -v dnf &> /dev/null; then
    dnf install -y bc
  elif command -v yum &> /dev/null; then
    yum install -y bc
  fi
fi

# Verificar se a entrada é um número válido
if [[ ! "$TAMANHO_GB" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Erro: O argumento deve ser um número válido."
  exit 1
fi

# ==============================================================================
# CASO 0: Desativar Swap
# ==============================================================================
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

# ==============================================================================
# CASO > 0: Criar ou Redimensionar Swap
# ==============================================================================
TAMANHO_MB=$(echo "$TAMANHO_GB * 1024" | bc | cut -d'.' -f1)

echo "Preparando swap de $TAMANHO_GB GB ($TAMANHO_MB MB)..."

# 1. Desativar swap antiga se existir
if swapon --show | grep -q "$SWAP_FILE"; then
  echo "Desativando swap antiga..."
  swapoff "$SWAP_FILE"
fi

# Remover arquivo antigo para evitar conflitos de atributos do sistema de arquivos
if [ -f "$SWAP_FILE" ]; then
  rm -f "$SWAP_FILE"
fi

# 2. Detectar se o sistema de arquivos da raiz é Btrfs
SISTEMA_ARQUIVOS=$(df -T / | awk 'NR==2 {print $2}')

if [ "$SISTEMA_ARQUIVOS" = "btrfs" ]; then
  echo "Detectado sistema de arquivos Btrfs (padrão Fedora)."
  echo "Criando arquivo de swap compatível com Btrfs..."
  # O próprio btrfs cria, desabilita o CoW e define o tamanho correto alinhado
  btrfs filesystem mkswapfile --size ${TAMANHO_MB}M "$SWAP_FILE"
else
  echo "Detectado sistema de arquivos tradicional ($SISTEMA_ARQUIVOS)."
  echo "Alocando espaço usando dd..."
  dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$TAMANHO_MB" status=progress
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
fi

# 3. Ativar a nova swap
echo "Ativando a nova swap..."
if ! swapon "$SWAP_FILE"; then
  echo "Erro crítico: Falha ao ativar a swap com swapon."
  exit 1
fi

# 4. Garantir persistência no /etc/fstab
if ! grep -q "$SWAP_FILE" /etc/fstab; then
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

echo "Sucesso! Nova swap de $TAMANHO_GB GB ativa e configurada."
echo "Status atual da memória:"
free -h