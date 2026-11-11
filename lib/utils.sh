#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/utils.sh — Utilidades comunes de URB-Tools
#  - Colores y mensajes
#  - Validación de entradas externas (IP, CIDR, hostnames, nombres, puertos)
#  - Carga segura de configuración (sin `source` ni `eval`)
#  - Rutas XDG del usuario
# =============================================================================

[[ -n "${_URB_UTILS_LOADED:-}" ]] && return 0
_URB_UTILS_LOADED=1

URB_VERSION="0.1.0"
URB_NAME="URB-Tools"

# --- Rutas del usuario (XDG). Nunca se tocan fuera de estas carpetas. ---------
URB_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/urb-tools"
URB_USER_CONFIG="${URB_CONFIG_DIR}/urb.conf"
URB_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/urb-tools"

declare -gA URB_CFG=()

# =============================================================================
#  Colores
# =============================================================================
C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
C_MAGENTA="" C_CYAN="" C_WHITE="" C_GRAY="" C_BCYAN="" C_BGREEN="" C_BBLUE=""
URB_COLOR_ON=0
URB_256=0

# urb_init_colors [auto|always|never]
urb_init_colors() {
    local mode="${1:-${URB_COLOR:-auto}}"
    if [[ -n "${NO_COLOR:-}" && "$mode" != "always" ]]; then mode="never"; fi
    if [[ "$mode" == "auto" ]]; then
        if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]; then mode="always"; else mode="never"; fi
    fi
    if [[ "$mode" != "always" ]]; then
        C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
        C_MAGENTA="" C_CYAN="" C_WHITE="" C_GRAY="" C_BCYAN="" C_BGREEN="" C_BBLUE=""
        URB_COLOR_ON=0
        return 0
    fi
    URB_COLOR_ON=1
    C_RESET=$'\e[0m'   C_BOLD=$'\e[1m'    C_DIM=$'\e[2m'
    C_RED=$'\e[31m'    C_GREEN=$'\e[32m'  C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m'   C_MAGENTA=$'\e[35m' C_CYAN=$'\e[36m'
    C_WHITE=$'\e[97m'  C_GRAY=$'\e[90m'
    C_BCYAN=$'\e[96m'  C_BGREEN=$'\e[92m' C_BBLUE=$'\e[94m'
    case "${COLORTERM:-}${TERM:-}" in
        *truecolor*|*24bit*|*256color*) URB_256=1 ;;
        *) URB_256=0 ;;
    esac
}

# =============================================================================
#  Mensajes
# =============================================================================
msg_info() { printf '%s[*]%s %s\n' "$C_BCYAN" "$C_RESET" "$*"; }
msg_ok()   { printf '%s[+]%s %s\n' "$C_BGREEN" "$C_RESET" "$*"; }
msg_warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
msg_err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
msg_dim()  { printf '%s%s%s\n' "$C_GRAY" "$*" "$C_RESET"; }

# Encabezado de sección para salidas de CLI:  ━━ TITLE ━━━━━━━━
msg_section() {
    local title="$1" width="${2:-60}" line
    local fill=$(( width - ${#title} - 4 ))
    (( fill < 3 )) && fill=3
    printf -v line '%*s' "$fill" ''
    if urb_is_utf8; then line="${line// /━}"; printf '\n%s━━ %s%s%s %s%s\n' "$C_BLUE" "$C_BOLD$C_BCYAN" "$title" "$C_RESET$C_BLUE" "$line" "$C_RESET"
    else line="${line// /-}"; printf '\n%s-- %s%s%s %s%s\n' "$C_BLUE" "$C_BOLD$C_BCYAN" "$title" "$C_RESET$C_BLUE" "$line" "$C_RESET"
    fi
}

# =============================================================================
#  Utilidades generales
# =============================================================================
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# require_cmd <comando> [paquete]  → 0 si existe; si no, explica cómo instalarlo
require_cmd() {
    local cmd="$1" pkg="${2:-$1}"
    has_cmd "$cmd" && return 0
    msg_err "Required command not found: ${cmd}"
    msg_dim "    Install it with:  sudo apt install ${pkg}"
    return 127
}

urb_is_utf8() {
    local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    [[ "${URB_ASCII:-0}" != "1" && "${loc^^}" == *UTF*8* ]]
}

urb_timestamp() { printf '%(%Y%m%d-%H%M%S)T' -1; }
urb_now()       { printf '%(%Y-%m-%d %H:%M:%S)T' -1; }

# Expande '~' inicial y $HOME / ${HOME} literales (sin eval).
urb_expand_path() {
    local p="$1"
    p="${p//\$\{HOME\}/$HOME}"
    p="${p//\$HOME/$HOME}"
    [[ "$p" == "~" ]] && p="$HOME"
    [[ "$p" == "~/"* ]] && p="$HOME/${p#\~/}"
    printf '%s' "$p"
}

# confirm "Pregunta" [default y|n] → 0 = sí. Lee de /dev/tty.
confirm() {
    local prompt="$1" def="${2:-n}" ans hint="[y/N]"
    [[ "$def" == "y" ]] && hint="[Y/n]"
    if [[ "${URB_ASSUME_YES:-0}" == "1" ]]; then return 0; fi
    if ! { : </dev/tty; } 2>/dev/null; then
        msg_warn "No interactive terminal: assuming 'no' for: ${prompt}"
        return 1
    fi
    printf '%s[?]%s %s %s ' "$C_YELLOW" "$C_RESET" "$prompt" "$hint" >/dev/tty
    IFS= read -r ans </dev/tty || ans=""
    ans="${ans,,}"
    [[ -z "$ans" ]] && ans="$def"
    [[ "$ans" == "y" || "$ans" == "yes" || "$ans" == "s" || "$ans" == "si" || "$ans" == "sí" ]]
}

# =============================================================================
#  Validación de entradas
# =============================================================================
is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

is_ipv4() {
    local ip="$1" o
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    for o in "${BASH_REMATCH[@]:1}"; do
        (( 10#$o <= 255 )) || return 1
    done
    return 0
}

is_cidr4() {
    [[ "$1" =~ ^([0-9.]+)/([0-9]{1,2})$ ]] || return 1
    local ip="${BASH_REMATCH[1]}" pfx="${BASH_REMATCH[2]}"
    is_ipv4 "$ip" && (( 10#$pfx <= 32 ))
}

# Rango nmap en el último octeto: 192.168.1.10-50
is_ipv4_range() {
    [[ "$1" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})-([0-9]{1,3})$ ]] || return 1
    local base="${BASH_REMATCH[1]}" a="${BASH_REMATCH[2]}" b="${BASH_REMATCH[3]}"
    is_ipv4 "${base}.${a}" && is_ipv4 "${base}.${b}" && (( 10#$a <= 10#$b ))
}

# IPv6 (comprobación estructural razonable, sin zonas %eth0)
is_ipv6() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9A-Fa-f:]+(/[0-9]{1,3})?$ ]] || return 1
    [[ "$ip" == *:*:* ]] || return 1
    local addr="${ip%%/*}"
    (( ${#addr} <= 39 )) || return 1
    [[ "$addr" != *:::* ]] || return 1
    return 0
}

is_hostname() {
    local h="$1"
    (( ${#h} >= 1 && ${#h} <= 253 )) || return 1
    # Si parece una IP numérica, debe ser una IPv4 válida
    [[ "$h" =~ ^[0-9.]+$ ]] && return 1
    [[ "$h" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\.?$ ]]
}

# Objetivo válido para escanear: IPv4, CIDR, rango, IPv6 o hostname.
# Nunca empieza por '-' (evita inyección de opciones en nmap).
is_valid_target() {
    local t="$1"
    [[ -n "$t" && "$t" != -* ]] || return 1
    is_ipv4 "$t" || is_cidr4 "$t" || is_ipv4_range "$t" || is_ipv6 "$t" || is_hostname "$t"
}

# IPv4 privada / de laboratorio (RFC1918, loopback, link-local, CGNAT)
is_private_ipv4() {
    local ip="${1%%/*}"
    is_ipv4 "$ip" || return 1
    local a b
    IFS=. read -r a b _ _ <<<"$ip"
    (( 10#$a == 10 )) && return 0
    (( 10#$a == 127 )) && return 0
    (( 10#$a == 172 && 10#$b >= 16 && 10#$b <= 31 )) && return 0
    (( 10#$a == 192 && 10#$b == 168 )) && return 0
    (( 10#$a == 169 && 10#$b == 254 )) && return 0
    (( 10#$a == 100 && 10#$b >= 64 && 10#$b <= 127 )) && return 0
    return 1
}

# Especificación de puertos: 22  |  22,80,443  |  1-1024  |  22,8000-8100
is_port_spec() {
    local spec="$1" part a b
    [[ "$spec" =~ ^[0-9,-]+$ ]] || return 1
    [[ "$spec" != *,,* && "$spec" != ,* && "$spec" != *, ]] || return 1
    local -a parts
    IFS=, read -ra parts <<<"$spec"
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]]; then
            a=$((10#${BASH_REMATCH[1]})); b=$((10#${BASH_REMATCH[2]}))
            (( a >= 1 && b <= 65535 && a <= b )) || return 1
        elif [[ "$part" =~ ^[0-9]{1,5}$ ]]; then
            a=$((10#$part)); (( a >= 1 && a <= 65535 )) || return 1
        else
            return 1
        fi
    done
    return 0
}

# Nombres de laboratorio / archivos: letras, números, . _ -  (máx. 64)
is_safe_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ && "$1" != *..* ]]; }

# Usuario de sistema (para filtros de logs)
is_username() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9._-]{0,31}\$?$ ]]; }

# Token de argumentos de nmap definido en perfiles de configuración.
# Bloquea opciones de salida/entrada de ficheros que URB controla.
is_safe_nmap_token() {
    local t="$1"
    [[ "$t" =~ ^[A-Za-z0-9_.,:=/+-]+$ ]] || return 1
    case "$t" in
        -o*|-i*|--resume*|--datadir*|--servicedb*|--versiondb*|--stylesheet*|--script-args-file*|--excludefile*) return 1 ;;
    esac
    return 0
}

# =============================================================================
#  Configuración (formato KEY=valor, sin ejecutar nada)
# =============================================================================
_urb_parse_config() {
    local f="$1" line key val n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Z][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            val="${val%"${val##*[![:space:]]}"}"
            if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi
            URB_CFG["$key"]="$val"
        else
            msg_warn "config: ignoring invalid line ${n} in ${f}"
        fi
    done <"$f"
}

# urb_load_config: valores por defecto del proyecto + config del usuario.
urb_load_config() {
    local f
    URB_CFG=()
    for f in "${URB_HOME}/config/default.conf" "${URB_CONFIG_FILE:-$URB_USER_CONFIG}"; do
        [[ -r "$f" ]] && _urb_parse_config "$f"
    done
    return 0
}

# cfg CLAVE [defecto]  → imprime el valor
cfg() { printf '%s' "${URB_CFG[$1]-${2-}}"; }

# cfg_bool CLAVE → 0 si el valor es verdadero
cfg_bool() {
    local v="${URB_CFG[$1]-${2:-0}}"
    v="${v,,}"
    [[ "$v" == "1" || "$v" == "yes" || "$v" == "true" || "$v" == "on" ]]
}

# config_set CLAVE VALOR → guarda en la config del usuario (crea si no existe)
config_set() {
    local key="$1" val="$2" f="${URB_CONFIG_FILE:-$URB_USER_CONFIG}" tmp
    [[ "$key" =~ ^[A-Z][A-Za-z0-9_]*$ ]] || { msg_err "Invalid config key: $key"; return 2; }
    [[ "$val" =~ ^[A-Za-z0-9_.,:=/+~\ -]*$ ]] || { msg_err "Invalid config value for $key"; return 2; }
    mkdir -p -- "$(dirname -- "$f")" || return 1
    [[ -e "$f" ]] || : >"$f" || return 1
    tmp="$(mktemp "${f}.XXXXXX")" || return 1
    awk -v k="$key" -v v="$val" '
        BEGIN { done = 0 }
        $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { print k "=\"" v "\""; done = 1; next }
        { print }
        END { if (!done) print k "=\"" v "\"" }
    ' "$f" >"$tmp" && mv -f -- "$tmp" "$f" || { rm -f -- "$tmp"; return 1; }
    URB_CFG["$key"]="$val"
}

# Inicialización cuando un módulo se ejecuta directamente (bash modules/x.sh)
urb_standalone_init() {
    local f
    for f in lib/ui.sh lib/system.sh modules/ctf.sh modules/scan.sh; do
        # shellcheck source=/dev/null
        source "${URB_HOME}/${f}" || { msg_err "Cannot load ${f}"; return 1; }
    done
    urb_init_colors
    urb_load_config
    ui_init_theme
}

# Directorio de resultados de escaneo
urb_scan_dir() { urb_expand_path "$(cfg SCAN_DIR "$URB_DATA_DIR/scans")"; }
urb_labs_dir() { urb_expand_path "$(cfg LABS_DIR "$HOME/urb-labs")"; }
