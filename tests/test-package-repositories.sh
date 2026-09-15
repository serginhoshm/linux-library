#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/work" "$TEST_ROOT/state" "$TEST_ROOT/apt-sources" "$TEST_ROOT/apt-keys" \
  "$TEST_ROOT/apt-shared-keys" "$TEST_ROOT/dnf-repos" "$TEST_ROOT/zypper-repos"
export LINUX_SETUP_STATE_DIR="$TEST_ROOT/state"
export LINUX_SETUP_APT_SOURCE_DIR="$TEST_ROOT/apt-sources"
export LINUX_SETUP_APT_KEYRING_DIR="$TEST_ROOT/apt-keys"
export LINUX_SETUP_APT_SHARED_KEYRING_DIR="$TEST_ROOT/apt-shared-keys"
export LINUX_SETUP_DNF_REPO_DIR="$TEST_ROOT/dnf-repos"
export LINUX_SETUP_ZYPPER_REPO_DIR="$TEST_ROOT/zypper-repos"

fail() {
  printf 'FALHOU: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "arquivo deveria ter sido preservado: $1"
}

assert_absent() {
  [[ ! -e "$1" ]] || fail "arquivo deveria ter sido removido: $1"
}

assert_content() {
  [[ "$(cat "$1")" == "$2" ]] || fail "conteudo original nao foi restaurado: $1"
}

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
WORK_DIR="$TEST_ROOT/work"

run_as_root() {
  if [[ "$1" =~ ^(rm|cp)$ ]]; then
    "$@"
  else
    printf '%s\n' "$*" >> "$TEST_ROOT/metadata-refresh.log"
  fi
}

printf '%s\n' preexisting > "$APT_SOURCE_DIR/preexisting.sources"
printf '%s\n' 'URIs: https://brave.com/original' > "$APT_SOURCE_DIR/brave-existing.sources"
PACKAGE_FAMILY=apt
begin_repository_transaction brave brave-browser brave.com
printf '%s\n' 'URIs: https://brave.com/changed' > "$APT_SOURCE_DIR/brave-existing.sources"
printf '%s\n' 'URIs: https://brave.com/apt' > "$APT_SOURCE_DIR/brave-browser-release.sources"
printf '%s\n' key > "$APT_KEYRING_DIR/brave-browser-archive-keyring.gpg"
printf '%s\n' unrelated > "$APT_SOURCE_DIR/other.sources"
finish_repository_transaction
assert_file "$APT_SOURCE_DIR/preexisting.sources"
assert_content "$APT_SOURCE_DIR/brave-existing.sources" 'URIs: https://brave.com/original'
assert_file "$APT_SOURCE_DIR/other.sources"
assert_absent "$APT_SOURCE_DIR/brave-browser-release.sources"
assert_absent "$APT_KEYRING_DIR/brave-browser-archive-keyring.gpg"
grep -Fxq 'apt-get update' "$TEST_ROOT/metadata-refresh.log" || fail "APT nao atualizou metadados apos limpeza"

PACKAGE_FAMILY=dnf
begin_repository_transaction slack slack slack.com
printf '%s\n' '[slack]' > "$DNF_REPO_DIR/slack.repo"
finish_repository_transaction
assert_absent "$DNF_REPO_DIR/slack.repo"
grep -Fxq 'dnf makecache' "$TEST_ROOT/metadata-refresh.log" || fail "DNF nao atualizou metadados apos limpeza"

PACKAGE_FAMILY=zypper
begin_repository_transaction signal signal signal.org
printf '%s\n' '[signal]' > "$ZYPPER_REPO_DIR/signal.repo"
reconcile_repository_transaction
assert_absent "$ZYPPER_REPO_DIR/signal.repo"
assert_absent "$STATE_DIR/repository-active"
grep -Fxq 'zypper --non-interactive refresh' "$TEST_ROOT/metadata-refresh.log" || fail "Zypper nao atualizou metadados apos limpeza"

PACKAGE_FAMILY=apt
begin_repository_transaction spotify spotify-client spotify.com
printf '%s\n' 'URIs: https://spotify.com/apt' > "$APT_SOURCE_DIR/spotify.sources"
REMOVE_FAILURE=1
run_as_root() {
  if [[ "$1" == rm && "$REMOVE_FAILURE" -eq 1 ]]; then
    return 1
  fi
  if [[ "$1" =~ ^(rm|cp)$ ]]; then
    "$@"
  else
    printf '%s\n' "$*" >> "$TEST_ROOT/metadata-refresh.log"
  fi
}
if finish_repository_transaction; then
  fail "limpeza com remocao negada nao pode ser sucesso"
fi
assert_file "$STATE_DIR/repository-active"
assert_file "$APT_SOURCE_DIR/spotify.sources"
REMOVE_FAILURE=0
reconcile_repository_transaction
assert_absent "$STATE_DIR/repository-active"
assert_absent "$APT_SOURCE_DIR/spotify.sources"

printf 'OK: transacoes de repositorios\n'