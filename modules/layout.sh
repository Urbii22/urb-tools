#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/layout.sh — urb layout: abre tu disposición de trabajo en QTerminal
#
#  Abre una pestaña con varios paneles o añade uno a la pestaña activa.
#  Usa la interfaz D-Bus de QTerminal a través de busctl.
#  Disposiciones: layout.conf para 4 paneles y layout-N.conf para los demás.
# =============================================================================

[[ -n "${_URB_LAYOUT_LOADED:-}" ]] && return 0
_URB_LAYOUT_LOADED=1

LAYOUT_FILE="${URB_LAYOUT_FILE:-${URB_CONFIG_DIR}/layout.conf}"
LAYOUT_FOUR_POSITIONS=(tl tr bl br)

layout_help() {
    cat <<EOF
${C_BOLD}urb layout${C_RESET} — open a work layout in QTerminal

${C_BOLD}USAGE${C_RESET}
  urb layout [N]          Open a new tab with N panes (2–9, default: 4)
  urb layout add APP      Split the current pane and run APP below it
                          APP: god, red, blue, claude, codex
  urb layout show [N]     Print the layout file for N panes
  urb layout edit [N]     Edit it with \$VISUAL or \$EDITOR (creates it if missing)
  urb layout reset [N]    Restore the defaults for N panes

${C_BOLD}DEFAULTS${C_RESET}
  2   GOD and the URB dashboard
  3   GOD, RED and BLUE
  4   Claude, BLUE, GOD and RED
  5   The four-pane commands plus the URB dashboard
  6–9 The five-pane commands plus plain shells

${C_BOLD}LAYOUT FILES${C_RESET}
  ${LAYOUT_FILE} for 4 panes; layout-N.conf alongside it for other sizes
  One line per pane:  <position> <folder> <command...>
    position  tl (top left) · tr (top right) · bl (bottom left) · br (bottom right)
              for 4 panes; 1 through N for the other sizes
    folder    '.' = where you run 'urb layout'; ~ and absolute paths work;
              with spaces, in double quotes: tl "~/my labs" urb red
    command   what to type in the pane ('-' = just a shell)

${C_BOLD}REQUIREMENTS${C_RESET}
  QTerminal (Kali's default terminal) and busctl (systemd). Run it from a
  QTerminal window, even inside GOD/RED/BLUE. Claude and Codex need their CLIs
  available in the shell that QTerminal opens.
EOF
}

_layout_default() {
    local pos i=0
    local -a commands=(claude 'urb blue' 'urb god' 'urb red' 'urb dashboard')
    case $# in
        2) commands=('urb god' 'urb dashboard') ;;
        3) commands=('urb god' 'urb red' 'urb blue') ;;
    esac
    printf '# pos  folder  command\n' || return 1
    for pos in "$@"; do
        printf '%s  .  %s\n' "$pos" "${commands[i]:--}" || return 1
        i=$(( i + 1 ))
    done
}

_layout_ensure_file() {
    local file="$1" temp; shift
    [[ -f "$file" ]] && return 0
    mkdir -p -- "$(dirname -- "$file")" || return 1
    temp="$(mktemp -- "${file}.XXXXXX")" || return 1
    if _layout_default "$@" >"$temp"; then
        mv -nT -- "$temp" "$file" 2>/dev/null
    fi
    rm -f -- "$temp"
    [[ -f "$file" ]]
}

# _layout_read → rellena LAYOUT_DIR[pos] y LAYOUT_CMD[pos]; avisa de líneas inválidas.
# Una carpeta con espacios va entre comillas dobles: tl "~/mis labs" urb red
_layout_read() {
    local file="$1"; shift
    local positions=" $* "
    declare -gA LAYOUT_DIR=() LAYOUT_CMD=()
    local line pos dir cmd n=0
    [[ -r "$file" ]] || { msg_err "Cannot read ${file}."; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$(( n + 1 ))
        line="${line%%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]+\"([^\"]*)\"[[:space:]]*(.*)$ ]]; then
            pos="${BASH_REMATCH[1]}" dir="${BASH_REMATCH[2]}" cmd="${BASH_REMATCH[3]}"
        else
            read -r pos dir cmd <<<"$line"
            if [[ "$dir" == \"* ]]; then
                msg_warn "${file##*/} line ${n}: unclosed quote in the folder; line skipped"; continue
            fi
        fi
        if [[ "$positions" != *" $pos "* ]]; then
            msg_warn "${file##*/} line ${n}: unknown position '${pos}' (use $*)"
            continue
        fi
        LAYOUT_DIR[$pos]="${dir:-.}"
        [[ "$cmd" == "-" ]] && cmd=""
        LAYOUT_CMD[$pos]="$cmd"
    done <"$file"
}

# --- D-Bus de QTerminal ------------------------------------------------------------
_LQ_SVC=""
declare -gA _LQ_IFACE=()

# Interfaz propia (no org.freedesktop.*) de un objeto; se cachea por tipo de ruta
_lq_iface() {
    local kind="${1%/*}"
    kind="${kind:-root}"
    if [[ -z "${_LQ_IFACE[$kind]:-}" ]]; then
        _LQ_IFACE[$kind]="$(busctl --user introspect "$_LQ_SVC" "$1" 2>/dev/null \
            | awk '$2=="interface" && $1 !~ /^org\.freedesktop\./ {print $1; exit}')"
    fi
    printf '%s' "${_LQ_IFACE[$kind]}"
}

# _lq_call RUTA MÉTODO [firma args...] → imprime la ruta devuelta (si la hay)
_lq_call() {
    local path="$1" method="$2" iface out; shift 2
    iface="$(_lq_iface "$path")"
    [[ -n "$iface" ]] || return 1
    out="$(busctl --user call "$_LQ_SVC" "$path" "$iface" "$method" "$@" 2>/dev/null)" || return 1
    awk '{gsub(/"/, "", $2); print $2}' <<<"$out"
}

# PIDs de la cadena de procesos de esta shell (y del cliente tmux, si estamos dentro)
_lq_ancestors() {
    local pid client="" bin
    local -a target=()
    if [[ -n "${TMUX:-}" ]] && bin="$(sess_tmux_bin)"; then
        [[ -n "${TMUX_PANE:-}" ]] && target=(-t "$TMUX_PANE")
        client="$("$bin" -S "${TMUX%%,*}" display-message -p "${target[@]}" '#{client_pid}' 2>/dev/null)"
    fi
    for pid in "$$" "$client"; do
        while [[ "$pid" =~ ^[1-9][0-9]*$ && "$pid" != 1 ]]; do
            printf '%s\n' "$pid"
            # El nombre del proceso (campo 2) puede llevar espacios: "(tmux: client)"
            pid="$(sed 's/^.*) //' "/proc/${pid}/stat" 2>/dev/null | awk '{print $2}')"
        done
    done
}

# Los layouts nuevos admiten el primer QTerminal como alternativa. Para
# dividir una pestaña existente, se exige encontrar la instancia de origen.
_lq_find_service() {
    local first="" service pid
    local -A services=()
    while read -r service pid _; do
        [[ "$service" =~ ^org\.lxqt\.QTerminal(-[0-9]+)?$ && "$pid" =~ ^[1-9][0-9]*$ ]] || continue
        services[$pid]="$service"
        [[ -n "$first" ]] || first="$service"
    done < <(busctl --user list --no-legend 2>/dev/null)
    [[ -n "$first" ]] || return 1
    while IFS= read -r pid; do
        service="${services[$pid]:-}"
        [[ -n "$service" ]] && { _LQ_SVC="$service"; return 0; }
    done < <(_lq_ancestors)
    [[ "${1:-}" != active-only ]] || return 1
    _LQ_SVC="$first"
}

_lq_window() {
    local w
    w="$(_lq_call / getActiveWindow)"
    if [[ "$w" != /windows/* && "${1:-}" != active-only ]]; then
        w="$(busctl --user tree "$_LQ_SVC" --list 2>/dev/null | grep -m1 '^/windows/')"
    fi
    [[ "$w" == /windows/* ]] && printf '%s' "$w"
}

# Texto que se escribe en un panel: cd a su carpeta y, si hay, su comando
_layout_line() {
    local dir="$1" cmd="$2" base="$3" line
    case "$dir" in
        .|"") dir="$base" ;;
        "~")  dir="$HOME" ;;
        "~/"*) dir="${HOME}/${dir#\~/}" ;;
        "~"*) local u="${dir%%/*}" rest="" h; [[ "$dir" == */* ]] && rest="/${dir#*/}"
              h="$(getent passwd "${u#\~}" 2>/dev/null | cut -d: -f6)"
              dir="${h:-${base}/${u}}${rest}" ;;
        /*) ;;
        *) dir="${base}/${dir}" ;;
    esac
    printf -v line 'cd %q' "$dir"
    [[ -n "$cmd" ]] && line+=" && ${cmd}"
    printf '%s\n' "$line"
}

layout_open() {
    local file="$1"; shift
    command -v busctl >/dev/null 2>&1 || { msg_err "urb layout needs busctl (systemd), which was not found."; return 1; }
    _layout_ensure_file "$file" "$@" || { msg_err "Could not create ${file}."; return 1; }
    _layout_read "$file" "$@" || return 1
    if ! _lq_find_service; then
        msg_err "No QTerminal found on D-Bus: urb layout only works in QTerminal."
        return 1
    fi
    local win tab i parent method columns=2
    local -a positions=("$@") term=()
    win="$(_lq_window)" || { msg_err "QTerminal (${_LQ_SVC}) has no window to open the tab in."; return 1; }
    tab="$(_lq_call "$win" newTab 'a{sv}' 0)" && [[ "$tab" == /tabs/* ]] \
        || { msg_err "QTerminal did not open a new tab (D-Bus newTab failed)."; return 1; }
    term[0]="$(_lq_call "$tab" getActiveTerminal)"
    (( $# > 6 )) && columns=3
    for (( i = 1; i < $#; i++ )); do
        if (( i < columns )); then
            parent=$(( i - 1 )); method=splitHorizontal
        else
            # Split the top pane again for a third row, keeping the lower pane tall.
            parent=$(( i % columns )); method=splitVertical
        fi
        [[ "${term[parent]:-}" == /terminals/* ]] || continue
        term[i]="$(_lq_call "${term[parent]}" "$method" 'a{sv}' 0)"
    done

    local pos failed=() base="$PWD"
    for i in "${!positions[@]}"; do
        pos="${positions[i]}"
        if [[ "${term[i]:-}" != /terminals/* ]]; then failed+=("$pos"); continue; fi
        _lq_call "${term[i]}" sendText s \
            "$(_layout_line "${LAYOUT_DIR[$pos]:-.}" "${LAYOUT_CMD[$pos]:-}" "$base")"$'\n' >/dev/null \
            || failed+=("$pos")
    done
    if (( ${#failed[@]} )); then
        msg_warn "Layout opened, but these panes could not be set up: ${failed[*]}"
        return 1
    fi
    msg_ok "Layout opened in a new QTerminal tab with $# panes."
}

layout_add() {
    local cmd win tab pane new_pane
    if (( $# != 1 )); then
        msg_err "Usage: urb layout add <god|red|blue|claude|codex>"
        return 2
    fi
    case "$1" in
        god|red|blue) cmd="urb $1" ;;
        claude|codex) cmd="$1" ;;
        -h|--help) layout_help; return ;;
        *) msg_err "Unknown app '$1'. Choose god, red, blue, claude or codex."; return 2 ;;
    esac
    command -v busctl >/dev/null 2>&1 || { msg_err "urb layout needs busctl (systemd), which was not found."; return 1; }
    if ! _lq_find_service active-only; then
        msg_err "Could not identify the originating QTerminal. Run 'urb layout add' from the pane you want to split."
        return 1
    fi
    if ! win="$(_lq_window active-only)" ||
       ! tab="$(_lq_call "$win" getActiveTab)" || [[ "$tab" != /tabs/* ]] ||
       ! pane="$(_lq_call "$tab" getActiveTerminal)" || [[ "$pane" != /terminals/* ]]; then
        msg_err "Could not find the active pane in QTerminal."
        return 1
    fi
    if ! new_pane="$(_lq_call "$pane" splitVertical 'a{sv}' 0)" ||
       [[ "$new_pane" != /terminals/* || "$new_pane" == "$pane" ]]; then
        msg_err "QTerminal could not split the active pane."
        return 1
    fi
    if ! _lq_call "$new_pane" sendText s "$(_layout_line . "$cmd" "$PWD")"$'\n' >/dev/null; then
        msg_err "Panel opened, but QTerminal could not send '$cmd' to it."
        return 1
    fi
    msg_ok "Added a panel for $cmd."
}

layout_main() {
    local action="${1:-open}"
    case "$action" in
        open|show|edit|reset) (( $# > 0 )) && shift ;;
        add) shift; layout_add "$@"; return ;;
        help|-h|--help) layout_help; return ;;
        [0-9]*) action=open ;;
        *) msg_err "Unknown layout action: $1"; msg_dim "    Run 'urb layout help'."; return 2 ;;
    esac
    local count="${1-4}" file="$LAYOUT_FILE" i
    if (( $# > 1 )) || [[ ! "$count" =~ ^[2-9]$ ]]; then
        msg_err "Choose a pane count from 2 to 9. Run 'urb layout help'."
        return 2
    fi

    local -a positions=()
    if (( count == 4 )); then
        positions=("${LAYOUT_FOUR_POSITIONS[@]}")
    else
        file="${LAYOUT_FILE%.conf}-${count}.conf"
        for (( i = 1; i <= count; i++ )); do positions+=("$i"); done
    fi

    case "$action" in
        open)  layout_open "$file" "${positions[@]}" ;;
        show)  _layout_ensure_file "$file" "${positions[@]}" && cat -- "$file" ;;
        edit)  _layout_ensure_file "$file" "${positions[@]}" || return 1
               local ed="${VISUAL:-${EDITOR:-}}"
               [[ -n "$ed" ]] || { has_cmd nano && ed="nano"; } || { has_cmd vi && ed="vi"; }
               [[ -n "$ed" ]] || { msg_err "No editor found: set \$EDITOR or edit ${file}"; return 1; }
               $ed "$file" ;;
        reset) mkdir -p -- "$(dirname -- "$file")" && _layout_default "${positions[@]}" >"$file" \
                   && msg_ok "Default layout restored in ${file}" ;;
    esac
}
