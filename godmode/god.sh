#!/usr/bin/env bash
# =============================================================================
#  godmode/god.sh — URB God Mode
#  Convierte la terminal actual (misma ventana) en un espacio de trabajo
#  avanzado: tmux con servidor y configuración PROPIOS + Zsh real + HUD.
#
#  Aislamiento:
#   - Servidor tmux en un socket aparte (tmux -L urb-god): tus sesiones tmux
#     y tu ~/.tmux.conf no se tocan.
#   - Zsh con ZDOTDIR temporal (godmode/zsh) que carga tu ~/.zshrc sin
#     modificarlo y añade el prompt de God Mode.
#   - No usa root ni concede privilegios: es tu usuario, tu shell.
#
#  Uso: urb god [--no-anim] | --status | --kill [--yes] | --check | --help
# =============================================================================
set -uo pipefail

GOD_DIR="$(cd -P -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)" || exit 1
URB_HOME="${URB_HOME:-$(cd -P -- "${GOD_DIR}/.." && pwd -P)}"
export URB_HOME

for _f in "${URB_HOME}/lib/utils.sh" "${URB_HOME}/lib/ui.sh" "${URB_HOME}/lib/system.sh" "${URB_HOME}/lib/lab.sh"; do
    # shellcheck source=/dev/null
    source "$_f" || { echo "urb god: cannot load ${_f}" >&2; exit 1; }
done
unset _f
urb_read_theme "${GOD_DIR}/themes/urb.theme" || { echo "urb god: cannot load theme" >&2; exit 1; }
# shellcheck source=animations/fx.sh
source "${GOD_DIR}/animations/fx.sh" || { echo "urb god: cannot load animations" >&2; exit 1; }

GOD_MIN_TMUX="3.0"
GOD_TMUX_BIN="" GOD_ZSH_BIN="" GOD_TMUX_VER="" GOD_ZSH_VER=""

# --- Perfiles (godmode/profiles/<nombre>.profile) ----------------------------------
# El perfil define identidad visual y aislamiento: nombre, etiqueta, sesión,
# socket tmux, tema y HUD. Por defecto "god" (comportamiento de siempre).
# El análisis del perfil y las consultas de sesión viven en godmode/session.sh.
SESS_GOD_DIR="$GOD_DIR"
# shellcheck source=session.sh
source "${GOD_DIR}/session.sh" || { echo "urb god: cannot load session.sh" >&2; exit 1; }

# god_load_profile NOMBRE → perfil (datos validados) + tema del perfil
god_load_profile() {
    sess_load_profile "$1" || return $?
    if [[ "$P_THEME" != "urb" ]]; then urb_read_theme "${GOD_DIR}/themes/${P_THEME}.theme"; fi
    return 0
}

# Degradado del logo según el tema (si la terminal admite 256 colores)
_god_apply_logo_gradient() {
    local -a g
    [[ -n "${URB_LOGO_GRADIENT:-}" ]] || return 0
    (( URB_COLOR_ON && URB_256 )) || return 0
    read -ra g <<<"$URB_LOGO_GRADIENT"
    (( ${#g[@]} >= 6 )) || return 0
    UI_LOGO_COLORS=()
    local c; for c in "${g[@]:0:6}"; do UI_LOGO_COLORS+=($'\e[1;38;5;'"${c}m"); done
}

god_help() {
    cat <<EOF
${C_BOLD}urb god${C_RESET} — URB God Mode: advanced workspace in your current terminal

${C_BOLD}USAGE${C_RESET}
  urb god               Engage God Mode (or reconnect to a running session)
  urb god --no-anim     Engage without animations
  urb god --status      Show whether a God Mode session is running
  urb god --kill        End the God Mode session (asks if programs are running)
  urb god --kill --yes  End it without asking
  urb god --check       Check God Mode dependencies (tmux >= ${GOD_MIN_TMUX}, zsh)
  urb god --help        This help

${C_BOLD}INSIDE GOD MODE${C_RESET}
  It is a real zsh (your ~/.zshrc, aliases, completion and history) running in
  tmux, with a compact HUD (CPU, RAM, IP, VPN, git) in the status bar.

  ${T_KEY}exit${C_RESET}          Leave: closes the shell and ends the session (back to your terminal)
  ${T_KEY}Ctrl+B d${C_RESET}      Detach: back to your terminal, programs KEEP RUNNING;
                'urb god' reconnects to them
  ${T_KEY}urb god --kill${C_RESET} Terminate: ends the session and everything running in it
  ${T_KEY}Ctrl+B c${C_RESET}      New window · ${T_KEY}Ctrl+B %${C_RESET} / ${T_KEY}Ctrl+B "${C_RESET} split panes (standard tmux keys)

  Closing the terminal window while in God Mode behaves like a detach.

${C_BOLD}ISOLATION${C_RESET}
  Own tmux server (socket '${GOD_SOCKET}') and config: your tmux sessions and
  ~/.tmux.conf are never touched. Your ~/.zshrc is loaded, never modified.
  God Mode runs as your user: it gives no extra privileges.

${C_BOLD}CONFIG${C_RESET} (urb config set KEY VALUE)
  ANIMATIONS=0|1   GOD_HUD_POSITION=top|bottom   GOD_MOUSE=0|1
EOF
}

# --- Utilidades ---------------------------------------------------------------------
god_tmux() { "$GOD_TMUX_BIN" -L "$GOD_SOCKET" "$@"; }

# god_version_ge "3.6a" "3.0" → 0 si la primera es >= la segunda (major.minor)
god_version_ge() {
    local a="$1" b="$2" a1 a2 b1 b2
    [[ "$a" =~ ([0-9]+)\.([0-9]+) ]] || return 1
    a1=$((10#${BASH_REMATCH[1]})) a2=$((10#${BASH_REMATCH[2]}))
    [[ "$b" =~ ([0-9]+)\.([0-9]+) ]] || return 1
    b1=$((10#${BASH_REMATCH[1]})) b2=$((10#${BASH_REMATCH[2]}))
    (( a1 > b1 || (a1 == b1 && a2 >= b2) ))
}

_god_resolve() {
    local name="$1" override="$2" p
    if [[ -n "$override" ]]; then
        if [[ -x "$override" ]]; then printf '%s' "$override"; return 0; fi
        p="$(command -v -- "$override" 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
        return 1
    fi
    p="$(command -v -- "$name" 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
    return 1
}

# Comprueba tmux y zsh. Retorna 0, 127 (falta) o 1 (tmux demasiado antiguo)
god_check_deps() {
    local quiet="${1:-0}" missing=() pkgs=() rc=0
    GOD_TMUX_BIN="$(_god_resolve tmux "${URB_GOD_TMUX:-}")" || { missing+=(tmux); pkgs+=(tmux); }
    GOD_ZSH_BIN="$(_god_resolve zsh "${URB_GOD_ZSH:-}")"    || { missing+=(zsh);  pkgs+=(zsh); }
    if [[ -n "$GOD_TMUX_BIN" ]]; then
        GOD_TMUX_VER="$("$GOD_TMUX_BIN" -V 2>/dev/null)"; GOD_TMUX_VER="${GOD_TMUX_VER#tmux }"
    fi
    if [[ -n "$GOD_ZSH_BIN" ]]; then
        GOD_ZSH_VER="$("$GOD_ZSH_BIN" --version 2>/dev/null)"; GOD_ZSH_VER="${GOD_ZSH_VER#zsh }"; GOD_ZSH_VER="${GOD_ZSH_VER%% *}"
    fi
    if (( ${#missing[@]} )); then
        (( quiet )) || { msg_err "God Mode needs: ${missing[*]} (not found)."
                         msg_dim "    Install with:  sudo apt install ${pkgs[*]}"
                         msg_dim "    The rest of URB-Tools works without them."; }
        return 127
    fi
    if ! god_version_ge "$GOD_TMUX_VER" "$GOD_MIN_TMUX"; then
        (( quiet )) || msg_err "tmux ${GOD_TMUX_VER} is too old: God Mode needs tmux >= ${GOD_MIN_TMUX}."
        rc=1
    fi
    return "$rc"
}

god_session_exists() { god_tmux has-session -t "=${GOD_SESSION}" 2>/dev/null; }

_god_anim_enabled() {
    [[ "${URB_NO_ANIM:-0}" == "1" ]] && return 1
    cfg_bool ANIMATIONS 1
}

# --- Acciones --------------------------------------------------------------------------
god_check() {
    local rc
    god_check_deps 1; rc=$?
    msg_section "GOD MODE DEPENDENCIES"
    if [[ -n "$GOD_TMUX_BIN" ]]; then printf '  %s%s%s tmux %s  %s(%s)%s\n' "$T_OK" "$G_OK" "$C_RESET" "$GOD_TMUX_VER" "$T_DIM" "$GOD_TMUX_BIN" "$C_RESET"
    else printf '  %s%s%s tmux   %smissing — sudo apt install tmux%s\n' "$T_BAD" "$G_BAD" "$C_RESET" "$T_BAD" "$C_RESET"; fi
    if [[ -n "$GOD_ZSH_BIN" ]]; then printf '  %s%s%s zsh %s  %s(%s)%s\n' "$T_OK" "$G_OK" "$C_RESET" "$GOD_ZSH_VER" "$T_DIM" "$GOD_ZSH_BIN" "$C_RESET"
    else printf '  %s%s%s zsh    %smissing — sudo apt install zsh%s\n' "$T_BAD" "$G_BAD" "$C_RESET" "$T_BAD" "$C_RESET"; fi
    if (( rc == 1 )); then msg_err "tmux ${GOD_TMUX_VER} < ${GOD_MIN_TMUX}"; fi
    (( rc == 0 )) && msg_ok "${P_NAME} is ready: run '${P_CMD}'."
    return "$rc"
}

god_status() {
    god_check_deps || return $?
    if god_session_exists; then
        local wins clients
        wins="$(god_tmux list-windows -t "=${GOD_SESSION}" 2>/dev/null | wc -l)"
        clients="$(god_tmux list-clients -t "=${GOD_SESSION}" 2>/dev/null | wc -l)"
        msg_ok "${P_NAME} session running: ${wins} window(s), ${clients} attached terminal(s)."
        god_tmux list-panes -s -t "=${GOD_SESSION}" -F '    #{window_index}.#{pane_index}  #{pane_current_command}  #{pane_current_path}' 2>/dev/null
        msg_dim "    '${P_CMD}' to reconnect · '${P_CMD} --kill' to end it"
    else
        msg_info "No ${P_NAME} session running."
    fi
    return 0
}

god_kill() {
    local assume_yes="${1:-0}" busy
    god_check_deps || return $?
    if ! god_session_exists; then msg_info "No ${P_NAME} session running."; return 0; fi
    if [[ -n "${TMUX:-}" && "$TMUX" == *"/${GOD_SOCKET},"* ]]; then
        msg_warn "You are inside ${P_NAME}: this will close the current terminal session too."
    fi
    # Procesos que no son una shell en espera
    busy="$(god_tmux list-panes -s -t "=${GOD_SESSION}" -F '#{pane_current_command}' 2>/dev/null \
            | grep -v -x -E 'zsh|bash|sh|-zsh|-bash' | sort -u | tr '\n' ' ')"
    if [[ -n "$busy" && "$assume_yes" != "1" ]]; then
        msg_warn "Programs still running in ${P_NAME}: ${busy}"
        confirm "End the ${P_NAME} session and terminate them?" n || { msg_info "Cancelled."; return 1; }
    fi
    # Solo el servidor del socket de este perfil: nunca otros servidores tmux
    if god_tmux kill-server 2>/dev/null; then msg_ok "${P_NAME} session ended."; return 0; fi
    msg_err "Could not end the ${P_NAME} session."
    return 1
}

# Líneas informativas reales para la animación de entrada
_god_engage_info() {
    local resume="$1" where="${PWD/#$HOME/\~}"
    GOD_INFO=("tmux ${GOD_TMUX_VER} · zsh ${GOD_ZSH_VER}")
    if (( resume )); then GOD_INFO+=("session: reconnecting to running ${P_NAME}")
    else GOD_INFO+=("session: new · ${where}"); fi
    if [[ "$P_HUD" == "red" ]]; then
        if lab_resolve "$PWD"; then
            local t; t="$(lab_target_get "$LAB_ROOT" 2>/dev/null)"
            GOD_INFO+=("lab: $(lab_name "$LAB_ROOT") (${LAB_SOURCE}) · target: ${t:-not set}")
        else
            GOD_INFO+=("lab: none — urb red lab new <name> --target <ip>")
        fi
        GOD_INFO+=("HUD: LAB · TARGET · VPN · IP · CPU · RAM")
    else
        GOD_INFO+=("HUD: CPU · RAM · IP · VPN · git")
    fi
}

# Animación de salida protegida: se dibuja en la pantalla alternativa, así que
# un Ctrl+C (o un cierre) durante ella debe devolver SIEMPRE la pantalla
# principal y el cursor. Sin este trap, la shell que lanzó urb quedaría en la
# pantalla alternativa (donde algunos terminales convierten la rueda del ratón
# en flechas ↑/↓). La sesión tmux no se ve afectada: ya está desconectada.
_god_fx_out() {
    trap 'printf "\e[0m\e[?25h\e[?1049l"; exit 130' INT TERM HUP
    god_fx_disengage "$1"
    trap - INT TERM HUP
}

god_start() {
    local use_anim=1 attach_only="${2:-0}"
    [[ "${1:-}" == "--no-anim" ]] && use_anim=0
    _god_anim_enabled || use_anim=0

    if [[ ! -t 0 || ! -t 1 ]]; then
        msg_err "${P_NAME} needs an interactive terminal."
        return 1
    fi
    god_check_deps || return $?

    if [[ -n "${TMUX:-}" ]]; then
        if [[ "$TMUX" == *"/${GOD_SOCKET},"* ]]; then
            msg_warn "You are already in ${P_NAME}."
        else
            msg_err "You are inside another tmux session. Detach first (Ctrl+B d) and run '${P_CMD}' again."
            msg_dim "    ${P_NAME} does not nest inside tmux, to avoid conflicts with your sessions."
        fi
        return 1
    fi

    ui_term_size
    if (( UI_COLS < 40 || UI_ROWS < 10 )); then
        msg_err "Terminal too small for ${P_NAME} (${UI_COLS}x${UI_ROWS}, minimum 40x10)."
        return 1
    fi

    # Modo "solo reconectar" (urb sessions attach): nunca crea una sesión
    if (( attach_only )) && ! god_session_exists; then
        msg_err "No ${P_NAME} session to attach to."
        msg_dim "    Start one with: ${P_CMD}"
        return 1
    fi

    # Entorno para tmux.conf (colores, rutas, terminfo, perfil) — solo para este servidor
    local term="screen-256color" pos mouse resume=0 rc
    if infocmp tmux-256color >/dev/null 2>&1; then term="tmux-256color"; fi
    pos="$(cfg GOD_HUD_POSITION top)"; [[ "$pos" == "bottom" ]] || pos="top"
    mouse="$(cfg GOD_MOUSE 0)"
    urb_read_theme "${GOD_DIR}/themes/urb.theme" 1
    [[ "$P_THEME" != "urb" ]] && urb_read_theme "${GOD_DIR}/themes/${P_THEME}.theme" 1
    export URB_GOD_DIR="$GOD_DIR" URB_GOD_TERM="$term" URB_GOD_HUD_POSITION="$pos"
    export URB_PROFILE="$P_PROFILE" URB_PROFILE_TAG="$P_TAG" URB_PROFILE_LABEL="$P_LABEL" \
           URB_PROFILE_THEME="$P_THEME" URB_PROFILE_HUD="$P_HUD" URB_PROFILE_CMD="$P_CMD"
    _god_apply_logo_gradient
    FX_TITLE="$P_TITLE"

    god_session_exists && resume=1

    # Animación de entrada (interrumpible; la terminal se restaura siempre)
    trap 'printf "\e[0m\e[?25h\e[?1049l"; exit 130' INT TERM HUP
    if (( use_anim )); then
        _god_engage_info "$resume"
        god_fx_engage "${GOD_INFO[@]}"
    fi

    if (( ! resume )); then
        local zcmd
        printf -v zcmd 'exec %q -i' "$GOD_ZSH_BIN"
        if ! god_tmux -f "${GOD_DIR}/tmux.conf" new-session -d -s "$GOD_SESSION" -c "$PWD" \
                -x "$UI_COLS" -y "$UI_ROWS" \
                env ZDOTDIR="${GOD_DIR}/zsh" URB_GOD=1 URB_GOD_DIR="$GOD_DIR" URB_HOME="$URB_HOME" \
                    URB_USER_ZDOTDIR="${ZDOTDIR:-$HOME}" URB_PROFILE="$P_PROFILE" URB_PROFILE_TAG="$P_TAG" \
                    URB_PROFILE_THEME="$P_THEME" URB_PROFILE_CMD="$P_CMD" "$GOD_ZSH_BIN" -i; then
            trap - INT TERM HUP
            msg_err "Could not start the ${P_NAME} tmux session."
            return 1
        fi
        # Nuevas ventanas/paneles: también la Zsh del perfil, en el directorio del panel.
        # Nota: set-environment/set-option NO aceptan el prefijo "=" de coincidencia
        # exacta (buscarían una sesión llamada "=red"); en este servidor privado
        # solo existen nuestras sesiones, así que se usa el nombre tal cual.
        local kv cfg_err=0
        for kv in "ZDOTDIR=${GOD_DIR}/zsh" "URB_GOD=1" "URB_GOD_DIR=${GOD_DIR}" "URB_HOME=${URB_HOME}" \
                  "URB_USER_ZDOTDIR=${ZDOTDIR:-$HOME}" "URB_PROFILE=${P_PROFILE}" "URB_PROFILE_TAG=${P_TAG}" \
                  "URB_PROFILE_THEME=${P_THEME}" "URB_PROFILE_CMD=${P_CMD}"; do
            god_tmux set-environment -t "$GOD_SESSION" "${kv%%=*}" "${kv#*=}" || cfg_err=1
        done
        god_tmux set-option -t "$GOD_SESSION" default-command "$zcmd" >/dev/null || cfg_err=1
        if [[ "$mouse" == "1" ]]; then god_tmux set-option -g mouse on >/dev/null || cfg_err=1; fi
        if (( cfg_err )); then
            # Sin reintentos: se informa. Si la sesión ya no existe, su shell terminó al arrancar.
            if god_session_exists; then
                msg_warn "${P_NAME}: could not fully configure the session (new windows may use your normal shell)."
            else
                trap - INT TERM HUP
                msg_err "The ${P_NAME} session ended right after starting: its shell exited."
                msg_dim "    Check your ~/.zshrc for an 'exit' or an error (try: zsh -i -c true)."
                return 1
            fi
        fi
    fi
    trap - INT TERM HUP

    # Guardar el título de la ventana y entrar (misma ventana de terminal)
    printf '\e[22;0t'
    god_tmux attach-session -t "=${GOD_SESSION}"
    rc=$?
    printf '\e[23;0t'

    # Cómo terminó la conexión (sin reintentos; solo se informa):
    #   sesión viva                  → desconexión (Ctrl+B d o ventana cerrada)
    #   sin sesión y attach = 0      → la sesión terminó: salió su última shell
    #                                  (exit, Ctrl+D) o alguien la cerró
    #   sin sesión y attach != 0     → el servidor tmux terminó de forma inesperada
    if god_session_exists; then
        if (( rc != 0 )); then
            msg_err "Could not attach to the ${P_NAME} session (tmux exit ${rc})."
            msg_dim "    The session is still running: '${P_CMD}' to retry, '${P_CMD} --kill' to end it."
            return 1
        fi
        (( use_anim )) && _god_fx_out "${P_TITLE} ${G_SEP} DETACHED"
        msg_info "Detached from ${P_NAME}: your programs keep running."
        msg_dim "    '${P_CMD}' to return · '${P_CMD} --kill' to end the session"
        return 0
    fi
    if (( rc != 0 )); then
        msg_err "The ${P_NAME} tmux server ended unexpectedly (tmux exit ${rc}). The session is gone."
        msg_dim "    This is not a normal detach; programs running in it were terminated."
        return 1
    fi
    (( use_anim )) && _god_fx_out "${P_TITLE} OFF"
    printf '%s%s %s off. Back to your terminal.%s\n' "$T_DIM" "$G_DIAM" "$P_NAME" "$C_RESET"
    msg_dim "    Session ended: its last shell exited (exit / Ctrl+D) or it was closed. Ctrl+B d detaches instead."
    return 0
}

god_main() {
    local action="start" anim_opt="" assume_yes=0 profile="god" help=0 attach_only=0
    while (( $# > 0 )); do
        case "$1" in
            -h|--help|help) help=1 ;;
            --no-anim)      anim_opt="--no-anim" ;;
            --status|status) action="status" ;;
            --kill|kill)    action="kill" ;;
            --check|check)  action="check" ;;
            --attach-only)  attach_only=1 ;;
            -y|--yes)       assume_yes=1 ;;
            --profile)      [[ $# -ge 2 ]] || { msg_err "--profile needs a value"; return 2; }; profile="$2"; shift ;;
            *) msg_err "Unknown option for 'urb god': $1"; msg_dim "    See: urb god --help"; return 2 ;;
        esac
        shift
    done
    god_load_profile "$profile" || return 2
    if (( help )); then god_help; return 0; fi
    if [[ ! "$GOD_SOCKET" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
        msg_err "Invalid URB_${P_TAG}_SOCKET name."; return 2
    fi
    case "$action" in
        start)  god_start "$anim_opt" "$attach_only" ;;
        status) god_status ;;
        kill)   god_kill "$assume_yes" ;;
        check)  god_check ;;
    esac
}

# Ejecución directa (bash godmode/god.sh) o desde `urb god`
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    urb_init_colors "${URB_COLOR:-auto}"
    urb_load_config
    ui_init_theme
    ui_load_logo
    god_main "$@"
    exit $?
fi
