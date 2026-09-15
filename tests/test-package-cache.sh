#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/work" "$TEST_ROOT/deb" "$TEST_ROOT/rpm"
export PATH="$TEST_ROOT/bin:$PATH"
export LINUX_SETUP_DEB_DIR="$TEST_ROOT/deb"
export LINUX_SETUP_RPM_DIR="$TEST_ROOT/rpm"

fail() {
  printf 'FALHOU: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "arquivo esperado nao existe: $1"
}

assert_absent() {
  [[ ! -e "$1" ]] || fail "arquivo antigo nao foi removido: $1"
}

cat > "$TEST_ROOT/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == download ]] || exit 2
touch "${2}_1.0_amd64.deb"
EOF

cat > "$TEST_ROOT/bin/dpkg" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == --print-architecture ]] || exit 2
printf '%s\n' amd64
EOF

cat > "$TEST_ROOT/bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
path="$2"
case "$path" in
  *chromium*) printf '%s\n' chromium amd64 ;;
  *) exit 2 ;;
esac
EOF

cat > "$TEST_ROOT/bin/dnf" <<'EOF'
#!/usr/bin/env bash
destination=""
package=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --destdir) destination="$2"; shift 2 ;;
    --arch) shift 2 ;;
    -q|download) shift ;;
    *) package="$1"; shift ;;
  esac
done
[[ -n "$destination" && -n "$package" ]] || exit 2
touch "$destination/${package}-1.0.x86_64.rpm"
EOF

cat > "$TEST_ROOT/bin/zypper" <<'EOF'
#!/usr/bin/env bash
destination=""
package=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --directory) destination="$2"; shift 2 ;;
    --non-interactive|download) shift ;;
    *) package="$1"; shift ;;
  esac
done
[[ -n "$destination" && -n "$package" ]] || exit 2
touch "$destination/${package}-1.0.x86_64.rpm"
EOF

cat > "$TEST_ROOT/bin/rpm" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == --eval ]]; then
  printf '%s\n' x86_64
  exit 0
fi
path="${@: -1}"
case "$path" in
  *flatseal*) printf '%s' 'flatseal x86_64' ;;
  *chromium*) printf '%s' 'chromium x86_64' ;;
  *) exit 2 ;;
esac
EOF
cat > "$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' curl-called >> "${HTTP_LOG:?}"
exit 2
EOF
chmod +x "$TEST_ROOT/bin/apt-get" "$TEST_ROOT/bin/dpkg" "$TEST_ROOT/bin/dpkg-deb" \
  "$TEST_ROOT/bin/dnf" "$TEST_ROOT/bin/zypper" "$TEST_ROOT/bin/rpm" "$TEST_ROOT/bin/curl"

# shellcheck source=../linux-setup.sh
source "$(dirname "$0")/../linux-setup.sh"
WORK_DIR="$TEST_ROOT/work"

touch "$DEB_DIR/chromium_0.9_amd64.deb"
PACKAGE_FAMILY=apt
download_native_package chromium
assert_file "$DEB_DIR/chromium_1.0_amd64.deb"
assert_absent "$DEB_DIR/chromium_0.9_amd64.deb"
[[ "$NATIVE_CACHE_PATH" == "$DEB_DIR/chromium_1.0_amd64.deb" ]] || fail "caminho APT incorreto"

export HTTP_LOG="$TEST_ROOT/http.log"
: > "$HTTP_LOG"
NATIVE_RESOLUTION_METHOD=external
NATIVE_DOWNLOAD_URL='https://example.test/chromium_1.0_amd64.deb'
NATIVE_EXPECTED_SHA256='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
download_native_package chromium
[[ "$NATIVE_CACHE_PATH" == "$DEB_DIR/chromium_1.0_amd64.deb" ]] || fail "cache externo validado nao foi reutilizado"
[[ ! -s "$HTTP_LOG" ]] || fail "cache externo validado nao pode acessar a rede"
NATIVE_RESOLUTION_METHOD=""
NATIVE_EXPECTED_SHA256=""

printf '!<arch>\n' > "$DEB_DIR/chromium_1.0_amd64.deb"
: > "$HTTP_LOG"
NATIVE_RESOLUTION_METHOD=catalog
NATIVE_DOWNLOAD_URL='https://example.test/chromium_1.0_amd64.deb'
NATIVE_RESOLUTION_VERSION=""
download_resolved_cache_asset chromium apt
[[ "$NATIVE_CACHE_PATH" == "$DEB_DIR/chromium_1.0_amd64.deb" ]] || fail "cache sem checksum nao foi reutilizado"
[[ ! -s "$HTTP_LOG" ]] || fail "cache sem checksum nao pode acessar a rede"
NATIVE_RESOLUTION_METHOD=""
NATIVE_RESOLUTION_VERSION=""

touch "$RPM_DIR/flatseal-0.9.x86_64.rpm"
PACKAGE_FAMILY=dnf
download_native_package flatseal
assert_file "$RPM_DIR/flatseal-1.0.x86_64.rpm"
assert_absent "$RPM_DIR/flatseal-0.9.x86_64.rpm"

PACKAGE_FAMILY=zypper
download_native_package chromium
assert_file "$RPM_DIR/chromium-1.0.x86_64.rpm"

PACKAGE_FAMILY=apt
DRY_RUN=1
download_native_package chromium >/dev/null
[[ "$NATIVE_CACHE_PATH" == "$DEB_DIR/chromium.DRY-RUN.deb" ]] || fail "cache simulado incorreto"

printf 'OK: cache de pacotes\n'