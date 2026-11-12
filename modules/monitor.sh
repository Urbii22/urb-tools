#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/monitor.sh — MONITOR: CPU, memoria, discos y procesos en vivo
#  CLI: urb monitor [--once] [--interval N] [--procs N]  |  urb monitor procs
# =============================================================================

[[ -n "${_URB_MONITOR_LOADED:-}" ]] && return 0
_URB_MONITOR_LOADED=1

monitor_help() {
    cat <<EOF
${C_BOLD}urb monitor${C_RESET} — live system monitoring

${C_BOLD}USAGE${C_RESET}
  urb monitor                 Live full-screen monitor (q to quit, s to sort)
  urb monitor --once          One snapshot, printed (scripts / non-interactive)
  urb monitor procs [-n N]    Top processes by CPU
  Options: --interval N (seconds), --procs N (rows)

${T_DIM}Process %CPU comes from ps: average over each process lifetime.${C_RESET}
EOF
}

# Lista de discos reales (sin sistemas de ficheros virtuales)
_mon_disks() {
    df -Pk -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null \
        | awk 'NR > 1 && $2 > 0 { print $6 "\t" $2 "\t" $3 "\t" $4 "\t" $5 }' \
        | grep -v -E $'^/(snap|run|boot/efi|usr/lib/wsl|init|mnt/wsl)|^/mnt/[a-z]\t' | head -n 6
}

_mon_procs() {
    local n="$1" sort="$2"
    ps -eo pid=,user=,pcpu=,pmem=,rss=,comm= --sort="-${sort}" 2>/dev/null | head -n "$n"
}

# --- Instantánea en texto --------------------------------------------------------
monitor_snapshot() {
    local nprocs="$1" cpu bar pc
    cpu="$(sys_cpu_usage_once 0.5)"
    sys_mem_read
    msg_section "SYSTEM MONITOR ${G_SEP} $(urb_now)"
    ui_bar bar "$cpu" 30; ui_pct_color pc "$cpu"
    printf '  %sCPU %s %s %s%3d%%%s  load %s  (%s cores)\n' "$T_LABEL" "$C_RESET" "$bar" "$pc" "$cpu" "$C_RESET" "$(sys_loadavg)" "$(sys_cpu_count)"
    ui_bar bar "$MEM_PCT" 30; ui_pct_color pc "$MEM_PCT"
    printf '  %sRAM %s %s %s%3d%%%s  %s / %s\n' "$T_LABEL" "$C_RESET" "$bar" "$pc" "$MEM_PCT" "$C_RESET" "$(fmt_kb "$MEM_USED_KB")" "$(fmt_kb "$MEM_TOTAL_KB")"
    if (( SWAP_TOTAL_KB > 0 )); then
        ui_bar bar "$SWAP_PCT" 30; ui_pct_color pc "$SWAP_PCT"
        printf '  %sSWAP%s %s %s%3d%%%s  %s / %s\n' "$T_LABEL" "$C_RESET" "$bar" "$pc" "$SWAP_PCT" "$C_RESET" "$(fmt_kb "$SWAP_USED_KB")" "$(fmt_kb "$SWAP_TOTAL_KB")"
    fi
    msg_section "STORAGE"
    local mnt tot used avail pct
    while IFS=$'\t' read -r mnt tot used avail pct; do
        pct="${pct%\%}"; is_uint "$pct" || pct=0
        ui_bar bar "$pct" 20; ui_pct_color pc "$pct"
        printf '  %-18s %s %s%3d%%%s  %s free of %s\n' "$mnt" "$bar" "$pc" "$pct" "$C_RESET" "$(fmt_kb "$avail")" "$(fmt_kb "$tot")"
    done < <(_mon_disks)
    msg_section "TOP PROCESSES (by CPU)"
    monitor_procs_table "$nprocs" pcpu
    printf '  %sUptime %s  %s%s\n' "$T_DIM" "$(sys_uptime)" "$(sys_os)" "$C_RESET"
}

monitor_procs_table() {
    local n="$1" sort="${2:-pcpu}" pid user pcpu pmem rss comm
    printf '  %s%7s %-12s %6s %6s %8s  %s%s\n' "$C_BOLD" "PID" "USER" "%CPU*" "%MEM" "RSS" "COMMAND" "$C_RESET"
    while read -r pid user pcpu pmem rss comm; do
        printf '  %7s %-12.12s %s%6s%s %6s %8s  %s%s%s\n' "$pid" "$user" "$T_KEY" "$pcpu" "$C_RESET" "$pmem" "$(fmt_kb "$rss")" "$T_VALUE" "$comm" "$C_RESET"
    done < <(_mon_procs "$n" "$sort")
}

# --- Monitor en vivo (pantalla completa) ---------------------------------------------
monitor_live() {
    if [[ ! -t 0 || ! -t 1 ]]; then monitor_snapshot "$(cfg MONITOR_PROCS 12)"; return $?; fi
    local interval="${1:-$(cfg MONITOR_INTERVAL 2)}" nprocs="${2:-$(cfg MONITOR_PROCS 12)}"
    is_uint "$interval" && (( interval >= 1 )) || interval=2
    is_uint "$nprocs" || nprocs=12
    local sort="pcpu" last=-999 own=0
    local -A pt=() pi=() ct=() ci=()
    local -a cores=() disks=() procs=()

    if (( ! _UI_ACTIVE )); then own=1; ui_install_traps; ui_screen_enter; fi
    stty -echo </dev/tty 2>/dev/null || true
    printf '\e[?25l'
    UI_NEED_CLEAR=1
    sys_cpu_read pt pi
    sleep 0.3

    while :; do
        ui_term_size
        if (( SECONDS - last >= interval )); then
            sys_cpu_read ct ci
            cores=()
            local k
            for k in $(printf '%s\n' "${!ct[@]}" | sort -V); do
                [[ -n "${pt[$k]:-}" ]] || continue
                cores+=("${k}|$(cpu_pct "${pt[$k]}" "${pi[$k]}" "${ct[$k]}" "${ci[$k]}")")
                pt[$k]=${ct[$k]}; pi[$k]=${ci[$k]}
            done
            sys_mem_read
            mapfile -t disks < <(_mon_disks)
            mapfile -t procs < <(_mon_procs 40 "$sort")
            last=$SECONDS
        fi
        _monitor_draw "$sort" "$nprocs"
        ui_read_key 1
        case "$UI_KEY" in
            q|Q|ESC|EOF|LEFT) break ;;
            s|S) if [[ "$sort" == "pcpu" ]]; then sort="pmem"; else sort="pcpu"; fi; last=-999 ;;
            r|R) last=-999 ;;
            *) : ;;
        esac
    done
    printf '\e[0m\e[2J\e[H\e[?25h'
    if (( own )); then ui_screen_leave; ui_remove_traps; fi
    return 0
}

_monitor_draw() {
    local sort="$1" nprocs="$2"
    local W=$UI_COLS x0=1 row=1 i bar pc txt line name pct inner bw
    (( W > 120 )) && { W=120; x0=$(( (UI_COLS - W) / 2 + 1 )); }
    ui_buf_begin
    if (( UI_COLS < 60 || UI_ROWS < 18 )); then
        ui_at 1 1 "${T_WARN}Monitor needs at least 60x18 (current ${UI_COLS}x${UI_ROWS}). q to quit.${C_RESET}"
        ui_flush; return 0
    fi
    inner=$(( W - 4 ))
    ui_fit txt "${G_DIAM} URB ${G_ARROW} MONITOR   $(sys_hostname)   up $(sys_uptime)   load $(sys_loadavg)" $(( W - 10 ))
    ui_at "$row" "$x0" "${T_TITLE}${txt}${C_RESET}${T_VALUE}$(printf '%(%H:%M:%S)T' -1)${C_RESET}"
    row=$(( row + 2 ))

    # CPU: total + núcleos en columnas
    local ncores=$(( ${#cores[@]} - 1 )) cols percol h
    (( ncores < 0 )) && ncores=0
    cols=$(( inner / 26 )); (( cols < 1 )) && cols=1
    percol=$(( (ncores + cols - 1) / cols )); (( percol > 4 )) && percol=4
    h=$(( 3 + percol ))
    ui_box "$row" "$x0" "$W" "$h" "CPU"
    pct="${cores[0]#*|}"; pct="${pct:-0}"
    bw=$(( inner - 12 )); (( bw > 60 )) && bw=60
    ui_bar bar "$pct" "$bw"; ui_pct_color pc "$pct"
    ui_at $(( row + 1 )) $(( x0 + 2 )) "${T_LABEL}ALL  ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$pct")${C_RESET}"
    local idx=0 c r
    for (( i = 1; i <= ncores && idx < cols * percol; i++ )); do
        name="${cores[i]%%|*}"; pct="${cores[i]#*|}"
        c=$(( idx / percol )); r=$(( idx % percol ))
        ui_bar bar "$pct" 12; ui_pct_color pc "$pct"
        ui_fit txt "${name#cpu}" 3
        ui_at $(( row + 2 + r )) $(( x0 + 2 + c * 26 )) "${T_DIM}c${txt}${C_RESET} ${bar} ${pc}$(printf '%3d%%' "$pct")${C_RESET}"
        idx=$(( idx + 1 ))
    done
    row=$(( row + h ))

    # Memoria
    local mh=4; (( SWAP_TOTAL_KB > 0 )) && mh=5
    ui_box "$row" "$x0" "$W" "$mh" "MEMORY"
    ui_bar bar "$MEM_PCT" "$bw"; ui_pct_color pc "$MEM_PCT"
    ui_at $(( row + 1 )) $(( x0 + 2 )) "${T_LABEL}RAM  ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$MEM_PCT")${C_RESET} ${T_DIM}$(fmt_kb "$MEM_USED_KB")/$(fmt_kb "$MEM_TOTAL_KB")${C_RESET}"
    ui_fit txt "available $(fmt_kb "$MEM_AVAIL_KB")" "$inner"
    ui_at $(( row + 2 )) $(( x0 + 2 )) "${T_DIM}${txt}${C_RESET}"
    if (( SWAP_TOTAL_KB > 0 )); then
        ui_bar bar "$SWAP_PCT" "$bw"; ui_pct_color pc "$SWAP_PCT"
        ui_at $(( row + 3 )) $(( x0 + 2 )) "${T_LABEL}SWAP ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$SWAP_PCT")${C_RESET}"
    fi
    row=$(( row + mh ))

    # Discos
    local nd=${#disks[@]}
    if (( nd > 0 && UI_ROWS - row > 10 )); then
        (( nd > 3 )) && nd=3
        ui_box "$row" "$x0" "$W" $(( nd + 2 )) "STORAGE"
        local mnt tot used avail p
        for (( i = 0; i < nd; i++ )); do
            IFS=$'\t' read -r mnt tot used avail p <<<"${disks[i]}"
            p="${p%\%}"; is_uint "$p" || p=0
            ui_fit txt "$mnt" 14
            ui_bar bar "$p" 24; ui_pct_color pc "$p"
            ui_at $(( row + 1 + i )) $(( x0 + 2 )) "${T_LABEL}${txt}${C_RESET} ${bar} ${pc}$(printf '%3d%%' "$p")${C_RESET} ${T_DIM}$(fmt_kb "$avail") free / $(fmt_kb "$tot")${C_RESET}"
        done
        row=$(( row + nd + 2 ))
    fi

    # Procesos: ocupan el resto
    local ph=$(( UI_ROWS - row ))
    local np=$(( ph - 3 )); (( np > nprocs )) && np=$nprocs
    if (( np >= 1 )); then
        local stitle="PROCESSES (sort: %CPU)"; [[ "$sort" == "pmem" ]] && stitle="PROCESSES (sort: %MEM)"
        ui_box "$row" "$x0" "$W" $(( np + 3 )) "$stitle"
        printf -v line '%7s %-12s %6s %6s %8s  %s' "PID" "USER" "%CPU*" "%MEM" "RSS" "COMMAND"
        ui_fit txt "$line" "$inner"
        ui_at $(( row + 1 )) $(( x0 + 2 )) "${C_BOLD}${T_LABEL}${txt}${C_RESET}"
        local pid user pcpu pmem rss comm
        for (( i = 0; i < np && i < ${#procs[@]}; i++ )); do
            read -r pid user pcpu pmem rss comm <<<"${procs[i]}"
            printf -v line '%7s %-12.12s %6s %6s %8s  %s' "$pid" "$user" "$pcpu" "$pmem" "$(fmt_kb "$rss")" "$comm"
            ui_fit txt "$line" "$inner"
            ui_at $(( row + 2 + i )) $(( x0 + 2 )) "${T_VALUE}${txt}${C_RESET}"
        done
        row=$(( row + np + 3 ))
    fi
    ui_fit txt " q quit  s sort cpu/mem  r refresh   * %CPU = average over process lifetime (ps)" "$W"
    ui_at "$UI_ROWS" "$x0" "${T_DIM}${txt}${C_RESET}"
    ui_flush
}

monitor_main() {
    local once=0 interval="" nprocs=""
    case "${1:-}" in
        procs|processes)
            shift
            local n; n="$(cfg MONITOR_PROCS 12)"
            if [[ "${1:-}" == "-n" ]]; then is_uint "${2:-}" || { msg_err "-n needs a number"; return 2; }; n="$2"; fi
            msg_section "TOP PROCESSES (by CPU)"
            monitor_procs_table "$n" pcpu
            return 0 ;;
        -h|--help|help) monitor_help; return 0 ;;
    esac
    while (( $# > 0 )); do
        case "$1" in
            --once)     once=1; shift ;;
            --interval) is_uint "${2:-}" && (( $2 >= 1 )) || { msg_err "--interval needs a number >= 1"; return 2; }; interval="$2"; shift 2 ;;
            --procs)    is_uint "${2:-}" || { msg_err "--procs needs a number"; return 2; }; nprocs="$2"; shift 2 ;;
            *) msg_err "Unknown option: $1"; msg_dim "    See: urb help monitor"; return 2 ;;
        esac
    done
    if (( once )) || [[ ! -t 1 || ! -t 0 ]]; then
        monitor_snapshot "${nprocs:-$(cfg MONITOR_PROCS 12)}"
    else
        monitor_live "$interval" "$nprocs"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    URB_HOME="$(cd -P -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)" || exit 1
    # shellcheck source=../lib/utils.sh
    source "${URB_HOME}/lib/utils.sh" && urb_standalone_init || exit 1
    monitor_main "$@"
    exit $?
fi
