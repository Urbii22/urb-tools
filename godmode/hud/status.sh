#!/usr/bin/env bash
# =============================================================================
#  godmode/hud/status.sh — HUD de la barra de estado de URB God Mode
#  tmux lo ejecuta cada status-interval: status.sh <ruta_del_panel> <ancho>
#  Imprime UNA línea con formato de tmux (#[fg=...]). Datos reales:
#  CPU (delta de /proc/stat entre ejecuciones), RAM, IP, VPN, Git y hora.
#  Reutiliza lib/system.sh de URB-Tools (sin dependencias circulares).
# =============================================================================
set -uo pipefail

GOD_DIR="$(cd -P -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd -P)" || exit 0
URB_HOME="$(cd -P -- "${GOD_DIR}/.." && pwd -P)" || exit 0
# shellcheck source=../../lib/utils.sh
source "${URB_HOME}/lib/utils.sh" || exit 0
# shellcheck source=../../lib/system.sh
source "${URB_HOME}/lib/system.sh" || exit 0
# shellcheck source=../themes/urb.theme
source "${GOD_DIR}/themes/urb.theme" 2>/dev/null

pane_path="${1:-$PWD}"
width="${2:-120}"
is_uint "$width" || width=120

c() { printf '#[fg=colour%s]' "$1"; }
SEP="$(c "${URB_C_SEP:-238}") │ "

pct_colour() {
    if   (( $1 >= 85 )); then printf '%s' "${URB_C_BAD:-196}"
    elif (( $1 >= 60 )); then printf '%s' "${URB_C_WARN:-220}"
    else printf '%s' "${URB_C_OK:-47}"
    fi
}

# --- CPU: delta respecto a la ejecución anterior (caché privada del usuario) --------
hud_cpu() {
    local dir="${XDG_RUNTIME_DIR:-/tmp}/urb-god-${UID}" cache pt="" pi="" tmp
    local -A t=() i=()
    cache="${dir}/cpu"
    sys_cpu_read t i || { printf '?'; return; }
    if [[ ! -d "$dir" ]]; then mkdir -m 700 -- "$dir" 2>/dev/null || true; fi
    if [[ -O "$dir" && -r "$cache" ]]; then read -r pt pi <"$cache"; fi
    if [[ -z "$pt" || ! "$pt" =~ ^[0-9]+$ || ! "$pi" =~ ^[0-9]+$ ]]; then
        # Primera ejecución: muestra corta para tener un valor real
        local -A t0=() i0=()
        sys_cpu_read t0 i0; sleep 0.25; sys_cpu_read t i
        pt="${t0[cpu]}" pi="${i0[cpu]}"
    fi
    if [[ -O "$dir" ]]; then
        tmp="$(mktemp "${cache}.XXXXXX" 2>/dev/null)" && printf '%s %s\n' "${t[cpu]}" "${i[cpu]}" >"$tmp" && mv -f -- "$tmp" "$cache"
    fi
    cpu_pct "$pt" "$pi" "${t[cpu]}" "${i[cpu]}"
}

hud_git() {
    local path="$1" branch dirty=""
    [[ -d "$path" ]] || return 0
    command -v git >/dev/null 2>&1 || return 0
    branch="$(git -C "$path" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$path" rev-parse --short HEAD 2>/dev/null)" || return 0
    [[ -n "$branch" ]] || return 0
    [[ -n "$(git -C "$path" status --porcelain --untracked-files=no 2>/dev/null | head -n 1)" ]] && dirty="*"
    printf '%s' "${branch}${dirty}"
}

cpu="$(hud_cpu)"
sys_mem_read || true
ip="$(sys_local_ip)"
vpn="$(sys_vpn_detect 2>/dev/null | head -n 1)"
vpn="${vpn%/*}"   # "tun0 10.10.14.5" (sin prefijo CIDR)
git_info="$(hud_git "$pane_path")"

out=""
# CPU y RAM
if is_uint "$cpu"; then out+="$(c "${URB_C_LABEL:-67}")CPU $(c "$(pct_colour "$cpu")")${cpu}%"; fi
out+="${SEP}$(c "${URB_C_LABEL:-67}")RAM $(c "$(pct_colour "$MEM_PCT")")${MEM_PCT}%"
(( width >= 130 )) && out+="$(c "${URB_C_DIM:-242}") $(fmt_kb "$MEM_USED_KB")/$(fmt_kb "$MEM_TOTAL_KB")"
# IP local
(( width >= 80 )) && out+="${SEP}$(c "${URB_C_LABEL:-67}")IP $(c "${URB_C_WHITE:-255}")${ip}"
# VPN
if [[ -n "$vpn" ]]; then
    if (( width >= 110 )); then out+="${SEP}$(c "${URB_C_OK:-47}")● VPN ${vpn}"
    else out+="${SEP}$(c "${URB_C_OK:-47}")● VPN ${vpn%% *}"; fi
else
    out+="${SEP}$(c "${URB_C_DIM:-242}")○ VPN off"
fi
# Git del directorio del panel activo
[[ -n "$git_info" ]] && out+="${SEP}$(c "${URB_C_WARN:-220}")git:${git_info}"
# Hora
(( width >= 120 )) && out+="${SEP}$(c "${URB_C_PRIMARY:-51}")$(printf '%(%H:%M)T' -1)"
printf '%s ' "$out"
