#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_NAME="Linux Setup"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly APP_LIBRARY="${LINUX_SETUP_APP_LIBRARY:-$SCRIPT_DIR/apps}"
readonly CATALOG_TOOL="$SCRIPT_DIR/catalog-tool.py"
readonly DEB_DIR="${LINUX_SETUP_DEB_DIR:-$SCRIPT_DIR/deb}"
readonly RPM_DIR="${LINUX_SETUP_RPM_DIR:-$SCRIPT_DIR/rpm}"
readonly LOG_DIR="${LINUX_SETUP_LOG_DIR:-$SCRIPT_DIR/logs}"
readonly STATE_DIR="${LINUX_SETUP_STATE_DIR:-$SCRIPT_DIR/.linux-setup-state}"
readonly APT_SOURCE_DIR="${LINUX_SETUP_APT_SOURCE_DIR:-/etc/apt/sources.list.d}"
readonly APT_KEYRING_DIR="${LINUX_SETUP_APT_KEYRING_DIR:-/etc/apt/keyrings}"
readonly APT_SHARED_KEYRING_DIR="${LINUX_SETUP_APT_SHARED_KEYRING_DIR:-/usr/share/keyrings}"
readonly DNF_REPO_DIR="${LINUX_SETUP_DNF_REPO_DIR:-/etc/yum.repos.d}"
readonly ZYPPER_REPO_DIR="${LINUX_SETUP_ZYPPER_REPO_DIR:-/etc/zypp/repos.d}"
readonly GRUB_DEFAULT_FILE="${LINUX_SETUP_GRUB_DEFAULT_FILE:-/etc/default/grub}"
readonly GRUB_DROPIN_DIR="${LINUX_SETUP_GRUB_DROPIN_DIR:-/etc/default/grub.d}"
readonly GRUB_SPLASH_DROPIN="$GRUB_DROPIN_DIR/99-linux-setup-splash.cfg"
readonly GRUB_CONFIG_FILE="${LINUX_SETUP_GRUB_CONFIG_FILE:-/boot/grub/grub.cfg}"
readonly UPDATE_GRUB_COMMAND="${LINUX_SETUP_UPDATE_GRUB_COMMAND:-/usr/sbin/update-grub}"
readonly UPDATE_INITRAMFS_COMMAND="${LINUX_SETUP_UPDATE_INITRAMFS_COMMAND:-/usr/sbin/update-initramfs}"
DRY_RUN="${LINUX_SETUP_DRY_RUN:-0}"
TEST_PACKAGE_FAMILY="${LINUX_SETUP_TEST_FAMILY:-}"
WORK_DIR=""
LOG_FILE=""

PACKAGE_FAMILY=""
DISTRO_NAME=""
DISTRO_VERSION=""
PACKAGE_METADATA_UPDATED=0
CHECKLIST_RESULT=()
NFS_DISCOVERED_REMOTES=()
NFS_DISCOVERED_MOUNTS=()
NFS_SELECTED_REMOTE=""
NFS_SELECTED_MOUNT=""
FLATPAK_IDS=()
FLATPAK_LABELS=()
APP_KEYS=()
APP_DESCRIPTIONS=()
APP_NATIVE_APT=()
APP_NATIVE_DNF=()
APP_NATIVE_ZYPPER=()
APP_DEB_DISCOVERY_TYPES=()
APP_DEB_DISCOVERY_SOURCES=()
APP_RPM_DISCOVERY_TYPES=()
APP_RPM_DISCOVERY_SOURCES=()
APP_ALIASES=()
APP_DEB_URLS=()
APP_DEB_VERSIONS=()
APP_DEB_SHA256=()
APP_DEB_CHECKSUM_URLS=()
APP_RPM_URLS=()
APP_RPM_VERSIONS=()
APP_RPM_SHA256=()
APP_RPM_CHECKSUM_URLS=()
APP_FLATPAK_SOURCE_TYPES=()
APP_FLATPAK_REMOTE_NAMES=()
APP_FLATPAK_REPOSITORY_URLS=()
APP_FLATPAK_REFS=()
NATIVE_RESOLUTION_STATUS=""
NATIVE_RESOLUTION_PACKAGE=""
NATIVE_RESOLUTION_METHOD=""
NATIVE_DOWNLOAD_URL=""
NATIVE_CHECKSUM_URL=""
NATIVE_EXPECTED_SHA256=""
NATIVE_RESOLUTION_VERSION=""
NATIVE_SOURCE_HOST=""
NATIVE_CACHE_PATH=""

die() {
  printf 'Erro: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[AVISO] %s\n' "$*" >&2
}

start_logging() {
  local timestamp

  mkdir -p -- "$LOG_DIR" || die "Nao foi possivel criar o diretorio de logs: $LOG_DIR"
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  LOG_FILE="${LINUX_SETUP_LOG_FILE:-$LOG_DIR/linux-setup-${timestamp}-$$.log}"
  touch "$LOG_FILE" || die "Nao foi possivel criar o log: $LOG_FILE"
  chmod 0600 "$LOG_FILE"
  ln -sfn -- "$(basename "$LOG_FILE")" "$LOG_DIR/latest.log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  printf '[LOG] inicio=%s pid=%s dry_run=%s arquivo=%s\n' "$timestamp" "$$" "$DRY_RUN" "$LOG_FILE"
}

log_event() {
  local event="$1"
  local status="$2"
  local detail="${3:-}"

  detail="${detail//$'\t'/ }"
  detail="${detail//$'\n'/ }"
  printf '[EVENT]\t%s\t%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$event" "$status" "$detail"
}

pause() {
  [[ -t 0 ]] || return 0
  read -r -p "Pressione Enter para continuar..." _
}

cleanup() {
  local status=$?
  [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
  [[ -z "$LOG_FILE" ]] || log_event execution "$status" "encerramento"
  return "$status"
}

repository_directories() {
  case "$PACKAGE_FAMILY" in
    apt) printf '%s\n' "$APT_SOURCE_DIR" "$APT_KEYRING_DIR" "$APT_SHARED_KEYRING_DIR" ;;
    dnf) printf '%s\n' "$DNF_REPO_DIR" ;;
    zypper) printf '%s\n' "$ZYPPER_REPO_DIR" ;;
  esac
}

repository_snapshot() {
  local directory

  while IFS= read -r directory; do
    [[ -d "$directory" ]] || continue
    find "$directory" -maxdepth 1 -type f -printf '%p\n'
  done < <(repository_directories) | LC_ALL=C sort -u
}

repository_artifact_matches_transaction() {
  local path="$1"
  local app_key="$2"
  local package="$3"
  local source_host="$4"
  local basename_lower

  basename_lower="$(basename "$path" | tr '[:upper:]' '[:lower:]')"
  [[ "$basename_lower" == *"${app_key,,}"* ]] && return 0
  [[ -n "$package" && "$basename_lower" == *"${package,,}"* ]] && return 0
  [[ -n "$source_host" ]] && grep -aFqi -- "$source_host" "$path" 2>/dev/null
}

begin_repository_transaction() {
  local app_key="$1"
  local package="$2"
  local source_host="${3:-}"
  local path index=0 backup

  if [[ "$DRY_RUN" == "1" ]]; then
    info "[SIMULACAO] Iniciar rastreamento de fontes para $app_key."
    return 0
  fi
  mkdir -p -- "$STATE_DIR"
  rm -rf -- "$STATE_DIR/repository-originals"
  mkdir -p -- "$STATE_DIR/repository-originals"
  repository_snapshot > "$STATE_DIR/repository-before"
  : > "$STATE_DIR/repository-original-manifest"
  while IFS= read -r path; do
    [[ -f "$path" ]] || continue
    backup="$STATE_DIR/repository-originals/$index"
    cp -a -- "$path" "$backup"
    printf '%s\t%s\t%s\n' "$(sha256sum "$path" | awk '{print $1}')" "$path" "$backup" \
      >> "$STATE_DIR/repository-original-manifest"
    index=$((index + 1))
  done < "$STATE_DIR/repository-before"
  printf '%s\t%s\t%s\n' "$app_key" "$package" "$source_host" > "$STATE_DIR/repository-active"
  chmod 0600 "$STATE_DIR/repository-before" "$STATE_DIR/repository-original-manifest" \
    "$STATE_DIR/repository-active"
}

finish_repository_transaction() {
  local app_key package source_host current path original_hash current_hash backup
  local removed=0
  local restored=0
  local cleanup_failed=0

  if [[ "$DRY_RUN" == "1" ]]; then
    info "[SIMULACAO] Remover somente fontes novas relacionadas ao aplicativo."
    return 0
  fi
  [[ -r "$STATE_DIR/repository-active" && -r "$STATE_DIR/repository-before" ]] || return 0
  IFS=$'\t' read -r app_key package source_host < "$STATE_DIR/repository-active"
  current="$(make_temp)"
  repository_snapshot > "$current"
  if [[ -r "$STATE_DIR/repository-original-manifest" ]]; then
    while IFS=$'\t' read -r original_hash path backup; do
      if [[ ! -f "$path" ]]; then
        info "Restaurando fonte preexistente removida durante a instalacao: $path"
        if run_as_root cp -a -- "$backup" "$path"; then
          restored=1
        else
          warn "Nao foi possivel restaurar $path"
          cleanup_failed=1
        fi
        continue
      fi
      current_hash="$(sha256sum "$path" | awk '{print $1}')" || {
        cleanup_failed=1
        continue
      }
      [[ "$current_hash" == "$original_hash" ]] && continue
      if repository_artifact_matches_transaction "$path" "$app_key" "$package" "$source_host"; then
        info "Restaurando conteudo preexistente alterado durante a instalacao: $path"
        if run_as_root cp -a -- "$backup" "$path"; then
          restored=1
        else
          warn "Nao foi possivel restaurar $path"
          cleanup_failed=1
        fi
      else
        warn "Fonte preexistente alterada foi preservada por nao corresponder a $app_key: $path"
      fi
    done < "$STATE_DIR/repository-original-manifest"
  fi
  while IFS= read -r path; do
    [[ -f "$path" ]] || continue
    if repository_artifact_matches_transaction "$path" "$app_key" "$package" "$source_host"; then
      info "Removendo fonte de atualizacao criada durante a instalacao: $path"
      if run_as_root rm -f -- "$path"; then
        removed=1
      else
        warn "Nao foi possivel remover $path"
        cleanup_failed=1
      fi
    else
      warn "Novo arquivo de repositorio preservado por nao corresponder a $app_key: $path"
    fi
  done < <(comm -13 "$STATE_DIR/repository-before" "$current")
  rm -f -- "$current"
  if [[ "$removed" -eq 1 || "$restored" -eq 1 ]]; then
    info "Atualizando metadados apos remover fontes temporarias."
    case "$PACKAGE_FAMILY" in
      apt) run_as_root apt-get update || warn "Falha ao atualizar metadados APT apos a limpeza." ;;
      dnf) run_as_root dnf makecache || warn "Falha ao atualizar metadados DNF apos a limpeza." ;;
      zypper) run_as_root zypper --non-interactive refresh || warn "Falha ao atualizar metadados Zypper apos a limpeza." ;;
    esac
  fi
  if [[ "$cleanup_failed" -eq 1 ]]; then
    warn "A transacao de repositorio permanece pendente para nova tentativa."
    return 1
  fi
  rm -rf -- "$STATE_DIR/repository-active" "$STATE_DIR/repository-before" \
    "$STATE_DIR/repository-original-manifest" "$STATE_DIR/repository-originals"
}

reconcile_repository_transaction() {
  [[ -r "$STATE_DIR/repository-active" ]] || return 0
  warn "Foi encontrada uma transacao de repositorio interrompida; iniciando limpeza seletiva."
  finish_repository_transaction || die "Nao foi possivel concluir a limpeza da transacao anterior."
}

make_temp() {
  mktemp "$WORK_DIR/file.XXXXXX"
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

load_app_catalog() {
  local catalog_output
  local key id label description apt_package dnf_package zypper_package
  local deb_type deb_source rpm_type rpm_source aliases
  local deb_url deb_version deb_sha256 deb_checksum_url
  local rpm_url rpm_version rpm_sha256 rpm_checksum_url
  local flatpak_source_type flatpak_remote flatpak_repository_url flatpak_ref

  [[ -x "$CATALOG_TOOL" || -r "$CATALOG_TOOL" ]] ||
    die "Ferramenta do catalogo nao encontrada: $CATALOG_TOOL"
  catalog_output="$(python3 "$CATALOG_TOOL" export-tsv "$APP_LIBRARY")" ||
    die "Nao foi possivel carregar a biblioteca: $APP_LIBRARY"
  APP_KEYS=()
  FLATPAK_IDS=()
  FLATPAK_LABELS=()
  APP_DESCRIPTIONS=()
  APP_NATIVE_APT=()
  APP_NATIVE_DNF=()
  APP_NATIVE_ZYPPER=()
  APP_DEB_DISCOVERY_TYPES=()
  APP_DEB_DISCOVERY_SOURCES=()
  APP_RPM_DISCOVERY_TYPES=()
  APP_RPM_DISCOVERY_SOURCES=()
  APP_ALIASES=()
  APP_DEB_URLS=()
  APP_DEB_VERSIONS=()
  APP_DEB_SHA256=()
  APP_DEB_CHECKSUM_URLS=()
  APP_RPM_URLS=()
  APP_RPM_VERSIONS=()
  APP_RPM_SHA256=()
  APP_RPM_CHECKSUM_URLS=()
  APP_FLATPAK_SOURCE_TYPES=()
  APP_FLATPAK_REMOTE_NAMES=()
  APP_FLATPAK_REPOSITORY_URLS=()
  APP_FLATPAK_REFS=()
  while IFS='|' read -r key id label description apt_package dnf_package zypper_package \
    deb_type deb_source rpm_type rpm_source aliases deb_url deb_version deb_sha256 deb_checksum_url \
    rpm_url rpm_version rpm_sha256 rpm_checksum_url flatpak_source_type flatpak_remote \
    flatpak_repository_url flatpak_ref || [[ -n "${key:-}" ]]; do
    APP_KEYS+=("$key")
    FLATPAK_IDS+=("$id")
    FLATPAK_LABELS+=("$label")
    APP_DESCRIPTIONS+=("$description")
    APP_NATIVE_APT+=("$apt_package")
    APP_NATIVE_DNF+=("$dnf_package")
    APP_NATIVE_ZYPPER+=("$zypper_package")
    APP_DEB_DISCOVERY_TYPES+=("$deb_type")
    APP_DEB_DISCOVERY_SOURCES+=("$deb_source")
    APP_RPM_DISCOVERY_TYPES+=("$rpm_type")
    APP_RPM_DISCOVERY_SOURCES+=("$rpm_source")
    APP_ALIASES+=("$aliases")
    APP_DEB_URLS+=("$deb_url")
    APP_DEB_VERSIONS+=("$deb_version")
    APP_DEB_SHA256+=("$deb_sha256")
    APP_DEB_CHECKSUM_URLS+=("$deb_checksum_url")
    APP_RPM_URLS+=("$rpm_url")
    APP_RPM_VERSIONS+=("$rpm_version")
    APP_RPM_SHA256+=("$rpm_sha256")
    APP_RPM_CHECKSUM_URLS+=("$rpm_checksum_url")
    APP_FLATPAK_SOURCE_TYPES+=("$flatpak_source_type")
    APP_FLATPAK_REMOTE_NAMES+=("$flatpak_remote")
    APP_FLATPAK_REPOSITORY_URLS+=("$flatpak_repository_url")
    APP_FLATPAK_REFS+=("$flatpak_ref")
  done <<< "$catalog_output"
  [[ ${#APP_KEYS[@]} -gt 0 ]] || die "O catalogo nao contem aplicativos validos."
}

native_package_for_app() {
  local index="$1"

  case "$PACKAGE_FAMILY" in
    apt) printf '%s\n' "${APP_NATIVE_APT[$index]}" ;;
    dnf) printf '%s\n' "${APP_NATIVE_DNF[$index]}" ;;
    zypper) printf '%s\n' "${APP_NATIVE_ZYPPER[$index]}" ;;
  esac
}

resolve_native_package() {
  local index="$1"
  local package alias aliases
  local -a alias_candidates=()

  NATIVE_RESOLUTION_STATUS="NOT_FOUND"
  NATIVE_RESOLUTION_PACKAGE=""
  NATIVE_RESOLUTION_METHOD=""
  NATIVE_DOWNLOAD_URL=""
  NATIVE_CHECKSUM_URL=""
  NATIVE_EXPECTED_SHA256=""
  NATIVE_SOURCE_HOST=""
  package="$(native_package_for_app "$index")"
  aliases="${APP_ALIASES[$index]}"
  if [[ -n "$package" ]]; then
    query_native_repository "$package"
    [[ "$NATIVE_RESOLUTION_STATUS" != "NOT_FOUND" ]] && return 0
  fi
  IFS=';' read -r -a alias_candidates <<< "$aliases"
  for alias in "${alias_candidates[@]}"; do
    [[ -n "$alias" && "$alias" != "$package" ]] || continue
    query_native_repository "$alias"
    [[ "$NATIVE_RESOLUTION_STATUS" != "NOT_FOUND" ]] && return 0
  done
  return 0
}

query_native_repository() {
  local package="$1"
  local output status

  NATIVE_RESOLUTION_STATUS="NOT_FOUND"
  NATIVE_RESOLUTION_PACKAGE=""

  case "$PACKAGE_FAMILY" in
    apt)
      if ! output="$(LC_ALL=C apt-cache policy "$package" 2>&1)"; then
        NATIVE_RESOLUTION_STATUS="ERROR"
        return 0
      fi
      if grep -Eq '^[[:space:]]*Candidate:[[:space:]]+[^[:space:]]+' <<< "$output" &&
        ! grep -Eq '^[[:space:]]*Candidate:[[:space:]]+\(none\)' <<< "$output"; then
        NATIVE_RESOLUTION_STATUS="FOUND"
        NATIVE_RESOLUTION_METHOD="repository"
      fi
      ;;
    dnf)
      if ! output="$(LC_ALL=C dnf -q repoquery --available --latest-limit 1 --qf '%{name}' "$package" 2>&1)"; then
        NATIVE_RESOLUTION_STATUS="ERROR"
        return 0
      fi
      if grep -Fxq "$package" <<< "$output"; then
        NATIVE_RESOLUTION_STATUS="FOUND"
        NATIVE_RESOLUTION_METHOD="repository"
      fi
      ;;
    zypper)
      if output="$(LC_ALL=C zypper --xmlout --non-interactive search --match-exact --type package "$package" 2>&1)"; then
        if grep -Fq "name=\"$package\"" <<< "$output" || grep -Fq "name='$package'" <<< "$output"; then
          NATIVE_RESOLUTION_STATUS="FOUND"
          NATIVE_RESOLUTION_METHOD="repository"
        fi
      else
        status=$?
        [[ "$status" -eq 104 ]] || NATIVE_RESOLUTION_STATUS="ERROR"
        return 0
      fi
      ;;
  esac

  [[ "$NATIVE_RESOLUTION_STATUS" == "FOUND" ]] && NATIVE_RESOLUTION_PACKAGE="$package"
  return 0
}

http_get() {
  local -a headers=(--header 'User-Agent: linux-setup')
  [[ -z "${GITHUB_TOKEN:-}" ]] || headers+=(--header "Authorization: Bearer $GITHUB_TOKEN")
  curl --fail --location --silent --show-error --connect-timeout 10 --max-time 120 --retry 2 \
    "${headers[@]}" "$@"
}

architecture_asset_tokens() {
  local architecture
  architecture="$(native_system_architecture)" || return 1
  case "$architecture" in
    amd64|x86_64) printf '%s\n' 'amd64,x86_64,x64,all,noarch' ;;
    arm64|aarch64) printf '%s\n' 'arm64,aarch64,all,noarch' ;;
    *) printf '%s\n' "$architecture,all,noarch" ;;
  esac
}

resolve_github_release() {
  local repository="$1"
  local extension tokens response result

  command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || return 2
  case "$PACKAGE_FAMILY" in
    apt) extension=.deb ;;
    dnf|zypper) extension=.rpm ;;
  esac
  tokens="$(architecture_asset_tokens)" || return 2
  response="$(http_get "https://api.github.com/repos/$repository/releases/latest")" || return 2
  result="$(python3 -c '
import json, re, sys
extension, tokens = sys.argv[1], sys.argv[2].lower().split(",")
data = json.load(sys.stdin)
assets = data.get("assets", [])
blocked = ("debug", "devel", "dbgsym", "symbols")
candidates = []
for asset in assets:
    name = asset.get("name", "").lower()
    if not name.endswith(extension) or any(word in name for word in blocked):
        continue
    if any(re.search(r"(?:^|[._+-])" + re.escape(token) + r"(?:[._+-]|$)", name) for token in tokens):
        candidates.append(asset)
if not candidates:
    raise SystemExit(3)
selected = candidates[0]
name = selected.get("name", "")
checksum = ""
digest = selected.get("digest", "") or ""
for asset in assets:
    asset_name = asset.get("name", "")
    if asset_name in (name + ".sha256", name + ".sha256sum"):
        checksum = asset.get("browser_download_url", "")
        break
if digest.startswith("sha256:"):
    digest = digest.removeprefix("sha256:")
else:
    digest = ""
print("|".join((selected.get("browser_download_url", ""), checksum, digest, data.get("tag_name", ""))))
' "$extension" "$tokens" <<< "$response")" || return $?
  IFS='|' read -r NATIVE_DOWNLOAD_URL NATIVE_CHECKSUM_URL NATIVE_EXPECTED_SHA256 NATIVE_RESOLUTION_VERSION <<< "$result"
  [[ "$NATIVE_DOWNLOAD_URL" == https://* ]] || return 2
}

resolve_apt_index() {
  local specification="$1"
  local package="$2"
  local index_url base_url architecture content result relative_path

  [[ "$PACKAGE_FAMILY" == "apt" ]] || return 3
  command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || return 2
  specification="${specification#apt-index:}"
  index_url="${specification%%;*}"
  base_url="${specification#*;}"
  architecture="$(native_system_architecture)" || return 2
  content="$(http_get "$index_url")" || return 2
  result="$(python3 -c '
import sys
package, architecture = sys.argv[1:]
for block in sys.stdin.read().split("\n\n"):
    fields = {}
    for line in block.splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            fields[key] = value
    if fields.get("Package") == package and fields.get("Architecture") in (architecture, "all"):
      print("|".join((fields.get("Filename", ""), fields.get("SHA256", ""), fields.get("Version", ""))))
    raise SystemExit(0)
' "$package" "$architecture" <<< "$content")" || return 2
      IFS='|' read -r relative_path NATIVE_EXPECTED_SHA256 NATIVE_RESOLUTION_VERSION <<< "$result"
  [[ -n "$relative_path" ]] || return 3
  NATIVE_DOWNLOAD_URL="${base_url%/}/${relative_path#/}"
  [[ "$NATIVE_DOWNLOAD_URL" == https://* ]] || return 2
}

resolve_deb_download_page() {
  local page_url="$1"
  local content result

  [[ "$PACKAGE_FAMILY" == "apt" ]] || return 3
  command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || return 2
  content="$(http_get "$page_url")" || return 2
  result="$(python3 -c '
import html, re, sys
content = html.unescape(sys.stdin.read()).replace("\\/", "/")
urls = re.findall(r"https://downloads\.slack-edge\.com/[^\"\x27<>\s]+\.deb", content)
if not urls:
    raise SystemExit(3)
print(urls[0])
' <<< "$content")" || return $?
  NATIVE_DOWNLOAD_URL="$result"
  [[ "$NATIVE_DOWNLOAD_URL" =~ ^https://downloads\.slack-edge\.com/.+\.deb$ ]] || return 2
}

resolve_external_package() {
  local index="$1"
  local package resolver source result

  NATIVE_RESOLUTION_STATUS="NOT_FOUND"
  NATIVE_RESOLUTION_PACKAGE=""
  NATIVE_RESOLUTION_METHOD=""
  NATIVE_DOWNLOAD_URL=""
  NATIVE_CHECKSUM_URL=""
  NATIVE_EXPECTED_SHA256=""
  NATIVE_RESOLUTION_VERSION=""
  NATIVE_SOURCE_HOST=""
  package="$(native_package_for_app "$index")"
  case "$PACKAGE_FAMILY" in
    apt)
      resolver="${APP_DEB_DISCOVERY_TYPES[$index]}"
      source="${APP_DEB_DISCOVERY_SOURCES[$index]}"
      ;;
    dnf|zypper)
      resolver="${APP_RPM_DISCOVERY_TYPES[$index]}"
      source="${APP_RPM_DISCOVERY_SOURCES[$index]}"
      ;;
  esac
  [[ -n "$package" && "$resolver" != "none" ]] || return 0

  if [[ "$DRY_RUN" == "1" ]]; then
    NATIVE_RESOLUTION_STATUS="FOUND"
    NATIVE_RESOLUTION_PACKAGE="$package"
    NATIVE_RESOLUTION_METHOD="external"
    NATIVE_DOWNLOAD_URL="${source%%;*}"
    NATIVE_SOURCE_HOST="simulacao"
    return 0
  fi

  result=0
  case "$resolver:$source" in
    github:*) resolve_github_release "$source" || result=$? ;;
    direct:https://*)
      NATIVE_DOWNLOAD_URL="$source"
      case "$PACKAGE_FAMILY:$NATIVE_DOWNLOAD_URL" in
        apt:*.deb|dnf:*.rpm|zypper:*.rpm) ;;
        *) result=3 ;;
      esac
      ;;
    page-deb:https://*) resolve_deb_download_page "$source" || result=$? ;;
    redirect-deb:https://*)
      [[ "$PACKAGE_FAMILY" == "apt" ]] && NATIVE_DOWNLOAD_URL="$source" || result=3
      ;;
    redirect-rpm:https://*)
      [[ "$PACKAGE_FAMILY" =~ ^(dnf|zypper)$ ]] && NATIVE_DOWNLOAD_URL="$source" || result=3
      ;;
    apt-index:https://*) resolve_apt_index "apt-index:$source" "$package" || result=$? ;;
    manual:*) result=3 ;;
    *) result=2 ;;
  esac
  case "$result" in
    0)
      NATIVE_RESOLUTION_STATUS="FOUND"
      NATIVE_RESOLUTION_PACKAGE="$package"
      NATIVE_RESOLUTION_METHOD="external"
      NATIVE_SOURCE_HOST="${NATIVE_DOWNLOAD_URL#https://}"
      NATIVE_SOURCE_HOST="${NATIVE_SOURCE_HOST%%/*}"
      ;;
    3) NATIVE_RESOLUTION_STATUS="NOT_FOUND" ;;
    *) NATIVE_RESOLUTION_STATUS="ERROR" ;;
  esac
}

resolve_app_package() {
  local index="$1"

  resolve_native_package "$index"
  [[ "$NATIVE_RESOLUTION_STATUS" == "NOT_FOUND" ]] || return 0
  resolve_external_package "$index"
}

verify_download_checksum() {
  local path="$1"
  local checksum_url="$2"
  local checksum_file expected actual

  if [[ -n "$NATIVE_EXPECTED_SHA256" ]]; then
    actual="$(sha256sum "$path" | awk '{print $1}')" || return 1
    [[ "${actual,,}" == "${NATIVE_EXPECTED_SHA256,,}" ]]
    return
  fi
  [[ -n "$checksum_url" ]] || {
    info "Checksum oficial nao publicado; confianca limitada a HTTPS e validacao do pacote."
    return 0
  }
  checksum_file="$(make_temp)"
  http_get --output "$checksum_file" "$checksum_url" || return 1
  expected="$(grep -Eio '[a-f0-9]{64}' "$checksum_file" | head -n 1)"
  [[ -n "$expected" ]] || return 1
  actual="$(sha256sum "$path" | awk '{print $1}')" || return 1
  [[ "${actual,,}" == "${expected,,}" ]]
}

find_verified_cached_package() {
  local directory="$1"
  local extension="$2"
  local package="$3"
  local path

  [[ "$NATIVE_RESOLUTION_METHOD" == "external" ]] || return 1
  [[ -n "$NATIVE_EXPECTED_SHA256" || -n "$NATIVE_CHECKSUM_URL" ]] || return 1
  while IFS= read -r -d '' path; do
    native_package_is_compatible "$path" "$package" || continue
    if verify_download_checksum "$path" "$NATIVE_CHECKSUM_URL"; then
      NATIVE_CACHE_PATH="$path"
      return 0
    fi
  done < <(find "$directory" -maxdepth 1 -type f -iname "*.${extension}" -print0)
  return 1
}

find_catalog_cached_package() {
  local directory="$1"
  local extension="$2"
  local expected_package="$3"
  local expected_path="$4"
  local expected_version="$5"
  local checksum_url="$6"
  local path metadata cached_version

  while IFS= read -r -d '' path; do
    [[ "$path" == "$expected_path" ]] || continue
    package_file_has_format "$path" "$PACKAGE_FAMILY" || continue
    if command -v dpkg-deb >/dev/null 2>&1 || command -v rpm >/dev/null 2>&1; then
      native_package_is_compatible "$path" "$expected_package" || continue
    fi
    if [[ -n "$expected_version" ]]; then
      metadata="$(package_file_metadata "$path")" || continue
      cached_version="${metadata#* }"
      [[ -n "$cached_version" && "$cached_version" == "$expected_version" ]] || continue
    fi
    if [[ -n "$NATIVE_EXPECTED_SHA256" || -n "$checksum_url" ]]; then
      verify_download_checksum "$path" "$checksum_url" || continue
    fi
    NATIVE_CACHE_PATH="$path"
    return 0
  done < <(find "$directory" -maxdepth 1 -type f -iname "*.${extension}" -print0)
  return 1
}

run_in_directory() {
  local directory="$1"
  shift

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[SIMULACAO] (cd %q &&' "$directory"
    printf ' %q' "$@"
    printf ')\n'
    return 0
  fi
  printf '[EXEC] (cd %q &&' "$directory"
  printf ' %q' "$@"
  printf ')\n'
  (cd -- "$directory" && "$@")
}

native_system_architecture() {
  local architecture
  architecture="$(uname -m)"
  case "$PACKAGE_FAMILY:$architecture" in
    apt:x86_64) printf '%s\n' amd64 ;;
    apt:aarch64) printf '%s\n' arm64 ;;
    apt:*) printf '%s\n' "$architecture" ;;
    dnf:*|zypper:*) printf '%s\n' "$architecture" ;;
  esac
}

native_package_identity() {
  local path="$1"

  case "$PACKAGE_FAMILY" in
    apt) dpkg-deb -f "$path" Package Architecture 2>/dev/null | paste -sd ' ' - ;;
    dnf|zypper) rpm -qp --queryformat '%{NAME} %{ARCH}' "$path" 2>/dev/null ;;
  esac
}

native_package_is_compatible() {
  local path="$1"
  local expected_package="$2"
  local identity package architecture system_architecture

  identity="$(native_package_identity "$path")" || return 1
  read -r package architecture <<< "$identity"
  [[ "$package" == "$expected_package" ]] || return 1
  system_architecture="$(native_system_architecture)" || return 1
  case "$PACKAGE_FAMILY" in
    apt) [[ "$architecture" == "$system_architecture" || "$architecture" == "all" ]] ;;
    dnf|zypper) [[ "$architecture" == "$system_architecture" || "$architecture" == "noarch" ]] ;;
  esac
}

prune_cached_package() {
  local directory="$1"
  local extension="$2"
  local expected_package="$3"
  local keep_path="$4"
  local path identity package

  while IFS= read -r -d '' path; do
    [[ "$path" == "$keep_path" ]] && continue
    identity="$(native_package_identity "$path")" || continue
    read -r package _ <<< "$identity"
    [[ "$package" == "$expected_package" ]] && rm -f -- "$path"
  done < <(find "$directory" -maxdepth 1 -type f -iname "*.${extension}" -print0)
  return 0
}

download_native_package() {
  local package="$1"
  local directory extension temporary_directory path destination architecture filename
  local -a downloaded=()

  NATIVE_CACHE_PATH=""
  case "$PACKAGE_FAMILY" in
    apt)
      directory="$DEB_DIR"
      extension="deb"
      ;;
    dnf|zypper)
      directory="$RPM_DIR"
      extension="rpm"
      ;;
  esac
  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "$NATIVE_RESOLUTION_METHOD" == "external" ]]; then
      printf '[SIMULACAO] curl --output %q %q\n' "$directory/${package}.DRY-RUN.${extension}" "$NATIVE_DOWNLOAD_URL"
    else
      printf '[SIMULACAO] baixar %q pelo gerenciador %q\n' "$package" "$PACKAGE_FAMILY"
    fi
    NATIVE_CACHE_PATH="$directory/${package}.DRY-RUN.${extension}"
    return 0
  fi
  mkdir -p -- "$directory"
  if find_verified_cached_package "$directory" "$extension" "$package"; then
    info "Reutilizando pacote validado do cache: $NATIVE_CACHE_PATH"
    return 0
  fi
  temporary_directory="$(mktemp -d "$WORK_DIR/download.XXXXXX")"

  if [[ "$NATIVE_RESOLUTION_METHOD" == "external" ]]; then
    filename="${NATIVE_DOWNLOAD_URL%%\?*}"
    filename="$(basename "$filename")"
    [[ "$filename" == *."$extension" ]] || filename="${package}.${extension}"
    path="$temporary_directory/$filename"
    run_command curl --fail --location --show-error --connect-timeout 10 --max-time 600 --retry 2 \
      --output "$path" "$NATIVE_DOWNLOAD_URL" || return 1
    if [[ "$DRY_RUN" != "1" ]]; then
      verify_download_checksum "$path" "$NATIVE_CHECKSUM_URL" || {
        warn "Falha ao validar o checksum publicado para $package."
        return 1
      }
    fi
  else
    case "$PACKAGE_FAMILY" in
      apt)
        run_in_directory "$temporary_directory" apt-get download "$package" || return 1
        ;;
      dnf)
        architecture="$(native_system_architecture)" || return 1
        run_command dnf -q download --destdir "$temporary_directory" --arch "$architecture,noarch" "$package" || return 1
        ;;
      zypper)
        run_command zypper --non-interactive download --directory "$temporary_directory" "$package" || return 1
        ;;
    esac
  fi

  while IFS= read -r -d '' path; do
    native_package_is_compatible "$path" "$package" && downloaded+=("$path")
  done < <(find "$temporary_directory" -maxdepth 1 -type f -iname "*.${extension}" -print0)
  [[ ${#downloaded[@]} -eq 1 ]] || {
    warn "O download de $package nao produziu exatamente um pacote compativel."
    return 1
  }

  destination="$directory/$(basename "${downloaded[0]}")"
  mv -f -- "${downloaded[0]}" "$destination"
  prune_cached_package "$directory" "$extension" "$package" "$destination"
  NATIVE_CACHE_PATH="$destination"
}

package_file_has_format() {
  local path="$1"
  local family="$2"
  local signature

  signature="$(od -An -tx1 -N8 "$path" 2>/dev/null | tr -d '[:space:]')"
  case "$family" in
    apt) [[ "$signature" == 213c617263683e0a* ]] ;;
    dnf|zypper) [[ "$signature" == edabeedb* ]] ;;
  esac
}

download_resolved_cache_asset() {
  local package="$1"
  local target_family="$2"
  local directory extension filename temporary destination

  case "$target_family" in
    apt) directory="$DEB_DIR"; extension=deb ;;
    dnf|zypper) directory="$RPM_DIR"; extension=rpm ;;
  esac
  filename="${NATIVE_DOWNLOAD_URL%%\?*}"
  filename="$(basename "$filename")"
  [[ "$filename" == *."$extension" ]] || filename="${package}.${extension}"
  destination="$directory/$filename"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[SIMULACAO] cache %s: curl --output %q %q\n' \
      "$target_family" "$destination" "$NATIVE_DOWNLOAD_URL"
    return 0
  fi

  mkdir -p -- "$directory"
  if find_catalog_cached_package "$directory" "$extension" "$package" "$destination" \
    "$NATIVE_RESOLUTION_VERSION" "$NATIVE_CHECKSUM_URL"; then
    info "Reutilizando pacote do cache $target_family: $NATIVE_CACHE_PATH"
    return 0
  fi
  temporary="$(mktemp "$WORK_DIR/cache.XXXXXX")"
  run_command curl --fail --location --show-error --connect-timeout 10 --max-time 600 --retry 2 \
    --output "$temporary" "$NATIVE_DOWNLOAD_URL" || return 1
  verify_download_checksum "$temporary" "$NATIVE_CHECKSUM_URL" || return 1
  package_file_has_format "$temporary" "$target_family" || {
    warn "A fonte de $package nao produziu um pacote .$extension valido."
    return 1
  }
  mv -f -- "$temporary" "$destination"
  info "Pacote armazenado no cache $target_family: $destination"
}

cache_app_package_for_family() {
  local index="$1"
  local target_family="$2"
  local package

  PACKAGE_FAMILY="$target_family"
  package="$(native_package_for_app "$index")"
  [[ -n "$package" ]] || return 3
  NATIVE_RESOLUTION_PACKAGE="$package"
  NATIVE_RESOLUTION_METHOD="catalog"
  case "$target_family" in
    apt)
      NATIVE_DOWNLOAD_URL="${APP_DEB_URLS[$index]}"
      NATIVE_RESOLUTION_VERSION="${APP_DEB_VERSIONS[$index]}"
      NATIVE_EXPECTED_SHA256="${APP_DEB_SHA256[$index]}"
      NATIVE_CHECKSUM_URL="${APP_DEB_CHECKSUM_URLS[$index]}"
      ;;
    dnf|zypper)
      NATIVE_DOWNLOAD_URL="${APP_RPM_URLS[$index]}"
      NATIVE_RESOLUTION_VERSION="${APP_RPM_VERSIONS[$index]}"
      NATIVE_EXPECTED_SHA256="${APP_RPM_SHA256[$index]}"
      NATIVE_CHECKSUM_URL="${APP_RPM_CHECKSUM_URLS[$index]}"
      ;;
  esac
  [[ -n "$NATIVE_DOWNLOAD_URL" ]] || return 3
  download_resolved_cache_asset "$package" "$target_family"
}

cache_application_packages() {
  local index="$1"
  local key="${APP_KEYS[$index]}"
  local original_family="$PACKAGE_FAMILY"
  local target_family result success=0

  for target_family in apt dnf; do
    result=0
    cache_app_package_for_family "$index" "$target_family" || result=$?
    case "$result" in
      0)
        success=1
        log_event cache-download OK "$key family=$target_family"
        ;;
      3) log_event cache-download NOT_FOUND "$key family=$target_family" ;;
      *) log_event cache-download ERROR "$key family=$target_family" ;;
    esac
  done
  PACKAGE_FAMILY="$original_family"
  [[ "$success" -eq 1 ]]
}

install_cached_native_package() {
  local path="$1"

  case "$PACKAGE_FAMILY" in
    apt)
      update_package_metadata
      run_as_root apt-get install -y -- "$path"
      ;;
    dnf) run_as_root dnf install -y -- "$path" ;;
    zypper) run_as_root zypper --non-interactive install -- "$path" ;;
  esac
}

ensure_local_package_directories() {
  mkdir -p -- "$DEB_DIR" "$RPM_DIR" || die "Nao foi possivel criar as pastas deb e rpm."
}

run_command() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[SIMULACAO]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  printf '[EXEC]'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

run_as_root() {
  if [[ "$DRY_RUN" == "1" || "$EUID" -eq 0 ]]; then
    run_command "$@"
    return
  fi
  command -v sudo >/dev/null 2>&1 || die "sudo nao esta instalado."
  run_command sudo "$@"
}

detect_platform() {
  [[ -r /etc/os-release ]] || die "Nao foi possivel identificar a distribuicao."

  # shellcheck disable=SC1091
  source /etc/os-release
  DISTRO_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
  DISTRO_VERSION="${VERSION_ID:-desconhecida}"

  if [[ "$DRY_RUN" == "1" && "$TEST_PACKAGE_FAMILY" =~ ^(apt|dnf|zypper)$ ]]; then
    PACKAGE_FAMILY="$TEST_PACKAGE_FAMILY"
  elif command -v apt-get >/dev/null 2>&1; then
    PACKAGE_FAMILY="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_FAMILY="dnf"
  elif command -v zypper >/dev/null 2>&1; then
    PACKAGE_FAMILY="zypper"
  else
    die "Distribuicao sem APT, DNF ou Zypper nao suportada."
  fi
}

update_package_metadata() {
  [[ "$PACKAGE_METADATA_UPDATED" -eq 1 ]] && return 0

  case "$PACKAGE_FAMILY" in
    apt) run_as_root apt-get update ;;
    dnf) run_as_root dnf makecache ;;
    zypper) run_as_root zypper --non-interactive refresh ;;
  esac
  PACKAGE_METADATA_UPDATED=1
}

is_native_package_installed() {
  local package="$1"

  case "$PACKAGE_FAMILY" in
    apt) dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -q '^installed$' ;;
    dnf) rpm -q "$package" >/dev/null 2>&1 ;;
    zypper) rpm -q "$package" >/dev/null 2>&1 ;;
  esac
}

install_native_packages() {
  local -a missing=()
  local package

  for package in "$@"; do
    if is_native_package_installed "$package"; then
      info "$package ja esta instalado."
    else
      missing+=("$package")
    fi
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0

  update_package_metadata
  case "$PACKAGE_FAMILY" in
    apt) run_as_root apt-get install -y -- "${missing[@]}" ;;
    dnf) run_as_root dnf install -y -- "${missing[@]}" ;;
    zypper) run_as_root zypper --non-interactive install -- "${missing[@]}" ;;
  esac
}

native_package_for() {
  local apt_package="$1"
  local dnf_package="$2"
  local zypper_package="$3"

  case "$PACKAGE_FAMILY" in
    apt) printf '%s\n' "$apt_package" ;;
    dnf) printf '%s\n' "$dnf_package" ;;
    zypper) printf '%s\n' "$zypper_package" ;;
  esac
}

service_exists() {
  [[ "$DRY_RUN" == "1" ]] && return 0
  systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q .
}

enable_service() {
  local service="$1"

  if service_exists "$service"; then
    run_as_root systemctl enable --now "$service"
  else
    warn "Servico nao encontrado: $service"
    return 1
  fi
}

install_managed_file() {
  local target="$1"
  local mode="$2"
  local temporary backup

  temporary="$(make_temp)"
  cat > "$temporary"
  if [[ -r "$target" ]] && cmp -s "$temporary" "$target"; then
    rm -f "$temporary"
    info "$target ja esta atualizado."
    return 1
  fi

  backup="${target}.linux-setup.bak"
  if [[ -e "$target" && ! -e "$backup" ]]; then
    if [[ -w "$(dirname "$target")" ]]; then
      run_command cp -a -- "$target" "$backup"
    else
      run_as_root cp -a -- "$target" "$backup"
    fi
  fi
  if [[ -w "$(dirname "$target")" && (! -e "$target" || -w "$target") ]]; then
    run_command install -D -m "$mode" -- "$temporary" "$target"
  else
    run_as_root install -D -m "$mode" -- "$temporary" "$target"
  fi
  rm -f "$temporary"
  info "$target atualizado."
  return 0
}

backup_file_once() {
  local target="$1"
  local backup="${target}.linux-setup.bak"

  [[ -e "$target" && ! -e "$backup" ]] || return 0
  if [[ -w "$(dirname "$target")" ]]; then
    run_command cp -a -- "$target" "$backup"
  else
    run_as_root cp -a -- "$target" "$backup"
  fi
}

boot_splash_dropin_content() {
  local state="$1"

  cat <<EOF
# Managed by Linux Setup. Local boot arguments remain in their original files.
linux_setup_cmdline=""
for linux_setup_argument in \${GRUB_CMDLINE_LINUX_DEFAULT:-}; do
  [ "\$linux_setup_argument" = "splash" ] && continue
  linux_setup_cmdline="\${linux_setup_cmdline}\${linux_setup_cmdline:+ }\${linux_setup_argument}"
done
EOF
  if [[ "$state" == "enabled" ]]; then
    cat <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="${linux_setup_cmdline}${linux_setup_cmdline:+ }splash"
EOF
  else
    cat <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="$linux_setup_cmdline"
EOF
  fi
  cat <<'EOF'
unset linux_setup_argument linux_setup_cmdline
EOF
}

grub_default_cmdline() {
  local shell_code

  [[ -r "$GRUB_DEFAULT_FILE" ]] || return 1
  shell_code="set -a; . \"$GRUB_DEFAULT_FILE\""
  if [[ -d "$GRUB_DROPIN_DIR" ]]; then
    shell_code+='; for config in "'"$GRUB_DROPIN_DIR"'"/*.cfg; do [[ -e "$config" ]] && . "$config"; done'
  fi
  shell_code+='; printf "%s\\n" "${GRUB_CMDLINE_LINUX_DEFAULT:-}"'
  bash -c "$shell_code"
}

cmdline_has_argument() {
  local cmdline="$1"
  local expected="$2"
  local argument

  for argument in $cmdline; do
    [[ "$argument" == "$expected" ]] && return 0
  done
  return 1
}

plymouth_initramfs_ready() {
  local initramfs="/boot/initrd.img-$(uname -r)"
  local contents

  [[ -r "$initramfs" ]] || return 1
  command -v lsinitramfs >/dev/null 2>&1 || return 1
  contents="$(lsinitramfs "$initramfs" 2>/dev/null)" || return 1
  grep -q '/plymouthd$' <<< "$contents" &&
    grep -q '/plymouth/renderers/drm.so$' <<< "$contents"
}

boot_splash_theme() {
  local file theme

  for file in /etc/plymouth/plymouthd.conf /usr/share/plymouth/plymouthd.defaults; do
    [[ -r "$file" ]] || continue
    theme="$(awk -F= '/^[[:space:]]*Theme=/{print $2; exit}' "$file")"
    [[ -z "$theme" ]] || { printf '%s\n' "$theme"; return 0; }
  done
  printf '%s\n' "nao detectado"
}

boot_splash_kms_driver() {
  local path driver

  for path in /sys/class/drm/card*/device/driver/module; do
    [[ -e "$path" ]] || continue
    driver="$(basename "$(readlink -f "$path")")"
    [[ -z "$driver" ]] || { printf '%s\n' "$driver"; return 0; }
  done
  printf '%s\n' "nao detectado"
}

show_boot_splash_status() {
  local configured_cmdline current_cmdline

  configured_cmdline="$(grub_default_cmdline 2>/dev/null || true)"
  current_cmdline="$(< /proc/cmdline)"
  printf 'GRUB configurado: %s\n' "${configured_cmdline:-sem argumentos padrao}"
  if cmdline_has_argument "$current_cmdline" splash; then
    printf 'Boot atual: splash ativo\n'
  else
    printf 'Boot atual: splash inativo\n'
  fi
  if is_native_package_installed plymouth; then
    printf 'Plymouth: instalado | Tema: %s\n' "$(boot_splash_theme)"
  else
    printf 'Plymouth: nao instalado\n'
  fi
  printf 'Driver KMS: %s\n' "$(boot_splash_kms_driver)"
  if plymouth_initramfs_ready; then
    printf 'Initramfs: Plymouth e renderer DRM presentes\n'
  else
    printf 'Initramfs: Plymouth ou renderer DRM nao detectado\n'
  fi
}

validate_boot_splash_prerequisites() {
  [[ "$PACKAGE_FAMILY" == "apt" ]] || { warn "Boot com splash esta disponivel somente em sistemas APT."; return 1; }
  [[ -r "$GRUB_DEFAULT_FILE" ]] || { warn "Configuracao do GRUB nao encontrada: $GRUB_DEFAULT_FILE"; return 1; }
  [[ -x "$UPDATE_GRUB_COMMAND" ]] || { warn "Comando update-grub nao encontrado: $UPDATE_GRUB_COMMAND"; return 1; }
}

validate_generated_grub() {
  local state="$1"
  local cmdline

  [[ "$DRY_RUN" == "1" ]] && return 0
  [[ -e "$GRUB_CONFIG_FILE" ]] || { warn "Configuracao gerada nao encontrada: $GRUB_CONFIG_FILE"; return 1; }
  cmdline="$(run_as_root awk '/^[[:space:]]*linux[[:space:]]/{print; exit}' "$GRUB_CONFIG_FILE")"
  if [[ "$state" == "enabled" ]]; then
    cmdline_has_argument "$cmdline" splash || { warn "O GRUB gerado nao contem splash."; return 1; }
  elif cmdline_has_argument "$cmdline" splash; then
    warn "O GRUB gerado ainda contem splash. Verifique configuracoes posteriores ao drop-in."
    return 1
  fi
  if command -v grub-script-check >/dev/null 2>&1; then
    run_as_root grub-script-check "$GRUB_CONFIG_FILE"
  fi
}

write_boot_splash_state() {
  local state="$1"

  if install_managed_file "$GRUB_SPLASH_DROPIN" 0644 < <(boot_splash_dropin_content "$state"); then
    run_as_root "$UPDATE_GRUB_COMMAND"
    validate_generated_grub "$state"
  else
    info "Boot com splash ja esta $([[ "$state" == "enabled" ]] && printf 'ativado' || printf 'desativado')."
  fi
}

enable_boot_splash() {
  local configured_cmdline

  validate_boot_splash_prerequisites || return 1
  if ! is_native_package_installed plymouth; then
    confirm "Plymouth nao esta instalado. Instalar agora?" || { info "Ativacao cancelada."; return 0; }
    install_native_packages plymouth
  fi
  if ! plymouth_initramfs_ready; then
    [[ -x "$UPDATE_INITRAMFS_COMMAND" ]] || { warn "Comando update-initramfs nao encontrado: $UPDATE_INITRAMFS_COMMAND"; return 1; }
    run_as_root "$UPDATE_INITRAMFS_COMMAND" -u
  fi
  configured_cmdline="$(grub_default_cmdline)" || return 1
  if cmdline_has_argument "$configured_cmdline" splash; then
    info "Boot com splash ja esta ativado."
    return 0
  fi
  write_boot_splash_state enabled || return 1
  info "Splash ativado para o proximo boot."
}

disable_boot_splash() {
  local configured_cmdline

  validate_boot_splash_prerequisites || return 1
  configured_cmdline="$(grub_default_cmdline)" || return 1
  if ! cmdline_has_argument "$configured_cmdline" splash; then
    info "Boot com splash ja esta desativado; nenhum pacote foi removido."
    return 0
  fi
  write_boot_splash_state disabled || return 1
  info "Splash desativado para o proximo boot; nenhum pacote foi removido."
}

boot_splash_menu() {
  local option

  while true; do
    print_header
    printf 'Boot com splash\n\n'
    show_boot_splash_status
    printf '\n1. Ativar splash\n'
    printf '2. Desativar splash\n'
    printf '0. Voltar\n\n'
    read -r -p "> " option
    case "$option" in
      1)
        if confirm "Ativar o splash no proximo boot?"; then
          enable_boot_splash || true
        fi
        pause
        ;;
      2)
        if confirm "Desativar somente o splash, sem remover pacotes?"; then
          disable_boot_splash || true
        fi
        pause
        ;;
      0) return 0 ;;
      *) warn "Opcao invalida."; pause ;;
    esac
  done
}

root_filesystem_type() {
  findmnt -n -o FSTYPE / 2>/dev/null || true
}

available_root_bytes() {
  df -B1 --output=avail / | awk 'NR==2 {print $1}'
}

flameshot_configuration() {
  local package real_user real_home wrapper content

  package="$(native_package_for flameshot flameshot flameshot)"
  install_native_packages "$package"
  real_user="${SUDO_USER:-$USER}"
  real_home="$(getent passwd "$real_user" | cut -d: -f6)"
  [[ -n "$real_home" ]] || die "Nao foi possivel localizar o home de $real_user."
  wrapper="$real_home/.local/bin/flameshot-gui"
  content='#!/usr/bin/env bash
exec env QT_QPA_PLATFORM=wayland flameshot gui "$@"
'

  if [[ -r "$wrapper" ]] && [[ "$(<"$wrapper")" == "${content%$'\n'}" ]]; then
    info "Integracao Wayland do Flameshot ja configurada."
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[SIMULACAO] criar %q para %q\n' "$wrapper" "$real_user"
    return 0
  fi
  install -d -m 0755 "$real_home/.local/bin"
  printf '%s' "$content" > "$wrapper"
  chmod 0755 "$wrapper"
  [[ "$EUID" -eq 0 ]] && chown "$real_user:$(id -gn "$real_user")" "$wrapper"
  info "Wrapper criado em $wrapper."
}

configure_plex_firewall() {
  local -a tcp_ports=(32400 32469)
  local -a udp_ports=(1900 5353 32410 32411 32412 32413 32414)
  local port

  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    for port in "${tcp_ports[@]}"; do
      firewall-cmd --permanent --query-port="${port}/tcp" >/dev/null 2>&1 ||
        run_as_root firewall-cmd --permanent --add-port="${port}/tcp"
    done
    for port in "${udp_ports[@]}"; do
      firewall-cmd --permanent --query-port="${port}/udp" >/dev/null 2>&1 ||
        run_as_root firewall-cmd --permanent --add-port="${port}/udp"
    done
    run_as_root firewall-cmd --reload
  elif command -v ufw >/dev/null 2>&1 && systemctl is-active --quiet ufw; then
    for port in "${tcp_ports[@]}"; do
      run_as_root ufw allow "${port}/tcp"
    done
    for port in "${udp_ports[@]}"; do
      run_as_root ufw allow "${port}/udp"
    done
  else
    warn "Nenhum firewalld ou UFW ativo. O firewall nao foi alterado."
    return 1
  fi
  info "Portas do Plex configuradas."
}

firewall_allow_service() {
  local service="$1"
  local ufw_rule="${2:-$service}"

  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --query-service="$service" >/dev/null 2>&1 ||
      run_as_root firewall-cmd --permanent --add-service="$service"
    run_as_root firewall-cmd --reload
  elif command -v ufw >/dev/null 2>&1 && systemctl is-active --quiet ufw; then
    run_as_root ufw allow "$ufw_rule"
  else
    info "Nenhum firewall gerenciado ativo; nenhuma regra foi adicionada."
  fi
}

firewall_allow_port() {
  local port="$1"
  local protocol="$2"

  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --query-port="${port}/${protocol}" >/dev/null 2>&1 ||
      run_as_root firewall-cmd --permanent --add-port="${port}/${protocol}"
    run_as_root firewall-cmd --reload
  elif command -v ufw >/dev/null 2>&1 && systemctl is-active --quiet ufw; then
    run_as_root ufw allow "${port}/${protocol}"
  else
    info "Nenhum firewall gerenciado ativo; nenhuma regra foi adicionada."
  fi
}

configure_swapfile() {
  local size_gib size_bytes available_bytes filesystem temporary_fstab current_bytes
  local swapfile="/swapfile"

  read -r -p "Tamanho do swapfile em GiB (0 remove): " size_gib
  [[ "$size_gib" =~ ^[0-9]+$ ]] || {
    warn "Informe um numero inteiro nao negativo."
    return 1
  }

  if [[ "$size_gib" -eq 0 ]]; then
    confirm "Desativar e remover somente $swapfile?" || return 0
    grep -q "^${swapfile}[[:space:]]" /proc/swaps 2>/dev/null && run_as_root swapoff "$swapfile"
    [[ -e "$swapfile" ]] && run_as_root rm -f -- "$swapfile"
    if grep -qE "^[[:space:]]*${swapfile}[[:space:]]" /etc/fstab; then
      temporary_fstab="$(make_temp)"
      awk -v path="$swapfile" '$1 != path {print}' /etc/fstab > "$temporary_fstab"
      backup_file_once /etc/fstab
      run_as_root install -m 0644 "$temporary_fstab" /etc/fstab
      rm -f "$temporary_fstab"
    fi
    info "Swapfile removido; outras areas de swap foram preservadas."
    return 0
  fi

  size_bytes=$((size_gib * 1024 * 1024 * 1024))
  available_bytes="$(available_root_bytes)"
  ((size_bytes < available_bytes)) || {
    warn "Espaco livre insuficiente para ${size_gib} GiB."
    return 1
  }
  confirm "Criar $swapfile com ${size_gib} GiB?" || return 0

  if grep -q "^${swapfile}[[:space:]]" /proc/swaps 2>/dev/null; then
    current_bytes=$(( $(awk -v path="$swapfile" '$1 == path {print $3}' /proc/swaps) * 1024 ))
    if [[ "$current_bytes" -eq "$size_bytes" ]]; then
      info "Swapfile ja esta ativo com o tamanho solicitado."
      return 0
    fi
    run_as_root swapoff "$swapfile"
  fi
  [[ -e "$swapfile" ]] && run_as_root rm -f -- "$swapfile"

  filesystem="$(root_filesystem_type)"
  if [[ "$filesystem" == "btrfs" ]]; then
    install_native_packages btrfs-progs
    run_as_root btrfs filesystem mkswapfile --size "${size_gib}G" "$swapfile"
  else
    run_as_root fallocate -l "${size_gib}G" "$swapfile"
    run_as_root chmod 0600 "$swapfile"
    run_as_root mkswap "$swapfile"
  fi
  run_as_root swapon "$swapfile"

  if ! grep -qE "^[[:space:]]*${swapfile}[[:space:]]" /etc/fstab; then
    if [[ "$DRY_RUN" == "1" ]]; then
      printf '[SIMULACAO] adicionar %q ao /etc/fstab\n' "$swapfile none swap sw 0 0"
    elif [[ "$EUID" -eq 0 ]]; then
      backup_file_once /etc/fstab
      printf '%s\n' "$swapfile none swap sw 0 0" >> /etc/fstab
    else
      backup_file_once /etc/fstab
      printf '%s\n' "$swapfile none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
    fi
  fi
  info "Swapfile configurado."
}

zram_has_persistent_manager() {
  awk 'NR > 1 && $1 ~ /^\/dev\/zram/ {found=1} END {exit !found}' /proc/swaps ||
    compgen -G '/run/systemd/generator*/dev-zram*.swap' >/dev/null ||
    systemctl list-unit-files --no-legend '*zram*' 2>/dev/null | grep -q . ||
    [[ -e /etc/systemd/zram-generator.conf ]] ||
    compgen -G '/etc/systemd/zram-generator.conf.d/*.conf' >/dev/null
}

configure_zram() {
  local size_gib algorithm priority helper service

  read -r -p "Tamanho do zram em GiB [4]: " size_gib
  size_gib="${size_gib:-4}"
  read -r -p "Algoritmo [zstd]: " algorithm
  algorithm="${algorithm:-zstd}"
  read -r -p "Prioridade [100]: " priority
  priority="${priority:-100}"
  [[ "$size_gib" =~ ^[1-9][0-9]*$ ]] || { warn "Tamanho invalido."; return 1; }
  [[ "$algorithm" =~ ^[a-zA-Z0-9_-]+$ ]] || { warn "Algoritmo invalido."; return 1; }
  [[ "$priority" =~ ^-?[0-9]+$ ]] || { warn "Prioridade invalida."; return 1; }

  if zram_has_persistent_manager; then
    info "O sistema ja possui um gerenciador persistente de zram."
    info "Nenhum dispositivo ativo sera desativado ou recriado."
    return 0
  fi

  warn "A configuracao sera aplicada somente no proximo boot."
  confirm "Criar um servico systemd persistente para zram?" || return 0
  helper="/usr/local/sbin/linux-setup-zram"
  service="/etc/systemd/system/linux-setup-zram.service"

  install_managed_file "$helper" 0755 <<EOF || true
#!/usr/bin/env bash
set -Eeuo pipefail
modprobe zram
if grep -q '^/dev/zram0[[:space:]]' /proc/swaps; then
  exit 0
fi
[[ -e /sys/block/zram0/reset ]] && echo 1 > /sys/block/zram0/reset
if grep -qw '$algorithm' /sys/block/zram0/comp_algorithm; then
  echo '$algorithm' > /sys/block/zram0/comp_algorithm
fi
echo '${size_gib}G' > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p '$priority' /dev/zram0
EOF

  install_managed_file "$service" 0644 <<EOF || true
[Unit]
Description=Zram swap managed by Linux Setup
DefaultDependencies=no
After=systemd-modules-load.service
Before=swap.target

[Service]
Type=oneshot
ExecStart=$helper
RemainAfterExit=yes

[Install]
WantedBy=swap.target
EOF
  run_as_root systemctl daemon-reload
  run_as_root systemctl enable linux-setup-zram.service
  info "Zram persistente configurado para o proximo boot."
}

replace_managed_block() {
  local target="$1"
  local mode="$2"
  local marker="$3"
  local remove_first_field="${4:-}"
  local source block output

  source="$(make_temp)"
  block="$(make_temp)"
  output="$(make_temp)"
  if [[ -e "$target" ]]; then
    if [[ -r "$target" ]]; then
      cat -- "$target" > "$source"
    else
      run_as_root cat -- "$target" > "$source"
    fi
  fi
  cat > "$block"
  awk -v begin="# BEGIN ${marker}" -v end="# END ${marker}" -v remove_first_field="$remove_first_field" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {lines[++count]=$0}
    END {
      while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
      for (line_number=1; line_number <= count; line_number++) {
        split(lines[line_number], fields)
        if (remove_first_field == "" || fields[1] != remove_first_field) print lines[line_number]
      }
    }
  ' "$source" > "$output"
  [[ ! -s "$output" ]] || printf '\n' >> "$output"
  {
    printf '# BEGIN %s\n' "$marker"
    cat "$block"
    printf '# END %s\n' "$marker"
  } >> "$output"
  install_managed_file "$target" "$mode" < "$output"
  local changed=$?
  rm -f "$source" "$block" "$output"
  return "$changed"
}

replace_samba_block() {
  local target="$1"
  local share_name="$2"
  local source block output

  source="$(make_temp)"
  block="$(make_temp)"
  output="$(make_temp)"
  if [[ -r "$target" ]]; then
    cat -- "$target" > "$source"
  elif [[ -e "$target" ]]; then
    run_as_root cat -- "$target" > "$source"
  fi
  cat > "$block"
  awk -v section="$share_name" '
    $0 == "# BEGIN LINUX-SETUP-SAMBA" {managed=1; next}
    $0 == "# END LINUX-SETUP-SAMBA" {managed=0; next}
    managed {next}
    /^\[[^]]+\][[:space:]]*$/ {
      current=$0
      sub(/^\[/, "", current)
      sub(/\][[:space:]]*$/, "", current)
      skip=(current == section)
    }
    !skip {lines[++count]=$0}
    END {
      while (count > 0 && lines[count] ~ /^[[:space:]]*$/) count--
      for (line_number=1; line_number <= count; line_number++) print lines[line_number]
    }
  ' "$source" > "$output"
  [[ ! -s "$output" ]] || printf '\n' >> "$output"
  {
    printf '# BEGIN LINUX-SETUP-SAMBA\n'
    cat "$block"
    printf '# END LINUX-SETUP-SAMBA\n'
  } >> "$output"
  install_managed_file "$target" 0644 < "$output"
  local changed=$?
  rm -f "$source" "$block" "$output"
  return "$changed"
}

configure_samba() {
  local share_path share_name guest_group config service changed=0
  local package

  read -r -e -p "Diretorio compartilhado [/srv/samba/share]: " share_path
  share_path="${share_path:-/srv/samba/share}"
  share_path="${share_path/#\~/$HOME}"
  read -r -p "Nome do compartilhamento [share]: " share_name
  share_name="${share_name:-share}"
  [[ "$share_name" =~ ^[a-zA-Z0-9._-]+$ ]] || { warn "Nome de compartilhamento invalido."; return 1; }

  warn "O compartilhamento sera gravavel e acessivel sem senha na rede local."
  confirm "Continuar com Samba guest?" || return 0
  package="$(native_package_for samba samba samba)"
  install_native_packages "$package"
  if [[ "$PACKAGE_FAMILY" == "apt" || "$PACKAGE_FAMILY" == "dnf" ]]; then
    install_native_packages wsdd
  fi
  guest_group="$(id -gn nobody 2>/dev/null || printf 'nogroup')"
  run_as_root install -d -m 0777 -o nobody -g "$guest_group" -- "$share_path"
  config="/etc/samba/smb.conf"

  replace_samba_block "$config" "$share_name" <<EOF || changed=$?
[global]
   map to guest = Bad User

[$share_name]
   path = $share_path
   browseable = yes
   read only = no
   guest ok = yes
   guest only = yes
   public = yes
   force user = nobody
   create mask = 0666
   directory mask = 0777
EOF
  run_as_root testparm -s "$config" >/dev/null

  if [[ "$PACKAGE_FAMILY" == "apt" ]]; then
    for service in smbd.service nmbd.service; do enable_service "$service" || return 1; done
    enable_service wsdd.service || true
  else
    for service in smb.service nmb.service; do enable_service "$service" || return 1; done
    [[ "$PACKAGE_FAMILY" != "dnf" ]] || enable_service wsdd.service || true
  fi
  if [[ "$changed" -eq 0 ]]; then
    if [[ "$PACKAGE_FAMILY" == "apt" ]]; then
      run_as_root systemctl restart smbd.service nmbd.service
    else
      run_as_root systemctl restart smb.service nmb.service
    fi
  fi
  firewall_allow_service samba Samba
  info "Samba configurado em $share_path."
}

configure_ftp() {
  local ftp_user ftp_root ftp_password ftp_password_confirm reset_password answer config temporary package

  read -r -p "Usuario FTP [filmes]: " ftp_user
  ftp_user="${ftp_user:-filmes}"
  [[ "$ftp_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || { warn "Usuario invalido."; return 1; }
  read -r -e -p "Diretorio FTP [/filmes]: " ftp_root
  ftp_root="${ftp_root:-/filmes}"
  ftp_root="${ftp_root/#\~/$HOME}"
  [[ ! "$ftp_root" =~ [[:space:]] ]] || { warn "O diretorio FTP nao pode conter espacos."; return 1; }
  warn "O FTP atual usa arquivos gravaveis e nao cifra usuario, senha ou trafego."
  confirm "Continuar com o servidor FTP?" || return 0

  package="$(native_package_for vsftpd vsftpd vsftpd)"
  install_native_packages "$package"
  reset_password=1
  if getent passwd "$ftp_user" >/dev/null; then
    read -r -p "Usuario existente. Alterar sua senha? [s/N] " answer
    [[ "$answer" =~ ^[sS]$ ]] || reset_password=0
  else
    run_as_root useradd --create-home --shell "$(command -v nologin || printf '/usr/sbin/nologin')" "$ftp_user"
  fi
  if ! grep -qxF '/usr/sbin/nologin' /etc/shells; then
    if [[ "$DRY_RUN" == "1" ]]; then
      printf '[SIMULACAO] adicionar /usr/sbin/nologin a /etc/shells\n'
    elif [[ "$EUID" -eq 0 ]]; then
      printf '%s\n' /usr/sbin/nologin >> /etc/shells
    else
      printf '%s\n' /usr/sbin/nologin | sudo tee -a /etc/shells >/dev/null
    fi
  fi
  if [[ "$reset_password" -eq 1 ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      info "Simulacao: senha seria definida sem ser registrada."
    else
      read -r -s -p "Senha para $ftp_user: " ftp_password
      printf '\n'
      read -r -s -p "Confirme a senha: " ftp_password_confirm
      printf '\n'
      [[ -n "$ftp_password" && "$ftp_password" == "$ftp_password_confirm" ]] || {
        unset ftp_password ftp_password_confirm
        warn "As senhas nao conferem ou estao vazias."
        return 1
      }
      if [[ "$EUID" -eq 0 ]]; then
        printf '%s:%s\n' "$ftp_user" "$ftp_password" | chpasswd
      else
        printf '%s:%s\n' "$ftp_user" "$ftp_password" | sudo chpasswd
      fi
      unset ftp_password ftp_password_confirm
    fi
  fi
  run_as_root install -d -m 0777 -o "$ftp_user" -g "$(id -gn "$ftp_user" 2>/dev/null || printf '%s' "$ftp_user")" -- "$ftp_root"
  run_as_root usermod -d "$ftp_root" "$ftp_user"

  config="/etc/vsftpd.conf"
  temporary="$(make_temp)"
  if [[ -r "$config" ]]; then
    awk -F= '
      $0 == "# BEGIN LINUX-SETUP-FTP" {skip=1; next}
      $0 == "# END LINUX-SETUP-FTP" {skip=0; next}
      skip {next}
      !($1 ~ /^(listen|listen_ipv6|anonymous_enable|local_enable|write_enable|local_umask|chroot_local_user|allow_writeable_chroot|local_root|pam_service_name)$/) {print}
    ' "$config" > "$temporary"
  fi
  cat >> "$temporary" <<EOF

# BEGIN LINUX-SETUP-FTP
listen=NO
listen_ipv6=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=000
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=$ftp_root
pam_service_name=vsftpd
# END LINUX-SETUP-FTP
EOF
  install_managed_file "$config" 0644 < "$temporary" || true
  rm -f "$temporary"
  if [[ "$PACKAGE_FAMILY" == "dnf" ]] && command -v setsebool >/dev/null 2>&1; then
    run_as_root setsebool -P ftpd_full_access 1
  fi
  enable_service vsftpd.service || return 1
  run_as_root systemctl restart vsftpd.service
  firewall_allow_service ftp 21/tcp
  info "FTP configurado para $ftp_user em $ftp_root."
}

sanitize_mount_name() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')"
  printf '%s\n' "${value:-compartilhamento}"
}

nfs_default_mountpoint() {
  local remote="$1"
  local export_path="${remote#*:}"
  printf '/mnt/nfs-%s\n' "$(sanitize_mount_name "$(basename "$export_path")")"
}

nfs_local_cidr() {
  local interface
  interface="$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')"
  [[ -n "$interface" ]] || return 1
  ip -o -4 addr show dev "$interface" scope global 2>/dev/null | awk 'NR==1 {print $4}'
}

nfs_discover() {
  local cidr host export_path
  local -a hosts=() exports=()

  cidr="$(nfs_local_cidr || true)"
  [[ -n "$cidr" ]] || { warn "Nao foi possivel detectar a rede IPv4 local."; return 1; }
  NFS_DISCOVERED_REMOTES=()
  NFS_DISCOVERED_MOUNTS=()
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[SIMULACAO] nmap -n -p 111,2049 --open %q\n' "$cidr"
    info "A varredura nao e executada no modo de simulacao."
    return 0
  fi

  info "Procurando servidores NFS em $cidr..."
  mapfile -t hosts < <(nmap -n -p 111,2049 --open "$cidr" -oG - 2>/dev/null | awk '/Host: / {print $2}' | sort -u)
  for host in "${hosts[@]}"; do
    mapfile -t exports < <(showmount -e "$host" 2>/dev/null | awk 'NR > 1 && $1 ~ /^\// {print $1}')
    for export_path in "${exports[@]}"; do
      NFS_DISCOVERED_REMOTES+=("${host}:${export_path}")
      NFS_DISCOVERED_MOUNTS+=("$(nfs_default_mountpoint "${host}:${export_path}")")
    done
  done
  if [[ ${#NFS_DISCOVERED_REMOTES[@]} -eq 0 ]]; then
    info "Nenhum export NFS foi encontrado."
  else
    nfs_print_discovered
  fi
}

nfs_print_discovered() {
  local index
  if [[ ${#NFS_DISCOVERED_REMOTES[@]} -eq 0 ]]; then
    info "Nenhum export no cache de descoberta."
    return 0
  fi
  for index in "${!NFS_DISCOVERED_REMOTES[@]}"; do
    printf '%d. %s -> %s\n' "$((index + 1))" "${NFS_DISCOVERED_REMOTES[$index]}" "${NFS_DISCOVERED_MOUNTS[$index]}"
  done
}

nfs_choose_remote() {
  local choice remote mountpoint

  NFS_SELECTED_REMOTE=""
  NFS_SELECTED_MOUNT=""
  if [[ ${#NFS_DISCOVERED_REMOTES[@]} -gt 0 ]]; then
    nfs_print_discovered
    read -r -p "Indice ou m para informar manualmente: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#NFS_DISCOVERED_REMOTES[@]})); then
      NFS_SELECTED_REMOTE="${NFS_DISCOVERED_REMOTES[$((choice - 1))]}"
      NFS_SELECTED_MOUNT="${NFS_DISCOVERED_MOUNTS[$((choice - 1))]}"
      return 0
    elif [[ ! "$choice" =~ ^[mM]$ ]]; then
      warn "Selecao invalida."
      return 1
    fi
  fi

  read -r -p "Export remoto (servidor:/caminho): " remote
  [[ "$remote" =~ ^[^[:space:]:]+:/[^[:space:]]*$ ]] || { warn "Export remoto invalido."; return 1; }
  read -r -e -p "Ponto de montagem [$(nfs_default_mountpoint "$remote")]: " mountpoint
  NFS_SELECTED_REMOTE="$remote"
  NFS_SELECTED_MOUNT="${mountpoint:-$(nfs_default_mountpoint "$remote")}"
  [[ ! "$NFS_SELECTED_MOUNT" =~ [[:space:]] ]] || { warn "O ponto de montagem nao pode conter espacos."; return 1; }
}

update_nfs_fstab() {
  local remote="$1"
  local mountpoint="$2"
  local action="$3"
  local temporary

  temporary="$(make_temp)"
  awk -v remote="$remote" -v mountpoint="$mountpoint" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {print; next}
    ($1 == remote || $2 == mountpoint) {next}
    {print}
  ' /etc/fstab > "$temporary"
  if [[ "$action" == "add" ]]; then
    printf '%s %s nfs rw,soft,timeo=50,retrans=2,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=10s 0 0\n' \
      "$remote" "$mountpoint" >> "$temporary"
  fi
  if cmp -s "$temporary" /etc/fstab; then
    info "/etc/fstab ja esta atualizado."
  else
    backup_file_once /etc/fstab
    run_as_root install -m 0644 "$temporary" /etc/fstab
  fi
  rm -f "$temporary"
}

nfs_mount_selected() {
  local persistent="$1"

  nfs_choose_remote || return 1
  run_as_root install -d -m 0755 -- "$NFS_SELECTED_MOUNT"
  if mountpoint -q "$NFS_SELECTED_MOUNT"; then
    info "$NFS_SELECTED_MOUNT ja esta montado."
  else
    run_as_root mount -t nfs -o rw,soft,timeo=50,retrans=2 "$NFS_SELECTED_REMOTE" "$NFS_SELECTED_MOUNT"
  fi
  if [[ "$persistent" == "1" ]]; then
    update_nfs_fstab "$NFS_SELECTED_REMOTE" "$NFS_SELECTED_MOUNT" add
    info "Montagem persistente configurada."
  else
    info "Montagem temporaria ativa; /etc/fstab nao foi alterado."
  fi
}

nfs_unmount_selected() {
  nfs_choose_remote || return 1
  mountpoint -q "$NFS_SELECTED_MOUNT" && run_as_root umount "$NFS_SELECTED_MOUNT"
  update_nfs_fstab "$NFS_SELECTED_REMOTE" "$NFS_SELECTED_MOUNT" remove
  info "Montagem e persistencia removidas."
}

nfs_list_exports() {
  local server
  read -r -p "Servidor (hostname ou IP): " server
  [[ "$server" =~ ^[a-zA-Z0-9._:-]+$ ]] || { warn "Servidor invalido."; return 1; }
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[SIMULACAO] showmount -e %q\n' "$server"
  else
    showmount -e "$server"
  fi
}

nfs_client_firewall() {
  local cidr
  cidr="$(nfs_local_cidr || true)"
  [[ -n "$cidr" ]] || { warn "Rede local nao detectada."; return 1; }
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall_allow_service nfs nfs
    firewall_allow_service rpc-bind 111/tcp
  elif command -v ufw >/dev/null 2>&1 && systemctl is-active --quiet ufw; then
    run_as_root ufw allow out to "$cidr" port 111 proto tcp
    run_as_root ufw allow out to "$cidr" port 111 proto udp
    run_as_root ufw allow out to "$cidr" port 2049 proto tcp
    run_as_root ufw allow out to "$cidr" port 2049 proto udp
  else
    info "Nenhum firewall gerenciado ativo; nenhuma regra foi adicionada."
  fi
}

nfs_client_menu() {
  local option

  while true; do
    print_header
    printf 'Cliente NFS\n\n'
    printf '1. Descobrir exports na LAN\n'
    printf '2. Listar exports de um servidor\n'
    printf '3. Montar e persistir\n'
    printf '4. Desmontar e remover persistencia\n'
    printf '5. Testar montagem temporaria\n'
    printf '6. Ajustar firewall do cliente\n'
    printf '7. Mostrar montagens NFS ativas\n'
    printf '0. Voltar\n\n'
    read -r -p "> " option
    case "$option" in
      1) nfs_discover || true; pause ;;
      2) nfs_list_exports || true; pause ;;
      3) nfs_mount_selected 1 || true; pause ;;
      4) nfs_unmount_selected || true; pause ;;
      5) nfs_mount_selected 0 || true; pause ;;
      6) nfs_client_firewall || true; pause ;;
      7) findmnt -t nfs,nfs4 -o SOURCE,TARGET,FSTYPE,OPTIONS || info "Nenhuma montagem NFS ativa."; pause ;;
      0) return 0 ;;
      *) warn "Opcao invalida."; pause ;;
    esac
  done
}

configure_nfs_client() {
  local package

  package="$(native_package_for nfs-common nfs-utils nfs-client)"
  case "$PACKAGE_FAMILY" in
    apt) install_native_packages "$package" nmap avahi-daemon libnss-mdns ;;
    dnf) install_native_packages "$package" nmap avahi nss-mdns ;;
    zypper) install_native_packages "$package" nmap avahi nss-mdns ;;
  esac
  enable_service avahi-daemon.service || enable_service avahi.service || true
  enable_service rpcbind.service || true
  nfs_client_menu
}

configure_nfs_server() {
  local share_path network package service changed=0

  read -r -e -p "Diretorio exportado [/srv/nfs/shared]: " share_path
  share_path="${share_path:-/srv/nfs/shared}"
  [[ ! "$share_path" =~ [[:space:]] ]] || { warn "O diretorio NFS nao pode conter espacos."; return 1; }
  read -r -p "Rede autorizada [192.168.0.0/16]: " network
  network="${network:-192.168.0.0/16}"
  [[ "$network" =~ ^[0-9a-fA-F:.]+/[0-9]+$ ]] || { warn "CIDR invalido."; return 1; }
  warn "O NFS sera gravavel por todos os clientes desse CIDR, sem autenticacao."
  confirm "Continuar com o servidor NFS?" || return 0

  package="$(native_package_for nfs-kernel-server nfs-utils nfs-kernel-server)"
  install_native_packages "$package"
  run_as_root install -d -m 0777 -o 1000 -g 1000 -- "$share_path"
  replace_managed_block /etc/exports 0644 "LINUX-SETUP-NFS" "$share_path" <<EOF || changed=$?
$share_path $network(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
EOF
  run_as_root exportfs -ra
  service="$(native_package_for nfs-kernel-server.service nfs-server.service nfs-server.service)"
  enable_service "$service" || return 1
  [[ "$changed" -eq 0 ]] && run_as_root systemctl restart "$service"
  firewall_allow_service nfs 2049/tcp
  firewall_allow_service rpc-bind 111/tcp
  info "NFS exportado em $share_path para $network."
}

configure_transmission() {
  local real_user real_home download_dir package service settings service_user temporary

  real_user="${SUDO_USER:-$USER}"
  real_home="$(getent passwd "$real_user" | cut -d: -f6)"
  read -r -e -p "Diretorio de downloads [$real_home/Downloads]: " download_dir
  download_dir="${download_dir:-$real_home/Downloads}"
  download_dir="${download_dir/#\~/$real_home}"
  warn "A Web UI ficara em 0.0.0.0:9091 sem autenticacao, como nos scripts atuais."
  confirm "Continuar com Transmission?" || return 0

  package="$(native_package_for transmission-daemon transmission-daemon transmission)"
  if [[ "$PACKAGE_FAMILY" == "zypper" ]]; then
    install_native_packages "$package" python3
  else
    install_native_packages "$package" transmission-cli python3
  fi
  run_as_root install -d -m 0777 -o "$real_user" -g "$(id -gn "$real_user")" -- "$download_dir"
  case "$PACKAGE_FAMILY" in
    apt)
      service="transmission-daemon.service"
      settings="/etc/transmission-daemon/settings.json"
      service_user="debian-transmission"
      ;;
    dnf)
      service="transmission-daemon.service"
      settings="/var/lib/transmission/.config/transmission-daemon/settings.json"
      service_user="transmission"
      ;;
    zypper)
      service="transmission.service"
      settings="/etc/transmission/settings.json"
      service_user="transmission"
      ;;
  esac
  if service_exists "$service"; then
    run_as_root systemctl stop "$service" || true
  fi
  temporary="$(make_temp)"
  if [[ -r "$settings" ]]; then
    cp -- "$settings" "$temporary"
  else
    printf '{}\n' > "$temporary"
  fi
  python3 - "$temporary" "$download_dir" <<'PY'
import json
import sys

path, download_dir = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    settings = json.load(source)
settings.update({
    "download-dir": download_dir,
    "rpc-enabled": True,
    "rpc-bind-address": "0.0.0.0",
    "rpc-port": 9091,
    "rpc-whitelist": "127.0.0.1,192.168.*.*",
    "rpc-whitelist-enabled": False,
    "rpc-authentication-required": False,
    "incomplete-dir-enabled": False,
    "umask": 0,
    "peer-port": 51413,
    "peer-port-random-on-start": False,
    "pex-enabled": True,
    "port-forwarding-enabled": True,
})
with open(path, "w", encoding="utf-8") as output:
    json.dump(settings, output, indent=4, sort_keys=True)
    output.write("\n")
PY
  install_managed_file "$settings" 0644 < "$temporary" || true
  rm -f "$temporary"
  getent passwd "$service_user" >/dev/null && run_as_root chown "$service_user:$(id -gn "$service_user")" "$settings"
  enable_service "$service" || return 1
  run_as_root systemctl restart "$service"
  firewall_allow_port 9091 tcp
  firewall_allow_port 51413 tcp
  firewall_allow_port 51413 udp
  info "Transmission configurado em http://localhost:9091."
}

confirm() {
  local prompt="$1"
  local answer

  read -r -p "$prompt [s/N] " answer
  [[ "$answer" =~ ^[sS]$ ]]
}

checklist() {
  local title="$1"
  local ids_name="$2"
  local labels_name="$3"
  local states_name="$4"
  local -n ids_ref="$ids_name"
  local -n labels_ref="$labels_name"
  local -n states_ref="$states_name"
  local input token index

  CHECKLIST_RESULT=()
  while true; do
    clear 2>/dev/null || true
    printf '%s\n\n' "$title"
    for index in "${!ids_ref[@]}"; do
      printf '%2d. [%s] %s' "$((index + 1))" "${states_ref[$index]}" "${labels_ref[$index]}"
      [[ "${states_ref[$index]}" == "i" ]] && printf ' (ja instalado)'
      [[ "${states_ref[$index]}" == "!" ]] && printf ' (indisponivel)'
      printf '\n'
    done
    printf '\nNumeros alternam itens; a=todos; n=nenhum; c=continuar; q=cancelar.\n'
    read -r -p "> " input

    case "$input" in
      q|Q) return 1 ;;
      c|C)
        for index in "${!ids_ref[@]}"; do
          [[ "${states_ref[$index]}" == "x" ]] && CHECKLIST_RESULT+=("${ids_ref[$index]}")
        done
        return 0
        ;;
      a|A)
        for index in "${!states_ref[@]}"; do
          [[ "${states_ref[$index]}" == " " ]] && states_ref[index]="x"
        done
        ;;
      n|N)
        for index in "${!states_ref[@]}"; do
          [[ "${states_ref[$index]}" == "x" ]] && states_ref[index]=" "
        done
        ;;
      *)
        for token in $input; do
          [[ "$token" =~ ^[0-9]+$ ]] || continue
          index=$((token - 1))
          ((index >= 0 && index < ${#states_ref[@]})) || continue
          [[ "${states_ref[$index]}" =~ ^(i|!)$ ]] && continue
          if [[ "${states_ref[$index]}" == "x" ]]; then
            states_ref[index]=" "
          else
            states_ref[index]="x"
          fi
        done
        ;;
    esac
  done
}

flatpak_is_installed() {
  flatpak info --system "$1" >/dev/null 2>&1 || flatpak info --user "$1" >/dev/null 2>&1
}

flatpak_is_installed_in_scope() {
  local scope="$1"
  local id="$2"
  flatpak info "--$scope" "$id" >/dev/null 2>&1
}

install_flatpak_app() {
  local id="$1"

  install_native_packages flatpak
  run_as_root flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  if flatpak_is_installed "$id"; then
    info "$id ja esta instalado."
  else
    run_as_root flatpak install --system -y flathub "$id"
  fi
}

remove_flatpak_after_native_install() {
  local id="$1"

  command -v flatpak >/dev/null 2>&1 || return 0
  if flatpak_is_installed_in_scope system "$id"; then
    run_as_root flatpak uninstall --system -y "$id" || return 1
  fi
  if flatpak_is_installed_in_scope user "$id"; then
    run_command flatpak uninstall --user -y "$id" || return 1
  fi
}

app_index_for_key() {
  local key="$1"
  local index

  for index in "${!APP_KEYS[@]}"; do
    [[ "${APP_KEYS[$index]}" == "$key" ]] && {
      printf '%s\n' "$index"
      return 0
    }
  done
  return 1
}

cached_native_package_for_app() {
  local index="$1"
  local package directory extension path identity cached_package

  NATIVE_CACHE_PATH=""
  package="$(native_package_for_app "$index")"
  [[ -n "$package" ]] || return 1
  case "$PACKAGE_FAMILY" in
    apt)
      directory="$DEB_DIR"
      extension="deb"
      ;;
    dnf|zypper)
      directory="$RPM_DIR"
      extension="rpm"
      ;;
  esac
  [[ -d "$directory" ]] || return 1
  while IFS= read -r -d '' path; do
    native_package_is_compatible "$path" "$package" || continue
    identity="$(native_package_identity "$path")" || continue
    read -r cached_package _ <<< "$identity"
    [[ "$cached_package" == "$package" ]] || continue
    NATIVE_CACHE_PATH="$path"
    return 0
  done < <(find "$directory" -maxdepth 1 -type f -iname "*.${extension}" -print0 | sort -z)
  return 1
}

install_app_with_fallback() {
  local index="$1"
  local allow_flatpak_fallback="${2:-0}"
  local key="${APP_KEYS[$index]}"
  local flatpak_id="${FLATPAK_IDS[$index]}"
  local package

  log_event application START "$key"
  package="$(native_package_for_app "$index")"
  if [[ -n "$package" ]] && is_native_package_installed "$package"; then
    info "${FLATPAK_LABELS[$index]} ja esta instalado como pacote nativo."
  elif cached_native_package_for_app "$index"; then
    log_event cache FOUND "$key package=$package cache=$NATIVE_CACHE_PATH"
    info "Instalando $package do cache local: $NATIVE_CACHE_PATH"
    if ! install_cached_native_package "$NATIVE_CACHE_PATH"; then
      log_event installation ERROR "$key package=$package cache=$NATIVE_CACHE_PATH"
      warn "Falha ao instalar o pacote em cache de $key; o Flatpak foi preservado."
      return 1
    fi
    if [[ "$DRY_RUN" != "1" ]] && ! is_native_package_installed "$package"; then
      log_event installation ERROR "$key verificacao-pos-instalacao"
      warn "A instalacao de $package nao foi confirmada; o Flatpak foi preservado."
      return 1
    fi
  else
    log_event cache NOT_FOUND "$key package=${package:-none}"
    if [[ "$allow_flatpak_fallback" != "1" ]]; then
      log_event application ERROR "$key cache-ausente fallback=disabled"
      warn "Nenhum pacote compativel em cache para $key; fallback Flathub desativado."
      return 1
    fi
    info "Nenhum pacote compativel em cache para $key; usando Flathub."
    if install_flatpak_app "$flatpak_id"; then
      log_event application OK "$key method=flatpak"
      return 0
    fi
    log_event application ERROR "$key method=flatpak"
    return 1
  fi

  log_event installation OK "$key method=native package=$package"
  remove_flatpak_after_native_install "$flatpak_id" || {
    log_event flatpak-removal PARTIAL "$key id=$flatpak_id"
    warn "$key foi instalado nativamente, mas o Flatpak duplicado nao foi removido."
    return 1
  }
  log_event application OK "$key method=native"
}

application_menu() {
  local -a states=()
  local -a selected=() labels=()
  local id index key package selected_index allow_flatpak_fallback=0

  for index in "${!APP_KEYS[@]}"; do
    key="${APP_KEYS[$index]}"
    id="${FLATPAK_IDS[$index]}"
    package="$(native_package_for_app "$index")"
    if [[ -n "$package" ]] && is_native_package_installed "$package"; then
      if command -v flatpak >/dev/null 2>&1 && flatpak_is_installed "$id"; then
        states+=(" ")
        labels+=("${FLATPAK_LABELS[$index]} - remover Flatpak duplicado")
      else
        states+=("i")
        labels+=("${FLATPAK_LABELS[$index]} - nativo")
      fi
    elif cached_native_package_for_app "$index"; then
      states+=(" ")
      labels+=("${FLATPAK_LABELS[$index]} - cache: $(basename "$NATIVE_CACHE_PATH")")
    else
      states+=(" ")
      labels+=("${FLATPAK_LABELS[$index]} - sem pacote compativel no cache")
    fi
  done

  checklist "Instalar aplicativos do cache local" APP_KEYS labels states || return 0
  selected=("${CHECKLIST_RESULT[@]}")
  if [[ ${#selected[@]} -eq 0 ]]; then
    info "Nenhum aplicativo selecionado."
    pause
    return 0
  fi

  printf '\nAplicativos selecionados:\n'
  printf '  - %s\n' "${selected[@]}"
  confirm "Iniciar a instalacao dos aplicativos selecionados?" || return 0
  if confirm "Usar Flathub quando nao houver pacote compativel no cache?"; then
    allow_flatpak_fallback=1
  fi
  log_event fallback-policy OK "flathub=$allow_flatpak_fallback aplicativos=${#selected[@]}"

  for key in "${selected[@]}"; do
    selected_index="$(app_index_for_key "$key")" || {
      warn "Aplicativo desconhecido no catalogo: $key"
      continue
    }
    install_app_with_fallback "$selected_index" "$allow_flatpak_fallback" || true
  done
  pause
}

application_cache_menu() {
  local -a states=() selected=()
  local key selected_index

  for _ in "${APP_KEYS[@]}"; do
    states+=(" ")
  done
  checklist "Preparar cache local (DEB e RPM)" APP_KEYS FLATPAK_LABELS states || return 0
  selected=("${CHECKLIST_RESULT[@]}")
  if [[ ${#selected[@]} -eq 0 ]]; then
    info "Nenhum aplicativo selecionado."
    pause
    return 0
  fi

  printf '\nAplicativos selecionados para cache:\n'
  printf '  - %s\n' "${selected[@]}"
  confirm "Baixar os pacotes DEB e RPM disponiveis?" || return 0
  for key in "${selected[@]}"; do
    selected_index="$(app_index_for_key "$key")" || continue
    cache_application_packages "$selected_index" ||
      warn "Nenhum pacote DEB ou RPM foi armazenado para $key."
  done
  pause
}

catalog_update_format() {
  local index="$1"
  local target_family="$2"
  local format checked_at status

  format="$([[ "$target_family" == apt ]] && printf deb || printf rpm)"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[SIMULACAO] consultar fonte %s de %s e atualizar somente o catalogo\n' \
      "$format" "${APP_KEYS[$index]}"
    return 0
  fi
  PACKAGE_FAMILY="$target_family"
  resolve_external_package "$index"
  status="$NATIVE_RESOLUTION_STATUS"
  checked_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  python3 "$CATALOG_TOOL" update-resolved "$APP_LIBRARY" "${APP_KEYS[$index]}" "$format" \
    "$status" "$checked_at" "$NATIVE_DOWNLOAD_URL" "$NATIVE_RESOLUTION_VERSION" \
    "$NATIVE_EXPECTED_SHA256" "$NATIVE_CHECKSUM_URL"
}

catalog_update_application() {
  local index="$1"
  local original_family="$PACKAGE_FAMILY"
  local target_family result success=0

  for target_family in apt dnf; do
    result=0
    catalog_update_format "$index" "$target_family" || result=$?
    if [[ "$result" -eq 0 ]]; then
      success=1
      log_event catalog-update OK "${APP_KEYS[$index]} family=$target_family"
    else
      log_event catalog-update ERROR "${APP_KEYS[$index]} family=$target_family"
    fi
  done
  PACKAGE_FAMILY="$original_family"
  [[ "$success" -eq 1 ]]
}

application_catalog_update_menu() {
  local -a states=() selected=()
  local key selected_index

  for _ in "${APP_KEYS[@]}"; do
    states+=("x")
  done
  checklist "Atualizar links do catalogo" APP_KEYS FLATPAK_LABELS states || return 0
  selected=("${CHECKLIST_RESULT[@]}")
  [[ ${#selected[@]} -gt 0 ]] || return 0
  confirm "Consultar novas versoes para os itens selecionados?" || return 0
  for key in "${selected[@]}"; do
    selected_index="$(app_index_for_key "$key")" || continue
    catalog_update_application "$selected_index" ||
      warn "Nao foi possivel atualizar as fontes de $key."
  done
  load_app_catalog
  pause
}

application_library_menu() {
  python3 "$CATALOG_TOOL" manage "$APP_LIBRARY" $([[ "$DRY_RUN" == "1" ]] && printf -- '--dry-run')
  load_app_catalog
  pause
}

applications_menu() {
  local option

  while true; do
    print_header
    printf 'Aplicativos\n\n'
    printf '1. Preparar cache local (DEB e RPM)\n'
    printf '2. Instalar aplicativos do cache\n'
    printf '3. Atualizar catalogo de links\n'
    printf '4. Gerenciar biblioteca\n'
    printf '0. Voltar\n\n'
    read -r -p "> " option
    case "$option" in
      1) application_cache_menu ;;
      2) application_menu ;;
      3) application_catalog_update_menu ;;
      4) application_library_menu ;;
      0) return 0 ;;
      *) warn "Opcao invalida."; pause ;;
    esac
  done
}

package_file_metadata() {
  local path="$1"

  case "$PACKAGE_FAMILY" in
    apt)
      dpkg-deb -f "$path" Package Version 2>/dev/null | paste -sd ' ' -
      ;;
    dnf|zypper)
      rpm -qp --queryformat '%{NAME} %{VERSION}-%{RELEASE}' "$path" 2>/dev/null
      ;;
  esac
}

local_package_is_current() {
  local path="$1"
  local package version installed_version

  case "$PACKAGE_FAMILY" in
    apt)
      package="$(dpkg-deb -f "$path" Package 2>/dev/null)" || return 1
      version="$(dpkg-deb -f "$path" Version 2>/dev/null)" || return 1
      installed_version="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null)" || return 1
      [[ "$version" == "$installed_version" ]]
      ;;
    dnf|zypper)
      package="$(rpm -qp --queryformat '%{NAME}' "$path" 2>/dev/null)" || return 1
      version="$(rpm -qp --queryformat '%{VERSION}-%{RELEASE}' "$path" 2>/dev/null)" || return 1
      installed_version="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' "$package" 2>/dev/null)" || return 1
      [[ "$version" == "$installed_version" ]]
      ;;
  esac
}

local_package_menu() {
  local directory path metadata index
  local expected_extension
  local -a files=() labels=() states=() selected=()

  case "$PACKAGE_FAMILY" in
    apt)
      expected_extension="deb"
      directory="$DEB_DIR"
      ;;
    dnf|zypper)
      expected_extension="rpm"
      directory="$RPM_DIR"
      ;;
  esac
  info "Lendo pacotes de $directory."

  while IFS= read -r -d '' path; do
    if metadata="$(package_file_metadata "$path")"; then
      files+=("$path")
      labels+=("$(basename "$path") - $metadata")
      if local_package_is_current "$path"; then
        states+=("i")
      else
        states+=(" ")
      fi
    else
      warn "Pacote invalido ignorado: $path"
    fi
  done < <(find "$directory" -maxdepth 1 -type f -iname "*.${expected_extension}" -print0 | sort -z)

  if [[ ${#files[@]} -eq 0 ]]; then
    info "Nenhum arquivo .$expected_extension valido encontrado."
    pause
    return 0
  fi

  checklist "Pacotes locais .$expected_extension" files labels states || return 0
  selected=("${CHECKLIST_RESULT[@]}")
  [[ ${#selected[@]} -gt 0 ]] || {
    info "Nenhum pacote selecionado."
    pause
    return 0
  }

  printf '\nPacotes selecionados:\n'
  for index in "${!selected[@]}"; do
    printf '  - %s\n' "${selected[$index]}"
  done
  confirm "Instalar estes pacotes locais?" || return 0

  case "$PACKAGE_FAMILY" in
    apt)
      update_package_metadata
      run_as_root apt-get install -y -- "${selected[@]}"
      ;;
    dnf)
      run_as_root dnf install -y -- "${selected[@]}"
      ;;
    zypper)
      run_as_root zypper --non-interactive install -- "${selected[@]}"
      ;;
  esac
  pause
}

configuration_menu() {
  local option

  while true; do
    print_header
    printf 'Configuracoes\n\n'
    printf '1. Samba guest share\n'
    printf '2. Servidor FTP\n'
    printf '3. Cliente NFS\n'
    printf '4. Servidor NFS\n'
    printf '5. Transmission\n'
    printf '6. Portas do Plex no firewall\n'
    printf '7. Swapfile\n'
    printf '8. Zram persistente\n'
    printf '9. Flameshot com integracao Wayland\n'
    [[ "$PACKAGE_FAMILY" == "apt" ]] && printf '10. Boot com splash\n'
    printf '0. Voltar\n\n'
    read -r -p "> " option
    case "$option" in
      1) configure_samba || true; pause ;;
      2) configure_ftp || true; pause ;;
      3) if confirm "Preparar este host como cliente NFS?"; then configure_nfs_client || true; fi; pause ;;
      4) configure_nfs_server || true; pause ;;
      5) configure_transmission || true; pause ;;
      6) if confirm "Configurar portas do Plex?"; then configure_plex_firewall || true; fi; pause ;;
      7) configure_swapfile || true; pause ;;
      8) configure_zram || true; pause ;;
      9) if confirm "Instalar e configurar Flameshot?"; then flameshot_configuration || true; fi; pause ;;
      10)
        if [[ "$PACKAGE_FAMILY" == "apt" ]]; then
          boot_splash_menu
        else
          warn "Opcao invalida."
          pause
        fi
        ;;
      0) return 0 ;;
      *) warn "Opcao invalida."; pause ;;
    esac
  done
}

print_header() {
  clear 2>/dev/null || true
  printf '%s\n' "============================================================"
  printf '  %s\n' "$SCRIPT_NAME"
  printf '  Sistema: %s (versao %s)\n' "$DISTRO_NAME" "$DISTRO_VERSION"
  printf '  Familia: %s | Arquitetura: %s\n' "$PACKAGE_FAMILY" "$(uname -m)"
  [[ "$DRY_RUN" == "1" ]] && printf '  Modo: SIMULACAO (nenhuma alteracao sera aplicada)\n'
  printf '%s\n\n' "============================================================"
}

main_menu() {
  local option

  while true; do
    print_header
    printf '1. Configuracoes\n'
    printf '2. Aplicativos\n'
    printf '3. Instalacoes de pacotes locais (.deb/.rpm)\n'
    printf '4. Sair\n\n'
    read -r -p "> " option

    case "$option" in
      1) configuration_menu ;;
      2) applications_menu ;;
      3) local_package_menu ;;
      4) return 0 ;;
      *) warn "Opcao invalida."; pause ;;
    esac
  done
}

main() {
  case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      printf 'Uso: %s [--dry-run]\n' "$0"
      printf '  --dry-run  Exibe as alteracoes sem aplica-las.\n'
      return 0
      ;;
    "") ;;
    *) die "Argumento desconhecido: $1" ;;
  esac
  start_logging
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/linux-setup.XXXXXX")"
  chmod 0700 "$WORK_DIR"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  detect_platform
  reconcile_repository_transaction
  ensure_local_package_directories
  load_app_catalog
  main_menu
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi