#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/sessions.sh — urb sessions: gestor de sesiones GOD / RED
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
  urb sessions                      List profiles and their session state
  urb sessions info <profile>       Details: windows, panes, clients, created
  urb sessions attach <profile>     Reconnect to a running session (never creates one)
  urb sessions kill <profile>       End a session (always asks; --yes to skip)

  Profiles: $(sess_profiles | tr '\n' ' ')

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
    local p rc=0 col err=()
    msg_section "URB SESSIONS"
    printf '  %s%-8s %-10s %7s %6s %8s  %s%s\n' "$C_BOLD" "PROFILE" "STATE" "WINDOWS" "PANES" "CLIENTS" "SOCKET" "$C_RESET"
    while IFS= read -r p; do
        sess_load_profile "$p" 2>/dev/null || continue
        sess_query "$GOD_SOCKET" "$GOD_SESSION" 1 || true
        col="$(_sess_state_color "$S_STATE")"
        if [[ "$S_STATE" == "none" || "$S_STATE" == "error" ]]; then
            printf '  %s%-8s%s %s%-10s%s %7s %6s %8s  %s%s%s\n' "$T_KEY" "$p" "$C_RESET" "$col" "$S_STATE" "$C_RESET" "-" "-" "-" "$T_DIM" "$GOD_SOCKET" "$C_RESET"
        else
            printf '  %s%-8s%s %s%-10s%s %7s %6s %8s  %s%s%s\n' "$T_KEY" "$p" "$C_RESET" "$col" "$S_STATE" "$C_RESET" "$S_WINDOWS" "$S_PANES" "$S_CLIENTS" "$T_DIM" "$GOD_SOCKET" "$C_RESET"
        fi
        [[ "$S_STATE" == "error" ]] && { err+=("${p}: ${S_ERR}"); rc=1; }
    done < <(sess_profiles)
    local e; for e in "${err[@]}"; do msg_err "$e"; done
    msg_dim "  urb sessions info|attach|kill <profile>"
    return "$rc"
}

sessions_info() {
    _sess_profile "${1:-}" || return $?
    local bin
    sess_query "$GOD_SOCKET" "$GOD_SESSION" 1
    msg_section "SESSION ${G_SEP} ${P_NAME}"
    printf '  %s%-9s%s %s%s%s\n' "$T_LABEL" "State" "$C_RESET" "$(_sess_state_color "$S_STATE")" "$S_STATE" "$C_RESET"
    printf '  %s%-9s%s %s (session "%s")\n' "$T_LABEL" "Socket" "$C_RESET" "$(sess_socket_path "$GOD_SOCKET")" "$GOD_SESSION"
    case "$S_STATE" in
        error) msg_err "tmux: ${S_ERR}"; return 1 ;;
        none)  msg_dim "  No session. Start one with: ${P_CMD}"; return 0 ;;
    esac
    printf '  %s%-9s%s %s\n' "$T_LABEL" "Created" "$C_RESET" "$(printf '%(%Y-%m-%d %H:%M:%S)T' "$S_CREATED")"
    printf '  %s%-9s%s %s window(s), %s pane(s), %s client(s)\n' "$T_LABEL" "Size" "$C_RESET" "$S_WINDOWS" "$S_PANES" "$S_CLIENTS"
    bin="$(sess_tmux_bin)" || return 1
    msg_section "PANES"
    "$bin" -L "$GOD_SOCKET" list-panes -s -t "=${GOD_SESSION}" \
        -F '  #{window_index}.#{pane_index}  #{?pane_active,*, } #{pane_current_command}  #{pane_current_path}' 2>&1
    if (( S_CLIENTS > 0 )); then
        msg_section "CLIENTS"
        "$bin" -L "$GOD_SOCKET" list-clients -t "=${GOD_SESSION}" -F '  #{client_tty}  #{client_width}x#{client_height}' 2>&1
    fi
    printf '\n'
    msg_dim "  urb sessions attach ${P_PROFILE} · urb sessions kill ${P_PROFILE}"
    return 0
}

sessions_attach() {
    local p="${1:-}"; shift || true
    _sess_profile "$p" || return $?
    local extra=()
    [[ "${1:-}" == "--no-anim" ]] && extra+=(--no-anim)
    sess_query "$GOD_SOCKET" "$GOD_SESSION" 0
    case "$S_STATE" in
        error) msg_err "tmux: ${S_ERR}"; return 1 ;;
        none)  msg_err "No ${P_NAME} session to attach to."; msg_dim "    Start one with: ${P_CMD}"; return 1 ;;
    esac
    local god="${URB_HOME}/godmode/god.sh"
    [[ -f "$god" ]] || { msg_err "God Mode files not found (${god})."; return 1; }
    # god.sh --attach-only vuelve a comprobarlo: nunca crea la sesión
    URB_COLOR="${color_mode:-${URB_COLOR:-auto}}" exec bash "$god" --profile "$P_PROFILE" --attach-only "${extra[@]}"
}

sessions_kill() {
    local p="" yes=0 bin busy
    while (( $# > 0 )); do
        case "$1" in
            -y|--yes) yes=1 ;;
            -*) msg_err "Unknown option: $1"; return 2 ;;
            *)  [[ -z "$p" ]] || { msg_err "Only one profile at a time."; return 2; }; p="$1" ;;
        esac
        shift
    done
    _sess_profile "$p" || return $?
    sess_query "$GOD_SOCKET" "$GOD_SESSION" 1
    case "$S_STATE" in
        error) msg_err "tmux: ${S_ERR}"; return 1 ;;
        none)  msg_info "No ${P_NAME} session running. Nothing to do."; return 0 ;;
    esac
    bin="$(sess_tmux_bin)" || return 1
    busy="$("$bin" -L "$GOD_SOCKET" list-panes -s -t "=${GOD_SESSION}" -F '#{pane_current_command}' 2>/dev/null \
            | grep -v -x -E 'zsh|bash|sh|-zsh|-bash' | sort -u | tr '\n' ' ')"
    msg_warn "This ends the ${P_NAME} session (${S_STATE}, ${S_WINDOWS} window(s), ${S_PANES} pane(s))."
    [[ -n "$busy" ]] && msg_warn "Programs running in it will be terminated: ${busy}"
    msg_dim "    Other profiles and your own tmux sessions are not affected."
    if (( ! yes )); then
        confirm "End the ${P_NAME} session?" n || { msg_info "Cancelled."; return 1; }
    fi
    # Solo la sesión de este perfil, en su propio socket
    if "$bin" -L "$GOD_SOCKET" kill-session -t "=${GOD_SESSION}" 2>/dev/null; then
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
        info|show)      [[ $# -eq 1 ]] || { msg_err "Usage: urb sessions info <profile>"; return 2; }; sessions_info "$1" ;;
        attach)         (( $# >= 1 && $# <= 2 )) || { msg_err "Usage: urb sessions attach <profile> [--no-anim]"; return 2; }; sessions_attach "$@" ;;
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
