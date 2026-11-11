#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/system.sh — Lectura de información REAL del sistema
#  Fuentes: /proc, /etc/os-release, ip, df, ps. Nada simulado.
#  Las funciones de parseo aceptan un fichero alternativo (para los tests).
# =============================================================================

[[ -n "${_URB_SYSTEM_LOADED:-}" ]] && return 0
_URB_SYSTEM_LOADED=1

# --- Identidad ----------------------------------------------------------------
sys_hostname() {
    local h="${HOSTNAME:-}"
    [[ -z "$h" && -r /proc/sys/kernel/hostname ]] && IFS= read -r h </proc/sys/kernel/hostname
    [[ -z "$h" ]] && h="$(uname -n 2>/dev/null)"
    printf '%s' "${h:-unknown}"
}

sys_user() {
    local u="${USER:-}"
    [[ -z "$u" ]] && u="$(id -un 2>/dev/null)"
    printf '%s' "${u:-unknown}"
}

# sys_os [fichero os-release]
sys_os() {
    local f="${1:-/etc/os-release}" line name="" pretty=""
    if [[ -r "$f" ]]; then
        while IFS= read -r line; do
            case "$line" in
                PRETTY_NAME=*) pretty="${line#PRETTY_NAME=}" ;;
                NAME=*)        name="${line#NAME=}" ;;
            esac
        done <"$f"
    fi
    pretty="${pretty:-$name}"
    pretty="${pretty#\"}"; pretty="${pretty%\"}"
    pretty="${pretty#\'}"; pretty="${pretty%\'}"
    [[ -z "$pretty" ]] && pretty="$(uname -s 2>/dev/null)"
    printf '%s' "${pretty:-unknown}"
}

# Identificador de distro (kali, ubuntu, debian...)
sys_os_id() {
    local f="${1:-/etc/os-release}" line id=""
    [[ -r "$f" ]] || { printf 'unknown'; return 0; }
    while IFS= read -r line; do
        [[ "$line" == ID=* ]] && id="${line#ID=}"
    done <"$f"
    id="${id#\"}"; id="${id%\"}"
    printf '%s' "${id:-unknown}"
}

sys_kernel() { uname -r 2>/dev/null || printf 'unknown'; }

sys_is_wsl() { [[ -r /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; }

# --- Tiempo de actividad ------------------------------------------------------
# fmt_duration segundos → "3d 4h 12m" / "4h 12m" / "12m"
fmt_duration() {
    local s=$1 d h m
    is_uint "$s" || { printf '?'; return 0; }
    d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
    if   (( d > 0 )); then printf '%dd %dh %dm' "$d" "$h" "$m"
    elif (( h > 0 )); then printf '%dh %dm' "$h" "$m"
    else printf '%dm' "$m"
    fi
}

# sys_uptime_seconds [fichero]
sys_uptime_seconds() {
    local f="${1:-/proc/uptime}" up=""
    [[ -r "$f" ]] && read -r up _ <"$f"
    printf '%s' "${up%%.*}"
}

sys_uptime() { fmt_duration "$(sys_uptime_seconds "$@")"; }

# sys_loadavg [fichero] → "0.31 0.25 0.20"
sys_loadavg() {
    local f="${1:-/proc/loadavg}" a b c
    if [[ -r "$f" ]] && read -r a b c _ <"$f"; then printf '%s %s %s' "$a" "$b" "$c"; else printf 'n/a'; fi
}

sys_cpu_count() {
    local n
    n="$(nproc 2>/dev/null)" || n=""
    is_uint "$n" || n="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
    printf '%s' "${n:-1}"
}

sys_cpu_model() {
    local line
    if [[ -r /proc/cpuinfo ]]; then
        while IFS= read -r line; do
            if [[ "$line" == "model name"* ]]; then
                line="${line#*:}"; line="${line# }"
                printf '%s' "$line"; return 0
            fi
        done </proc/cpuinfo
    fi
    printf 'unknown'
}

# --- Formato de tamaños ---------------------------------------------------------
# fmt_kb kilobytes → "512K", "3.8G"...
fmt_kb() {
    local v=$1 i=0 frac=0
    local -a u=(K M G T P)
    is_uint "$v" || { printf '?'; return 0; }
    while (( v >= 1024 && i < 4 )); do
        frac=$(( (v % 1024) * 10 / 1024 ))
        v=$(( v / 1024 ))
        i=$(( i + 1 ))
    done
    if (( i == 0 || v >= 100 )); then printf '%d%s' "$v" "${u[i]}"
    else printf '%d.%d%s' "$v" "$frac" "${u[i]}"
    fi
}

# --- CPU (/proc/stat) -----------------------------------------------------------
# sys_cpu_read TOTALES_assoc IDLE_assoc [fichero]
# Rellena arrays asociativos indexados por "cpu", "cpu0", "cpu1"...
sys_cpu_read() {
    local -n __tot=$1 __idl=$2
    local f="${3:-/proc/stat}" name user nice system idle iowait irq softirq steal
    __tot=(); __idl=()
    [[ -r "$f" ]] || return 1
    while read -r name user nice system idle iowait irq softirq steal _; do
        [[ "$name" == cpu* ]] || break
        __tot["$name"]=$(( user + nice + system + idle + ${iowait:-0} + ${irq:-0} + ${softirq:-0} + ${steal:-0} ))
        __idl["$name"]=$(( idle + ${iowait:-0} ))
    done <"$f"
    return 0
}

# cpu_pct total_prev idle_prev total_now idle_now → porcentaje entero de uso
cpu_pct() {
    local dt=$(( $3 - $1 )) di=$(( $4 - $2 ))
    if (( dt <= 0 )); then printf '0'; return 0; fi
    local p=$(( (100 * (dt - di) + dt / 2) / dt ))
    (( p < 0 )) && p=0
    (( p > 100 )) && p=100
    printf '%d' "$p"
}

# Uso de CPU puntual (dos muestras separadas por un intervalo corto)
sys_cpu_usage_once() {
    local -A t1=() i1=() t2=() i2=()
    sys_cpu_read t1 i1 || { printf '0'; return 1; }
    sleep "${1:-0.4}"
    sys_cpu_read t2 i2 || { printf '0'; return 1; }
    cpu_pct "${t1[cpu]}" "${i1[cpu]}" "${t2[cpu]}" "${i2[cpu]}"
}

# --- Memoria (/proc/meminfo) -----------------------------------------------------
# sys_mem_read [fichero] → MEM_TOTAL_KB MEM_AVAIL_KB MEM_USED_KB MEM_PCT SWAP_*
sys_mem_read() {
    local f="${1:-/proc/meminfo}" k v free=0 buffers=0 cached=0 sreclaim=0
    MEM_TOTAL_KB=0 MEM_AVAIL_KB=-1 SWAP_TOTAL_KB=0 SWAP_FREE_KB=0
    [[ -r "$f" ]] || return 1
    while read -r k v _; do
        case "$k" in
            MemTotal:)     MEM_TOTAL_KB=$v ;;
            MemAvailable:) MEM_AVAIL_KB=$v ;;
            MemFree:)      free=$v ;;
            Buffers:)      buffers=$v ;;
            Cached:)       cached=$v ;;
            SReclaimable:) sreclaim=$v ;;
            SwapTotal:)    SWAP_TOTAL_KB=$v ;;
            SwapFree:)     SWAP_FREE_KB=$v ;;
        esac
    done <"$f"
    # Kernels antiguos sin MemAvailable
    (( MEM_AVAIL_KB < 0 )) && MEM_AVAIL_KB=$(( free + buffers + cached + sreclaim ))
    MEM_USED_KB=$(( MEM_TOTAL_KB - MEM_AVAIL_KB ))
    (( MEM_USED_KB < 0 )) && MEM_USED_KB=0
    MEM_PCT=0
    (( MEM_TOTAL_KB > 0 )) && MEM_PCT=$(( (MEM_USED_KB * 100 + MEM_TOTAL_KB / 2) / MEM_TOTAL_KB ))
    SWAP_USED_KB=$(( SWAP_TOTAL_KB - SWAP_FREE_KB ))
    SWAP_PCT=0
    (( SWAP_TOTAL_KB > 0 )) && SWAP_PCT=$(( (SWAP_USED_KB * 100 + SWAP_TOTAL_KB / 2) / SWAP_TOTAL_KB ))
    return 0
}

# --- Disco ------------------------------------------------------------------------
# sys_disk_read [ruta] → DISK_TOTAL_KB DISK_USED_KB DISK_AVAIL_KB DISK_PCT DISK_MOUNT
sys_disk_read() {
    local path="${1:-/}" line fs total used avail pct mount
    DISK_TOTAL_KB=0 DISK_USED_KB=0 DISK_AVAIL_KB=0 DISK_PCT=0 DISK_MOUNT="$path"
    line="$(df -Pk -- "$path" 2>/dev/null | awk 'NR==2')" || return 1
    [[ -n "$line" ]] || return 1
    read -r fs total used avail pct mount <<<"$line"
    is_uint "$total" || return 1
    DISK_TOTAL_KB=$total DISK_USED_KB=$used DISK_AVAIL_KB=$avail
    DISK_PCT="${pct%\%}"; is_uint "$DISK_PCT" || DISK_PCT=0
    DISK_MOUNT="${mount:-$path}"
    : "$fs"
    return 0
}

# --- Red -----------------------------------------------------------------------------
# IP local "principal": la que el kernel usaría para salir (no envía paquetes)
sys_local_ip() {
    local out ip=""
    if has_cmd ip; then
        out="$(ip -4 route get 1.1.1.1 2>/dev/null)"
        if [[ "$out" =~ src[[:space:]]+([0-9.]+) ]]; then ip="${BASH_REMATCH[1]}"; fi
        if [[ -z "$ip" ]]; then
            out="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4; exit}')"
            ip="${out%%/*}"
        fi
    fi
    printf '%s' "${ip:-none}"
}

# sys_gateway → "10.0.2.2 eth0" (vacío si no hay ruta por defecto)
sys_gateway() {
    local line via="" dev=""
    has_cmd ip || return 1
    line="$(ip -4 route show default 2>/dev/null | head -n1)"
    [[ "$line" =~ via[[:space:]]+([^[:space:]]+) ]] && via="${BASH_REMATCH[1]}"
    [[ "$line" =~ dev[[:space:]]+([^[:space:]]+) ]] && dev="${BASH_REMATCH[1]}"
    [[ -n "$via$dev" ]] && printf '%s %s' "${via:-direct}" "$dev"
    return 0
}

# Parsea la salida de `ip -br addr` → líneas "nombre|estado|ipv4/cidr|ipv6"
# sys_parse_ip_br < entrada
sys_parse_ip_br() {
    local name state rest a v4 v6
    while read -r name state rest; do
        [[ -z "$name" ]] && continue
        name="${name%%@*}"
        v4="" v6=""
        for a in $rest; do
            if [[ -z "$v4" && "$a" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then v4="$a"
            elif [[ -z "$v6" && "$a" == *:* ]]; then v6="$a"
            fi
        done
        printf '%s|%s|%s|%s\n' "$name" "$state" "$v4" "$v6"
    done
}

# sys_interfaces → líneas "nombre|estado|ipv4/cidr|ipv6"
sys_interfaces() {
    has_cmd ip || return 1
    ip -br addr show 2>/dev/null | sys_parse_ip_br
}

# Detecta interfaces de VPN activas (tun/tap/wg/ppp/tailscale...)
# Salida: "tun0 10.10.14.5/23" por cada VPN encontrada
sys_vpn_detect() {
    local name state v4
    while IFS='|' read -r name state v4 _; do
        case "$name" in
            tun*|tap*|wg*|ppp*|tailscale*|nordlynx*|proton*|ipsec*|vpn*|zt*)
                [[ "$state" == "DOWN" ]] && continue
                printf '%s %s\n' "$name" "${v4:-no-ipv4}" ;;
        esac
    done < <(if [[ -n "${1:-}" ]]; then cat -- "$1"; else sys_interfaces; fi)
}
