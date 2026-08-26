#!/usr/bin/env bash
set -euo pipefail

echo "[1/2] Instalando Flameshot no OpenSUSE..."
sudo zypper install -y flameshot

mkdir -p "$HOME/.local/bin"
cat <<'EOF' > "$HOME/.local/bin/flameshot-gui"
#!/usr/bin/env bash
export QT_QPA_PLATFORM=wayland
exec flameshot gui
EOF
chmod +x "$HOME/.local/bin/flameshot-gui"

echo "[2/2] Flameshot instalado com sucesso."
echo "Use: ~/.local/bin/flameshot-gui"
