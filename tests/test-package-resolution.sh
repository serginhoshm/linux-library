#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
export PATH="$TEST_ROOT/bin:$PATH"

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

cat > "$TEST_ROOT/bin/apt-cache" <<'EOF'
#!/usr/bin/env sh
case "${MOCK_RESULT:-found}" in
  found) printf '%s\n' 'chromium:' '  Candidate: 1.0' ;;
  missing) printf '%s\n' 'chromium:' '  Candidate: (none)' ;;
  error) exit 2 ;;
esac
EOF

cat > "$TEST_ROOT/bin/dnf" <<'EOF'
#!/usr/bin/env sh
case "${MOCK_RESULT:-found}" in
  found) printf '%s\n' 'flatseal' ;;
  missing) exit 0 ;;
  error) exit 1 ;;
esac
EOF

cat > "$TEST_ROOT/bin/zypper" <<'EOF'
#!/usr/bin/env sh
case "${MOCK_RESULT:-found}" in
  found) printf '%s\n' '<solvable status="not-installed" name="chromium" edition="1.0"/>' ;;
  missing) exit 104 ;;
  error) exit 4 ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/apt-cache" "$TEST_ROOT/bin/dnf" "$TEST_ROOT/bin/zypper"

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
load_app_catalog
assert_equals 18 "${#APP_KEYS[@]}" "catalogo unificado"

find_app_index() {
  local expected="$1"
  local index
  for index in "${!APP_KEYS[@]}"; do
    [[ "${APP_KEYS[$index]}" == "$expected" ]] && {
      printf '%s\n' "$index"
      return 0
    }
  done
  return 1
}

chromium_index="$(find_app_index chromium)"
flatseal_index="$(find_app_index flatseal)"
flatpak_only_index="$(find_app_index 4ktube)"
slack_index="$(find_app_index slack)"

PACKAGE_FAMILY=apt
MOCK_RESULT=found resolve_native_package "$chromium_index"
assert_equals FOUND "$NATIVE_RESOLUTION_STATUS" "APT deve encontrar candidato exato"
assert_equals chromium "$NATIVE_RESOLUTION_PACKAGE" "APT deve retornar nome do pacote"
MOCK_RESULT=missing resolve_native_package "$chromium_index"
assert_equals NOT_FOUND "$NATIVE_RESOLUTION_STATUS" "APT deve distinguir pacote ausente"
MOCK_RESULT=error resolve_native_package "$chromium_index"
assert_equals ERROR "$NATIVE_RESOLUTION_STATUS" "APT deve distinguir erro operacional"

PACKAGE_FAMILY=dnf
MOCK_RESULT=found resolve_native_package "$flatseal_index"
assert_equals FOUND "$NATIVE_RESOLUTION_STATUS" "DNF deve encontrar candidato exato"
MOCK_RESULT=missing resolve_native_package "$flatseal_index"
assert_equals NOT_FOUND "$NATIVE_RESOLUTION_STATUS" "DNF deve distinguir pacote ausente"
MOCK_RESULT=error resolve_native_package "$flatseal_index"
assert_equals ERROR "$NATIVE_RESOLUTION_STATUS" "DNF deve distinguir erro operacional"

PACKAGE_FAMILY=zypper
MOCK_RESULT=found resolve_native_package "$chromium_index"
assert_equals FOUND "$NATIVE_RESOLUTION_STATUS" "Zypper deve encontrar candidato exato"
MOCK_RESULT=missing resolve_native_package "$chromium_index"
assert_equals NOT_FOUND "$NATIVE_RESOLUTION_STATUS" "Zypper deve distinguir pacote ausente"
MOCK_RESULT=error resolve_native_package "$chromium_index"
assert_equals ERROR "$NATIVE_RESOLUTION_STATUS" "Zypper deve distinguir erro operacional"

PACKAGE_FAMILY=apt
MOCK_RESULT=error resolve_native_package "$flatpak_only_index"
assert_equals ERROR "$NATIVE_RESOLUTION_STATUS" "busca avancada deve consultar aliases mesmo sem pacote principal"

MOCK_RESULT=missing resolve_native_package "$slack_index"
assert_equals NOT_FOUND "$NATIVE_RESOLUTION_STATUS" "Slack ausente nao pode aceitar pacote homonimo sem relacao"
assert_equals slack-desktop "$(native_package_for_app "$slack_index")" "nome nativo do Slack"

printf 'OK: resolucao de pacotes\n'