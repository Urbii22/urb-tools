#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/dashboard.sh — URB Terminal: dashboard principal interactivo
#  Diseño adaptable: logo grande o compacto, paneles lado a lado o apilados.
# =============================================================================

[[ -n "${_URB_DASH_LOADED:-}" ]] && return 0
_URB_DASH_LOADED=1

# Elementos del menú: TECLA|ETIQUETA|Descripción|función
DASH_ITEMS=(
    "1|RECON|Network Scanning (nmap)|scan_menu"
    "2|NETWORK|Network Discovery|network_menu"
    "3|MONITOR|System Monitoring|monitor_live"
    "4|LOGS|Security Log Analysis|logs_menu"
    "5|CTF|Laboratory Management|ctf_menu"
    "6|SETTINGS|Configuration|settings_menu"
    "Q|EXIT|Close URB Terminal|"
)

# --- Datos (se recogen cada REFRESH_INTERVAL segundos) -------------------------
declare -gA _D_TOT_PREV=() _D_IDL_PREV=()
D_CPU=0
_dash_collect_static() {
    D_HOST="$(sys_hostname)"
    D_USER="$(sys_user)"
    D_OS="$(sys_os)"
    D_KERNEL="$(sys_kernel)"
    D_NCPU="$(sys_cpu_count)"
    sys_is_wsl && D_OS+=" (WSL)"
    return 0
}

_dash_collect() {
    local -A tot=() idl=()
    local first=0
    (( ${#_D_TOT_PREV[@]} == 0 )) && first=1
    if (( first )); then
        sys_cpu_read _D_TOT_PREV _D_IDL_PREV
        sleep 0.25
    fi
    if sys_cpu_read tot idl && [[ -n "${tot[cpu]:-}" && -n "${_D_TOT_PREV[cpu]:-}" ]]; then
        D_CPU="$(cpu_pct "${_D_TOT_PREV[cpu]}" "${_D_IDL_PREV[cpu]}" "${tot[cpu]}" "${idl[cpu]}")"
        local k
        _D_TOT_PREV=(); _D_IDL_PREV=()
        for k in "${!tot[@]}"; do _D_TOT_PREV[$k]=${tot[$k]}; _D_IDL_PREV[$k]=${idl[$k]}; done
    fi
    sys_mem_read || true
    sys_disk_read / || true
    D_UPTIME="$(sys_uptime)"
    D_LOAD="$(sys_loadavg)"
    D_IP="$(sys_local_ip)"
    D_GW="$(sys_gateway)"
    mapfile -t D_IFACES < <(sys_interfaces 2>/dev/null)
    mapfile -t D_VPN < <(printf '%s\n' "${D_IFACES[@]}" | sys_vpn_detect /dev/stdin 2>/dev/null)
    D_STAMP="$(printf '%(%H:%M:%S)T' -1)"
}

# --- Dibujo --------------------------------------------------------------------
_dash_draw() {
    local tick=$1 sel=$2
    local W x0 row inner big=0 header_h info_h avail wide=0 i
    local line txt bar pc
    ui_buf_begin

    if (( UI_COLS < 60 || UI_ROWS < 20 )); then
        ui_at 1 1 "${T_WARN}URB Terminal needs at least 60x20 (current: ${UI_COLS}x${UI_ROWS}).${C_RESET}"
        ui_at 2 1 "${T_DIM}Resize the window, or press q to quit.${C_RESET}"
        ui_flush
        return 0
    fi

    # Alineado arriba a la izquierda, con un margen fijo de 1 columna a cada lado
    local margin=1
    W=$(( UI_COLS - 2 * margin )); (( W > 112 )) && W=112
    x0=$(( 1 + margin ))
    (( W >= 90 )) && wide=1

    # Alto disponible para el panel de información
    local res_h=5 menu_h=$(( ${#DASH_ITEMS[@]} + 2 )) foot_h=1
    if (( UI_ROWS >= 7 + 7 + res_h + menu_h + foot_h + 1 )); then big=1; header_h=7; else header_h=2; fi
    avail=$(( UI_ROWS - header_h - res_h - menu_h - foot_h ))
    if (( wide )); then info_h=7; else info_h=8; fi
    (( info_h > avail )) && info_h=$avail

    # ---------- Cabecera ----------
    row=1
    local pulse="$G_DOT" pcol=$T_ACCENT
    if cfg_bool ANIMATIONS 1 && (( tick % 2 )); then pcol=$T_DIM; pulse="$G_RING"; fi
    if (( big )); then
        local lw; lw="$(ui_logo_width)"
        for i in "${!UI_LOGO[@]}"; do
            (( i >= 6 )) && break
            ui_at $(( row + i )) $(( x0 + 1 )) "${UI_LOGO_COLORS[i % 6]}${UI_LOGO[i]}${C_RESET}"
        done
        local tx=$(( x0 + lw + 4 ))
        ui_at $(( row + 1 )) "$tx" "${T_TITLE}URB-TOOLS${C_RESET} ${T_DIM}v${URB_VERSION}${C_RESET}"
        ui_at $(( row + 2 )) "$tx" "${T_ACCENT}CYBERSECURITY TOOLKIT${C_RESET}"
        ui_at $(( row + 3 )) "$tx" "${T_DIM}${D_USER}@${D_HOST}${C_RESET}"
        ui_at $(( row + 4 )) "$tx" "${pcol}${pulse}${C_RESET} ${T_DIM}LIVE${C_RESET}  ${T_VALUE}${D_STAMP}${C_RESET}"
        if (( ${#D_VPN[@]} > 0 )); then
            ui_at $(( row + 5 )) "$tx" "${T_OK}${G_DIAM} VPN ${D_VPN[0]}${C_RESET}"
        else
            ui_at $(( row + 5 )) "$tx" "${T_DIM}${G_DIAM} VPN off${C_RESET}"
        fi
    else
        ui_fit txt " ${G_DIAM} URB-TOOLS ${G_SEP} CYBERSECURITY TOOLKIT ${G_SEP} v${URB_VERSION}" $(( W - 12 ))
        ui_at "$row" "$x0" "${T_TITLE}${txt}${C_RESET}${pcol}${pulse}${C_RESET} ${T_VALUE}${D_STAMP}${C_RESET}"
    fi
    row=$(( row + header_h ))

    # ---------- Paneles de información ----------
    if (( info_h >= 3 )); then
        local -a sysl=() netl=()
        sysl+=("Host|${D_HOST}" "User|${D_USER}" "OS|${D_OS}" "Kernel|${D_KERNEL}" "Uptime|${D_UPTIME}")
        netl+=("Local IP|${D_IP}")
        if [[ -n "$D_GW" ]]; then netl+=("Gateway|${D_GW% *} via ${D_GW#* }"); else netl+=("Gateway|none"); fi
        if (( ${#D_VPN[@]} > 0 )); then netl+=("VPN|${G_DOT} ACTIVE ${D_VPN[0]}"); else netl+=("VPN|${G_RING} inactive"); fi
        local ifl name state v4
        for ifl in "${D_IFACES[@]}"; do
            IFS='|' read -r name state v4 _ <<<"$ifl"
            [[ "$name" == "lo" ]] && continue
            netl+=("${name}|${state} ${v4:--}")
        done

        if (( wide )); then
            local lwid=$(( W / 2 )) rwid=$(( W - W / 2 ))
            ui_box "$row" "$x0" "$lwid" "$info_h" "SYSTEM"
            ui_box "$row" $(( x0 + lwid )) "$rwid" "$info_h" "NETWORK"
            _dash_kv_list "$row" "$x0" "$lwid" "$info_h" "${sysl[@]}"
            _dash_kv_list "$row" $(( x0 + lwid )) "$rwid" "$info_h" "${netl[@]}"
        else
            ui_box "$row" "$x0" "$W" "$info_h" "SYSTEM ${G_SEP} NETWORK"
            # Prioridad en pantallas estrechas: identidad, IP, VPN (clave en CTF), gateway
            local -a mix=("Host|${D_USER}@${D_HOST}" "${netl[0]}" "${netl[2]}" "${netl[1]}" "OS|${D_OS}" "Uptime|${D_UPTIME}" "${netl[@]:3}")
            _dash_kv_list "$row" "$x0" "$W" "$info_h" "${mix[@]}"
        fi
        row=$(( row + info_h ))
    fi

    # ---------- Recursos ----------
    inner=$(( W - 4 ))
    local bw=$(( inner - 36 )); (( bw > 48 )) && bw=48; (( bw < 10 )) && bw=10
    ui_box "$row" "$x0" "$W" "$res_h" "RESOURCES"
    ui_bar bar "$D_CPU" "$bw"; ui_pct_color pc "$D_CPU"
    ui_fit txt "load ${D_LOAD} (${D_NCPU} cpu)" $(( inner - bw - 12 ))
    ui_at $(( row + 1 )) $(( x0 + 2 )) "${T_LABEL}CPU  ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$D_CPU")${C_RESET}  ${T_DIM}${txt}${C_RESET}"
    ui_bar bar "$MEM_PCT" "$bw"; ui_pct_color pc "$MEM_PCT"
    ui_fit txt "$(fmt_kb "$MEM_USED_KB") / $(fmt_kb "$MEM_TOTAL_KB")" $(( inner - bw - 12 ))
    ui_at $(( row + 2 )) $(( x0 + 2 )) "${T_LABEL}RAM  ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$MEM_PCT")${C_RESET}  ${T_VALUE}${txt}${C_RESET}"
    ui_bar bar "$DISK_PCT" "$bw"; ui_pct_color pc "$DISK_PCT"
    ui_fit txt "$(fmt_kb "$DISK_AVAIL_KB") free / $(fmt_kb "$DISK_TOTAL_KB") (${DISK_MOUNT})" $(( inner - bw - 12 ))
    ui_at $(( row + 3 )) $(( x0 + 2 )) "${T_LABEL}DISK ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$DISK_PCT")${C_RESET}  ${T_VALUE}${txt}${C_RESET}"
    row=$(( row + res_h ))

    # ---------- Menú ----------
    ui_box "$row" "$x0" "$W" "$menu_h" "MAIN MENU"
    local key label desc
    for i in "${!DASH_ITEMS[@]}"; do
        IFS='|' read -r key label desc _ <<<"${DASH_ITEMS[i]}"
        ui_fit txt "$label" 11
        if (( i == sel )); then
            ui_fit line " ${G_ARROW} [${key}] ${txt}${desc}" $(( inner ))
            ui_at $(( row + 1 + i )) $(( x0 + 2 )) "${T_SEL}${line}${C_RESET}"
        else
            ui_fit line "${desc}" $(( inner - 18 ))
            ui_at $(( row + 1 + i )) $(( x0 + 2 )) "   ${T_KEY}[${key}]${C_RESET} ${T_VALUE}${txt}${C_RESET}${T_DIM}${line}${C_RESET} "
        fi
    done
    row=$(( row + menu_h ))

    # ---------- Pie ----------
    ui_fit txt " ${G_UP}${G_DOWN}/jk move  ${G_ENTER} select  1-6 jump  r refresh  q quit" "$W"
    ui_at "$row" "$x0" "${T_DIM}${txt}${C_RESET}"
    ui_flush
}

# _dash_kv_list fila col ancho alto "Etiqueta|valor"...
_dash_kv_list() {
    local r=$1 c=$2 w=$3 h=$4; shift 4
    local i=0 item label val vcol max=$(( h - 2 ))
    for item in "$@"; do
        (( i >= max )) && break
        label="${item%%|*}"; val="${item#*|}"
        vcol=$T_VALUE
        case "$val" in
            "${G_DOT} ACTIVE"*|UP*) vcol=$T_OK ;;
            "${G_RING} inactive"|DOWN*|none) vcol=$T_DIM ;;
        esac
        ui_kv $(( r + 1 + i )) $(( c + 2 )) $(( w - 4 )) "$label" "$val" "$vcol" 10
        i=$(( i + 1 ))
    done
}

# --- Animación de arranque: comprobaciones REALES de dependencias ---------------
_dash_boot() {
    cfg_bool ANIMATIONS 1 || return 0
    local i r c lw tool status
    ui_term_size
    (( UI_COLS < 60 || UI_ROWS < 20 )) && return 0
    lw="$(ui_logo_width)"
    r=$(( UI_ROWS / 2 - 6 )); (( r < 1 )) && r=1
    c=$(( (UI_COLS - lw) / 2 + 1 ))
    printf '\e[2J'
    for i in "${!UI_LOGO[@]}"; do
        printf '\e[%d;%dH%s%s%s' $(( r + i )) "$c" "${UI_LOGO_COLORS[i % 6]}" "${UI_LOGO[i]}" "$C_RESET"
        IFS= read -rsn1 -t 0.04 _ </dev/tty && return 0
    done
    local cc=$(( (UI_COLS - 40) / 2 + 1 )) rr=$(( r + ${#UI_LOGO[@]} + 1 ))
    printf '\e[%d;%dH%s' "$rr" "$cc" "${T_TITLE}CYBERSECURITY TOOLKIT ${T_DIM}v${URB_VERSION}${C_RESET}"
    rr=$(( rr + 2 ))
    for tool in ip ss nmap fzf figlet curl; do
        if has_cmd "$tool"; then status="${T_OK}[ ${G_OK} ]${C_RESET}"; else status="${T_WARN}[ -- ]${C_RESET}"; fi
        printf '\e[%d;%dH%s %s%-8s%s' "$rr" "$cc" "$status" "$T_DIM" "$tool" "$C_RESET"
        rr=$(( rr + 1 ))
        IFS= read -rsn1 -t 0.05 _ </dev/tty && return 0
    done
    IFS= read -rsn1 -t 0.35 _ </dev/tty || true
}

# --- Lanzar un módulo desde el dashboard -----------------------------------------
# Se ejecuta en una subshell: un error o `exit` del módulo nunca cierra la TUI.
_dash_launch() {
    local fn="$1"
    declare -F "$fn" >/dev/null || { return 0; }
    ui_suspend
    trap ':' INT
    ( trap - INT TERM EXIT; "$fn" )
    trap 'exit 130' INT
    # Los ajustes pueden haber cambiado dentro del módulo (SETTINGS)
    urb_load_config
    [[ "${URB_NO_ANIM:-0}" == "1" ]] && URB_CFG[ANIMATIONS]=0
    ui_resume
}

# --- Bucle principal --------------------------------------------------------------
dashboard_run() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        msg_err "The URB dashboard needs an interactive terminal."
        msg_dim "    Non-interactive alternatives: urb help | urb monitor --once | urb network"
        return 1
    fi
    local interval sel=0 tick=0 n=${#DASH_ITEMS[@]} last=0 now fn
    interval="$(cfg REFRESH_INTERVAL 2)"; is_uint "$interval" && (( interval >= 1 )) || interval=2

    ui_install_traps
    ui_screen_enter
    ui_load_logo
    _dash_boot
    _dash_collect_static
    _dash_collect
    UI_NEED_CLEAR=1
    last=$SECONDS

    while :; do
        ui_term_size
        if (( _UI_RESIZED )); then _UI_RESIZED=0; UI_NEED_CLEAR=1; fi
        now=$SECONDS
        if (( now - last >= interval )); then _dash_collect; last=$now; fi
        _dash_draw "$tick" "$sel"
        ui_read_key 1
        case "$UI_KEY" in
            UP|k|K)   sel=$(( (sel - 1 + n) % n )) ;;
            DOWN|j|J) sel=$(( (sel + 1) % n )) ;;
            r|R)      _dash_collect; last=$SECONDS ;;
            q|Q|EOF)  break ;;
            ESC)      sel=$(( n - 1 )) ;;
            [1-6])    sel=$(( UI_KEY - 1 )); fn="${DASH_ITEMS[sel]##*|}"; _dash_launch "$fn"; _dash_collect; last=$SECONDS ;;
            ENTER|RIGHT|l)
                fn="${DASH_ITEMS[sel]##*|}"
                [[ -z "$fn" ]] && break
                _dash_launch "$fn"; _dash_collect; last=$SECONDS ;;
            TIMEOUT)  tick=$(( tick + 1 )) ;;
            *) : ;;
        esac
    done
    ui_screen_leave
    trap - EXIT INT TERM HUP WINCH
    printf '%s%s URB Terminal closed. Stay ethical.%s\n' "$T_DIM" "$G_DIAM" "$C_RESET"
    return 0
}
