#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/work"

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

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
WORK_DIR="$TEST_ROOT/work"
load_app_catalog
PACKAGE_FAMILY=apt
MOCK_HTTP_MODE=github

native_system_architecture() {
  printf '%s\n' amd64
}

http_get() {
  if [[ "${1:-}" == --output ]]; then
    printf '%s  pacote.deb\n' 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' > "$2"
    return 0
  fi
  case "$MOCK_HTTP_MODE" in
    github)
      printf '%s\n' '{"assets":[{"name":"gearlever_1.0_amd64.deb","browser_download_url":"https://example.test/gearlever_1.0_amd64.deb","digest":"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},{"name":"gearlever_1.0_amd64.deb.sha256","browser_download_url":"https://example.test/gearlever.sha256"}]}'
      ;;
    github-missing) printf '%s\n' '{"assets":[{"name":"gearlever.AppImage","browser_download_url":"https://example.test/gearlever.AppImage"}]}' ;;
    apt-index)
      printf '%s\n' 'Package: signal-desktop' 'Architecture: amd64' 'Version: 1.0' 'Filename: pool/s/signal-desktop_1.0_amd64.deb' 'SHA256: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' ''
      ;;
    slack-page)
      printf '%s\n' '<a href="https://downloads.slack-edge.com/desktop-releases/linux/x64/4.52.155/slack-desktop-4.52.155-amd64.deb">DEB</a>'
      ;;
  esac
}

gearlever_index=0
signal_index=3

resolve_external_package "$gearlever_index"
assert_equals FOUND "$NATIVE_RESOLUTION_STATUS" "GitHub deve encontrar DEB compativel"
assert_equals 'https://example.test/gearlever_1.0_amd64.deb' "$NATIVE_DOWNLOAD_URL" "URL GitHub"
assert_equals 'https://example.test/gearlever.sha256' "$NATIVE_CHECKSUM_URL" "checksum GitHub"
assert_equals 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' "$NATIVE_EXPECTED_SHA256" "digest GitHub"

MOCK_HTTP_MODE=github-missing
resolve_external_package "$gearlever_index"
assert_equals NOT_FOUND "$NATIVE_RESOLUTION_STATUS" "GitHub sem asset compativel"

MOCK_HTTP_MODE=apt-index
resolve_external_package "$signal_index"
assert_equals FOUND "$NATIVE_RESOLUTION_STATUS" "indice APT deve encontrar pacote"
assert_equals 'https://updates.signal.org/desktop/apt/pool/s/signal-desktop_1.0_amd64.deb' "$NATIVE_DOWNLOAD_URL" "URL do indice APT"
assert_equals 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' "$NATIVE_EXPECTED_SHA256" "SHA256 do indice APT"

printf abc > "$TEST_ROOT/pacote.deb"
verify_download_checksum "$TEST_ROOT/pacote.deb" 'https://example.test/pacote.sha256' || fail "checksum valido rejeitado"

PACKAGE_FAMILY=dnf
resolve_external_package 13
assert_equals NOT_FOUND "$NATIVE_RESOLUTION_STATUS" "DNF nao pode receber o DEB direto do Steam"

PACKAGE_FAMILY=apt
MOCK_HTTP_MODE=slack-page
resolve_external_package 4
assert_equals FOUND "$NATIVE_RESOLUTION_STATUS" "pagina do Slack deve fornecer DEB no APT"
assert_equals 'https://downloads.slack-edge.com/desktop-releases/linux/x64/4.52.155/slack-desktop-4.52.155-amd64.deb' "$NATIVE_DOWNLOAD_URL" "DEB extraido da pagina Slack"
PACKAGE_FAMILY=dnf
resolve_external_package 4
assert_equals NOT_FOUND "$NATIVE_RESOLUTION_STATUS" "pagina DEB do Slack deve ser rejeitada no DNF"

DRY_RUN=1
PACKAGE_FAMILY=apt
MOCK_HTTP_MODE=error
resolve_external_package "$gearlever_index"
assert_equals FOUND "$NATIVE_RESOLUTION_STATUS" "simulacao deve planejar fonte sem rede"

printf 'OK: resolucao externa\n'