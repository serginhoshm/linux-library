#!/usr/bin/env bash
set -euo pipefail

if command -v flatpak >/dev/null 2>&1; then
  echo "[1/2] Instalando Signal via Flatpak..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub org.signal.Signal
else
  echo "[1/2] Instalando Signal via repositório do sistema..."
  sudo dnf install -y signal-desktop || true
fi

echo "[2/2] Processo concluído."
