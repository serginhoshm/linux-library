#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME=""
LOCAL_NET=""
REAL_USER=""
USER_UID="0"
USER_GID="0"
NFS_OPTS=""
ACCESS_MODE="lan"
SERVER_HOSTNAME=""
SERVER_MDNS_NAME=""

banner() {
    cat <<'EOF'
============================================================
 NFS Server Helper - Configuracao assistida
------------------------------------------------------------
 Este script vai:
 - verificar e instalar pacotes necessarios do servidor NFS
 - detectar automaticamente a rede local ativa
 - permitir adicionar/remover exports em menu interativo
 - reiniciar o servidor NFS e ajustar permissoes dos exports
============================================================
EOF
}

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "Execute como root: sudo $0"
        exit 1
    fi
}

detect_real_user() {
    if [[ -n "${SUDO_USER:-}" ]] && id "${SUDO_USER}" >/dev/null 2>&1; then
        REAL_USER="${SUDO_USER}"
    elif logname >/dev/null 2>&1; then
        REAL_USER="$(logname)"
    elif id -un >/dev/null 2>&1; then
        REAL_USER="$(id -un)"
    else
        REAL_USER="root"
    fi

    USER_UID="$(id -u "${REAL_USER}" 2>/dev/null || echo 0)"
    USER_GID="$(id -g "${REAL_USER}" 2>/dev/null || echo 0)"
    NFS_OPTS="rw,sync,all_squash,anonuid=${USER_UID},anongid=${USER_GID},no_subtree_check"
}

detect_distro_and_install() {
    echo "[Pre-config] Verificando distribuicao e pacotes..."

    if [[ -f /etc/debian_version ]]; then
        SERVICE_NAME="nfs-kernel-server"
        export DEBIAN_FRONTEND=noninteractive
        apt update
        apt install -y nfs-kernel-server avahi-daemon libnss-mdns
    elif [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
        SERVICE_NAME="nfs-server"
        dnf install -y nfs-utils avahi nss-mdns
    else
        echo "Distribuicao nao suportada automaticamente."
        exit 1
    fi

    systemctl enable --now "${SERVICE_NAME}"
    systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
}

detect_server_name() {
    SERVER_HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
    SERVER_MDNS_NAME="${SERVER_HOSTNAME}.local"
}

ip_to_int() {
    local ip="$1"
    local a b c d
    IFS=. read -r a b c d <<<"${ip}"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int_to_ip() {
    local ip_int="$1"
    echo "$(( (ip_int >> 24) & 255 )).$(( (ip_int >> 16) & 255 )).$(( (ip_int >> 8) & 255 )).$(( ip_int & 255 ))"
}

cidr_to_mask_int() {
    local prefix="$1"
    if [[ "${prefix}" -eq 0 ]]; then
        echo 0
    else
        echo $(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    fi
}

network_from_cidr() {
    local ip_cidr="$1"
    local ip="${ip_cidr%/*}"
    local prefix="${ip_cidr#*/}"
    local ip_int mask_int net_int

    ip_int="$(ip_to_int "${ip}")"
    mask_int="$(cidr_to_mask_int "${prefix}")"
    net_int=$(( ip_int & mask_int ))

    echo "$(int_to_ip "${net_int}")/${prefix}"
}

detect_local_network() {
    local default_dev cidr
    default_dev="$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')"

    if [[ -n "${default_dev}" ]]; then
        cidr="$(ip -o -f inet addr show dev "${default_dev}" 2>/dev/null | awk 'NR==1 {print $4}')"
    else
        cidr=""
    fi

    if [[ -z "${cidr}" ]]; then
        cidr="$(ip -o -f inet addr show scope global 2>/dev/null | awk 'NR==1 {print $4}')"
    fi

    if [[ -z "${cidr}" ]]; then
        echo "Nao foi possivel detectar automaticamente a rede local ativa."
        read -r -p "Informe a rede em CIDR (exemplo 192.168.1.0/24): " LOCAL_NET
    else
        LOCAL_NET="$(network_from_cidr "${cidr}")"
    fi

    echo "[Pre-config] Rede local para compartilhamento: ${LOCAL_NET}"
}

pause_menu() {
    echo
    read -r -p "Pressione Enter para voltar ao menu..." _
}

choose_access_mode() {
    local choice confirm

    echo
    echo "Modo de acesso para novos exports:"
    echo "1) Seguro (apenas rede local detectada: ${LOCAL_NET})"
    echo "2) Aberto (0.0.0.0/0 - alto risco)"
    read -r -p "Escolha [1-2] (padrao 1): " choice

    case "${choice:-1}" in
        1)
            ACCESS_MODE="lan"
            ;;
        2)
            echo "ATENCAO: esse modo permite acesso a partir de qualquer origem roteavel."
            read -r -p "Digite EU ACEITO para confirmar: " confirm
            if [[ "${confirm}" == "EU ACEITO" ]]; then
                ACCESS_MODE="open"
            else
                echo "Confirmacao nao reconhecida. Mantendo modo seguro de LAN."
                ACCESS_MODE="lan"
            fi
            ;;
        *)
            echo "Opcao invalida. Mantendo modo seguro de LAN."
            ACCESS_MODE="lan"
            ;;
    esac
}

show_exports_status() {
    echo "--------------------------------------------"
    echo "Exports atuais (/etc/exports):"

    if [[ ! -f /etc/exports ]] || ! grep -Eq '^[[:space:]]*[^#[:space:]]' /etc/exports; then
        echo "(nenhum export configurado)"
        return
    fi

    awk '!/^[[:space:]]*($|#)/ {print}' /etc/exports | nl -w1 -s') '
}

reload_exports() {
    exportfs -arv
}

add_nfs_export() {
    local share_dir export_line target_net tmp_file

    read -r -p "Diretorio absoluto para exportar (ex: /srv/nfs/dados): " share_dir

    if [[ -z "${share_dir}" || "${share_dir}" != /* ]]; then
        echo "Diretorio invalido. Use um caminho absoluto."
        pause_menu
        return
    fi

    if [[ ! -d "${share_dir}" ]]; then
        echo "Diretorio nao existe. Criando ${share_dir}..."
        mkdir -p "${share_dir}"
    fi

    chown -R "${REAL_USER}:${REAL_USER}" "${share_dir}"
    chmod 755 "${share_dir}"

    touch /etc/exports
    tmp_file="$(mktemp)"
    awk -v path="${share_dir}" '$1 != path {print}' /etc/exports > "${tmp_file}"
    mv "${tmp_file}" /etc/exports

    if [[ "${ACCESS_MODE}" == "open" ]]; then
        target_net="0.0.0.0/0"
    else
        target_net="${LOCAL_NET}"
    fi

    export_line="${share_dir} ${target_net}(${NFS_OPTS})"
    echo "${export_line}" >> /etc/exports

    echo "Export adicionado: ${export_line}"
    reload_exports
    restart_nfs_server "silent"
    pause_menu
}

remove_nfs_export() {
    local -a paths
    local idx selected path confirm tmp_file

    if [[ ! -f /etc/exports ]] || ! grep -Eq '^[[:space:]]*[^#[:space:]]' /etc/exports; then
        echo "Nao ha exports para remover."
        pause_menu
        return
    fi

    mapfile -t paths < <(awk '!/^[[:space:]]*($|#)/ {print $1}' /etc/exports)
    echo "Selecione o export para remover:"
    for idx in "${!paths[@]}"; do
        printf "%d) %s\n" "$((idx + 1))" "${paths[$idx]}"
    done

    read -r -p "Numero: " selected
    if ! [[ "${selected}" =~ ^[0-9]+$ ]] || (( selected < 1 || selected > ${#paths[@]} )); then
        echo "Opcao invalida."
        pause_menu
        return
    fi

    path="${paths[$((selected - 1))]}"

    read -r -p "Confirma remover o export ${path}? [s/N]: " confirm
    if [[ ! "${confirm}" =~ ^[sS]$ ]]; then
        echo "Remocao cancelada."
        pause_menu
        return
    fi

    tmp_file="$(mktemp)"
    awk -v target="${path}" '$1 != target {print}' /etc/exports > "${tmp_file}"
    mv "${tmp_file}" /etc/exports

    echo "Export removido: ${path}"
    reload_exports
    restart_nfs_server "silent"
    pause_menu
}

restart_nfs_server() {
    local mode="${1:-verbose}"

    systemctl restart "${SERVICE_NAME}"
    reload_exports

    if [[ "${mode}" != "silent" ]]; then
        echo "Servidor NFS reiniciado com sucesso."
        pause_menu
    fi
}

fix_permissions_all_exports() {
    local -a paths
    local path

    if [[ ! -f /etc/exports ]] || ! grep -Eq '^[[:space:]]*[^#[:space:]]' /etc/exports; then
        echo "Nao ha exports para ajustar permissoes."
        pause_menu
        return
    fi

    mapfile -t paths < <(awk '!/^[[:space:]]*($|#)/ {print $1}' /etc/exports | sort -u)

    for path in "${paths[@]}"; do
        if [[ -d "${path}" ]]; then
            chown -R "${REAL_USER}:${REAL_USER}" "${path}"
            chmod -R u+rwX,go+rX "${path}"
            echo "Permissoes ajustadas: ${path}"
        else
            echo "Ignorado (diretorio nao existe): ${path}"
        fi
    done

    pause_menu
}

main_menu() {
    local option

    while true; do
        clear
        banner
        echo "Usuario de mapeamento anonimo: ${REAL_USER} (UID ${USER_UID} / GID ${USER_GID})"
        echo "Rede local detectada: ${LOCAL_NET}"
        echo "Referencia recomendada para clientes: ${SERVER_MDNS_NAME}"
        if [[ "${ACCESS_MODE}" == "open" ]]; then
            echo "Modo de acesso padrao (novos exports): ABERTO (0.0.0.0/0)"
        else
            echo "Modo de acesso padrao (novos exports): LAN (${LOCAL_NET})"
        fi
        echo
        echo "============== MENU NFS =============="
        echo "1. Adicionar um NFS"
        echo "2. Remover um NFS"
        echo "3. Reiniciar servidor NFS"
        echo "4. Ajustar permissoes em todos os exports"
        echo "5. Sair"
        show_exports_status
        echo "======================================"
        read -r -p "Escolha uma opcao: " option

        case "${option}" in
            1) add_nfs_export ;;
            2) remove_nfs_export ;;
            3) restart_nfs_server ;;
            4) fix_permissions_all_exports ;;
            5)
                echo "Saindo do assistente NFS."
                exit 0
                ;;
            *)
                echo "Opcao invalida."
                pause_menu
                ;;
        esac
    done
}

banner
check_root
detect_real_user
detect_distro_and_install
detect_local_network
detect_server_name
choose_access_mode
main_menu