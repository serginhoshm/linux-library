#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Execute como root: sudo $0"
  exit 1
fi

echo "[1/4] Instalando Flatpak..."
sudo dnf install -y flatpak

echo "[2/4] Adicionando Flathub..."
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "[3/4] Instalando aplicativos essenciais..."
APPS=(
  it.mijorus.gearlever
  com.github.tchx84.Flatseal
  org.signal.Signal
  com.slack.Slack
  com.brave.Browser
  com.spotify.Client
  org.chromium.Chromium
  com.jetbrains.PyCharm-Professional
  org.sqlitebrowser.sqlitebrowser
)

for APP in "${APPS[@]}"; do
  sudo flatpak install -y flathub "$APP" || true
  echo "Instalado: $APP"
done

echo "[4/4] Finalizado."
