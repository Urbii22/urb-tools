#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/dashboard.sh — URB Terminal: dashboard principal (centro de control)
#
#  Desde aquí se abren, sin menús anidados:
#   - Entornos de terminal: GOD, RED, (BLUE: próximamente) y una Zsh normal
#   - Herramientas: RECON, NETWORK, MONITOR, LOGS, CTF
#   - Sistema: SETTINGS, SESSIONS, HELP, EXIT
#
#  Transiciones (ver _dash_child):
#   - GOD/RED/Zsh/ayuda son PROCESOS HIJOS reales (los mismos lanzadores que
#     `urb god`, `urb red`...), ejecutados en la pantalla PRINCIPAL con el
#     estado de la terminal restaurado. Al terminar (exit, detach o error) se
#     vuelve aquí; el dashboard nunca mata sesiones ni procesos.
#   - Los módulos de herramientas se ejecutan en una subshell dentro de la
#     pantalla alternativa, como siempre.
#  Diseño adaptable: alineado arriba a la izquierda; en pantallas pequeñas se
#  ocultan primero los paneles de información y el menú se desplaza.
# =============================================================================

[[ -n "${_URB_DASH_LOADED:-}" ]] && return 0
_URB_DASH_LOADED=1

# --- Elementos del menú ---------------------------------------------------------
# SECCIÓN|TECLA|ETIQUETA|Descripción|tipo|destino|estado
#   tipo:   env  (entorno de terminal) · tool (módulo) · sys (sistema)
#   estado: ready · soon (visible, deshabilitado: no se puede ejecutar)
# Un perfil futuro (p. ej. DEV) = una línea "env" con destino = nombre del
# perfil (godmode/profiles/<nombre>.profile). Mientras no exista, "soon".
DASH_SECTIONS=(
    "ENV|TERMINAL ENVIRONMENTS"
    "TOOLS|CYBERSECURITY TOOLS"
    "SYS|SYSTEM"
)
DASH_ITEMS=(
    "ENV|G|GOD MODE|Productivity shell: zsh + tmux + HUD|env|god|ready"
    "ENV|R|RED MODE|Offensive labs: target, workspace, red HUD|env|red|ready"
    "ENV|B|BLUE MODE|Offline SOC investigation|env|blue|ready"
    "ENV|Z|NORMAL SHELL|Your plain zsh: no URB theme or HUD|env|zsh|ready"
    "TOOLS|1|RECON|Network Scanning (nmap)|tool|scan_menu|ready"
    "TOOLS|2|NETWORK|Network Discovery|tool|network_menu|ready"
    "TOOLS|3|MONITOR|System Monitoring|tool|monitor_live|ready"
    "TOOLS|4|LOGS|Security Log Analysis|tool|logs_menu|ready"
    "TOOLS|5|CTF|Laboratory Management|tool|ctf_menu|ready"
    "SYS|6|SETTINGS|Configuration|tool|settings_menu|ready"
    "SYS|S|SESSIONS|GOD / RED / BLUE sessions: state and reconnect|sys|sessions|ready"
    "SYS|H|HELP|Commands, keys and manual|sys|help|ready"
    "SYS|Q|EXIT|Close URB Terminal|sys|exit|ready"
)

# Campos de los elementos (se rellenan con _dash_parse)
DI_SEC=() DI_KEY=() DI_LABEL=() DI_DESC=() DI_KIND=() DI_TARGET=() DI_STATE=()
DASH_ROWS=()          # filas del menú: "S|título de sección" o "I|índice"
DASH_OFF=0            # primera fila visible del menú (desplazamiento)
DASH_SEL=0
DASH_STATUS="" DASH_STATUS_COL=""
declare -gA D_SES=()  # estado de sesión por perfil (attached|detached|none|error)

_dash_parse() {
    local i sec key label desc kind target state s sid stitle
    DI_SEC=() DI_KEY=() DI_LABEL=() DI_DESC=() DI_KIND=() DI_TARGET=() DI_STATE=()
    for i in "${!DASH_ITEMS[@]}"; do
        IFS='|' read -r sec key label desc kind target state <<<"${DASH_ITEMS[i]}"
        DI_SEC+=("$sec") DI_KEY+=("$key") DI_LABEL+=("$label") DI_DESC+=("$desc")
        DI_KIND+=("$kind") DI_TARGET+=("$target") DI_STATE+=("${state:-ready}")
    done
    DASH_ROWS=()
    for s in "${DASH_SECTIONS[@]}"; do
        sid="${s%%|*}"; stitle="${s#*|}"
        DASH_ROWS+=("S|${stitle}")
        for i in "${!DI_SEC[@]}"; do
            [[ "${DI_SEC[i]}" == "$sid" ]] && DASH_ROWS+=("I|${i}")
        done
    done
}

# ¿Se puede ejecutar el elemento i?
dash_selectable() { [[ "${DI_STATE[$1]:-}" == "ready" ]]; }

# dash_move SEL DIRECCIÓN(-1|1) → DASH_SEL = siguiente elemento seleccionable
# siguiendo el orden visual del menú (con vuelta al principio/final)
dash_move() {
    local sel=$1 dir=$2 n=${#DASH_ROWS[@]} pos=-1 i r idx
    for i in "${!DASH_ROWS[@]}"; do [[ "${DASH_ROWS[i]}" == "I|${sel}" ]] && { pos=$i; break; }; done
    (( pos < 0 )) && pos=0
    for (( i = 1; i <= n; i++ )); do
        r="${DASH_ROWS[(( (pos + dir * i) % n + n ) % n)]}"
        [[ "$r" == I\|* ]] || continue
        idx="${r#I|}"
        if dash_selectable "$idx"; then DASH_SEL=$idx; return 0; fi
    done
    DASH_SEL=$sel
}

# dash_key_index TECLA → DASH_KIDX = índice del elemento con esa tecla (o -1)
dash_key_index() {
    local k="${1^^}" i
    DASH_KIDX=-1
    [[ ${#k} -eq 1 ]] || return 1
    for i in "${!DI_KEY[@]}"; do
        [[ "${DI_KEY[i]}" == "$k" ]] && { DASH_KIDX=$i; return 0; }
    done
    return 1
}

_dash_status() { DASH_STATUS="$2"; DASH_STATUS_COL="$1"; }

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
    _dash_collect_sessions
}

# Estado de las sesiones de los perfiles del menú (solo lectura: nunca crea nada)
_dash_collect_sessions() {
    local i t
    D_SES=()
    declare -F sess_query >/dev/null || return 0
    for i in "${!DI_KIND[@]}"; do
        [[ "${DI_KIND[i]}" == "env" && "${DI_STATE[i]}" == "ready" ]] || continue
        t="${DI_TARGET[i]}"
        _dash_is_profile "$t" || continue
        D_SES[$t]="$(_dash_session_state "$t")"
    done
}

# Estado de la sesión de un perfil, sin alterar las variables P_* del proceso
_dash_session_state() {
    ( sess_load_profile "$1" >/dev/null 2>&1 || exit 0
      sess_query "$GOD_SOCKET" "$GOD_SESSION" 0 >/dev/null 2>&1
      printf '%s' "$S_STATE" )
}

_dash_is_profile() { [[ "$1" =~ ^[a-z]{1,16}$ && -r "${URB_HOME}/godmode/profiles/${1}.profile" ]]; }

# --- Dibujo --------------------------------------------------------------------
_dash_draw() {
    local tick=$1 sel=$2
    local W x0 row i txt bar pc wide=0 big=0 header_h foot_h=2 body_h menu_h menu_full rem
    ui_buf_begin

    if (( UI_COLS < 50 || UI_ROWS < 12 )); then
        ui_at 1 1 "${T_WARN}URB Terminal needs at least 50x12 (current: ${UI_COLS}x${UI_ROWS}).${C_RESET}"
        ui_at 2 1 "${T_DIM}Resize the window, or press q to quit.${C_RESET}"
        ui_flush
        return 0
    fi

    # Alineado arriba a la izquierda, con un margen fijo de 1 columna a cada lado
    W=$(( UI_COLS - 2 )); (( W > 120 )) && W=120
    x0=2
    (( W >= 100 )) && wide=1
    menu_full=$(( ${#DASH_ROWS[@]} + 2 ))

    # Cabecera grande (logo) solo si cabe el menú completo; si no, una línea
    local lw; lw="$(ui_logo_width)"
    if (( W >= lw + 32 )); then
        if (( wide )) && (( UI_ROWS >= 7 + menu_full + foot_h )); then big=1
        elif (( ! wide )) && (( UI_ROWS >= 7 + menu_full + foot_h + 5 )); then big=1
        fi
    fi
    if (( big )); then header_h=7; elif (( UI_ROWS >= 18 )); then header_h=2; else header_h=1; fi
    body_h=$(( UI_ROWS - header_h - foot_h ))
    menu_h=$menu_full; (( menu_h > body_h )) && menu_h=$body_h

    # ---------- Cabecera ----------
    row=1
    local pulse="$G_DOT" pcol=$T_ACCENT vpn
    if cfg_bool ANIMATIONS 1 && (( tick % 2 )); then pcol=$T_DIM; pulse="$G_RING"; fi
    if (( ${#D_VPN[@]} > 0 )); then vpn="${T_OK}${G_DIAM} VPN ${D_VPN[0]}${C_RESET}"; else vpn="${T_DIM}${G_DIAM} VPN off${C_RESET}"; fi
    if (( big )); then
        for i in "${!UI_LOGO[@]}"; do
            (( i >= 6 )) && break
            ui_at $(( row + i )) $(( x0 + 1 )) "${UI_LOGO_COLORS[i % 6]}${UI_LOGO[i]}${C_RESET}"
        done
        local tx=$(( x0 + lw + 4 ))
        ui_at $(( row + 1 )) "$tx" "${T_TITLE}URB-TOOLS${C_RESET} ${T_DIM}v${URB_VERSION}${C_RESET}"
        ui_at $(( row + 2 )) "$tx" "${T_ACCENT}CONTROL CENTER${C_RESET} ${T_DIM}${G_SEP} terminals ${G_SEP} cyber tools${C_RESET}"
        ui_at $(( row + 3 )) "$tx" "${T_DIM}${D_USER}@${D_HOST}${C_RESET}"
        ui_at $(( row + 4 )) "$tx" "${pcol}${pulse}${C_RESET} ${T_DIM}LIVE${C_RESET}  ${T_VALUE}${D_STAMP}${C_RESET}"
        ui_at $(( row + 5 )) "$tx" "$vpn"
    else
        ui_fit txt " ${G_DIAM} URB-TOOLS ${G_SEP} CONTROL CENTER ${G_SEP} v${URB_VERSION}" $(( W - 13 ))
        ui_at "$row" "$x0" "${T_TITLE}${txt}${C_RESET} ${pcol}${pulse}${C_RESET} ${T_VALUE}${D_STAMP}${C_RESET}"
    fi
    row=$(( row + header_h ))

    # ---------- Cuerpo ----------
    local -a sysl=() netl=()
    _dash_info_lines
    if (( wide )); then
        # Menú a la izquierda; recursos, sistema y red apilados a la derecha
        local mw=$(( W * 56 / 100 )); (( mw > 66 )) && mw=66
        local sw=$(( W - mw - 1 )) sx=$(( x0 + mw + 1 )) sr=$row h
        _dash_draw_menu "$row" "$x0" "$mw" "$menu_h" "$sel"
        rem=$body_h
        if (( rem >= 5 )); then _dash_draw_resources "$sr" "$sx" "$sw"; sr=$(( sr + 5 )); rem=$(( rem - 5 )); fi
        if (( rem >= 4 )); then
            h=$(( ${#sysl[@]} + 2 )); (( h > rem )) && h=$rem
            ui_box "$sr" "$sx" "$sw" "$h" "SYSTEM"
            _dash_kv_list "$sr" "$sx" "$sw" "$h" "${sysl[@]}"
            sr=$(( sr + h )); rem=$(( rem - h ))
        fi
        if (( rem >= 3 )); then
            h=$(( ${#netl[@]} + 2 )); (( h > rem )) && h=$rem
            ui_box "$sr" "$sx" "$sw" "$h" "NETWORK"
            _dash_kv_list "$sr" "$sx" "$sw" "$h" "${netl[@]}"
            sr=$(( sr + h ))
        fi
        (( sr - row > menu_h )) && menu_h=$(( sr - row ))
        row=$(( row + menu_h ))
    else
        # Prioridad: menú completo > recursos > sistema/red
        rem=$(( body_h - menu_h ))
        local show_res=0 info_h=0
        if (( rem >= 5 )); then show_res=1; rem=$(( rem - 5 )); fi
        if (( rem >= 4 )); then info_h=$rem; (( info_h > 8 )) && info_h=8; fi
        if (( info_h )); then
            ui_box "$row" "$x0" "$W" "$info_h" "SYSTEM ${G_SEP} NETWORK"
            # Prioridad en pantallas estrechas: identidad, IP, VPN (clave en CTF), gateway
            local -a mix=("Host|${D_USER}@${D_HOST}" "${netl[0]}" "${netl[2]}" "${netl[1]}" "OS|${D_OS}" "Uptime|${D_UPTIME}" "${netl[@]:3}")
            _dash_kv_list "$row" "$x0" "$W" "$info_h" "${mix[@]}"
            row=$(( row + info_h ))
        fi
        if (( show_res )); then _dash_draw_resources "$row" "$x0" "$W"; row=$(( row + 5 )); fi
        _dash_draw_menu "$row" "$x0" "$W" "$menu_h" "$sel"
        row=$(( row + menu_h ))
    fi

    # ---------- Pie: estado de la última acción + teclas ----------
    ui_fit txt " ${DASH_STATUS}" "$W"
    if [[ -n "$DASH_STATUS" ]]; then ui_at "$row" "$x0" "${DASH_STATUS_COL}${txt}${C_RESET}"
    else ui_at "$row" "$x0" "$txt"; fi
    ui_fit txt " ${G_UP}${G_DOWN} move  ${G_ENTER} open  G R Z terminals  1-6 tools  S sessions  H help  q quit" "$W"
    ui_at $(( row + 1 )) "$x0" "${T_DIM}${txt}${C_RESET}"
    ui_flush
}

_dash_info_lines() {
    sysl=("Host|${D_HOST}" "User|${D_USER}" "OS|${D_OS}" "Kernel|${D_KERNEL}" "Uptime|${D_UPTIME}")
    netl=("Local IP|${D_IP}")
    if [[ -n "$D_GW" ]]; then netl+=("Gateway|${D_GW% *} via ${D_GW#* }"); else netl+=("Gateway|none"); fi
    if (( ${#D_VPN[@]} > 0 )); then netl+=("VPN|${G_DOT} ACTIVE ${D_VPN[0]}"); else netl+=("VPN|${G_RING} inactive"); fi
    local ifl name state v4
    for ifl in "${D_IFACES[@]}"; do
        IFS='|' read -r name state v4 _ <<<"$ifl"
        [[ "$name" == "lo" ]] && continue
        netl+=("${name}|${state} ${v4:--}")
    done
}

_dash_draw_resources() {
    local r=$1 c=$2 w=$3 inner bw bar pc txt
    inner=$(( w - 4 ))
    bw=$(( inner - 36 )); (( bw > 48 )) && bw=48; (( bw < 10 )) && bw=10
    ui_box "$r" "$c" "$w" 5 "RESOURCES"
    ui_bar bar "$D_CPU" "$bw"; ui_pct_color pc "$D_CPU"
    ui_fit txt "load ${D_LOAD} (${D_NCPU} cpu)" $(( inner - bw - 12 ))
    ui_at $(( r + 1 )) $(( c + 2 )) "${T_LABEL}CPU  ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$D_CPU")${C_RESET}  ${T_DIM}${txt}${C_RESET}"
    ui_bar bar "$MEM_PCT" "$bw"; ui_pct_color pc "$MEM_PCT"
    ui_fit txt "$(fmt_kb "$MEM_USED_KB") / $(fmt_kb "$MEM_TOTAL_KB")" $(( inner - bw - 12 ))
    ui_at $(( r + 2 )) $(( c + 2 )) "${T_LABEL}RAM  ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$MEM_PCT")${C_RESET}  ${T_VALUE}${txt}${C_RESET}"
    ui_bar bar "$DISK_PCT" "$bw"; ui_pct_color pc "$DISK_PCT"
    ui_fit txt "$(fmt_kb "$DISK_AVAIL_KB") free / $(fmt_kb "$DISK_TOTAL_KB") (${DISK_MOUNT})" $(( inner - bw - 12 ))
    ui_at $(( r + 3 )) $(( c + 2 )) "${T_LABEL}DISK ${C_RESET}${bar} ${pc}$(printf '%3d%%' "$DISK_PCT")${C_RESET}  ${T_VALUE}${txt}${C_RESET}"
}

# Etiqueta de estado de un elemento: texto|color
_dash_item_tag() {
    local i=$1 t="${DI_TARGET[$1]}"
    DTAG="" DTAG_COL=""
    if [[ "${DI_STATE[i]}" == "soon" ]]; then DTAG="COMING SOON"; DTAG_COL=$T_WARN; return 0; fi
    [[ "${DI_KIND[i]}" == "env" ]] || return 0
    case "${D_SES[$t]:-}" in
        attached) DTAG="${G_DOT} attached"; DTAG_COL=$T_OK ;;
        detached) DTAG="${G_DOT} detached"; DTAG_COL=$T_WARN ;;
        error)    DTAG="${G_BAD} tmux error"; DTAG_COL=$T_BAD ;;
    esac
}

# _dash_draw_menu fila col ancho alto seleccionado
_dash_draw_menu() {
    local r=$1 c=$2 w=$3 h=$4 sel=$5
    local inner=$(( w - 4 )) vis=$(( h - 2 )) n=${#DASH_ROWS[@]} pos=0 i k row idx
    local txt line desc dw lab key
    (( vis < 1 )) && return 0
    for i in "${!DASH_ROWS[@]}"; do [[ "${DASH_ROWS[i]}" == "I|${sel}" ]] && { pos=$i; break; }; done
    # Desplazamiento: el elemento seleccionado (y su sección, si cabe) siempre visible
    if (( pos < DASH_OFF )); then DASH_OFF=$pos; fi
    if (( pos > 0 )) && [[ "${DASH_ROWS[pos-1]}" == S\|* ]] && (( pos - 1 < DASH_OFF )); then DASH_OFF=$(( pos - 1 )); fi
    if (( pos >= DASH_OFF + vis )); then DASH_OFF=$(( pos - vis + 1 )); fi
    (( DASH_OFF > n - vis )) && DASH_OFF=$(( n - vis ))
    (( DASH_OFF < 0 )) && DASH_OFF=0

    ui_box "$r" "$c" "$w" "$h" "MAIN MENU"
    if (( DASH_OFF > 0 )); then ui_at "$r" $(( c + w - 9 )) "${T_KEY} ${G_UP} more ${C_RESET}"; fi
    if (( DASH_OFF + vis < n )); then ui_at $(( r + h - 1 )) $(( c + w - 9 )) "${T_KEY} ${G_DOWN} more ${C_RESET}"; fi

    for (( k = 0; k < vis && DASH_OFF + k < n; k++ )); do
        row="${DASH_ROWS[DASH_OFF + k]}"
        if [[ "$row" == S\|* ]]; then
            ui_repeat line "$G_H" "$inner"
            txt="${row#S|} "
            line="${txt}${line:${#txt}}"
            ui_fit line "$line" "$inner"
            ui_at $(( r + 1 + k )) $(( c + 2 )) "${T_LABEL}${C_BOLD}${line:0:${#txt}}${C_RESET}${T_DIMBAR}${line:${#txt}}${C_RESET}"
            continue
        fi
        idx="${row#I|}"
        _dash_item_tag "$idx"
        ui_fit lab "${DI_LABEL[idx]}" 13
        key="[${DI_KEY[idx]}]"
        dw=$(( inner - 21 - (${#DTAG} ? ${#DTAG} + 1 : 0) ))
        ui_fit desc "${DI_DESC[idx]}" "$dw"
        if (( idx == sel )); then
            ui_fit line " ${G_ARROW} ${key} ${lab}${desc}${DTAG:+ ${DTAG}}" "$inner"
            ui_at $(( r + 1 + k )) $(( c + 2 )) "${T_SEL}${line}${C_RESET}"
        elif [[ "${DI_STATE[idx]}" != "ready" ]]; then
            ui_at $(( r + 1 + k )) $(( c + 2 )) "   ${T_DIMBAR}${key} ${lab}${desc}${C_RESET}${DTAG:+ ${DTAG_COL}${DTAG}${C_RESET}} "
        else
            ui_at $(( r + 1 + k )) $(( c + 2 )) "   ${T_KEY}${key}${C_RESET} ${T_VALUE}${lab}${C_RESET}${T_DIM}${desc}${C_RESET}${DTAG:+ ${DTAG_COL}${DTAG}${C_RESET}} "
        fi
    done
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
    for tool in ip ss nmap tmux zsh fzf; do
        if has_cmd "$tool"; then status="${T_OK}[ ${G_OK} ]${C_RESET}"; else status="${T_WARN}[ -- ]${C_RESET}"; fi
        printf '\e[%d;%dH%s %s%-8s%s' "$rr" "$cc" "$status" "$T_DIM" "$tool" "$C_RESET"
        rr=$(( rr + 1 ))
        IFS= read -rsn1 -t 0.05 _ </dev/tty && return 0
    done
    IFS= read -rsn1 -t 0.35 _ </dev/tty || true
}

# =============================================================================
#  Lanzadores
# =============================================================================

# --- Módulos de herramientas (en la pantalla de la TUI) ---------------------------
# Se ejecuta en una subshell: un error o `exit` del módulo nunca cierra la TUI.
_dash_launch() {
    local fn="$1"
    declare -F "$fn" >/dev/null || { _dash_status "$T_BAD" "${G_BAD} ${fn}: not available"; return 0; }
    ui_suspend
    trap ':' INT
    ( trap - INT TERM EXIT; "$fn" )
    trap 'exit 130' INT
    # Los ajustes pueden haber cambiado dentro del módulo (SETTINGS)
    urb_load_config
    [[ "${URB_NO_ANIM:-0}" == "1" ]] && URB_CFG[ANIMATIONS]=0
    ui_resume
}

# --- Programas interactivos hijos (GOD, RED, Zsh, ayuda) --------------------------
# _dash_child MOUSE_RESET PAUSA_SI_ERROR comando...
#  1. Sale de la TUI: pantalla principal, cursor visible, stty ORIGINAL (eco).
#  2. Ejecuta el comando en primer plano. Señales: el dashboard instala
#     manejadores no-op (no "ignorar", que heredaría el hijo), así que Ctrl+C,
#     Ctrl+\ y Ctrl+Z llegan al hijo con su acción normal y el dashboard
#     sigue vivo. Bash ejecuta el manejador cuando el hijo termina.
#  3. Al volver: modos de ratón apagados (solo tras tmux), stty original,
#     teclas pendientes descartadas y vuelta a la pantalla de la TUI.
#  → DASH_RC = código de salida del hijo
_dash_child() {
    local mreset=$1 pause=$2; shift 2
    ui_screen_leave
    trap ':' INT QUIT TSTP
    "$@"
    DASH_RC=$?
    trap 'exit 130' INT
    trap 'exit 131' QUIT
    trap ':' TSTP
    (( mreset )) && ui_mouse_reset
    printf '\e[0m\e[?25h'
    ui_tty_restore
    if (( pause )) && (( DASH_RC != 0 && DASH_RC != 130 )); then
        ui_pause "Press any key to return to the URB dashboard${G_ELL}"
    fi
    ui_drain_input
    ui_screen_enter
    UI_NEED_CLEAR=1
    return 0
}

# --- Entornos con tmux (GOD, RED y futuros perfiles) ------------------------------
# Reutiliza los lanzadores de siempre en un proceso hijo: `urb god` (urb_god),
# `urb red` (red_main) y `urb sessions attach` (sessions_attach). Cada uno hace
# `exec bash godmode/god.sh ...` dentro de la subshell: no hay una segunda
# implementación. Nunca se mata una sesión al volver.
#   _dash_tmux_profile PERFIL start|attach
_dash_tmux_profile() {
    local p="$1" mode="${2:-start}" before after name cmd sock
    if ! _dash_is_profile "$p" || ! ( sess_load_profile "$p" >/dev/null 2>&1 ); then
        _dash_status "$T_BAD" "${G_BAD} Profile '${p}' is not installed (godmode/profiles/${p}.profile)."
        return 0
    fi
    sess_load_profile "$p" >/dev/null 2>&1
    name="$P_NAME" cmd="$P_CMD" sock="$GOD_SOCKET"

    # Nada de tmux dentro de tmux: se explica y se sigue en el dashboard
    if [[ -n "${TMUX:-}" ]]; then
        if [[ "$TMUX" == *"/${sock},"* ]]; then
            _dash_status "$T_WARN" "${G_DIAM} You are already inside ${name}. Ctrl+B d detaches it (it keeps running)."
        else
            _dash_status "$T_BAD" "${G_BAD} ${name} cannot start inside another tmux session (no nesting). Detach it (Ctrl+B d) and run 'urb' again."
        fi
        return 0
    fi

    before="$(_dash_session_state "$p")"
    if [[ "$mode" == "attach" && "$before" != "attached" && "$before" != "detached" ]]; then
        _dash_status "$T_WARN" "${G_DIAM} No ${name} session to reconnect to. Start one with its menu entry or '${cmd}'."
        return 0
    fi

    case "$mode:$p" in
        attach:*) _dash_child 1 1 _dash_run_sub sessions_attach "$p" ;;
        start:god) _dash_child 1 1 _dash_run_sub urb_god ;;
        start:red) _dash_child 1 1 _dash_run_sub red_main ;;
        *)         _dash_child 1 1 _dash_run_sub urb_god --profile "$p" ;;
    esac
    after="$(_dash_session_state "$p")"

    # Detach, salida normal y fallo se distinguen por el código de god.sh y
    # por el estado REAL de la sesión después (no se adivina)
    if (( DASH_RC == 0 || DASH_RC == 130 )); then
        case "$after" in
            detached)
                _dash_status "$T_WARN" "${G_DOT} ${name} detached: your programs keep running. Press its key again to reconnect." ;;
            attached)
                _dash_status "$T_WARN" "${G_DOT} ${name} is still attached in another terminal (not taken over). Its programs keep running." ;;
            none)
                if (( DASH_RC == 130 )) && [[ "$before" == "none" ]]; then
                    _dash_status "$T_DIM" "${G_DIAM} ${name}: start cancelled (Ctrl+C)."
                else
                    _dash_status "$T_DIM" "${G_DIAM} ${name} session ended (exit). A new one starts the next time."
                fi ;;
            *)  _dash_status "$T_BAD" "${G_BAD} ${name}: could not read the session state (tmux error)." ;;
        esac
    else
        _dash_status "$T_BAD" "${G_BAD} ${name} failed (exit ${DASH_RC}). See '${cmd} --check' or 'urb sessions'."
    fi
    return 0
}

# Ejecuta una función de la CLI en una subshell (su `exec` reemplaza la subshell,
# no el dashboard). Los traps del dashboard no pasan a la subshell.
_dash_run_sub() {
    ( trap - EXIT INT QUIT TERM HUP TSTP WINCH; "$@" )
}

# --- NORMAL SHELL: Zsh real con la configuración del usuario --------------------
_dash_zsh_bin() {
    local p o="${URB_GOD_ZSH:-}"
    if [[ -n "$o" ]]; then
        [[ -x "$o" ]] && { printf '%s' "$o"; return 0; }
        p="$(command -v -- "$o" 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
        return 1
    fi
    p="$(command -v zsh 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
    return 1
}

# Zsh interactiva normal en el directorio actual. Si urb se abrió desde GOD/RED,
# se deshace lo que añaden esos perfiles (ZDOTDIR propio, URB_GOD, URB_PROFILE...)
# para que cargue la configuración de siempre del usuario. Tampoco hereda las
# opciones globales de urb (p. ej. --yes no debe afectar a la shell).
_dash_run_shell() {
    local z="$1" zd=""
    printf '%s%s Normal zsh (opened from URB) %s %s. Type %sexit%s to return to the dashboard.%s\n' \
        "$T_DIM" "$G_DIAM" "$G_SEP" "${PWD/#$HOME/\~}" "$T_KEY" "$T_DIM" "$C_RESET"
    (
        trap - EXIT INT QUIT TERM HUP TSTP WINCH
        if [[ -n "${URB_GOD:-}" ]]; then
            zd="${URB_USER_ZDOTDIR:-}"
            if [[ -n "$zd" && "$zd" != "$HOME" ]]; then export ZDOTDIR="$zd"; else unset ZDOTDIR; fi
        fi
        unset URB_GOD URB_GOD_DIR URB_GOD_GREETED URB_GOD_TERM URB_GOD_HUD_POSITION URB_USER_ZDOTDIR \
              URB_PROFILE URB_PROFILE_TAG URB_PROFILE_LABEL URB_PROFILE_THEME URB_PROFILE_HUD URB_PROFILE_CMD \
              URB_ASSUME_YES URB_ASCII URB_NO_ANIM URB_COLOR
        exec "$z" -i
    )
}

_dash_shell() {
    local z t0
    if ! z="$(_dash_zsh_bin)"; then
        _dash_status "$T_BAD" "${G_BAD} zsh is not installed (sudo apt install zsh). You are still in the dashboard."
        return 0
    fi
    t0=$SECONDS
    _dash_child 0 0 _dash_run_shell "$z"
    if (( DASH_RC != 0 && DASH_RC != 130 && SECONDS - t0 < 2 )); then
        # Terminó al instante con error: probablemente falló al arrancar
        _dash_status "$T_BAD" "${G_BAD} zsh exited right after starting (exit ${DASH_RC}). Check your ~/.zshrc (try: zsh -i -c true)."
    elif (( DASH_RC == 0 )); then
        _dash_status "$T_DIM" "${G_DIAM} Normal shell closed. Back in the dashboard."
    else
        _dash_status "$T_DIM" "${G_DIAM} Normal shell closed (last exit status ${DASH_RC}). Back in the dashboard."
    fi
}

# --- HELP -----------------------------------------------------------------------------
_dash_run_help() {
    if ! declare -F urb_help >/dev/null; then msg_err "Help is not available."; return 1; fi
    if has_cmd less; then
        ( trap - EXIT INT QUIT TERM HUP TSTP WINCH; urb_help | less -R )
    else
        urb_help
        ui_pause "Press any key to return to the URB dashboard${G_ELL}"
    fi
}

# --- SESSIONS: estado y reconexión (sin menús anidados de más de un nivel) --------
_dash_sessions() {
    local -a profs=() items=()
    local p st desc choice n
    while :; do
        mapfile -t profs < <(sess_profiles)
        items=()
        for p in "${profs[@]}"; do
            items+=("$(
                sess_load_profile "$p" >/dev/null 2>&1 || { printf '%s|invalid profile' "$p"; exit 0; }
                sess_query "$GOD_SOCKET" "$GOD_SESSION" 0 >/dev/null 2>&1
                case "$S_STATE" in
                    attached) printf '%s|attached (%s window(s)) in another terminal: Enter joins it' "$P_NAME" "$S_WINDOWS" ;;
                    detached) printf '%s|detached (%s window(s)): Enter reconnects' "$P_NAME" "$S_WINDOWS" ;;
                    error)    printf '%s|tmux error: %s' "$P_NAME" "$S_ERR" ;;
                    *)        printf '%s|no session' "$P_NAME" ;;
                esac
            )")
        done
        items+=("Full list|urb sessions: sockets, panes and clients" "Back|Return to the dashboard")
        n=${#profs[@]}
        ui_menu "SESSIONS" "Reconnect only: 'urb sessions kill <profile>' ends one" "${items[@]}" || break
        choice=$UI_CHOICE
        if (( choice < n )); then
            p="${profs[choice]}"
            st="$(_dash_session_state "$p")"
            if [[ "$st" == "attached" || "$st" == "detached" ]]; then
                _dash_tmux_profile "$p" attach
                return 0
            fi
            desc="${items[choice]#*|}"
            msg_info "${items[choice]%%|*}: ${desc}. Start it from the dashboard."
            ui_pause
        elif (( choice == n )); then
            sessions_list
            ui_pause
        else
            break
        fi
    done
    ui_resume
}

# --- Activar un elemento -------------------------------------------------------------
# Retorna 10 si el elemento es EXIT
_dash_activate() {
    local i=$1
    if ! dash_selectable "$i"; then
        _dash_status "$T_WARN" "${G_DIAM} ${DI_LABEL[i]}: coming soon, not available yet."
        return 0
    fi
    case "${DI_KIND[i]}" in
        env)
            if [[ "${DI_TARGET[i]}" == "zsh" ]]; then _dash_shell
            else _dash_tmux_profile "${DI_TARGET[i]}" start; fi ;;
        tool) _dash_status "" ""; _dash_launch "${DI_TARGET[i]}" ;;
        sys)
            case "${DI_TARGET[i]}" in
                exit)     return 10 ;;
                help)     _dash_child 0 0 _dash_run_help ;;
                sessions) ui_suspend; _dash_sessions ;;
            esac ;;
    esac
    return 0
}

# --- Bucle principal --------------------------------------------------------------
# dashboard_run ["mensaje de estado inicial" [color]]
dashboard_run() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        msg_err "The URB dashboard needs an interactive terminal."
        msg_dim "    Non-interactive alternatives: urb help | urb monitor --once | urb network"
        return 1
    fi
    local interval tick=0 last=0 now rc
    interval="$(cfg REFRESH_INTERVAL 2)"; is_uint "$interval" && (( interval >= 1 )) || interval=2

    _dash_parse
    DASH_SEL=0; DASH_OFF=0
    dash_selectable 0 || dash_move 0 1
    _dash_status "${2:-$T_WARN}" "${1:-}"

    ui_install_traps
    trap '_dash_cleanup' EXIT
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
        _dash_draw "$tick" "$DASH_SEL"
        ui_read_key 1
        rc=0
        case "$UI_KEY" in
            UP|k|K)   dash_move "$DASH_SEL" -1 ;;
            DOWN|j|J) dash_move "$DASH_SEL" 1 ;;
            $'\f')    _dash_collect; last=$SECONDS; UI_NEED_CLEAR=1 ;;
            q|Q|ESC|EOF) break ;;
            ENTER|RIGHT|l)
                _dash_activate "$DASH_SEL"; rc=$?
                (( rc == 10 )) && break
                _dash_collect; last=$SECONDS ;;
            TIMEOUT)  tick=$(( tick + 1 )) ;;
            *)
                if dash_key_index "$UI_KEY"; then
                    dash_selectable "$DASH_KIDX" && DASH_SEL=$DASH_KIDX
                    _dash_activate "$DASH_KIDX"; rc=$?
                    (( rc == 10 )) && break
                    _dash_collect; last=$SECONDS
                fi ;;
        esac
    done
    _dash_cleanup
    ui_remove_traps
    printf '%s%s URB Terminal closed. Stay ethical.%s\n' "$T_DIM" "$G_DIAM" "$C_RESET"
    return 0
}

_dash_cleanup() {
    ui_screen_leave
    return 0
}
