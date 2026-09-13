#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_NAME="Linux Setup"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly FLATPAK_CATALOG="$SCRIPT_DIR/flatpak-apps.md"
readonly DEB_DIR="$SCRIPT_DIR/deb"
readonly RPM_DIR="$SCRIPT_DIR/rpm"
DRY_RUN="${LINUX_SETUP_DRY_RUN:-0}"
TEST_PACKAGE_FAMILY="${LINUX_SETUP_TEST_FAMILY:-}"
WORK_DIR=""

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

pause() {
  [[ -t 0 ]] || return 0
  read -r -p "Pressione Enter para continuar..." _
}

cleanup() {
  [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
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

load_flatpak_catalog() {
  local raw_id raw_label id label
  local -A seen=()

  [[ -r "$FLATPAK_CATALOG" ]] || die "Catalogo Flatpak nao encontrado: $FLATPAK_CATALOG"
  FLATPAK_IDS=()
  FLATPAK_LABELS=()
  while IFS='|' read -r _ raw_id raw_label _ _; do
    id="$(trim_whitespace "${raw_id//\`/}")"
    label="$(trim_whitespace "$raw_label")"
    [[ "$id" =~ ^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$ ]] || continue
    [[ -n "$label" ]] || die "Nome vazio para o Flatpak $id."
    [[ -z "${seen[$id]:-}" ]] || die "ID Flatpak duplicado no catalogo: $id"
    seen[$id]=1
    FLATPAK_IDS+=("$id")
    FLATPAK_LABELS+=("$label")
  done < "$FLATPAK_CATALOG"
  [[ ${#FLATPAK_IDS[@]} -gt 0 ]] || die "O catalogo Flatpak nao contem aplicativos validos."
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
          [[ "${states_ref[$index]}" != "i" ]] && states_ref[index]="x"
        done
        ;;
      n|N)
        for index in "${!states_ref[@]}"; do
          [[ "${states_ref[$index]}" != "i" ]] && states_ref[index]=" "
        done
        ;;
      *)
        for token in $input; do
          [[ "$token" =~ ^[0-9]+$ ]] || continue
          index=$((token - 1))
          ((index >= 0 && index < ${#states_ref[@]})) || continue
          [[ "${states_ref[$index]}" == "i" ]] && continue
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

flatpak_menu() {
  local -a states=()
  local -a selected=()
  local id index

  for id in "${FLATPAK_IDS[@]}"; do
    if command -v flatpak >/dev/null 2>&1 && flatpak_is_installed "$id"; then
      states+=("i")
    else
      states+=(" ")
    fi
  done

  checklist "Instalacoes Flatpak" FLATPAK_IDS FLATPAK_LABELS states || return 0
  selected=("${CHECKLIST_RESULT[@]}")
  if [[ ${#selected[@]} -eq 0 ]]; then
    info "Nenhum aplicativo selecionado."
    pause
    return 0
  fi

  printf '\nAplicativos selecionados:\n'
  printf '  - %s\n' "${selected[@]}"
  confirm "Instalar estes Flatpaks no escopo do sistema?" || return 0

  case "$PACKAGE_FAMILY" in
    apt|dnf|zypper) install_native_packages flatpak ;;
  esac
  run_as_root flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

  for id in "${selected[@]}"; do
    if flatpak_is_installed "$id"; then
      info "$id ja esta instalado."
    else
      run_as_root flatpak install --system -y flathub "$id"
    fi
  done
  pause
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
    printf '2. Instalacoes Flatpak\n'
    printf '3. Instalacoes de pacotes locais (.deb/.rpm)\n'
    printf '4. Sair\n\n'
    read -r -p "> " option

    case "$option" in
      1) configuration_menu ;;
      2) flatpak_menu ;;
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
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/linux-setup.XXXXXX")"
  chmod 0700 "$WORK_DIR"
  trap cleanup EXIT INT TERM
  detect_platform
  ensure_local_package_directories
  load_flatpak_catalog
  main_menu
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi