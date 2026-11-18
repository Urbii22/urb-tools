#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/layout.sh — urb layout: abre tu disposición de trabajo en QTerminal
#
#  Una pestaña nueva partida en 4 paneles (arriba-izq, arriba-der, abajo-izq,
#  abajo-der); en cada uno entra en su carpeta y escribe su comando.
#  Usa la interfaz D-Bus de QTerminal (newTab, splitHorizontal, splitVertical,
#  sendText) a través de busctl. No toca nada fuera de la pestaña nueva.
#  Disposición: ~/.config/urb-tools/layout.conf (se crea con la de por defecto).
# =============================================================================

[[ -n "${_URB_LAYOUT_LOADED:-}" ]] && return 0
_URB_LAYOUT_LOADED=1

LAYOUT_FILE="${URB_LAYOUT_FILE:-${URB_CONFIG_DIR}/layout.conf}"
LAYOUT_POSITIONS=(tl tr bl br)

layout_help() {
    cat <<EOF
${C_BOLD}urb layout${C_RESET} — open your 4-pane work layout in QTerminal

${C_BOLD}USAGE${C_RESET}
  urb layout            New QTerminal tab split in 4 panes, each one running its command
  urb layout show       Print the layout file
  urb layout edit       Edit the layout file (\$EDITOR, created with the default if missing)
  urb layout reset      Restore the default layout file

${C_BOLD}LAYOUT FILE${C_RESET} (${LAYOUT_FILE})
  One line per pane:  <position> <folder> <command...>
    position  tl (top left) · tr (top right) · bl (bottom left) · br (bottom right)
    folder    '.' = where you run 'urb layout'; ~ and absolute paths work
    command   what to type in the pane ('-' = just a shell)
  Default:
$(_layout_default | sed 's/^/    /')

${C_BOLD}REQUIREMENTS${C_RESET}
  QTerminal (Kali's default terminal) and busctl (systemd). Run it from a
  QTerminal window, even inside GOD/RED/BLUE: the tab opens in that window.
EOF
}

_layout_default() {
    cat <<'EOF'
# pos  folder  command
tl  .  claude
tr  .  urb blue
bl  .  urb god
br  .  urb red
EOF
}

_layout_ensure_file() {
    [[ -f "$LAYOUT_FILE" ]] && return 0
    mkdir -p -- "$(dirname -- "$LAYOUT_FILE")" && _layout_default >"$LAYOUT_FILE"
}

# _layout_read → rellena LAYOUT_DIR[pos] y LAYOUT_CMD[pos]; avisa de líneas inválidas
_layout_read() {
    declare -gA LAYOUT_DIR=() LAYOUT_CMD=()
    local line pos dir cmd n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$(( n + 1 ))
        line="${line%%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        read -r pos dir cmd <<<"$line"
        case "$pos" in
            tl|tr|bl|br) ;;
            *) msg_warn "layout.conf line ${n}: unknown position '${pos}' (use tl, tr, bl, br)"; continue ;;
        esac
        LAYOUT_DIR[$pos]="${dir:-.}"
        [[ "$cmd" == "-" ]] && cmd=""
        LAYOUT_CMD[$pos]="$cmd"
    done <"$LAYOUT_FILE"
}

# --- D-Bus de QTerminal ------------------------------------------------------------
_LQ_SVC=""
declare -gA _LQ_IFACE=()

# Interfaz propia (no org.freedesktop.*) de un objeto; se cachea por tipo de ruta
_lq_iface() {
    local kind="${1%/*}"
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
    local pid
    for pid in "$$" "$( [[ -n "${TMUX:-}" ]] && tmux display-message -p '#{client_pid}' 2>/dev/null )"; do
        while [[ -n "$pid" && "$pid" != 0 && "$pid" != 1 ]]; do
            printf '%s\n' "$pid"
            pid="$(awk '{print $4}' "/proc/${pid}/stat" 2>/dev/null)"
        done
    done
}

# Elige el QTerminal en el que se ejecuta esto (o el primero que haya)
_lq_find_service() {
    local svcs anc s
    svcs="$(busctl --user list --no-legend 2>/dev/null | awk '$1 ~ /^org\.lxqt\.QTerminal-[0-9]+$/ {print $1}')"
    [[ -n "$svcs" ]] || return 1
    anc=" $(_lq_ancestors | tr '\n' ' ') "
    for s in $svcs; do
        [[ "$anc" == *" ${s##*-} "* ]] && { _LQ_SVC="$s"; return 0; }
    done
    _LQ_SVC="${svcs%%$'\n'*}"
}

_lq_window() {
    local w
    w="$(_lq_call / getActiveWindow)"
    [[ "$w" == /windows/* ]] || w="$(busctl --user tree "$_LQ_SVC" --list 2>/dev/null | grep -m1 '^/windows/')"
    [[ -n "$w" ]] && printf '%s' "$w"
}

# Texto que se escribe en un panel: cd a su carpeta y, si hay, su comando
_layout_line() {
    local dir="$1" cmd="$2" base="$3" line
    case "$dir" in
        .|"") dir="$base" ;;
        "~")  dir="$HOME" ;;
        "~/"*) dir="${HOME}/${dir#\~/}" ;;
        /*) ;;
        *) dir="${base}/${dir}" ;;
    esac
    printf -v line 'cd %q' "$dir"
    [[ -n "$cmd" ]] && line+=" && ${cmd}"
    printf '%s\n' "$line"
}

layout_open() {
    command -v busctl >/dev/null 2>&1 || { msg_err "urb layout needs busctl (systemd), which was not found."; return 1; }
    _layout_ensure_file || { msg_err "Could not create ${LAYOUT_FILE}."; return 1; }
    _layout_read
    if ! _lq_find_service; then
        msg_err "No QTerminal found on D-Bus: urb layout only works in QTerminal."
        return 1
    fi
    local win tab
    declare -A term=()
    win="$(_lq_window)" || { msg_err "QTerminal (${_LQ_SVC}) has no window to open the tab in."; return 1; }
    tab="$(_lq_call "$win" newTab 'a{sv}' 0)" && [[ "$tab" == /tabs/* ]] \
        || { msg_err "QTerminal did not open a new tab (D-Bus newTab failed)."; return 1; }
    term[tl]="$(_lq_call "$tab" getActiveTerminal)"
    [[ -n "${term[tl]}" ]] && term[tr]="$(_lq_call "${term[tl]}" splitHorizontal 'a{sv}' 0)"
    [[ -n "${term[tl]}" ]] && term[bl]="$(_lq_call "${term[tl]}" splitVertical 'a{sv}' 0)"
    [[ -n "${term[tr]}" ]] && term[br]="$(_lq_call "${term[tr]}" splitVertical 'a{sv}' 0)"

    local pos failed=() base="$PWD"
    for pos in "${LAYOUT_POSITIONS[@]}"; do
        if [[ "${term[$pos]:-}" != /terminals/* ]]; then failed+=("$pos"); continue; fi
        _lq_call "${term[$pos]}" sendText s \
            "$(_layout_line "${LAYOUT_DIR[$pos]:-.}" "${LAYOUT_CMD[$pos]:-}" "$base")"$'\n' >/dev/null \
            || failed+=("$pos")
    done
    if (( ${#failed[@]} )); then
        msg_warn "Layout opened, but these panes could not be set up: ${failed[*]}"
        return 1
    fi
    msg_ok "Layout opened in a new QTerminal tab."
}

layout_main() {
    case "${1:-open}" in
        open)  layout_open ;;
        show)  _layout_ensure_file && cat -- "$LAYOUT_FILE" ;;
        edit)  _layout_ensure_file && "${EDITOR:-nano}" "$LAYOUT_FILE" ;;
        reset) mkdir -p -- "$(dirname -- "$LAYOUT_FILE")" && _layout_default >"$LAYOUT_FILE" \
                   && msg_ok "Default layout restored in ${LAYOUT_FILE}" ;;
        help|-h|--help) layout_help ;;
        *) msg_err "Unknown layout action: $1"; msg_dim "    Run 'urb layout help'."; return 2 ;;
    esac
}
