#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/sessions.sh — urb sessions: gestor de sesiones GOD / RED / BLUE
#
#  - Consultar nunca crea sesiones ni arranca servidores tmux.
#  - Cada perfil tiene su propio socket: actuar sobre uno no afecta a otro.
#  - attach solo reconecta (no crea); kill pide confirmación siempre salvo --yes.
#  Usa godmode/session.sh (perfiles y consultas compartidas).
# =============================================================================

[[ -n "${_URB_SESSIONS_LOADED:-}" ]] && return 0
_URB_SESSIONS_LOADED=1

sessions_help() {
    cat <<EOF
${C_BOLD}urb sessions${C_RESET} — URB session manager (GOD, RED, BLUE)

${C_BOLD}USAGE${C_RESET}
  urb sessions                                      List sessions and their names
  urb sessions info <profile> [session]             Show windows, panes and clients
  urb sessions attach <profile> [session] [--no-anim] Reconnect to a running session
  urb sessions kill <profile> [session] [--yes]      End a session (always asks unless --yes)
  urb sessions menu                                 Interactive menu: enter, switch, open or close
                                                    (inside GOD/RED/BLUE: Ctrl+B s or 'sessions')

  Profiles: $(sess_profiles | paste -sd' ')
  When a profile has multiple sessions, specify the session name from the list.

${C_BOLD}STATES${C_RESET}
  attached   running, with a terminal connected
  detached   running in the background (programs keep running)
  none       no session
  error      tmux could not be queried (message shown)

Querying never creates sessions. Each profile uses its own tmux socket, so
commands on one profile never affect another or your own tmux sessions.
EOF
}

_sess_state_color() {
    case "$1" in
        attached) printf '%s' "$T_OK" ;;
        detached) printf '%s' "$T_WARN" ;;
        error)    printf '%s' "$T_BAD" ;;
        *)        printf '%s' "$T_DIM" ;;
    esac
}

# Valida y carga el perfil pedido (god|red|...)
_sess_profile() {
    local p="${1:-}"
    [[ -n "$p" ]] || { msg_err "Missing profile. Available: $(sess_profiles | tr '\n' ' ')"; return 2; }
    if ! sess_profiles | grep -qx -- "$p"; then
        msg_err "Unknown profile: '${p}'. Available: $(sess_profiles | tr '\n' ' ')"
        return 2
    fi
    sess_load_profile "$p" || return 2
}

sessions_list() {
    local only="${1:-}" p row rc=0 err=()
    msg_section "URB SESSIONS"
    printf '  %s%-8s %-10s %7s %6s %8s  %-18s %s%s\n' "$C_BOLD" "PROFILE" "STATE" "WINDOWS" "PANES" "CLIENTS" "SESSION" "SOCKET" "$C_RESET"
    while IFS= read -r p; do
        [[ -z "$only" || "$only" == "$p" ]] || continue
        sess_load_profile "$p" 2>/dev/null || continue
        if ! sess_snapshot; then
            err+=("${p}: ${S_ERR}"); rc=1
            _sessions_list_row "$p" error - - - -
        elif (( ${#S_ROWS[@]} == 0 )); then
            _sessions_list_row "$p" none - - - -
        else
            for row in "${S_ROWS[@]}"; do
                sess_read_row "$row" 1
                _sessions_list_row "$p" "$S_STATE" "$S_WINDOWS" "$S_PANES" "$S_CLIENTS" "$S_NAME"
            done
        fi
    done < <(sess_profiles)
    local e; for e in "${err[@]}"; do msg_err "$e"; done
    msg_dim "  urb sessions info|attach|kill <profile> [session]"
    return "$rc"
}

_sessions_list_row() {
    printf '  %s%-8s%s %s%-10s%s %7s %6s %8s  %-18s %s%s%s\n' \
        "$T_KEY" "$1" "$C_RESET" "$(_sess_state_color "$2")" "$2" "$C_RESET" \
        "$3" "$4" "$5" "$6" "$T_DIM" "$GOD_SOCKET" "$C_RESET"
}

sessions_info() {
    _sess_profile "${1:-}" || return $?
    local bin
    sess_query "${2:-}" 1
    case "$S_STATE" in
        error)    msg_err "tmux: ${S_ERR}"; return 1 ;;
        multiple) sess_choice_error; return 2 ;;
        none)
            if [[ -n "${2:-}" ]]; then msg_err "Session '$2' is not running."; return 1; fi
            msg_dim "  No session. Start one with: ${P_CMD}"; return 0 ;;
    esac
    msg_section "SESSION ${G_SEP} ${P_NAME}"
    printf '  %s%-9s%s %s%s%s\n' "$T_LABEL" "State" "$C_RESET" "$(_sess_state_color "$S_STATE")" "$S_STATE" "$C_RESET"
    printf '  %s%-9s%s %s (session "%s")\n' "$T_LABEL" "Socket" "$C_RESET" "$(sess_socket_path "$GOD_SOCKET")" "$S_NAME"
    printf '  %s%-9s%s %s\n' "$T_LABEL" "Created" "$C_RESET" "$(printf '%(%Y-%m-%d %H:%M:%S)T' "$S_CREATED")"
    printf '  %s%-9s%s %s window(s), %s pane(s), %s client(s)\n' "$T_LABEL" "Size" "$C_RESET" "$S_WINDOWS" "$S_PANES" "$S_CLIENTS"
    bin="$(sess_tmux_bin)" || return 1
    msg_section "PANES"
    "$bin" -L "$GOD_SOCKET" list-panes -s -t "=${S_NAME}" \
        -F '  #{window_index}.#{pane_index}  #{?pane_active,*, } #{pane_current_command}  #{pane_current_path}' 2>&1
    if (( S_CLIENTS > 0 )); then
        msg_section "CLIENTS"
        "$bin" -L "$GOD_SOCKET" list-clients -t "=${S_NAME}" -F '  #{client_tty}  #{client_width}x#{client_height}' 2>&1
    fi
    printf '\n'
    msg_dim "  urb sessions attach ${P_PROFILE} ${S_NAME} · urb sessions kill ${P_PROFILE} ${S_NAME}"
    return 0
}

sessions_attach() {
    local p="${1:-}"; shift || true
    _sess_profile "$p" || return $?
    local name="" extra=()
    while (( $# > 0 )); do
        case "$1" in
            --no-anim) extra+=(--no-anim) ;;
            -*) msg_err "Unknown option: $1"; return 2 ;;
            *) [[ -z "$name" ]] || { msg_err "Only one session at a time."; return 2; }; name="$1" ;;
        esac
        shift
    done
    [[ -n "$name" ]] && extra+=(--session-name "$name")
    local god="${URB_HOME}/godmode/god.sh"
    [[ -f "$god" ]] || { msg_err "God Mode files not found (${god})."; return 1; }
    URB_COLOR="${color_mode:-${URB_COLOR:-auto}}" exec bash "$god" --profile "$P_PROFILE" --attach-only "${extra[@]}"
}

sessions_kill() {
    local p="" name="" yes=0
    while (( $# > 0 )); do
        case "$1" in
            -y|--yes) yes=1 ;;
            -*) msg_err "Unknown option: $1"; return 2 ;;
            *)  if [[ -z "$p" ]]; then p="$1"
                elif [[ -z "$name" ]]; then name="$1"
                else msg_err "Only one session at a time."; return 2; fi ;;
        esac
        shift
    done
    _sess_profile "$p" || return $?
    sessions_end "$name" "$yes" 1
}

sessions_end() {
    local name="$1" yes="$2" always_confirm="$3" bin busy
    sess_query "$name" 1
    case "$S_STATE" in
        error)    msg_err "tmux: ${S_ERR}"; return 1 ;;
        multiple) sess_choice_error; return 2 ;;
        none)
            if [[ -n "$name" ]]; then msg_err "Session '$name' is not running."; return 1; fi
            msg_info "No ${P_NAME} session running. Nothing to do."; return 0 ;;
    esac
    bin="$(sess_tmux_bin)" || return 1
    busy="$("$bin" -L "$GOD_SOCKET" list-panes -s -t "=${S_NAME}" -F '#{pane_current_command}' 2>/dev/null \
            | grep -v -x -E 'zsh|bash|sh|-zsh|-bash' | sort -u | tr '\n' ' ')"
    msg_warn "This ends the ${P_NAME} session '${S_NAME}' (${S_STATE}, ${S_WINDOWS} window(s), ${S_PANES} pane(s))."
    [[ -n "$busy" ]] && msg_warn "Programs still running in '${S_NAME}': ${busy}"
    if (( ! yes )) && { (( always_confirm )) || [[ -n "$busy" ]]; }; then
        confirm "End session '${S_NAME}'?" n || { msg_info "Cancelled."; return 1; }
    fi
    if "$bin" -L "$GOD_SOCKET" kill-session -t "=${S_NAME}" 2>/dev/null; then
        msg_ok "${P_NAME} session ended."
        return 0
    fi
    msg_err "Could not end the ${P_NAME} session."
    return 1
}

# =============================================================================
#  Menú de sesiones: árbol plegable por perfil
#  urb sessions menu · Ctrl+B s y 'sessions' dentro de GOD/RED/BLUE · S del dashboard
#  Enter entra o cambia · n abre una nueva · x cierra · ←/→ pliega · q sale
# =============================================================================
declare -gA SMP_TAG=() SMP_LONG=() SMP_COL=() SMP_SELC=() SMP_SOCK=() SMP_ERR=() SMP_N=() SM_FOLD=()
SMP=() SMS_P=() SMS_N=() SMS_ST=() SMS_W=() SMS_PATH=() SMS_ACT=()
SM_ROW_T=() SM_ROW_I=()
SM_SEL=0 SM_NOW=0 SM_MSG="" SM_SUB=""
SM_CUR_SOCK="" SM_CUR_SESS=""
SM_ACT="quit" SM_P="" SM_N=""

_sm_glyphs() {
    if urb_is_utf8; then SG_OPEN='▾' SG_CLOSED='▸' SG_LR='←→'
    else SG_OPEN='v' SG_CLOSED='>' SG_LR='<>'
    fi
}

# Color del perfil (URB_C_PRIMARY de su tema): texto y fondo de selección
_sm_profile_color() {
    local p="$1" theme="$2" f n="" line
    for f in "${SESS_GOD_DIR}/themes/urb.theme" "${SESS_GOD_DIR}/themes/${theme}.theme"; do
        [[ -r "$f" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            [[ "$line" =~ ^URB_C_PRIMARY=([0-9]{1,3})$ ]] && n="${BASH_REMATCH[1]}"
        done <"$f"
    done
    if (( URB_COLOR_ON && URB_256 )) && [[ -n "$n" ]]; then
        SMP_COL[$p]=$'\e[38;5;'"$n"'m'
        SMP_SELC[$p]=$'\e[1;38;5;16;48;5;'"$n"'m'
    elif (( URB_COLOR_ON )); then
        case "$p" in god) n=3 ;; red) n=1 ;; blue) n=4 ;; *) n=6 ;; esac
        SMP_COL[$p]=$'\e[9'"$n"'m'
        SMP_SELC[$p]=$'\e[1;30;4'"$n"'m'
    else
        SMP_COL[$p]="" SMP_SELC[$p]="$T_SEL"
    fi
}

# Una consulta por perfil (solo lectura)
_sm_collect() {
    local p row
    SMP=() SMS_P=() SMS_N=() SMS_ST=() SMS_W=() SMS_PATH=() SMS_ACT=()
    printf -v SM_NOW '%(%s)T' -1
    while IFS= read -r p; do
        sess_load_profile "$p" >/dev/null 2>&1 || continue
        SMP+=("$p")
        SMP_TAG[$p]="$P_TAG" SMP_LONG[$p]="$P_NAME" SMP_SOCK[$p]="$GOD_SOCKET"
        SMP_ERR[$p]="" SMP_N[$p]=0
        _sm_profile_color "$p" "$P_THEME"
        if ! sess_snapshot; then SMP_ERR[$p]="${S_ERR:-tmux error}"; continue; fi
        SMP_N[$p]=${#S_ROWS[@]}
        for row in "${S_ROWS[@]}"; do
            sess_read_row "$row"
            SMS_P+=("$p") SMS_N+=("$S_NAME") SMS_ST+=("$S_STATE") SMS_W+=("$S_WINDOWS")
            SMS_PATH+=("${S_PATH:-}") SMS_ACT+=("${S_ACTIVITY:-$S_CREATED}")
        done
    done < <(sess_profiles)
}

_sm_rows() {
    local p i
    SM_ROW_T=() SM_ROW_I=()
    for p in "${SMP[@]}"; do
        SM_ROW_T+=(P) SM_ROW_I+=("$p")
        [[ "${SM_FOLD[$p]:-0}" == 1 ]] && continue
        for i in "${!SMS_P[@]}"; do
            if [[ "${SMS_P[i]}" == "$p" ]]; then SM_ROW_T+=(S) SM_ROW_I+=("$i"); fi
        done
    done
}

# _sm_key VAR fila → "P:perfil" o "S:perfil:sesión"
_sm_key() {
    local -n __k=$1
    local r=$2 i
    __k=""
    (( r < ${#SM_ROW_T[@]} )) || return 0
    if [[ "${SM_ROW_T[r]}" == P ]]; then __k="P:${SM_ROW_I[r]}"
    else i=${SM_ROW_I[r]}; __k="S:${SMS_P[i]}:${SMS_N[i]}"
    fi
}

_sm_select() {
    local want="$1" r k
    for r in "${!SM_ROW_T[@]}"; do
        _sm_key k "$r"
        [[ "$k" == "$want" ]] && { SM_SEL=$r; return 0; }
    done
    return 1
}

# Recarga (opcional) y reconstruye las filas conservando la selección
_sm_reload() {
    local collect="$1" want p
    _sm_key want "$SM_SEL"
    (( collect )) && _sm_collect
    _sm_rows
    if ! _sm_select "$want"; then
        p="${want#?:}"; p="${p%%:*}"
        _sm_select "P:$p" || SM_SEL=0
    fi
    (( SM_SEL < ${#SM_ROW_T[@]} )) || SM_SEL=0
}

_sm_is_current() {
    [[ -n "$SM_CUR_SESS" && "${SMP_SOCK[${SMS_P[$1]}]}" == "$SM_CUR_SOCK" && "${SMS_N[$1]}" == "$SM_CUR_SESS" ]]
}

_sm_age() {
    local -n __a=$1
    local s=$(( SM_NOW - ${2:-0} ))
    (( s < 0 )) && s=0
    if   (( s < 60 ));    then __a="${s}s"
    elif (( s < 3600 ));  then __a="$(( s / 60 ))m"
    elif (( s < 86400 )); then __a="$(( s / 3600 ))h"
    else __a="$(( s / 86400 ))d"
    fi
}

_sm_draw() {
    local msg="$1" n=${#SM_ROW_T[@]} w h r0 c0 inner visible first=0 k row line txt p i col st age path fold
    w=$(( UI_COLS - 2 )); (( w > 100 )) && w=100
    # Si cambia el número de filas, la caja centrada se mueve: borrar el marco anterior
    visible=$(( UI_ROWS - 6 )); (( visible > n )) && visible=$n
    (( n != ${SM_LAST_N:--1} )) && UI_NEED_CLEAR=1
    SM_LAST_N=$n
    ui_buf_begin
    if (( UI_COLS < 40 || UI_ROWS < 8 )); then
        ui_at 1 1 "${T_WARN}Terminal too small (${UI_COLS}x${UI_ROWS}). Resize or press q.${C_RESET}"
        ui_flush; return 0
    fi
    (( SM_SEL >= visible )) && first=$(( SM_SEL - visible + 1 ))
    h=$(( visible + 4 ))
    r0=$(( (UI_ROWS - h - 2) / 2 + 1 )); (( r0 < 1 )) && r0=1
    c0=$(( (UI_COLS - w) / 2 + 1 ))
    inner=$(( w - 4 ))
    ui_fit line "${G_DIAM} URB ${G_ARROW} SESSIONS" "$w"
    ui_at "$r0" "$c0" "${T_TITLE}${line}${C_RESET}"
    ui_box $(( r0 + 1 )) "$c0" "$w" "$h" "$SM_SUB"
    for (( k = first; k < first + visible; k++ )); do
        row=$(( r0 + 3 + k - first ))
        if [[ "${SM_ROW_T[k]}" == P ]]; then
            p="${SM_ROW_I[k]}"; col="${SMP_COL[$p]}"
            if [[ "${SM_FOLD[$p]:-0}" == 1 ]]; then fold="$SG_CLOSED"; else fold="$SG_OPEN"; fi
            if [[ -n "${SMP_ERR[$p]}" ]]; then
                txt="${fold} ${SMP_TAG[$p]}  ${SMP_LONG[$p]} ${G_SEP} tmux error: ${SMP_ERR[$p]}"
            else
                txt="${fold} ${SMP_TAG[$p]} (${SMP_N[$p]})  ${SMP_LONG[$p]}"
                (( SMP_N[$p] == 0 )) && txt+=" ${G_SEP} no sessions, n opens one"
            fi
            ui_fit line " ${txt}" "$inner"
            if (( k == SM_SEL )); then ui_at "$row" $(( c0 + 2 )) "${SMP_SELC[$p]}${line}${C_RESET}"
            else ui_at "$row" $(( c0 + 2 )) "${C_BOLD}${col}${line}${C_RESET}"
            fi
        else
            i="${SM_ROW_I[k]}"; p="${SMS_P[i]}"; col="${SMP_COL[$p]}"
            _sm_age age "${SMS_ACT[i]}"
            path="${SMS_PATH[i]}"
            [[ -n "${HOME:-}" && "$path" == "$HOME"* ]] && path="~${path#"$HOME"}"
            st="${SMS_ST[i]}"; _sm_is_current "$i" && st="current"
            printf -v txt '   %s %-20s %-9s %3sw %5s  %s' "$G_DOT" "${SMS_N[i]}" "$st" "${SMS_W[i]}" "$age" "$path"
            ui_fit line "$txt" "$inner"
            if (( k == SM_SEL )); then
                ui_at "$row" $(( c0 + 2 )) "${SMP_SELC[$p]}${line}${C_RESET}"
            else
                case "$st" in current) st="$T_ACCENT" ;; attached) st="$T_OK" ;; *) st="$T_VALUE" ;; esac
                ui_at "$row" $(( c0 + 2 )) "${col}${line:0:26}${C_RESET}${st}${line:26}${C_RESET}"
            fi
        fi
    done
    if [[ -n "$msg" ]]; then
        ui_fit line "$msg" "$w"
        ui_at $(( r0 + h + 1 )) "$c0" "${T_WARN}${line}${C_RESET}"
    else
        ui_fit line "${G_UP}${G_DOWN} move  ${G_ENTER} enter  ${SG_LR} fold  n new  x close  r refresh  q quit" "$w"
        ui_at $(( r0 + h + 1 )) "$c0" "${T_DIM}${line}${C_RESET}"
    fi
    ui_flush
}

# Cierra la sesión i tras confirmar (y/N) en la barra inferior
_sm_kill() {
    local i=$1 p name sock bin busy q
    p="${SMS_P[i]}" name="${SMS_N[i]}"
    sock="${SMP_SOCK[$p]}"
    bin="$(sess_tmux_bin)" || { SM_MSG="tmux is not installed."; return 1; }
    busy="$("$bin" -L "$sock" list-panes -s -t "=${name}" -F '#{pane_current_command}' 2>/dev/null \
            | grep -v -x -E 'zsh|bash|sh|-zsh|-bash' | sort -u | tr '\n' ' ')"
    q="Close ${SMP_TAG[$p]} session ${name}?"
    _sm_is_current "$i" && q+=" You are in it."
    [[ -n "$busy" ]] && q+=" Running: ${busy% }."
    ui_term_size
    _sm_draw "${q}  [y/N]"
    ui_read_key
    if [[ "$UI_KEY" != y && "$UI_KEY" != Y ]]; then SM_MSG="Cancelled."; return 1; fi
    if "$bin" -L "$sock" kill-session -t "=${name}" 2>/dev/null; then SM_MSG="${name} closed."; return 0; fi
    SM_MSG="Could not close ${name}."
    return 1
}

# Bucle del menú → SM_ACT (attach|new|quit), SM_P, SM_N. Cerrar se resuelve aquí.
_sm_run() {
    local n i p want="" msg
    SM_ACT="quit" SM_P="" SM_N="" SM_MSG="" SM_SEL=0
    _sm_glyphs
    _sm_collect
    _sm_rows
    for i in "${!SMS_P[@]}"; do
        if _sm_is_current "$i"; then want="S:${SMS_P[i]}:${SMS_N[i]}"; break; fi
        [[ -z "$want" ]] && want="S:${SMS_P[i]}:${SMS_N[i]}"
    done
    [[ -n "$want" ]] && _sm_select "$want"
    if [[ -n "$SM_CUR_SESS" ]]; then SM_SUB="In ${SM_CUR_SESS}"; else SM_SUB="Open, switch or close sessions"; fi
    UI_NEED_CLEAR=1
    stty -echo </dev/tty 2>/dev/null || true
    printf '\e[?25l'
    while :; do
        ui_term_size
        msg="$SM_MSG"; SM_MSG=""
        _sm_draw "$msg"
        ui_read_key 2
        n=${#SM_ROW_T[@]}
        (( n > 0 )) || n=1
        i="${SM_ROW_I[SM_SEL]:-}"
        case "${SM_ROW_T[SM_SEL]:-}" in P) p="$i" ;; S) p="${SMS_P[i]}" ;; *) p="" ;; esac
        case "$UI_KEY" in
            TIMEOUT|r|R) _sm_reload 1 ;;
            UP|k|K)      SM_SEL=$(( (SM_SEL - 1 + n) % n )) ;;
            DOWN|j|J)    SM_SEL=$(( (SM_SEL + 1) % n )) ;;
            RIGHT|l|L)   if [[ -n "$p" ]]; then SM_FOLD[$p]=0; _sm_reload 0; fi ;;
            LEFT|h|H)    if [[ -n "$p" ]]; then SM_FOLD[$p]=1; _sm_rows; _sm_select "P:$p"; fi ;;
            ENTER)
                if [[ "${SM_ROW_T[SM_SEL]:-}" == S ]]; then
                    SM_ACT="attach" SM_P="$p" SM_N="${SMS_N[i]}"; break
                elif [[ -n "$p" && -z "${SMP_ERR[$p]}" ]] && (( SMP_N[$p] == 0 )); then
                    SM_ACT="new" SM_P="$p"; break
                elif [[ -n "$p" ]]; then
                    if [[ "${SM_FOLD[$p]:-0}" == 1 ]]; then SM_FOLD[$p]=0; else SM_FOLD[$p]=1; fi
                    _sm_reload 0
                fi ;;
            n|N) if [[ -n "$p" ]]; then SM_ACT="new" SM_P="$p"; break; fi ;;
            x|X)
                if [[ "${SM_ROW_T[SM_SEL]:-}" == S ]]; then _sm_kill "$i"; _sm_reload 1
                else SM_MSG="Select a session to close it."
                fi ;;
            q|Q|ESC|EOF) break ;;
            *) : ;;
        esac
    done
    printf '\e[0m\e[2J\e[H\e[?25h'
    if [[ -n "$_UI_STTY" ]]; then stty "$_UI_STTY" </dev/tty 2>/dev/null || true
    else stty echo </dev/tty 2>/dev/null || true
    fi
    return 0
}

# urb sessions menu [--client C] [--current SESIÓN] [--cwd DIR] [--socket RUTA]
# Dentro de una sesión URB cambia sin salir: switch-client en el mismo perfil;
# a otro perfil, el cliente se desconecta y entra en la otra sesión (sigue viva).
sessions_menu() {
    local client="" current="" cwd="$PWD" sockpath="" bin p q cmd urb
    while (( $# > 0 )); do
        case "$1" in
            --client|--current|--cwd|--socket)
                [[ $# -ge 2 ]] || { msg_err "$1 needs a value"; return 2; }
                case "$1" in
                    --client)  client="$2" ;;
                    --current) current="$2" ;;
                    --cwd)     cwd="$2" ;;
                    --socket)  sockpath="$2" ;;
                esac
                shift ;;
            *) msg_err "Unknown option: $1"; msg_dim "    Usage: urb sessions menu"; return 2 ;;
        esac
        shift
    done
    if [[ ! -t 0 || ! -t 1 ]]; then msg_err "The sessions menu needs an interactive terminal."; return 1; fi
    bin="$(sess_tmux_bin)" || { msg_err "tmux is not installed."; return 1; }

    # ¿Dentro de una sesión URB? Solo cuenta el socket de un perfil URB.
    SM_CUR_SOCK="" SM_CUR_SESS=""
    [[ -z "$sockpath" && -n "${TMUX:-}" ]] && sockpath="${TMUX%%,*}"
    if [[ -n "$sockpath" ]]; then
        while IFS= read -r p; do
            q="$(sess_load_profile "$p" >/dev/null 2>&1 && printf '%s' "$GOD_SOCKET")"
            [[ -n "$q" && "${sockpath##*/}" == "$q" ]] && SM_CUR_SOCK="$q"
        done < <(sess_profiles)
    fi
    if [[ -n "$SM_CUR_SOCK" ]]; then
        [[ -n "$current" ]] || current="$("$bin" -S "$sockpath" display-message -p '#{session_name}' 2>/dev/null)"
        SM_CUR_SESS="$current"
    fi

    _sm_run
    [[ "$SM_ACT" == quit ]] && return 0
    urb="${URB_HOME}/bin/urb"

    if [[ -z "$SM_CUR_SOCK" ]]; then
        case "$SM_ACT" in
            attach) sessions_attach "$SM_P" "$SM_N" ;;
            new)    URB_COLOR="${color_mode:-${URB_COLOR:-auto}}" exec "$urb" "$SM_P" ;;
        esac
        return $?
    fi

    if [[ "$SM_ACT" == attach && "${SMP_SOCK[$SM_P]}" == "$SM_CUR_SOCK" ]]; then
        [[ "$SM_N" == "$SM_CUR_SESS" ]] && return 0
        "$bin" -S "$sockpath" switch-client ${client:+-c "$client"} -t "=${SM_N}" && return 0
        msg_err "Could not switch to ${SM_N}."
        return 1
    fi
    if [[ "$SM_ACT" == attach ]]; then
        printf -v cmd 'exec %q sessions attach %q %q --no-anim' "$urb" "$SM_P" "$SM_N"
    else
        printf -v cmd 'cd %q 2>/dev/null; exec %q %q --no-anim' "$cwd" "$urb" "$SM_P"
    fi
    "$bin" -S "$sockpath" detach-client ${client:+-t "$client"} -E "$cmd" && return 0
    msg_err "Could not leave the current session."
    return 1
}

# urb sessions popup [cliente] [sesión] [directorio] [socket]
# Abre el menú en una ventana flotante de tmux (Ctrl+B s o 'sessions' en la shell).
sessions_popup() {
    local client="${1:-}" current="${2:-}" cwd="${3:-$PWD}" sockpath="${4:-}" bin cmd
    [[ -z "$sockpath" && -n "${TMUX:-}" ]] && sockpath="${TMUX%%,*}"
    if [[ -z "$sockpath" ]]; then sessions_menu; return $?; fi
    bin="$(sess_tmux_bin)" || { msg_err "tmux is not installed."; return 1; }
    [[ -n "$client" ]]  || client="$("$bin" -S "$sockpath" display-message -p '#{client_name}' 2>/dev/null)"
    [[ -n "$current" ]] || current="$("$bin" -S "$sockpath" display-message -p '#{session_name}' 2>/dev/null)"
    printf -v cmd '%q sessions menu --client %q --current %q --cwd %q --socket %q' \
        "${URB_HOME}/bin/urb" "$client" "$current" "$cwd" "$sockpath"
    "$bin" -S "$sockpath" display-popup ${client:+-c "$client"} -E -w 90% -h 80% -T ' URB SESSIONS ' "$cmd" 2>/dev/null && return 0
    "$bin" -S "$sockpath" display-popup ${client:+-c "$client"} -E -w 90% -h 80% "$cmd" 2>/dev/null && return 0
    # tmux sin ventanas flotantes (< 3.2): el menú en la propia shell, si hay terminal
    if [[ -t 0 && -t 1 ]]; then
        sessions_menu --client "$client" --current "$current" --cwd "$cwd" --socket "$sockpath"
        return $?
    fi
    "$bin" -S "$sockpath" display-message ${client:+-c "$client"} "URB: popups need tmux 3.2+. Type 'sessions' in the shell." 2>/dev/null
    return 1
}

sessions_main() {
    local action="${1:-list}"
    (( $# > 0 )) && shift
    case "$action" in
        list|ls)        [[ $# -eq 0 ]] || { msg_err "Usage: urb sessions [list]"; return 2; }; sessions_list ;;
        info|show)      (( $# >= 1 && $# <= 2 )) || { msg_err "Usage: urb sessions info <profile> [session]"; return 2; }; sessions_info "$@" ;;
        attach)         (( $# >= 1 && $# <= 3 )) || { msg_err "Usage: urb sessions attach <profile> [session] [--no-anim]"; return 2; }; sessions_attach "$@" ;;
        kill|end)       sessions_kill "$@" ;;
        menu|ui)        sessions_menu "$@" ;;
        popup)          sessions_popup "$@" ;;
        -h|--help|help) sessions_help ;;
        *) msg_err "Unknown sessions action: ${action}"; msg_dim "    See: urb sessions --help"; return 2 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    URB_HOME="$(cd -P -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)" || exit 1
    # shellcheck source=../lib/utils.sh
    source "${URB_HOME}/lib/utils.sh" && urb_standalone_init || exit 1
    # shellcheck source=../godmode/session.sh
    source "${URB_HOME}/godmode/session.sh" || exit 1
    sessions_main "$@"
    exit $?
fi
