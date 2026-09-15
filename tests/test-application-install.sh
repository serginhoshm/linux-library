#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
COMMAND_LOG="$TEST_ROOT/commands.log"
mkdir -p "$TEST_ROOT/work" "$TEST_ROOT/state" "$TEST_ROOT/apt-sources" "$TEST_ROOT/apt-keys" \
  "$TEST_ROOT/apt-shared-keys" "$TEST_ROOT/dnf-repos" "$TEST_ROOT/zypper-repos"
export LINUX_SETUP_STATE_DIR="$TEST_ROOT/state"
export LINUX_SETUP_APT_SOURCE_DIR="$TEST_ROOT/apt-sources"
export LINUX_SETUP_APT_KEYRING_DIR="$TEST_ROOT/apt-keys"
export LINUX_SETUP_APT_SHARED_KEYRING_DIR="$TEST_ROOT/apt-shared-keys"
export LINUX_SETUP_DNF_REPO_DIR="$TEST_ROOT/dnf-repos"
export LINUX_SETUP_ZYPPER_REPO_DIR="$TEST_ROOT/zypper-repos"
: > "$COMMAND_LOG"

fail() {
  printf 'FALHOU: %s\n' "$*" >&2
  exit 1
}

assert_logged() {
  grep -Fxq "$1" "$COMMAND_LOG" || fail "comando nao registrado: $1"
}

assert_not_logged() {
  ! grep -Fxq "$1" "$COMMAND_LOG" || fail "comando inesperado: $1"
}

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
load_app_catalog
WORK_DIR="$TEST_ROOT/work"
PACKAGE_FAMILY=apt
DRY_RUN=0
MOCK_INSTALLED=0
MOCK_CACHE=1
MOCK_INSTALL_FAILURE=0

is_native_package_installed() {
  [[ "$MOCK_INSTALLED" -eq 1 ]]
}

cached_native_package_for_app() {
  [[ "$MOCK_CACHE" -eq 1 ]] || return 1
  NATIVE_CACHE_PATH="/cache/chromium.deb"
}

install_cached_native_package() {
  printf 'install:%s\n' "$1" >> "$COMMAND_LOG"
  [[ "$MOCK_INSTALL_FAILURE" -eq 0 ]] || return 1
  MOCK_INSTALLED=1
}

remove_flatpak_after_native_install() {
  printf 'remove:%s\n' "$1" >> "$COMMAND_LOG"
}

install_flatpak_app() {
  printf 'flatpak:%s\n' "$1" >> "$COMMAND_LOG"
}

chromium_index=7

install_app_with_fallback "$chromium_index" 0
assert_logged 'install:/cache/chromium.deb'
assert_logged 'remove:org.chromium.Chromium'
assert_not_logged 'flatpak:org.chromium.Chromium'

: > "$COMMAND_LOG"
MOCK_INSTALLED=1
install_app_with_fallback "$chromium_index" 0
assert_not_logged 'install:/cache/chromium.deb'
assert_logged 'remove:org.chromium.Chromium'

: > "$COMMAND_LOG"
MOCK_INSTALLED=0
MOCK_CACHE=0
if install_app_with_fallback "$chromium_index" 0; then
  fail "cache ausente sem fallback nao pode ser sucesso"
fi
assert_not_logged 'flatpak:org.chromium.Chromium'
assert_not_logged 'remove:org.chromium.Chromium'

: > "$COMMAND_LOG"
install_app_with_fallback "$chromium_index" 1
assert_logged 'flatpak:org.chromium.Chromium'
assert_not_logged 'install:/cache/chromium.deb'

: > "$COMMAND_LOG"
MOCK_CACHE=1
MOCK_INSTALL_FAILURE=1
if install_app_with_fallback "$chromium_index" 1; then
  fail "falha de instalacao do cache nao pode ser mascarada"
fi
assert_logged 'install:/cache/chromium.deb'
assert_not_logged 'flatpak:org.chromium.Chromium'
assert_not_logged 'remove:org.chromium.Chromium'

printf 'OK: instalacao de aplicativos\n'