#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

echo "[1/3] Instalando Flatpak..."
sudo zypper install -y flatpak

sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "[2/3] Instalando ferramentas essenciais..."
APPS=(
  it.mijorus.gearlever
  com.github.tchx84.Flatseal
  org.signal.Signal
  com.slack.Slack
  com.brave.Browser
  com.spotify.Client
)

for APP in "${APPS[@]}"; do
  sudo flatpak install -y flathub "$APP" || true
  echo "Instalado: $APP"
done

echo "[3/3] Finalizado."
