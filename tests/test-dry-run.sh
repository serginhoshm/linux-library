#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/work" "$TEST_ROOT/state" "$TEST_ROOT/deb" "$TEST_ROOT/rpm"
export PATH="$TEST_ROOT/bin:$PATH"
export LINUX_SETUP_STATE_DIR="$TEST_ROOT/state"
export LINUX_SETUP_DEB_DIR="$TEST_ROOT/deb"
export LINUX_SETUP_RPM_DIR="$TEST_ROOT/rpm"

fail() {
  printf 'FALHOU: %s\n' "$*" >&2
  exit 1
}

for command_name in curl sudo apt-get dnf zypper; do
  cat > "$TEST_ROOT/bin/$command_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "chamado: $(basename "$0")" >> "${SIDE_EFFECT_LOG:?}"
exit 99
EOF
  chmod +x "$TEST_ROOT/bin/$command_name"
done
export SIDE_EFFECT_LOG="$TEST_ROOT/side-effects.log"
: > "$SIDE_EFFECT_LOG"

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
WORK_DIR="$TEST_ROOT/work"
DRY_RUN=1
PACKAGE_FAMILY=apt
load_app_catalog

resolve_external_package 0
[[ "$NATIVE_RESOLUTION_STATUS" == FOUND ]] || fail "fonte externa nao foi planejada"
download_native_package gearlever >/dev/null
begin_repository_transaction gearlever gearlever example.test
finish_repository_transaction
run_as_root apt-get install -y gearlever >/dev/null

[[ ! -s "$SIDE_EFFECT_LOG" ]] || fail "dry-run executou comando externo"
[[ ! -e "$STATE_DIR/repository-active" ]] || fail "dry-run gravou estado transacional"
[[ -z "$(find "$DEB_DIR" "$RPM_DIR" -type f -print -quit)" ]] || fail "dry-run gravou cache"

printf 'OK: dry-run\n'