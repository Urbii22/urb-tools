#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/ui.sh — Motor de interfaz TUI de URB Terminal
#  - Tema de color y glifos (UTF-8 con alternativa ASCII)
#  - Pantalla alternativa, cursor y estado de la terminal (siempre restaurados)
#  - Búfer de dibujo por coordenadas (un solo printf por frame: sin parpadeo)
#  - Cajas, barras de progreso, logo, lectura de teclas y menús
# =============================================================================

[[ -n "${_URB_UI_LOADED:-}" ]] && return 0
_URB_UI_LOADED=1

UI_COLS=80
UI_ROWS=24
UI_BUF=""
UI_KEY=""
UI_CHOICE=0
UI_NEED_CLEAR=1
_UI_STTY=""
_UI_ACTIVE=0
_UI_RESIZED=0

# =============================================================================
#  Tema y glifos
# =============================================================================
ui_init_theme() {
    if urb_is_utf8; then
        G_TL='╭' G_TR='╮' G_BL='╰' G_BR='╯' G_H='─' G_V='│'
        G_FULL='█' G_EMPTY='░' G_ARROW='▶' G_DOT='●' G_RING='○' G_SEP='·'
        G_ELL='…' G_DIAM='◆' G_OK='✔' G_BAD='✘' G_UP='↑' G_DOWN='↓' G_ENTER='⏎'
        G_SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    else
        G_TL='+' G_TR='+' G_BL='+' G_BR='+' G_H='-' G_V='|'
        G_FULL='#' G_EMPTY='.' G_ARROW='>' G_DOT='*' G_RING='o' G_SEP='-'
        G_ELL='~' G_DIAM='*' G_OK='+' G_BAD='x' G_UP='^' G_DOWN='v' G_ENTER='RET'
        G_SPIN=('|' '/' '-' '\')
    fi

    if (( URB_COLOR_ON )) && (( URB_256 )); then
        T_BORDER=$'\e[38;5;31m'      # azul acero
        T_TITLE=$'\e[1;38;5;51m'     # cian brillante
        T_LABEL=$'\e[38;5;67m'       # azul grisáceo
        T_VALUE=$'\e[38;5;255m'      # blanco
        T_ACCENT=$'\e[38;5;48m'      # verde menta
        T_OK=$'\e[38;5;47m'
        T_WARN=$'\e[38;5;220m'
        T_BAD=$'\e[38;5;196m'
        T_DIM=$'\e[38;5;242m'
        T_DIMBAR=$'\e[38;5;238m'
        T_SEL=$'\e[1;38;5;16;48;5;44m'   # texto oscuro sobre cian
        T_KEY=$'\e[1;38;5;45m'
        UI_LOGO_COLORS=($'\e[1;38;5;51m' $'\e[1;38;5;45m' $'\e[1;38;5;39m' $'\e[1;38;5;33m' $'\e[1;38;5;27m' $'\e[1;38;5;21m')
    elif (( URB_COLOR_ON )); then
        T_BORDER=$C_BLUE T_TITLE="$C_BOLD$C_BCYAN" T_LABEL=$C_CYAN T_VALUE=$C_WHITE
        T_ACCENT=$C_BGREEN T_OK=$C_GREEN T_WARN=$C_YELLOW T_BAD=$C_RED T_DIM=$C_GRAY
        T_DIMBAR=$C_GRAY T_SEL=$'\e[1;30;46m' T_KEY="$C_BOLD$C_BCYAN"
        UI_LOGO_COLORS=("$C_BOLD$C_BCYAN" "$C_BOLD$C_BCYAN" "$C_BOLD$C_CYAN" "$C_BOLD$C_BBLUE" "$C_BOLD$C_BLUE" "$C_BOLD$C_BLUE")
    else
        T_BORDER="" T_TITLE="" T_LABEL="" T_VALUE="" T_ACCENT="" T_OK="" T_WARN=""
        T_BAD="" T_DIM="" T_DIMBAR="" T_SEL=$'\e[7m' T_KEY=""
        UI_LOGO_COLORS=("" "" "" "" "" "")
        # Sin color, el resaltado en vídeo inverso solo si es una terminal
        [[ -t 1 ]] || T_SEL=""
    fi
}

# =============================================================================
#  Logo URB
# =============================================================================
UI_LOGO=()
ui_load_logo() {
    local style font
    style="$(cfg LOGO_STYLE block)"
    font="$(cfg LOGO_FONT slant)"
    UI_LOGO=()
    if [[ "$style" == "figlet" ]] && has_cmd figlet && is_safe_name "$font"; then
        mapfile -t UI_LOGO < <(figlet -w 200 -f "$font" "URB" 2>/dev/null)
        # Quitar líneas vacías finales
        while (( ${#UI_LOGO[@]} > 0 )) && [[ -z "${UI_LOGO[-1]// /}" ]]; do unset 'UI_LOGO[-1]'; done
        (( ${#UI_LOGO[@]} > 0 )) && return 0
    fi
    if urb_is_utf8; then
        UI_LOGO=(
            '██╗   ██╗██████╗ ██████╗ '
            '██║   ██║██╔══██╗██╔══██╗'
            '██║   ██║██████╔╝██████╔╝'
            '██║   ██║██╔══██╗██╔══██╗'
            '╚██████╔╝██║  ██║██████╔╝'
            ' ╚═════╝ ╚═╝  ╚═╝╚═════╝ '
        )
    else
        UI_LOGO=(
            ' _   _ ____  ____  '
            '| | | |  _ \| __ ) '
            '| | | | |_) |  _ \ '
            '| |_| |  _ <| |_) |'
            ' \___/|_| \_\____/ '
            '                   '
        )
    fi
}

ui_logo_width() {
    local l w=0
    for l in "${UI_LOGO[@]}"; do (( ${#l} > w )) && w=${#l}; done
    printf '%s' "$w"
}

# Imprime el logo en modo CLI (help/version)
ui_print_logo() {
    local i
    (( ${#UI_LOGO[@]} )) || ui_load_logo
    for i in "${!UI_LOGO[@]}"; do
        printf '  %s%s%s\n' "${UI_LOGO_COLORS[i % 6]}" "${UI_LOGO[i]}" "$C_RESET"
    done
}

# =============================================================================
#  Texto
# =============================================================================
# ui_fit VAR "texto" ancho → recorta con … o rellena con espacios (texto plano)
# Nota: las funciones que escriben en una variable del llamador (local -n)
# usan locales con prefijo "__" para no colisionar con el nombre recibido.
ui_fit() {
    local -n __fit_out=$1
    local __fs="$2" __fw=$3 __fpad
    if (( __fw <= 0 )); then __fit_out=""; return 0; fi
    if (( ${#__fs} > __fw )); then
        if (( __fw > 1 )); then __fs="${__fs:0:__fw-1}${G_ELL}"; else __fs="${__fs:0:__fw}"; fi
    fi
    __fpad=$(( __fw - ${#__fs} ))
    printf -v __fit_out '%s%*s' "$__fs" "$__fpad" ''
}

# ui_repeat VAR carácter n
ui_repeat() {
    local -n __rep_out=$1
    local __rch="$2" __rn=$3 __rs
    (( __rn < 0 )) && __rn=0
    printf -v __rs '%*s' "$__rn" ''
    __rep_out="${__rs// /$__rch}"
}

# ui_bar VAR porcentaje ancho → barra coloreada (longitud visible = ancho)
ui_bar() {
    local -n __bar_out=$1
    local __bp=$2 __bw=$3 __bfill __bempty __bcol __bf __be
    is_uint "$__bp" || __bp=0
    (( __bp > 100 )) && __bp=100
    (( __bw < 1 )) && __bw=1
    __bfill=$(( (__bp * __bw + 50) / 100 ))
    __bempty=$(( __bw - __bfill ))
    if   (( __bp >= 85 )); then __bcol=$T_BAD
    elif (( __bp >= 60 )); then __bcol=$T_WARN
    else __bcol=$T_OK
    fi
    ui_repeat __bf "$G_FULL" "$__bfill"
    ui_repeat __be "$G_EMPTY" "$__bempty"
    __bar_out="${__bcol}${__bf}${C_RESET}${T_DIMBAR}${__be}${C_RESET}"
}

# Color según umbral (para porcentajes)
ui_pct_color() {
    local -n __pc_out=$1
    if   (( $2 >= 85 )); then __pc_out=$T_BAD
    elif (( $2 >= 60 )); then __pc_out=$T_WARN
    else __pc_out=$T_OK
    fi
}

# =============================================================================
#  Pantalla y terminal
# =============================================================================
ui_term_size() {
    local r="" c=""
    if [[ -t 1 ]] && read -r r c < <(stty size </dev/tty 2>/dev/null) && is_uint "$r" && is_uint "$c" && (( r > 0 && c > 0 )); then
        :
    else
        c="$(tput cols 2>/dev/null)"; r="$(tput lines 2>/dev/null)"
        is_uint "$c" || c=80
        is_uint "$r" || r=24
    fi
    if (( r != UI_ROWS || c != UI_COLS )); then UI_NEED_CLEAR=1; fi
    UI_ROWS=$r
    UI_COLS=$c
}

# Ciclo de vida de la TUI (un único punto de entrada y salida):
#   ui_screen_enter  pantalla alternativa + cursor oculto + sin eco
#   ui_screen_leave  deshace exactamente eso y restaura el stty original
# Ambas son idempotentes (llamarlas dos veces no hace nada) y seguras desde
# traps. El estado stty se guarda UNA vez por proceso (el de la shell que
# lanzó urb) y es el que se restaura siempre, aunque un programa hijo lo
# haya dejado alterado. URB no activa modos de ratón ni toca otros modos.
ui_screen_enter() {
    (( _UI_ACTIVE )) && return 0
    [[ -n "$_UI_STTY" ]] || _UI_STTY="$(stty -g </dev/tty 2>/dev/null || true)"
    stty -echo </dev/tty 2>/dev/null || true
    printf '\e[?1049h\e[?25l\e[2J\e[H'
    _UI_ACTIVE=1
    UI_NEED_CLEAR=1
}

ui_screen_leave() {
    (( _UI_ACTIVE )) || return 0
    _UI_ACTIVE=0
    printf '\e[0m\e[?25h\e[?1049l'
    ui_tty_restore
}

# Restaura el stty guardado al entrar (o uno razonable si no se pudo guardar)
ui_tty_restore() {
    if [[ -n "$_UI_STTY" ]]; then
        stty "$_UI_STTY" </dev/tty 2>/dev/null || stty sane </dev/tty 2>/dev/null || true
    else
        stty sane </dev/tty 2>/dev/null || true
    fi
}

# Tras un programa hijo que usa tmux (GOD/RED): tmux puede activar el ratón
# (GOD_MOUSE=1 o 'set mouse on') y, si su cliente muere sin limpiar, esos
# modos quedarían activos. Se desactivan solo los modos de informe de ratón
# (1000/1002/1003/1005/1006/1015); nada más (p. ej. no se toca el 1007).
ui_mouse_reset() { printf '\e[?1000l\e[?1002l\e[?1003l\e[?1005l\e[?1006l\e[?1015l'; }

# Descarta teclas pendientes (p. ej. pulsadas mientras volvía un hijo)
ui_drain_input() {
    local _k
    while IFS= read -rsn1 -t 0.01 _k </dev/tty 2>/dev/null; do :; done
    return 0
}

# Para ejecutar una tarea "normal" (con eco y cursor) dentro de la pantalla TUI
ui_suspend() {
    printf '\e[0m\e[2J\e[H\e[?25h'
    if [[ -n "$_UI_STTY" ]]; then stty "$_UI_STTY" </dev/tty 2>/dev/null || true; fi
}

ui_resume() {
    stty -echo </dev/tty 2>/dev/null || true
    printf '\e[?25l\e[2J\e[H'
    UI_NEED_CLEAR=1
}

# Traps: la terminal SIEMPRE se restaura al salir (normal, Ctrl+C, Ctrl+\, kill)
#  - QUIT (Ctrl+\) por defecto mataría el proceso SIN pasar por EXIT, dejando la
#    pantalla alternativa y el eco desactivado en la shell del usuario.
#  - TSTP (Ctrl+Z) por defecto detendría la TUI y devolvería la shell en la
#    pantalla alternativa: se ignora mientras la TUI está en primer plano.
#    Es un manejador (no un "ignorar" heredable): los procesos hijos reciben
#    las señales con su acción normal.
ui_install_traps() {
    trap 'ui_screen_leave' EXIT
    trap 'exit 130' INT
    trap 'exit 131' QUIT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    trap ':' TSTP
    trap '_UI_RESIZED=1' WINCH
}

ui_remove_traps() { trap - EXIT INT QUIT TERM HUP TSTP WINCH; }

# =============================================================================
#  Búfer de dibujo
# =============================================================================
ui_buf_begin() {
    if (( UI_NEED_CLEAR )); then UI_BUF=$'\e[0m\e[2J\e[H'; UI_NEED_CLEAR=0
    else UI_BUF=$'\e[0m\e[H'
    fi
}
ui_at()      { UI_BUF+=$'\e['"$1;$2"'H'"$3"; }
ui_flush()   { printf '%s' "$UI_BUF"; UI_BUF=""; }

# ui_box fila col ancho alto "TÍTULO" [color]
ui_box() {
    local r=$1 c=$2 w=$3 h=$4 title="${5:-}" col="${6:-$T_BORDER}"
    local inner=$(( w - 2 )) line blank i t rest
    (( w < 4 || h < 2 )) && return 0
    ui_repeat line "$G_H" "$inner"
    printf -v blank '%*s' "$inner" ''
    if [[ -n "$title" ]] && (( inner > 6 )); then
        t=" ${title} "
        (( ${#t} > inner - 2 )) && t="${t:0:inner-2}"
        rest=$(( inner - 1 - ${#t} ))
        ui_at "$r" "$c" "${col}${G_TL}${G_H}${C_RESET}${T_TITLE}${t}${C_RESET}${col}${line:0:rest}${G_TR}${C_RESET}"
    else
        ui_at "$r" "$c" "${col}${G_TL}${line}${G_TR}${C_RESET}"
    fi
    for (( i = 1; i < h - 1; i++ )); do
        ui_at $(( r + i )) "$c" "${col}${G_V}${C_RESET}${blank}${col}${G_V}${C_RESET}"
    done
    ui_at $(( r + h - 1 )) "$c" "${col}${G_BL}${line}${G_BR}${C_RESET}"
}

# ui_kv fila col ancho "Etiqueta" "valor" [color_valor] [ancho_etiqueta]
ui_kv() {
    local r=$1 c=$2 w=$3 label="$4" val="$5" vcol="${6:-$T_VALUE}" lw="${7:-10}" l v
    ui_fit l "$label" "$lw"
    ui_fit v "$val" $(( w - lw ))
    ui_at "$r" "$c" "${T_LABEL}${l}${C_RESET}${vcol}${v}${C_RESET}"
}

# =============================================================================
#  Teclado
# =============================================================================
# ui_read_key [timeout] → UI_KEY = UP DOWN LEFT RIGHT ENTER ESC BACKSPACE TIMEOUT EOF o el carácter
ui_read_key() {
    local t="${1:-}" k="" rest="" junk rc
    UI_KEY=""
    if [[ -n "$t" ]]; then
        IFS= read -rsn1 -t "$t" k </dev/tty; rc=$?
    else
        IFS= read -rsn1 k </dev/tty; rc=$?
    fi
    if (( rc > 128 )); then UI_KEY="TIMEOUT"; return 0; fi
    if (( rc != 0 )); then UI_KEY="EOF"; return 0; fi
    case "$k" in
        $'\e')
            IFS= read -rsn2 -t 0.02 rest </dev/tty || true
            case "$rest" in
                '[A'|'OA') UI_KEY="UP" ;;
                '[B'|'OB') UI_KEY="DOWN" ;;
                '[C'|'OC') UI_KEY="RIGHT" ;;
                '[D'|'OD') UI_KEY="LEFT" ;;
                '')        UI_KEY="ESC" ;;
                *)         UI_KEY="OTHER"
                           # Consumir el resto de secuencias largas (PgUp, F1...)
                           while IFS= read -rsn1 -t 0.005 junk </dev/tty; do :; done ;;
            esac
            ;;
        ''|$'\n'|$'\r') UI_KEY="ENTER" ;;
        $'\x7f'|$'\b')  UI_KEY="BACKSPACE" ;;
        *)              UI_KEY="$k" ;;
    esac
    return 0
}

ui_pause() {
    local msg="${1:-Press any key to return${G_ELL}}"
    [[ -t 0 ]] || return 0
    printf '\n%s %s %s' "$T_DIM" "$msg" "$C_RESET"
    IFS= read -rsn1 _ </dev/tty || true
    # Descarta secuencias de escape pendientes (flechas)
    while IFS= read -rsn1 -t 0.01 _ </dev/tty; do :; done
    printf '\n'
}

# ui_prompt VAR "Etiqueta" [defecto] → entrada con edición readline
ui_prompt() {
    local -n __pr_out=$1
    local __pdef="${3:-}" __pans=""
    local __pp="${T_KEY}${G_ARROW}${C_RESET} ${2}"
    [[ -n "$__pdef" ]] && __pp+=" ${T_DIM}[${__pdef}]${C_RESET}"
    __pp+=": "
    printf '%s' "$__pp"
    IFS= read -re __pans </dev/tty || { __pr_out=""; return 1; }
    [[ -z "$__pans" ]] && __pans="$__pdef"
    __pr_out="$__pans"
}

# =============================================================================
#  Menú interactivo genérico (usado por los módulos)
#  ui_menu "TÍTULO" "subtítulo" "LABEL|Descripción" ...
#  → UI_CHOICE (índice 0..n-1). Retorna 1 si se cancela (q / Esc / ←).
# =============================================================================
ui_menu() {
    local title="$1" sub="$2"; shift 2
    local -a items=("$@")
    local n=${#items[@]} sel=0
    (( n == 0 )) && return 1

    if [[ "$(cfg MENU_ENGINE builtin)" == "fzf" ]] && has_cmd fzf; then
        _ui_menu_fzf "$title" "$sub" "${items[@]}"
        return $?
    fi

    if [[ ! -t 0 || ! -t 1 ]]; then msg_err "Interactive menu needs a terminal."; return 1; fi
    UI_NEED_CLEAR=1
    stty -echo </dev/tty 2>/dev/null || true
    printf '\e[?25l'
    local rc=1
    while :; do
        ui_term_size
        _ui_menu_draw "$title" "$sub" "$sel" "${items[@]}"
        ui_read_key 1
        case "$UI_KEY" in
            UP|k|K)        sel=$(( (sel - 1 + n) % n )) ;;
            DOWN|j|J)      sel=$(( (sel + 1) % n )) ;;
            ENTER|RIGHT|l) UI_CHOICE=$sel; rc=0; break ;;
            q|Q|ESC|LEFT|h|BACKSPACE|EOF) rc=1; break ;;
            [1-9])
                if (( UI_KEY <= n )); then UI_CHOICE=$(( UI_KEY - 1 )); rc=0; break; fi ;;
            *) : ;;
        esac
    done
    # Volver a modo "texto" para que el módulo pueda imprimir y pedir datos
    printf '\e[0m\e[2J\e[H\e[?25h'
    if [[ -n "$_UI_STTY" ]]; then stty "$_UI_STTY" </dev/tty 2>/dev/null || true
    else stty echo </dev/tty 2>/dev/null || true
    fi
    return "$rc"
}

_ui_menu_draw() {
    local title="$1" sub="$2" sel="$3"; shift 3
    local -a items=("$@")
    local n=${#items[@]} i w h r0 c0 inner label desc txt line maxl=0 lw
    for i in "${items[@]}"; do label="${i%%|*}"; (( ${#label} > maxl )) && maxl=${#label}; done
    lw=$(( maxl + 2 ))
    w=$(( UI_COLS - 4 )); (( w > 76 )) && w=76
    h=$(( n + 4 ))
    ui_buf_begin
    if (( UI_COLS < 40 || UI_ROWS < h + 2 )); then
        ui_at 1 1 "${T_WARN}Terminal too small (${UI_COLS}x${UI_ROWS}). Resize or press q.${C_RESET}"
        ui_flush; return 0
    fi
    r0=$(( (UI_ROWS - h - 2) / 2 + 1 )); (( r0 < 1 )) && r0=1
    c0=$(( (UI_COLS - w) / 2 + 1 ))
    inner=$(( w - 4 ))
    # Encabezado: URB ▸ TÍTULO
    ui_fit line "${G_DIAM} URB ${G_ARROW} ${title}" "$w"
    ui_at "$r0" "$c0" "${T_TITLE}${line}${C_RESET}"
    ui_box $(( r0 + 1 )) "$c0" "$w" "$h" "$sub"
    for (( i = 0; i < n; i++ )); do
        label="${items[i]%%|*}"
        desc="${items[i]#*|}"
        [[ "$desc" == "${items[i]}" ]] && desc=""
        ui_fit txt "$label" "$lw"
        ui_fit line " [$(( i + 1 ))] ${txt}${desc}" $(( inner - 2 ))
        if (( i == sel )); then
            ui_at $(( r0 + 3 + i )) $(( c0 + 2 )) "${T_SEL}${G_ARROW}${line} ${C_RESET}"
        else
            ui_at $(( r0 + 3 + i )) $(( c0 + 2 )) " ${T_KEY}${line:0:4}${C_RESET}${T_VALUE}${line:4}${C_RESET} "
        fi
    done
    ui_fit line "${G_UP}${G_DOWN} move  ${G_ENTER} select  1-${n} jump  q/Esc back" "$w"
    ui_at $(( r0 + h + 1 )) "$c0" "${T_DIM}${line}${C_RESET}"
    ui_flush
}

_ui_menu_fzf() {
    local title="$1" sub="$2"; shift 2
    local i out idx
    out="$(
        idx=0
        for i in "$@"; do
            printf '%d\t%-12s %s\n' "$idx" "${i%%|*}" "${i#*|}"
            idx=$(( idx + 1 ))
        done | fzf --height=60% --layout=reverse --border=rounded --ansi \
                   --delimiter=$'\t' --with-nth=2.. --no-multi \
                   --prompt="URB ▸ ${title} ▸ " --header="${sub}" \
                   --color='fg:252,hl:51,fg+:16,bg+:44,hl+:16,border:31,prompt:51,pointer:48,header:67' \
                   2>/dev/tty
    )" || return 1
    UI_CHOICE="${out%%$'\t'*}"
    is_uint "$UI_CHOICE" || return 1
    UI_NEED_CLEAR=1
    return 0
}

# Spinner para tareas en segundo plano (texto real, sin porcentajes inventados)
# ui_spinner_frame i → imprime el glifo
ui_spinner_frame() { printf '%s' "${G_SPIN[$1 % ${#G_SPIN[@]}]}"; }
