#!/usr/bin/env bash
set -euo pipefail

echo "[1/2] Instalando Flameshot no Linux Mint..."
sudo apt update
sudo apt install -y flameshot

mkdir -p "$HOME/.local/bin"
cat <<'EOF' > "$HOME/.local/bin/flameshot-gui"
#!/usr/bin/env bash
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
	export QT_QPA_PLATFORM=wayland
fi
exec flameshot gui
EOF
chmod +x "$HOME/.local/bin/flameshot-gui"

echo "[2/2] Flameshot instalado com sucesso."
echo "Use: ~/.local/bin/flameshot-gui"
