#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
COMMAND_LOG="$TEST_ROOT/commands.log"
: > "$COMMAND_LOG"

fail() {
  printf 'FALHOU: %s\n' "$*" >&2
  exit 1
}

assert_logged() {
  grep -Fxq "$1" "$COMMAND_LOG" || fail "evento nao registrado: $1"
}

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
load_app_catalog
PACKAGE_FAMILY=apt
DRY_RUN=0

resolve_external_package() {
  fail "preparacao de cache nao pode executar descoberta"
}

download_resolved_cache_asset() {
  printf 'cache:%s:%s\n' "$2" "$1" >> "$COMMAND_LOG"
}

chromium_index="$(app_index_for_key chromium)"
APP_DEB_URLS[$chromium_index]="https://example.test/chromium.deb"
APP_RPM_URLS[$chromium_index]="https://example.test/chromium.rpm"
cache_application_packages "$chromium_index"
assert_logged 'cache:apt:chromium'
assert_logged 'cache:dnf:chromium'
[[ "$PACKAGE_FAMILY" == apt ]] || fail "familia original nao foi restaurada"

: > "$COMMAND_LOG"
confirm_count=0
is_native_package_installed() { return 1; }
cached_native_package_for_app() { return 1; }
checklist() {
  CHECKLIST_RESULT=("${APP_KEYS[0]}" "${APP_KEYS[1]}")
}
confirm() {
  confirm_count=$((confirm_count + 1))
  return 0
}
install_app_with_fallback() {
  printf 'policy:%s:%s\n' "${APP_KEYS[$1]}" "$2" >> "$COMMAND_LOG"
}
application_menu
[[ "$confirm_count" -eq 2 ]] || fail "politica de fallback foi perguntada mais de uma vez"
assert_logged "policy:${APP_KEYS[0]}:1"
assert_logged "policy:${APP_KEYS[1]}:1"

: > "$COMMAND_LOG"
print_header() { :; }
application_cache_menu() { printf '%s\n' prepare >> "$COMMAND_LOG"; }
application_menu() { printf '%s\n' install >> "$COMMAND_LOG"; }
printf '1\n2\n0\n' | applications_menu
assert_logged prepare
assert_logged install

printf 'OK: submenu de aplicativos\n'