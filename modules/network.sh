#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/network.sh — NETWORK: información y diagnóstico de red
#  CLI: urb network [summary|interfaces|routes|gateway|connections|discover|ping|check]
# =============================================================================

[[ -n "${_URB_NETWORK_LOADED:-}" ]] && return 0
_URB_NETWORK_LOADED=1

network_help() {
    cat <<EOF
${C_BOLD}urb network${C_RESET} — network information and diagnostics

${C_BOLD}USAGE${C_RESET}
  urb network [action] [options]

${C_BOLD}ACTIONS${C_RESET}
  summary                 Overview: IP, gateway, VPN, DNS, interfaces (default)
  interfaces              Interfaces with state, MAC, IPv4 and IPv6
  routes                  Routing table and default gateway
  gateway                 Default gateway and reachability
  connections [--listen|--established]
                          Active TCP/UDP sockets (ss)
  discover <CIDR> [--sudo] [--force]
                          Host discovery with nmap -sn (lab networks only)
  ping <host> [-c N]      Connectivity test to a host
  check                   Connectivity check: gateway, internet, DNS, HTTPS

${T_DIM}Discovery is limited to private/lab ranges unless --force is used.${C_RESET}
EOF
}

# --- Utilidades IPv4 -----------------------------------------------------------
_ip2int() { local a b c d; IFS=. read -r a b c d <<<"$1"; printf '%d' $(( (10#$a << 24) + (10#$b << 16) + (10#$c << 8) + 10#$d )); }
_int2ip() { local n=$1; printf '%d.%d.%d.%d' $(( (n >> 24) & 255 )) $(( (n >> 16) & 255 )) $(( (n >> 8) & 255 )) $(( n & 255 )); }

# net_cidr_network 10.0.2.15/24 → 10.0.2.0/24
net_cidr_network() {
    is_cidr4 "$1" || return 1
    local ip="${1%/*}" pfx="${1#*/}" n mask
    n="$(_ip2int "$ip")"
    if (( pfx == 0 )); then mask=0; else mask=$(( (0xFFFFFFFF << (32 - pfx)) & 0xFFFFFFFF )); fi
    printf '%s/%d' "$(_int2ip $(( n & mask )))" "$pfx"
}

# Red local principal (para sugerir en el descubrimiento)
net_primary_cidr() {
    local ip name state v4
    ip="$(sys_local_ip)"
    while IFS='|' read -r name state v4 _; do
        [[ -n "$v4" && "${v4%/*}" == "$ip" ]] && { net_cidr_network "$v4"; return 0; }
    done < <(sys_interfaces)
    return 1
}

_net_dns_servers() {
    local line out=()
    [[ -r /etc/resolv.conf ]] || return 0
    while read -r line; do
        [[ "$line" =~ ^nameserver[[:space:]]+([^[:space:]]+) ]] && out+=("${BASH_REMATCH[1]}")
    done </etc/resolv.conf
    printf '%s' "${out[*]}"
}

_net_kv() { printf '  %s%-12s%s %s\n' "$T_LABEL" "$1" "$C_RESET" "$2"; }

# --- Acciones -------------------------------------------------------------------
network_summary() {
    require_cmd ip iproute2 || return 127
    local gw vpn
    gw="$(sys_gateway)"
    msg_section "NETWORK SUMMARY"
    _net_kv "Hostname" "$(sys_hostname)"
    _net_kv "Local IP" "$(sys_local_ip)"
    if [[ -n "$gw" ]]; then _net_kv "Gateway" "${gw% *} (dev ${gw#* })"; else _net_kv "Gateway" "${T_DIM}none${C_RESET}"; fi
    vpn="$(sys_vpn_detect | head -n1)"
    if [[ -n "$vpn" ]]; then _net_kv "VPN" "${T_OK}${G_DOT} active${C_RESET} ${vpn}"; else _net_kv "VPN" "${T_DIM}${G_RING} inactive${C_RESET}"; fi
    _net_kv "DNS" "$(_net_dns_servers)"
    network_interfaces
}

network_interfaces() {
    require_cmd ip iproute2 || return 127
    local -A macs=()
    local name state mac v4 v6 col
    while read -r name state mac _; do macs["${name%%@*}"]="$mac"; done < <(ip -br link show 2>/dev/null)
    msg_section "INTERFACES"
    printf '  %s%-14s %-9s %-19s %-20s %s%s\n' "$C_BOLD" "NAME" "STATE" "MAC" "IPv4" "IPv6" "$C_RESET"
    while IFS='|' read -r name state v4 v6; do
        case "$state" in UP) col=$T_OK ;; DOWN) col=$T_BAD ;; *) col=$T_WARN ;; esac
        printf '  %s%-14s%s %s%-9s%s %-19s %s%-20s%s %s%s%s\n' "$T_KEY" "$name" "$C_RESET" "$col" "$state" "$C_RESET" \
            "${macs[$name]:--}" "$T_VALUE" "${v4:--}" "$C_RESET" "$T_DIM" "${v6:--}" "$C_RESET"
    done < <(sys_interfaces)
}

network_routes() {
    require_cmd ip iproute2 || return 127
    local gw
    msg_section "ROUTES (IPv4)"
    ip -4 route show 2>/dev/null | while IFS= read -r line; do
        if [[ "$line" == default* ]]; then printf '  %s%s%s\n' "$T_OK" "$line" "$C_RESET"
        else printf '  %s\n' "$line"; fi
    done
    gw="$(sys_gateway)"
    printf '\n'
    if [[ -n "$gw" ]]; then msg_ok "Default gateway: ${gw% *} via ${gw#* }"; else msg_warn "No default IPv4 route."; fi
    local n6; n6="$(ip -6 route show 2>/dev/null | wc -l)"
    msg_dim "  IPv6 routes: ${n6}  (ip -6 route)"
}

network_gateway() {
    require_cmd ip iproute2 || return 127
    local gw ip
    gw="$(sys_gateway)"
    msg_section "GATEWAY"
    if [[ -z "$gw" ]]; then msg_warn "No default gateway configured."; return 1; fi
    ip="${gw% *}"
    _net_kv "Gateway" "$ip"
    _net_kv "Interface" "${gw#* }"
    if is_ipv4 "$ip" && has_cmd ping; then
        if ping -c 1 -W 2 -- "$ip" >/dev/null 2>&1; then _net_kv "Reachable" "${T_OK}${G_OK} yes (ICMP)${C_RESET}"
        else _net_kv "Reachable" "${T_WARN}${G_BAD} no ICMP reply (may be filtered)${C_RESET}"; fi
    fi
    return 0
}

# Formatea la salida de `ss -H -tunap`
_net_ss_table() {
    local netid state rq sq lcl peer proc pname col
    printf '  %s%-5s %-11s %-28s %-28s %s%s\n' "$C_BOLD" "PROTO" "STATE" "LOCAL" "REMOTE" "PROCESS" "$C_RESET"
    while read -r netid state rq sq lcl peer proc; do
        [[ -z "$netid" ]] && continue
        pname="-"
        if [[ "$proc" =~ \(\(\"([^\"]+)\",pid=([0-9]+) ]]; then pname="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; fi
        case "$state" in LISTEN|UNCONN) col=$T_ACCENT ;; ESTAB) col=$T_OK ;; *) col=$T_DIM ;; esac
        printf '  %-5s %s%-11s%s %-28s %-28s %s%s%s\n' "$netid" "$col" "$state" "$C_RESET" "$lcl" "$peer" "$T_DIM" "$pname" "$C_RESET"
    done
    : "$rq" "$sq"
}

network_connections() {
    require_cmd ss iproute2 || return 127
    local mode="all"
    case "${1:-}" in
        --listen|-l) mode="listen" ;;
        --established|-e) mode="estab" ;;
        "") ;;
        *) msg_err "Unknown option: $1"; return 2 ;;
    esac
    if [[ "$mode" != "estab" ]]; then
        msg_section "LISTENING SOCKETS"
        ss -H -tulnp 2>/dev/null | _net_ss_table
    fi
    if [[ "$mode" != "listen" ]]; then
        msg_section "ESTABLISHED CONNECTIONS"
        ss -H -tunp state established 2>/dev/null | awk '{ print $1, "ESTAB", $2, $3, $4, $5, $6 }' | _net_ss_table
    fi
    (( EUID != 0 )) && msg_dim "  Process names of other users are only visible with root (sudo ss -tunap)."
    return 0
}

network_ping() {
    local host="" count=4
    while (( $# > 0 )); do
        case "$1" in
            -c) [[ $# -ge 2 ]] && is_uint "$2" && (( $2 >= 1 && $2 <= 100 )) || { msg_err "-c needs a number 1-100"; return 2; }; count="$2"; shift 2 ;;
            -*) msg_err "Unknown option: $1"; return 2 ;;
            *)  host="$1"; shift ;;
        esac
    done
    [[ -n "$host" ]] || { msg_err "Missing host. Usage: urb network ping <host> [-c N]"; return 2; }
    if ! is_ipv4 "$host" && ! is_ipv6 "$host" && ! is_hostname "$host"; then msg_err "Invalid host: ${host}"; return 2; fi
    require_cmd ping iputils-ping || return 127
    msg_section "PING ${host}"
    ping -c "$count" -W 2 -- "$host"
    local rc=$?
    (( rc == 0 )) && msg_ok "Host reachable." || msg_warn "No reply from ${host} (exit ${rc})."
    return "$rc"
}

network_check() {
    local gw ip host name url t0 code ok=0 total=0
    host="$(cfg CHECK_PING_HOST 1.1.1.1)"; name="$(cfg CHECK_DNS_NAME kali.org)"; url="$(cfg CHECK_HTTP_URL https://www.kali.org)"
    msg_section "CONNECTIVITY CHECK"
    _check() { total=$(( total + 1 )); if [[ "$1" == 0 ]]; then ok=$(( ok + 1 )); printf '  %s%s%s %-28s %s%s%s\n' "$T_OK" "$G_OK" "$C_RESET" "$2" "$T_DIM" "$3" "$C_RESET"; else printf '  %s%s%s %-28s %s%s%s\n' "$T_BAD" "$G_BAD" "$C_RESET" "$2" "$T_DIM" "$3" "$C_RESET"; fi; }

    gw="$(sys_gateway)"; ip="${gw% *}"
    if [[ -z "$gw" ]]; then _check 1 "Default gateway" "no default route"
    elif is_ipv4 "$ip" && has_cmd ping; then
        ping -c 1 -W 2 -- "$ip" >/dev/null 2>&1; _check $? "Gateway ${ip}" "ICMP"
    else _check 0 "Default gateway" "${gw}"
    fi

    if is_ipv4 "$host" && has_cmd ping; then
        ping -c 1 -W 3 -- "$host" >/dev/null 2>&1; _check $? "Internet (${host})" "ICMP"
    else _check 1 "Internet" "ping unavailable or invalid CHECK_PING_HOST"
    fi

    if is_hostname "$name"; then
        local res; res="$(getent ahostsv4 -- "$name" 2>/dev/null | awk 'NR==1{print $1}')"
        if [[ -n "$res" ]]; then _check 0 "DNS (${name})" "$res"; else _check 1 "DNS (${name})" "no answer"; fi
    fi

    if has_cmd curl && [[ "$url" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/%-]*)?$ ]]; then
        t0=$SECONDS
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 -- "$url" 2>/dev/null)" || code="000"
        local hrc=1; [[ "$code" =~ ^[23] ]] && hrc=0
        _check "$hrc" "HTTP(S) ${url#*://}" "status ${code}, $(( SECONDS - t0 ))s"
    else
        _check 1 "HTTP(S)" "curl unavailable or invalid CHECK_HTTP_URL"
    fi

    local vpn; vpn="$(sys_vpn_detect | head -n1)"
    if [[ -n "$vpn" ]]; then printf '  %s%s%s %-28s %s%s%s\n' "$T_OK" "$G_DOT" "$C_RESET" "VPN" "$T_DIM" "$vpn" "$C_RESET"
    else printf '  %s%s%s %-28s %s%s%s\n' "$T_DIM" "$G_RING" "$C_RESET" "VPN" "$T_DIM" "inactive" "$C_RESET"; fi
    printf '\n'
    if (( ok == total )); then msg_ok "All checks passed (${ok}/${total})."; return 0
    else msg_warn "${ok}/${total} checks passed."; return 1; fi
}

# Descubrimiento de hosts con nmap -sn
network_discover() {
    local target="" force=0 use_sudo=0
    while (( $# > 0 )); do
        case "$1" in
            --force) force=1; shift ;;
            --sudo)  use_sudo=1; shift ;;
            -*) msg_err "Unknown option: $1"; return 2 ;;
            *)  target="$1"; shift ;;
        esac
    done
    if [[ -z "$target" ]]; then
        target="$(net_primary_cidr)" || { msg_err "Missing network. Usage: urb network discover <CIDR>"; return 2; }
        msg_info "No network given: using local network ${target}"
    fi
    if ! is_cidr4 "$target" && ! is_ipv4 "$target" && ! is_ipv4_range "$target"; then
        msg_err "Invalid network: ${target} (expected CIDR like 192.168.56.0/24)"
        return 2
    fi
    if is_cidr4 "$target" && (( 10#${target#*/} < 16 )) && (( ! force )); then
        msg_err "Network ${target} is too large (prefix < /16). Use --force if you really mean it."
        return 2
    fi
    if cfg_bool DISCOVER_PRIVATE_ONLY 1 && ! is_private_ipv4 "${target%%-*}" && (( ! force )); then
        msg_err "${target} is not a private/lab range. Discovery is restricted to authorized lab networks."
        msg_dim "    Use --force only if you are authorized to scan it."
        return 2
    fi
    require_cmd nmap || { msg_dim "    Known neighbours (ARP cache) instead:"; ip neigh show 2>/dev/null | sed 's/^/    /'; return 127; }
    if (( use_sudo )) && (( EUID != 0 )); then
        require_cmd sudo || return 127
        sudo -v || { msg_err "sudo authentication failed."; return 1; }
    else
        use_sudo=0
    fi

    local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/urb-disc.XXXXXX")" || return 1
    msg_section "HOST DISCOVERY ${G_SEP} ${target}"
    (( use_sudo || EUID == 0 )) || msg_dim "  Tip: --sudo enables ARP discovery (more reliable on local networks)."
    local rc
    scan_run_nmap "${tmp}/disc" "$use_sudo" -sn "$target"; rc=$?
    (( use_sudo )) && sudo -n chown -R -- "$(id -u):$(id -g)" "$tmp" 2>/dev/null

    if [[ -s "${tmp}/disc.nmap" ]]; then
        printf '  %s%-18s %-34s %s%s\n' "$C_BOLD" "IP" "HOSTNAME" "MAC / VENDOR" "$C_RESET"
        awk '
            /^Nmap scan report for / {
                if (ip != "") print ip "\t" name "\t" mac
                ip = ""; mac = ""
                if ($0 ~ /\[host down/) next
                s = substr($0, 22)
                if (match(s, /\(.*\)$/)) { name = substr(s, 1, RSTART - 2); ip = substr(s, RSTART + 1, RLENGTH - 2) }
                else { name = "-"; ip = s }
            }
            /^MAC Address: / { mac = substr($0, 14) }
            END { if (ip != "") print ip "\t" name "\t" mac }
        ' "${tmp}/disc.nmap" | while IFS=$'\t' read -r ip name mac; do
            printf '  %s%-18s%s %-34s %s%s%s\n' "$T_OK" "$ip" "$C_RESET" "$name" "$T_DIM" "${mac:--}" "$C_RESET"
        done
        local up; up="$(grep -c 'Status: Up' "${tmp}/disc.gnmap" 2>/dev/null)"
        printf '\n'; msg_ok "${up:-0} host(s) up."
    fi
    rm -rf -- "$tmp"
    return "$rc"
}

network_main() {
    local action="${1:-summary}"
    (( $# > 0 )) && shift
    case "$action" in
        summary|info)          network_summary ;;
        interfaces|ifaces|if)  network_interfaces ;;
        routes|route)          network_routes ;;
        gateway|gw)            network_gateway ;;
        connections|conns|ss)  network_connections "$@" ;;
        discover|sweep)        network_discover "$@" ;;
        ping)                  network_ping "$@" ;;
        check)                 network_check ;;
        -h|--help|help)        network_help ;;
        *) msg_err "Unknown network action: ${action}"; msg_dim "    See: urb help network"; return 2 ;;
    esac
}

network_menu() {
    local input def
    while :; do
        ui_menu "NETWORK" "Network Discovery" \
            "Summary|IP, gateway, VPN, DNS and interfaces" \
            "Interfaces|State, MAC and addresses" \
            "Routes|Routing table and default gateway" \
            "Connections|Listening and established sockets" \
            "Discover|Find hosts in an authorized lab network" \
            "Ping|Test reachability of a host" \
            "Check|Gateway / internet / DNS / HTTPS check" \
            "Back|Return to dashboard" || return 0
        case "$UI_CHOICE" in
            0) network_summary ;;
            1) network_interfaces ;;
            2) network_routes ;;
            3) network_connections ;;
            4) def="$(net_primary_cidr 2>/dev/null)"
               msg_section "HOST DISCOVERY"
               msg_dim "  Only networks you are authorized to scan (lab / home)."
               ui_prompt input "Network (CIDR)" "$def" || continue
               [[ -z "$input" ]] && continue
               if (( EUID != 0 )) && confirm "Use sudo for ARP discovery (more accurate)?" n; then network_discover "$input" --sudo
               else network_discover "$input"; fi ;;
            5) ui_prompt input "Host" "$(sys_gateway | cut -d' ' -f1)" || continue
               [[ -n "$input" ]] && network_ping "$input" ;;
            6) network_check ;;
            *) return 0 ;;
        esac
        ui_pause
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    URB_HOME="$(cd -P -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)" || exit 1
    # shellcheck source=../lib/utils.sh
    source "${URB_HOME}/lib/utils.sh" && urb_standalone_init || exit 1
    network_main "$@"
    exit $?
fi
