#!/usr/bin/env bash
set -euo pipefail

echo "[1/4] Instalando dependências..."
sudo apt update
sudo apt install -y wget gpg

echo "[2/4] Instalando a chave oficial do Signal..."
wget -qO- https://updates.signal.org/desktop/apt/keys.asc \
	| gpg --dearmor \
	| sudo tee /usr/share/keyrings/signal-desktop-keyring.gpg >/dev/null

echo "[3/4] Configurando o repositório oficial..."
wget -qO- https://updates.signal.org/static/desktop/apt/signal-desktop.sources \
	| sudo tee /etc/apt/sources.list.d/signal-desktop.sources >/dev/null

echo "[4/4] Instalando o Signal Desktop..."
sudo apt update
sudo apt install -y signal-desktop

