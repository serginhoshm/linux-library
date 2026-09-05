#!/usr/bin/env bash
set -euo pipefail

if ! lspci | grep -qi 'NVIDIA'; then
	echo "Nenhuma GPU NVIDIA detectada. Nada a fazer."
	exit 0
fi

echo "Instalando o driver NVIDIA recomendado para o Linux Mint..."
sudo apt update
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers install

echo "Driver instalado. Reinicie o sistema para carregá-lo."
