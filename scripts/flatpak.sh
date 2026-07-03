#!/usr/bin/env bash

# Sair imediatamente se algum comando falhar
set -e

echo "===================================================="
echo "  Iniciando a configuração do Flatpak no Debian     "
echo "===================================================="

# 1. Atualizar a lista de pacotes do sistema
echo -e "\n[1/4] Atualizando os repositórios do APT..."
sudo apt update

# 2. Instalar o Flatpak e o FUSE 3
# Nota: O fuse3 é a versão moderna no Debian, ideal para o GearLever e AppImages
echo -e "\n[2/4] Instalando Flatpak e FUSE 3..."
sudo apt install -y flatpak fuse3

# 3. Adicionar o repositório oficial do Flathub
echo -e "\n[3/4] Adicionando o repositório Flathub..."
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 4. Definir e instalar a lista de aplicativos
echo -e "\n[4/4] Instalando os aplicativos Flatpak..."

APPS=(
    "it.mijorus.gearlever"                           # GearLever
    "com.github.tchx84.Flatseal"                     # Flatseal
    "com.warlordsoftwares.youtube-downloader-4ktube" # 4K Tube Video Downloader
    "org.signal.Signal"                              # Signal
    "com.slack.Slack"                                # Slack
    "com.brave.Browser"                              # Brave Browser
    "com.spotify.Client"                             # Spotify
    "org.chromium.Chromium"                          # Chromium
    "com.opera.opera-gx"                             # Opera GX
    "com.github.PintaProject.Pinta"                  # Pinta
    "com.jetbrains.PyCharm-Professional"             # PyCharm Professional
    "dev.aunetx.deezer"                              # Deezer
    "org.sqlitebrowser.sqlitebrowser"                # SQLite Browser
)

# Instalar cada aplicativo da lista sem pedir confirmação manual (-y)
for APP in "${APPS[@]}"; do
    echo "----------------------------------------------------"
    echo "Instalando: $APP"
    echo "----------------------------------------------------"
    sudo flatpak install flathub "$APP" -y
done

echo "===================================================="
echo "  ¡Processo concluído com sucesso!                  "
echo "  Recomenda-se reiniciar o sistema para que os      "
echo "  ícones dos aplicativos apareçam no seu menu.      "
echo "===================================================="