#!/usr/bin/env bash
# =============================================================================
#  uninstall.sh — Desinstalador de URB-Tools
#  Elimina SOLO lo que creó install.sh: el lanzador ~/.local/bin/urb y la
#  copia de la aplicación en ~/.local/lib/urb-tools.
#  Conserva tu configuración, resultados de escaneo y laboratorios CTF.
#  Uso: ./uninstall.sh [--yes]
# =============================================================================
set -uo pipefail

APP_DIR="${URB_APP_DIR:-$HOME/.local/lib/urb-tools}"
BIN_DIR="${URB_BIN_DIR:-$HOME/.local/bin}"
LAUNCHER="${BIN_DIR}/urb"
HELP_LAUNCHER="${BIN_DIR}/urb-help"
MARKER=".urb-install"
ASSUME_YES=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then R=$'\e[0m' GR=$'\e[92m' YE=$'\e[33m' RE=$'\e[31m' CY=$'\e[96m'
else R="" GR="" YE="" RE="" CY=""; fi
ok()   { printf '%s[+]%s %s\n' "$GR" "$R" "$*"; }
info() { printf '%s[*]%s %s\n' "$CY" "$R" "$*"; }
warn() { printf '%s[!]%s %s\n' "$YE" "$R" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$RE" "$R" "$*" >&2; }

case "${1:-}" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) printf 'Usage: ./uninstall.sh [--yes]\nRemoves the urb launcher and %s. Keeps config and data.\n' "$APP_DIR"; exit 0 ;;
    "") ;;
    *) err "Unknown option: $1"; exit 2 ;;
esac

(( EUID == 0 )) && { err "Run as your normal user, not root."; exit 1; }

# Misma comprobación que install.sh: un enlace solo es de URB-Tools si apunta a
# <dir>/bin/urb y <dir> es una instalación (marcador) o un árbol de código de URB-Tools.
is_urb_tree() {
    local dir="$1"
    [[ -f "${dir}/${MARKER}" ]] && return 0
    [[ -f "${dir}/bin/urb" && -f "${dir}/lib/utils.sh" ]] &&
        grep -q '^URB_NAME="URB-Tools"$' "${dir}/lib/utils.sh" 2>/dev/null
}
is_urb_launcher() {
    local link="$1" name="${2:-urb}" target
    [[ -L "$link" ]] || return 1
    target="$(readlink -- "$link")" || return 1
    [[ "$target" == */bin/"$name" ]] || return 1
    [[ "$target" == /* ]] || target="$(dirname -- "$link")/${target}"
    [[ "$target" == "${APP_DIR}/bin/${name}" ]] && return 0
    is_urb_tree "${target%/bin/"$name"}"
}

found=0
is_urb_launcher "$LAUNCHER" && found=1
is_urb_launcher "$HELP_LAUNCHER" urb-help && found=1
[[ -f "${APP_DIR}/${MARKER}" ]] && found=1
if (( ! found )); then info "URB-Tools does not seem to be installed for this user. Nothing to do."; exit 0; fi

# God Mode: una sesión abierta NO se cierra (podría tener trabajo en marcha); solo se avisa
for _p in "God Mode|${URB_GOD_SOCKET:-urb-god}|urb god" "URB Red|${URB_RED_SOCKET:-urb-red}|urb red"; do
    IFS='|' read -r _pname _psock _pcmd <<<"$_p"
    if command -v tmux >/dev/null 2>&1 && tmux -L "$_psock" has-session 2>/dev/null; then
        warn "A ${_pname} session is still running. It will NOT be closed: your programs keep running,"
        warn "but its HUD and new windows will stop working once the files are removed."
        printf '    To end it first:  %s --kill   (or type exit inside it)\n' "$_pcmd"
    fi
done
unset _p _pname _psock _pcmd

if (( ! ASSUME_YES )); then
    if ! { : </dev/tty; } 2>/dev/null; then err "No terminal to confirm. Use --yes."; exit 1; fi
    printf '%s[?]%s Remove the urb launcher and %s? [y/N] ' "$YE" "$R" "$APP_DIR" >/dev/tty
    IFS= read -r ans </dev/tty || ans=""
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" || "${ans,,}" == "s" ]] || { info "Cancelled."; exit 0; }
fi

rc=0
if is_urb_launcher "$LAUNCHER"; then
    if rm -f -- "$LAUNCHER"; then ok "Removed launcher ${LAUNCHER}"; else err "Cannot remove ${LAUNCHER}"; rc=1; fi
elif [[ -L "$LAUNCHER" ]]; then
    warn "${LAUNCHER} points to $(readlink -- "$LAUNCHER"); not an URB launcher, left untouched."
elif [[ -e "$LAUNCHER" ]]; then
    warn "${LAUNCHER} is not a symlink created by the installer; left untouched."
fi
# Acceso directo urb-help: solo si es nuestro
if is_urb_launcher "$HELP_LAUNCHER" urb-help; then
    if rm -f -- "$HELP_LAUNCHER"; then ok "Removed launcher ${HELP_LAUNCHER}"; else err "Cannot remove ${HELP_LAUNCHER}"; rc=1; fi
elif [[ -e "$HELP_LAUNCHER" || -L "$HELP_LAUNCHER" ]]; then
    warn "${HELP_LAUNCHER} is not an URB launcher; left untouched."
fi

if [[ -f "${APP_DIR}/${MARKER}" ]]; then
    rm -rf -- "${APP_DIR:?}" && ok "Removed ${APP_DIR}" || { err "Cannot remove ${APP_DIR}"; rc=1; }
elif [[ -d "$APP_DIR" ]]; then
    warn "${APP_DIR} has no installer marker; left untouched."
fi

printf '\nKept (your personal data). Delete manually only if you want to:\n'
printf '  config:  %s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/urb-tools"
printf '  data:    %s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/urb-tools"
printf '  labs:    %s (or your LABS_DIR)\n' "$HOME/urb-labs"
exit "$rc"
