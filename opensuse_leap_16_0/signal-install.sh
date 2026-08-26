#!/usr/bin/env bash
set -euo pipefail

echo "[1/2] Instalando Signal no openSUSE via Flatpak..."
sudo zypper install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak install -y flathub org.signal.Signal

echo "[2/2] Processo concluído."
