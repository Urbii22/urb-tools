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

found=0
[[ -L "$LAUNCHER" ]] && found=1
[[ -f "${APP_DIR}/${MARKER}" ]] && found=1
if (( ! found )); then info "URB-Tools does not seem to be installed for this user. Nothing to do."; exit 0; fi

if (( ! ASSUME_YES )); then
    if ! { : </dev/tty; } 2>/dev/null; then err "No terminal to confirm. Use --yes."; exit 1; fi
    printf '%s[?]%s Remove the urb launcher and %s? [y/N] ' "$YE" "$R" "$APP_DIR" >/dev/tty
    IFS= read -r ans </dev/tty || ans=""
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" || "${ans,,}" == "s" ]] || { info "Cancelled."; exit 0; }
fi

rc=0
if [[ -L "$LAUNCHER" ]]; then
    target="$(readlink -- "$LAUNCHER")"
    case "$target" in
        */bin/urb) rm -f -- "$LAUNCHER" && ok "Removed launcher ${LAUNCHER}" || { err "Cannot remove ${LAUNCHER}"; rc=1; } ;;
        *) warn "${LAUNCHER} points to ${target}; not an URB launcher, left untouched." ;;
    esac
elif [[ -e "$LAUNCHER" ]]; then
    warn "${LAUNCHER} is not a symlink created by the installer; left untouched."
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
