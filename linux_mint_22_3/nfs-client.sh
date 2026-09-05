#!/usr/bin/env bash

set -euo pipefail

LOCAL_NET=""
MOUNT_OPTS="rw,soft,timeo=50,retrans=2,_netdev"
FSTAB_MOUNT_OPTS="${MOUNT_OPTS},nofail,x-systemd.automount,x-systemd.mount-timeout=10s"
TEST_MOUNT_OPTS="rw,soft,timeo=50,retrans=2"
CLIENT_SERVICE_HINT=""

declare -a DISCOVERED_IPS=()
declare -a DISCOVERED_REFS=()
declare -a DISCOVERED_ITEM_REFS=()
declare -a DISCOVERED_ITEM_IPS=()
declare -a DISCOVERED_ITEM_EXPORTS=()
declare -a DISCOVERED_ITEM_MOUNTS=()

banner() {
    cat <<'EOF'
============================================================
 NFS Client Helper - Configuracao assistida
------------------------------------------------------------
 Este script vai:
 - verificar e instalar dependencias do cliente NFS
 - descobrir servidores NFS na rede local
 - montar/desmontar compartilhamentos com persistencia
 - usar mountpoints no padrao /mnt/nfs-<compartilhamento>
============================================================
EOF
}

check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "Execute como root: sudo $0"
        exit 1
    fi
}

pause_menu() {
    echo
    read -r -p "Pressione Enter para voltar ao menu..." _
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

    echo "[Pre-config] Rede local detectada: ${LOCAL_NET}"
}

detect_distro_and_install() {
    echo "[Pre-config] Verificando distribuicao e pacotes..."

    if [[ -f /etc/debian_version ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt update
        apt install -y nfs-common nmap avahi-daemon libnss-mdns
        CLIENT_SERVICE_HINT="nfs-common"
        systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
    elif [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
        dnf install -y nfs-utils nmap avahi nss-mdns
        CLIENT_SERVICE_HINT="nfs-utils"
        systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
    else
        echo "Distribuicao nao suportada automaticamente."
        exit 1
    fi

    echo "[Pre-config] Dependencias do cliente NFS prontas (${CLIENT_SERVICE_HINT})."
}

sanitize_share_name() {
    local raw_name="$1"
    echo "${raw_name}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//'
}

mountpoint_from_export() {
    local remote_export="$1"
    local base_name clean_name

    base_name="$(basename "${remote_export}")"
    clean_name="$(sanitize_share_name "${base_name}")"
    if [[ -z "${clean_name}" ]]; then
        clean_name="compartilhamento"
    fi

    echo "/mnt/nfs-${clean_name}"
}

resolve_preferred_ref() {
    local ip="$1"
    local mdns_name

    if command -v avahi-resolve-address >/dev/null 2>&1; then
        mdns_name="$(avahi-resolve-address "${ip}" 2>/dev/null | awk '{print $2}')"
        if [[ -n "${mdns_name}" ]]; then
            echo "${mdns_name}"
            return
        fi
    fi

    echo "${ip}"
}

resolve_ip_from_ref() {
    local ref="$1"
    local resolved_ip

    if [[ "${ref}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "${ref}"
        return
    fi

    resolved_ip="$(getent ahostsv4 "${ref}" 2>/dev/null | awk 'NR==1 {print $1}')"
    echo "${resolved_ip}"
}

list_exports_raw() {
    local server_ref="$1"
    showmount -e "${server_ref}" 2>/dev/null | awk 'NR > 1 && $1 ~ /^\// {print $1}'
}

append_discovered_item() {
    local ref="$1"
    local ip="$2"
    local export_path="$3"
    local mountpoint

    mountpoint="$(mountpoint_from_export "${export_path}")"
    DISCOVERED_ITEM_REFS+=("${ref}")
    DISCOVERED_ITEM_IPS+=("${ip}")
    DISCOVERED_ITEM_EXPORTS+=("${export_path}")
    DISCOVERED_ITEM_MOUNTS+=("${mountpoint}")
}

print_discovered_items() {
    local idx
    if [[ ${#DISCOVERED_ITEM_REFS[@]} -eq 0 ]]; then
        echo "Nenhum compartilhamento descoberto no cache."
        return
    fi

    echo "Compartilhamentos descobertos (use o indice nas opcoes 3, 4 e 5):"
    for idx in "${!DISCOVERED_ITEM_REFS[@]}"; do
        printf "%d) %s (ip: %s) | export: %s | mount: %s\n" \
            "$((idx + 1))" \
            "${DISCOVERED_ITEM_REFS[$idx]}" \
            "${DISCOVERED_ITEM_IPS[$idx]}" \
            "${DISCOVERED_ITEM_EXPORTS[$idx]}" \
            "${DISCOVERED_ITEM_MOUNTS[$idx]}"
    done
}

discover_nfs_servers() {
    local mode="${1:-interactive}"
    local -a scan_ips=()
    local -a exports=()
    local ip ref export_path

    DISCOVERED_IPS=()
    DISCOVERED_REFS=()
    DISCOVERED_ITEM_REFS=()
    DISCOVERED_ITEM_IPS=()
    DISCOVERED_ITEM_EXPORTS=()
    DISCOVERED_ITEM_MOUNTS=()

    echo "[Descoberta] Varredura na rede ${LOCAL_NET} (portas 111 e 2049)..."

    mapfile -t scan_ips < <(
        nmap -n -p 111,2049 --open "${LOCAL_NET}" -oG - 2>/dev/null \
            | awk '/Host: / {print $2}' \
            | sort -u
    )

    if [[ ${#scan_ips[@]} -eq 0 ]]; then
        echo "Nenhum host candidato encontrado nas portas NFS/RPC."
        if [[ "${mode}" == "interactive" ]]; then
            pause_menu
        fi
        return
    fi

    for ip in "${scan_ips[@]}"; do
        if showmount -e "${ip}" >/dev/null 2>&1; then
            ref="$(resolve_preferred_ref "${ip}")"
            DISCOVERED_IPS+=("${ip}")
            DISCOVERED_REFS+=("${ref}")

            mapfile -t exports < <(list_exports_raw "${ip}")
            for export_path in "${exports[@]}"; do
                append_discovered_item "${ref}" "${ip}" "${export_path}"
            done
        fi
    done

    if [[ ${#DISCOVERED_ITEM_REFS[@]} -eq 0 ]]; then
        echo "Hosts encontrados, mas nenhum respondeu com exports NFS."
        if [[ "${mode}" == "interactive" ]]; then
            pause_menu
        fi
        return
    fi

    print_discovered_items

    if [[ "${mode}" == "interactive" ]]; then
        pause_menu
    fi
}

ensure_discovery_cache() {
    if [[ ${#DISCOVERED_ITEM_REFS[@]} -eq 0 ]]; then
        echo "[Info] Nenhum cache de discovery encontrado. Executando descoberta agora..." >&2
        discover_nfs_servers "auto" >&2
    fi
}

choose_export_from_server_manual() {
    local server_ref="$1"
    local server_ip="$2"
    local -a exports=()
    local choice

    mapfile -t exports < <(list_exports_raw "${server_ref}")
    if [[ ${#exports[@]} -eq 0 ]]; then
        echo "||"
        return
    fi

    echo "Exports disponiveis em ${server_ref}:" >&2
    for choice in "${!exports[@]}"; do
        printf "%d) %s (mount: %s)\n" "$((choice + 1))" "${exports[$choice]}" "$(mountpoint_from_export "${exports[$choice]}")" >&2
    done
    read -r -p "Escolha o indice do export: " choice

    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#exports[@]} )); then
        echo "||"
        return
    fi

    echo "${server_ref}|${server_ip}|${exports[$((choice - 1))]}"
}

choose_discovered_item() {
    local selected idx manual_ref manual_ip manual_item

    ensure_discovery_cache

    while true; do
        if [[ ${#DISCOVERED_ITEM_REFS[@]} -gt 0 ]]; then
            print_discovered_items >&2
            echo "0) Fallback manual (hostname/IP + indice do export)" >&2
            echo "r) Refazer discovery" >&2
            read -r -p "Escolha o indice: " selected

            if [[ "${selected}" =~ ^[0-9]+$ ]] && (( selected >= 1 && selected <= ${#DISCOVERED_ITEM_REFS[@]} )); then
                idx=$((selected - 1))
                echo "${DISCOVERED_ITEM_REFS[$idx]}|${DISCOVERED_ITEM_IPS[$idx]}|${DISCOVERED_ITEM_EXPORTS[$idx]}"
                return
            elif [[ "${selected}" == "0" ]]; then
                read -r -p "Servidor (hostname.local ou IP): " manual_ref
                if [[ -z "${manual_ref}" ]]; then
                    echo "Servidor invalido." >&2
                    continue
                fi
                manual_ip="$(resolve_ip_from_ref "${manual_ref}")"
                manual_item="$(choose_export_from_server_manual "${manual_ref}" "${manual_ip}")"
                if [[ "${manual_item}" == "||" ]]; then
                    echo "Falha ao selecionar export manualmente." >&2
                    continue
                fi
                echo "${manual_item}"
                return
            elif [[ "${selected}" =~ ^[rR]$ ]]; then
                discover_nfs_servers "auto" >&2
            else
                echo "Opcao invalida." >&2
            fi
        else
            echo "Nenhum item descoberto na rede." >&2
            read -r -p "Fallback manual - servidor (hostname.local ou IP): " manual_ref
            if [[ -z "${manual_ref}" ]]; then
                echo "Servidor invalido." >&2
                continue
            fi
            manual_ip="$(resolve_ip_from_ref "${manual_ref}")"
            manual_item="$(choose_export_from_server_manual "${manual_ref}" "${manual_ip}")"
            if [[ "${manual_item}" == "||" ]]; then
                echo "Falha ao selecionar export manualmente." >&2
                continue
            fi
            echo "${manual_item}"
            return
        fi
    done
}

choose_server_target() {
    local selected manual_ref idx

    ensure_discovery_cache

    while true; do
        if [[ ${#DISCOVERED_REFS[@]} -gt 0 ]]; then
            echo "Selecione o servidor por indice:"
            for idx in "${!DISCOVERED_REFS[@]}"; do
                printf "%d) %s (ip: %s)\n" "$((idx + 1))" "${DISCOVERED_REFS[$idx]}" "${DISCOVERED_IPS[$idx]}"
            done
            echo "0) Informar manualmente hostname/IP"
            echo "r) Refazer discovery"
            read -r -p "Escolha: " selected

            if [[ "${selected}" =~ ^[0-9]+$ ]] && (( selected >= 1 && selected <= ${#DISCOVERED_REFS[@]} )); then
                echo "${DISCOVERED_REFS[$((selected - 1))]}|${DISCOVERED_IPS[$((selected - 1))]}"
                return
            elif [[ "${selected}" == "0" ]]; then
                read -r -p "Servidor (hostname.local ou IP): " manual_ref
                if [[ -n "${manual_ref}" ]]; then
                    echo "${manual_ref}|"
                    return
                fi
                echo "Servidor invalido."
            elif [[ "${selected}" =~ ^[rR]$ ]]; then
                discover_nfs_servers "auto"
            else
                echo "Opcao invalida."
            fi
        else
            echo "Nenhum servidor encontrado via discovery."
            read -r -p "Fallback manual - informe hostname/IP: " manual_ref
            if [[ -n "${manual_ref}" ]]; then
                echo "${manual_ref}|"
                return
            fi
            echo "Servidor invalido."
        fi
    done
}

list_exports_from_server() {
    local selected server_ref
    selected="$(choose_server_target)"
    server_ref="${selected%%|*}"

    if [[ -z "${server_ref}" ]]; then
        echo "Servidor invalido."
        pause_menu
        return
    fi

    echo "Consultando exports de ${server_ref}..."
    if ! showmount -e "${server_ref}"; then
        echo "Falha ao consultar exports de ${server_ref}."
    fi

    pause_menu
}

ensure_mountpoint() {
    local mountpoint="$1"
    if [[ ! -d "${mountpoint}" ]]; then
        mkdir -p "${mountpoint}"
    fi
}

write_fstab_entry() {
    local remote="$1"
    local mountpoint="$2"
    local tmp_file line

    line="${remote} ${mountpoint} nfs ${FSTAB_MOUNT_OPTS} 0 0"
    tmp_file="$(mktemp)"

    awk -v remote="${remote}" -v mountpoint="${mountpoint}" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ {print; next}
        ($1 == remote || $2 == mountpoint) {next}
        {print}
    ' /etc/fstab > "${tmp_file}"

    printf "%s\n" "${line}" >> "${tmp_file}"
    mv "${tmp_file}" /etc/fstab
}

remove_fstab_entry() {
    local remote="$1"
    local mountpoint="$2"
    local tmp_file

    tmp_file="$(mktemp)"

    awk -v remote="${remote}" -v mountpoint="${mountpoint}" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ {print; next}
        ($1 == remote || $2 == mountpoint) {next}
        {print}
    ' /etc/fstab > "${tmp_file}"

    mv "${tmp_file}" /etc/fstab
}

mount_and_persist() {
    local selected server_ref server_ip remote_export remote mountpoint

    selected="$(choose_discovered_item)"
    server_ref="${selected%%|*}"
    selected="${selected#*|}"
    server_ip="${selected%%|*}"
    remote_export="${selected#*|}"

    if [[ -z "${server_ref}" || -z "${remote_export}" ]]; then
        echo "Selecao invalida."
        pause_menu
        return
    fi

    mountpoint="$(mountpoint_from_export "${remote_export}")"
    remote="${server_ref}:${remote_export}"

    ensure_mountpoint "${mountpoint}"

    if findmnt -rn -T "${mountpoint}" >/dev/null 2>&1; then
        echo "Ja existe montagem ativa em ${mountpoint}."
    else
        mount -t nfs -o "${MOUNT_OPTS}" "${remote}" "${mountpoint}"
        echo "Montagem ativa: ${remote} em ${mountpoint}"
    fi

    write_fstab_entry "${remote}" "${mountpoint}"
    if [[ -n "${server_ip}" && "${server_ip}" != "${server_ref}" ]]; then
        remove_fstab_entry "${server_ip}:${remote_export}" "${mountpoint}"
        write_fstab_entry "${remote}" "${mountpoint}"
    fi
    echo "Persistencia aplicada no /etc/fstab (boot tolerante + automount sob demanda)."

    pause_menu
}

unmount_and_unpersist() {
    local selected server_ref server_ip remote_export mountpoint remote remote_ip

    selected="$(choose_discovered_item)"
    server_ref="${selected%%|*}"
    selected="${selected#*|}"
    server_ip="${selected%%|*}"
    remote_export="${selected#*|}"

    if [[ -z "${server_ref}" || -z "${remote_export}" ]]; then
        echo "Selecao invalida."
        pause_menu
        return
    fi

    mountpoint="$(mountpoint_from_export "${remote_export}")"
    remote="${server_ref}:${remote_export}"
    remote_ip="${server_ip}:${remote_export}"

    if findmnt -rn -T "${mountpoint}" >/dev/null 2>&1; then
        umount "${mountpoint}"
        echo "Desmontado: ${mountpoint}"
    else
        echo "Mountpoint nao estava montado: ${mountpoint}"
    fi

    remove_fstab_entry "${remote}" "${mountpoint}"
    if [[ -n "${server_ip}" && "${server_ip}" != "${server_ref}" ]]; then
        remove_fstab_entry "${remote_ip}" "${mountpoint}"
    fi
    echo "Entrada removida do /etc/fstab (se existente): ${remote} ${mountpoint}"

    pause_menu
}

test_temporary_mount() {
    local selected server_ref remote_export remote mountpoint

    selected="$(choose_discovered_item)"
    server_ref="${selected%%|*}"
    selected="${selected#*|}"
    remote_export="${selected#*|}"

    if [[ -z "${server_ref}" || -z "${remote_export}" ]]; then
        echo "Selecao invalida."
        pause_menu
        return
    fi

    mountpoint="$(mountpoint_from_export "${remote_export}")"
    remote="${server_ref}:${remote_export}"

    ensure_mountpoint "${mountpoint}"
    mount -t nfs -o "${TEST_MOUNT_OPTS}" "${remote}" "${mountpoint}"
    echo "Teste concluido. Montagem temporaria ativa em ${mountpoint}."
    echo "(Nenhuma alteracao no /etc/fstab foi feita.)"

    pause_menu
}

adjust_firewall_client() {
    if systemctl is-active --quiet ufw; then
        ufw allow out to "${LOCAL_NET}" port 111 proto tcp
        ufw allow out to "${LOCAL_NET}" port 111 proto udp
        ufw allow out to "${LOCAL_NET}" port 2049 proto tcp
        ufw allow out to "${LOCAL_NET}" port 2049 proto udp
        echo "Regras de saida aplicadas no UFW para a rede ${LOCAL_NET}."
    elif systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service=nfs
        firewall-cmd --permanent --add-service=rpc-bind
        firewall-cmd --reload
        echo "Servicos NFS/rpc-bind aplicados no firewalld."
    else
        echo "Nenhum firewall gerenciado (ufw/firewalld) ativo."
    fi

    pause_menu
}

show_active_mounts() {
    echo "Montagens NFS ativas:"
    if ! findmnt -t nfs,nfs4 -o SOURCE,TARGET,FSTYPE,OPTIONS; then
        echo "Nenhuma montagem NFS ativa."
    fi
    pause_menu
}

main_menu() {
    local option

    while true; do
        clear
        banner
        echo "Rede local detectada: ${LOCAL_NET}"
        echo "Padrao de mountpoint: /mnt/nfs-<compartilhamento>"
        echo
        echo "============== MENU CLIENTE NFS =============="
        echo "1. Descobrir compartilhamentos NFS na LAN (lista com indice)"
        echo "2. Listar exports de um servidor"
        echo "3. Montar e persistir (fstab, por indice da lista)"
        echo "4. Desmontar e remover persistencia (fstab, por indice da lista)"
        echo "5. Teste de montagem (temporario, por indice da lista)"
        echo "6. Ajustar firewall do cliente"
        echo "7. Mostrar montagens NFS ativas"
        echo "8. Sair"
        echo "==============================================="
        read -r -p "Escolha uma opcao: " option

        case "${option}" in
            1) discover_nfs_servers ;;
            2) list_exports_from_server ;;
            3) mount_and_persist ;;
            4) unmount_and_unpersist ;;
            5) test_temporary_mount ;;
            6) adjust_firewall_client ;;
            7) show_active_mounts ;;
            8)
                echo "Saindo do assistente NFS cliente."
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
detect_distro_and_install
detect_local_network
main_menu