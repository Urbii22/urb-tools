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

  Profiles: $(sess_profiles | tr '\n' ' ')
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

sessions_main() {
    local action="${1:-list}"
    (( $# > 0 )) && shift
    case "$action" in
        list|ls)        [[ $# -eq 0 ]] || { msg_err "Usage: urb sessions [list]"; return 2; }; sessions_list ;;
        info|show)      (( $# >= 1 && $# <= 2 )) || { msg_err "Usage: urb sessions info <profile> [session]"; return 2; }; sessions_info "$@" ;;
        attach)         (( $# >= 1 && $# <= 3 )) || { msg_err "Usage: urb sessions attach <profile> [session] [--no-anim]"; return 2; }; sessions_attach "$@" ;;
        kill|end)       sessions_kill "$@" ;;
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
