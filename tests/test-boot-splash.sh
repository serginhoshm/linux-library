#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/default/grub.d" "$TEST_ROOT/boot/grub" "$TEST_ROOT/bin" "$TEST_ROOT/work"

export LINUX_SETUP_GRUB_DEFAULT_FILE="$TEST_ROOT/default/grub"
export LINUX_SETUP_GRUB_DROPIN_DIR="$TEST_ROOT/default/grub.d"
export LINUX_SETUP_GRUB_CONFIG_FILE="$TEST_ROOT/boot/grub/grub.cfg"
export LINUX_SETUP_UPDATE_GRUB_COMMAND="$TEST_ROOT/bin/update-grub"
export LINUX_SETUP_UPDATE_INITRAMFS_COMMAND="$TEST_ROOT/bin/update-initramfs"
export PATH="$TEST_ROOT/bin:$PATH"

cat > "$TEST_ROOT/bin/update-grub" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat > "$TEST_ROOT/bin/grub-script-check" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat > "$TEST_ROOT/bin/update-initramfs" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$TEST_ROOT/bin/update-grub" "$TEST_ROOT/bin/grub-script-check" "$TEST_ROOT/bin/update-initramfs"

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
WORK_DIR="$TEST_ROOT/work"
PACKAGE_FAMILY=apt
COMMAND_LOG="$TEST_ROOT/commands.log"
: > "$COMMAND_LOG"

fail() {
  printf 'FALHOU: %s\n' "$*" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message: esperado '$expected', obtido '$actual'"
}

run_as_root() {
  printf '%q ' "$@" >> "$COMMAND_LOG"
  printf '\n' >> "$COMMAND_LOG"
  if [[ "$1" == "$UPDATE_GRUB_COMMAND" ]]; then
    printf 'linux /boot/vmlinuz-test %s\n' "$(grub_default_cmdline)" > "$GRUB_CONFIG_FILE"
    return 0
  fi
  "$@"
}

printf '%s\n' 'GRUB_CMDLINE_LINUX_DEFAULT="quiet nomodeset splash-mode=logo key=value"' > "$GRUB_DEFAULT_FILE"

enabled="$(boot_splash_dropin_content enabled)"
disabled="$(boot_splash_dropin_content disabled)"
printf '%s\n' "$enabled" | dash -n || fail "drop-in de ativacao nao e POSIX sh"
printf '%s\n' "$disabled" | dash -n || fail "drop-in de desativacao nao e POSIX sh"

actual="$(GRUB_CMDLINE_LINUX_DEFAULT='quiet nomodeset splash-mode=logo splash splash key=value' dash -c "$enabled; printf '%s' \"\$GRUB_CMDLINE_LINUX_DEFAULT\"")"
assert_equals 'quiet nomodeset splash-mode=logo key=value splash' "$actual" "ativacao deve normalizar apenas splash"

actual="$(GRUB_CMDLINE_LINUX_DEFAULT='quiet nomodeset splash-mode=logo splash splash key=value' dash -c "$disabled; printf '%s' \"\$GRUB_CMDLINE_LINUX_DEFAULT\"")"
assert_equals 'quiet nomodeset splash-mode=logo key=value' "$actual" "desativacao deve preservar outros argumentos"

write_boot_splash_state enabled
assert_equals 'quiet nomodeset splash-mode=logo key=value splash' "$(grub_default_cmdline)" "drop-in ativo deve prevalecer"
update_count="$(grep -c '/update-grub ' "$COMMAND_LOG")"
assert_equals 1 "$update_count" "primeira ativacao deve regenerar o GRUB"

write_boot_splash_state enabled
update_count="$(grep -c '/update-grub ' "$COMMAND_LOG")"
assert_equals 1 "$update_count" "ativacao idempotente nao deve regenerar o GRUB"

write_boot_splash_state disabled
assert_equals 'quiet nomodeset splash-mode=logo key=value' "$(grub_default_cmdline)" "drop-in inativo deve remover somente splash"
grep -Eq '(^|[[:space:]])(apt|apt-get|dpkg)[[:space:]].*(remove|purge)|update-initramfs' "$COMMAND_LOG" &&
  fail "desativacao nao pode remover pacotes nem atualizar initramfs"

write_boot_splash_state disabled
update_count="$(grep -c '/update-grub ' "$COMMAND_LOG")"
assert_equals 2 "$update_count" "desativacao idempotente nao deve regenerar o GRUB"

printf 'OK: boot splash\n'