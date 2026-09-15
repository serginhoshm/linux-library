#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
COMMAND_LOG="$TEST_ROOT/commands.log"
export PATH="$TEST_ROOT/bin:$PATH"
export COMMAND_LOG

fail() {
  printf 'FALHOU: %s\n' "$*" >&2
  exit 1
}

cat > "$TEST_ROOT/bin/flatpak" <<'EOF'
#!/usr/bin/env bash
case "$1:$2" in
  info:--system) [[ "${MOCK_SYSTEM:-1}" -eq 1 ]] ;;
  info:--user) [[ "${MOCK_USER:-1}" -eq 1 ]] ;;
  uninstall:*) printf '%s\n' "$*" >> "$COMMAND_LOG" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/flatpak"

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"

run_as_root() {
  "$@"
}

run_command() {
  "$@"
}

MOCK_SYSTEM=1 MOCK_USER=1 remove_flatpak_after_native_install org.example.App
grep -Fxq 'uninstall --system -y org.example.App' "$COMMAND_LOG" || fail "Flatpak system nao removido"
grep -Fxq 'uninstall --user -y org.example.App' "$COMMAND_LOG" || fail "Flatpak user nao removido"

: > "$COMMAND_LOG"
MOCK_SYSTEM=0 MOCK_USER=1 remove_flatpak_after_native_install org.example.App
! grep -q -- '--system' "$COMMAND_LOG" || fail "escopo system ausente nao deve ser removido"
grep -Fxq 'uninstall --user -y org.example.App' "$COMMAND_LOG" || fail "Flatpak user nao removido isoladamente"

printf 'OK: migracao Flatpak\n'