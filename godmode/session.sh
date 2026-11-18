#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  godmode/session.sh — Perfiles y consultas de sesiones (compartido)
#  Lo usan godmode/god.sh (shell interactiva), modules/sessions.sh
#  (urb sessions) y el HUD. Requiere lib/utils.sh.
#
#  Reglas:
#   - Los perfiles (*.profile) son DATOS validados: nunca se ejecutan.
#   - Las consultas son de solo lectura: list-sessions / list-* nunca
#     arrancan un servidor ni crean sesiones.
#   - Cada perfil usa su propio socket tmux: nada de lo que se haga sobre
#     un perfil afecta a otro.
# =============================================================================

[[ -n "${_URB_GOD_SESSION_LOADED:-}" ]] && return 0
_URB_GOD_SESSION_LOADED=1

SESS_GOD_DIR="${SESS_GOD_DIR:-$(cd -P -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)}"

# Valores por defecto = perfil god (comportamiento histórico)
P_PROFILE="god" P_NAME="God Mode" P_TITLE="GOD MODE" P_LABEL="URB GOD" P_TAG="GOD"
P_CMD="urb god" P_THEME="urb" P_HUD="god"
GOD_SESSION="god"
GOD_SOCKET="urb-god"

# sess_profiles → nombres de perfil disponibles (ordenados)
sess_profiles() {
    local f n
    for f in "${SESS_GOD_DIR}"/profiles/*.profile; do
        [[ -f "$f" ]] || continue
        n="${f##*/}"; n="${n%.profile}"
        [[ "$n" =~ ^[a-z]{1,16}$ ]] && printf '%s\n' "$n"
    done | sort
}

# sess_load_profile NOMBRE → P_*, GOD_SESSION, GOD_SOCKET (datos validados)
sess_load_profile() {
    local name="$1" f line k v ovar
    [[ "$name" =~ ^[a-z]{1,16}$ ]] || { msg_err "Invalid profile name: ${name}"; return 2; }
    f="${SESS_GOD_DIR}/profiles/${name}.profile"
    [[ -r "$f" ]] || { msg_err "Unknown profile: ${name}"; return 2; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^(PROFILE_[A-Z]+)=([A-Za-z0-9\ ._-]{1,32})$ ]] || { msg_warn "profile ${name}: ignoring invalid line"; continue; }
        k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
        case "$k" in
            PROFILE_NAME)    P_NAME="$v" ;;
            PROFILE_TITLE)   P_TITLE="$v" ;;
            PROFILE_LABEL)   P_LABEL="$v" ;;
            PROFILE_TAG)     [[ "$v" =~ ^[A-Z]{1,8}$ ]] && P_TAG="$v" ;;
            PROFILE_CMD)     P_CMD="$v" ;;
            PROFILE_SESSION) [[ "$v" =~ ^[a-z0-9_-]{1,32}$ ]] && GOD_SESSION="$v" ;;
            PROFILE_SOCKET)  [[ "$v" =~ ^[A-Za-z0-9_-]{1,64}$ ]] && GOD_SOCKET="$v" ;;
            PROFILE_THEME)   [[ "$v" =~ ^[a-z]{1,16}$ && -r "${SESS_GOD_DIR}/themes/${v}.theme" ]] && P_THEME="$v" ;;
            PROFILE_HUD)     [[ "$v" =~ ^[a-z]{1,16}$ ]] && P_HUD="$v" ;;
            *) msg_warn "profile ${name}: unknown key ${k}" ;;
        esac
    done <"$f"
    P_PROFILE="$name"
    # Socket alternativo por variable de entorno (URB_GOD_SOCKET, URB_RED_SOCKET...)
    ovar="URB_${P_TAG}_SOCKET"
    if [[ -n "${!ovar:-}" ]]; then
        [[ "${!ovar}" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { msg_err "Invalid ${ovar} name."; return 2; }
        GOD_SOCKET="${!ovar}"
    fi
    return 0
}

# Binario de tmux (URB_GOD_TMUX permite indicar otro)
sess_tmux_bin() {
    local p
    if [[ -n "${URB_GOD_TMUX:-}" ]]; then
        [[ -x "$URB_GOD_TMUX" ]] && { printf '%s' "$URB_GOD_TMUX"; return 0; }
        p="$(command -v -- "$URB_GOD_TMUX" 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
        return 1
    fi
    p="$(command -v tmux 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
    return 1
}

sess_socket_path() { printf '%s/tmux-%s/%s' "${TMUX_TMPDIR:-/tmp}" "$(id -u)" "$1"; }

# Una consulta por perfil. Conserva las sesiones de nombre fijo de versiones anteriores.
sess_snapshot() {
    local bin out row name suffix
    S_ROWS=() S_ERR=""
    if ! bin="$(sess_tmux_bin)"; then S_STATE="error"; S_ERR="tmux is not installed"; return 1; fi
    # Sin fichero de socket no hay servidor: no se llama a tmux
    [[ -e "$(sess_socket_path "$GOD_SOCKET")" ]] || return 0
    if ! out="$("$bin" -L "$GOD_SOCKET" list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{session_created}' 2>&1)"; then
        case "$out" in
            *"no server running"*|*"error connecting"*"No such file"*|*"Connection refused"*)
                return 0 ;;   # socket huérfano: el servidor ya no existe
            *)  S_STATE="error"; S_ERR="${out%%$'\n'*}"; return 1 ;;
        esac
    fi
    while IFS= read -r row; do
        name="${row%%|*}"
        suffix="${name#"$GOD_SESSION"-}"
        if [[ "$name" == "$GOD_SESSION" || ( "$name" != "$suffix" && "$suffix" =~ ^[0-9]+-[0-9]{5}$ ) ]]; then
            S_ROWS+=("$row")
        fi
    done <<<"$out"
}

sess_read_row() {
    local row="$1" panes="${2:-0}" bin out
    IFS='|' read -r S_NAME S_WINDOWS S_CLIENTS S_CREATED <<<"$row"
    if (( S_CLIENTS > 0 )); then S_STATE="attached"; else S_STATE="detached"; fi
    S_PANES=0
    if (( panes )); then
        S_PANES="-"
        if bin="$(sess_tmux_bin)" && out="$("$bin" -L "$GOD_SOCKET" list-panes -s -t "=${S_NAME}" -F x 2>/dev/null)"; then
            S_PANES="$(grep -c . <<<"$out")"
        fi
    fi
}

# Sin nombre, se elige automáticamente solo cuando hay una única sesión.
sess_query() {
    local name="${1:-}" panes="${2:-0}" row
    S_STATE="none"
    sess_snapshot || return 1
    if [[ -z "$name" ]] && (( ${#S_ROWS[@]} > 1 )); then
        S_STATE="multiple"
        return 0
    fi
    for row in "${S_ROWS[@]}"; do
        [[ -z "$name" || "${row%%|*}" == "$name" ]] || continue
        sess_read_row "$row" "$panes"
        return 0
    done
}

sess_choice_error() {
    msg_err "Multiple ${P_NAME} sessions. Specify a session name."
    msg_dim "    Run 'urb sessions' to see their names."
}

# sess_count_alive → total de sesiones activas (attached o detached)
sess_count_alive() {
    local p n=0
    while IFS= read -r p; do
        sess_load_profile "$p" 2>/dev/null || continue
        sess_snapshot || continue
        n=$(( n + ${#S_ROWS[@]} ))
    done < <(sess_profiles)
    printf '%d' "$n"
}
