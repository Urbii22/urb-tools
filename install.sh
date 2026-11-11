#!/usr/bin/env bash
# =============================================================================
#  install.sh — Instalador de URB-Tools (usuario, sin root)
#
#  - Comprueba sistema operativo, versión de Bash y dependencias.
#  - Informa de lo que falta y SOLO instala paquetes si lo confirmas (sudo apt).
#  - Copia la aplicación a ~/.local/lib/urb-tools y crea ~/.local/bin/urb.
#  - Idempotente: puede ejecutarse varias veces (actualiza la copia instalada).
#  - Nunca sobrescribe tu configuración ni tus datos.
#  - NO modifica .bashrc, .zshrc ni ningún otro archivo personal: si
#    ~/.local/bin no está en el PATH, te dice cómo añadirlo.
#
#  Uso: ./install.sh [--yes] [--no-deps] [--link] [--help]
# =============================================================================
set -uo pipefail

SRC_DIR="$(cd -P -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)" || exit 1
APP_DIR="${URB_APP_DIR:-$HOME/.local/lib/urb-tools}"
BIN_DIR="${URB_BIN_DIR:-$HOME/.local/bin}"
LAUNCHER="${BIN_DIR}/urb"
MARKER=".urb-install"

ASSUME_YES=0
INSTALL_DEPS=1
LINK_MODE=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    R=$'\e[0m' B=$'\e[1m' CY=$'\e[96m' GR=$'\e[92m' YE=$'\e[33m' RE=$'\e[31m' GY=$'\e[90m'
else
    R="" B="" CY="" GR="" YE="" RE="" GY=""
fi
info() { printf '%s[*]%s %s\n' "$CY" "$R" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '%s[!]%s %s\n' "$YE" "$R" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$RE" "$R" "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }

ask() {
    local ans
    (( ASSUME_YES )) && return 0
    if ! { : </dev/tty; } 2>/dev/null; then warn "No terminal: assuming 'no' for: $1"; return 1; fi
    printf '%s[?]%s %s [y/N] ' "$YE" "$R" "$1" >/dev/tty
    IFS= read -r ans </dev/tty || ans=""
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" || "${ans,,}" == "s" || "${ans,,}" == "si" ]]
}

usage() {
    cat <<EOF
URB-Tools installer

Usage: ./install.sh [options]

  -y, --yes      Answer yes to all questions (non-interactive)
      --no-deps  Do not offer to install missing packages
      --link     Developer mode: ~/.local/bin/urb points to this repository
                 (changes in the repo apply immediately; no copy)
  -h, --help     Show this help

Installs to:  ${APP_DIR}
Launcher:     ${LAUNCHER}
Never touches .bashrc/.zshrc, your config (~/.config/urb-tools) or data.
EOF
}

while (( $# > 0 )); do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --no-deps) INSTALL_DEPS=0 ;;
        --link) LINK_MODE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done

printf '\n%s%s  URB-Tools installer%s\n\n' "$B" "$CY" "$R"

# --- 1. Usuario --------------------------------------------------------------
if (( EUID == 0 )); then
    err "Do not run the installer as root. Run it as your normal user:"
    printf '      ./install.sh\n'
    printf '    sudo is only used (after asking) to install missing packages with apt.\n'
    exit 1
fi

# --- 2. Sistema operativo y Bash -----------------------------------------------
os_id="unknown" os_like="" os_name="unknown"
if [[ -r /etc/os-release ]]; then
    os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
    os_like="$(sed -n 's/^ID_LIKE=//p' /etc/os-release | tr -d '"')"
    os_name="$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"')"
fi
case "$os_id" in
    kali) ok "Operating system: ${os_name}" ;;
    *)
        if [[ " $os_id $os_like " == *" debian "* || " $os_like " == *" ubuntu "* ]]; then
            warn "Operating system: ${os_name} (not Kali; Debian-based, should work)"
        else
            warn "Operating system: ${os_name} (not Kali; untested)"
        fi ;;
esac
grep -qi microsoft /proc/version 2>/dev/null && info "WSL detected"

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    err "Bash >= 4.4 is required (found ${BASH_VERSION})."
    exit 1
fi
ok "Bash ${BASH_VERSION}"

# --- 3. Dependencias -------------------------------------------------------------
# comando:paquete
REQUIRED=("ip:iproute2" "ss:iproute2" "ps:procps" "df:coreutils" "awk:mawk" "sed:sed" "find:findutils" "tput:ncurses-bin")
OPTIONAL=("nmap:nmap" "fzf:fzf" "figlet:figlet" "curl:curl" "ping:iputils-ping" "less:less")
missing_req=() missing_opt=() pkgs=()
for e in "${REQUIRED[@]}"; do has "${e%%:*}" || { missing_req+=("${e%%:*}"); pkgs+=("${e#*:}"); }; done
for e in "${OPTIONAL[@]}"; do has "${e%%:*}" || { missing_opt+=("${e%%:*}"); pkgs+=("${e#*:}"); }; done

if (( ${#missing_req[@]} == 0 )); then ok "Required dependencies: all present"
else err "Missing required: ${missing_req[*]}"; fi
if (( ${#missing_opt[@]} == 0 )); then ok "Optional dependencies: all present"
else warn "Missing optional: ${missing_opt[*]}"; fi

if (( ${#pkgs[@]} > 0 )); then
    # Paquetes únicos
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
    if (( INSTALL_DEPS )) && has apt-get && has sudo; then
        if ask "Install missing packages with 'sudo apt-get install ${pkgs[*]}'?"; then
            if sudo apt-get update && sudo apt-get install -y "${pkgs[@]}"; then ok "Packages installed."
            else warn "Package installation failed; continuing. Install later with: sudo apt install ${pkgs[*]}"; fi
        else
            info "Skipped. Install later with: sudo apt install ${pkgs[*]}"
        fi
    else
        info "Install later with: sudo apt install ${pkgs[*]}"
    fi
    if (( ${#missing_req[@]} > 0 )); then
        for e in "${missing_req[@]}"; do has "$e" || { err "Required command still missing: ${e}. Aborting."; exit 1; }; done
    fi
fi

# --- 4. Copiar la aplicación --------------------------------------------------------
for f in bin/urb lib/utils.sh lib/ui.sh lib/system.sh lib/dashboard.sh config/default.conf; do
    [[ -f "${SRC_DIR}/${f}" ]] || { err "Incomplete source tree: missing ${f}"; exit 1; }
done

if (( LINK_MODE )); then
    TARGET_HOME="$SRC_DIR"
    info "Developer mode: launcher will point to ${SRC_DIR}"
else
    if [[ -e "$APP_DIR" && ! -f "${APP_DIR}/${MARKER}" ]]; then
        err "${APP_DIR} exists but was not created by this installer. Not touching it."
        exit 1
    fi
    if [[ "$(readlink -f -- "$APP_DIR" 2>/dev/null)" == "$SRC_DIR" ]]; then
        err "APP_DIR points to the source tree; refusing to overwrite."; exit 1
    fi
    staging="${APP_DIR}.new.$$"
    mkdir -p -- "$staging" || { err "Cannot create ${staging}"; exit 1; }
    if ! cp -R -- "${SRC_DIR}/bin" "${SRC_DIR}/lib" "${SRC_DIR}/modules" "${SRC_DIR}/config" "$staging/"; then
        rm -rf -- "$staging"; err "Copy failed."; exit 1
    fi
    for f in README.md LICENSE install.sh uninstall.sh; do
        [[ -f "${SRC_DIR}/${f}" ]] && cp -- "${SRC_DIR}/${f}" "$staging/"
    done
    printf 'installed=%s\nsource=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SRC_DIR" >"${staging}/${MARKER}"
    if [[ -d "$APP_DIR" ]]; then
        rm -rf -- "${APP_DIR:?}" || { rm -rf -- "$staging"; err "Cannot replace old install"; exit 1; }
        info "Updating existing installation"
    fi
    mv -- "$staging" "$APP_DIR" || { err "Cannot move files to ${APP_DIR}"; exit 1; }
    TARGET_HOME="$APP_DIR"
    ok "Application installed in ${APP_DIR}"
fi
chmod +x -- "${TARGET_HOME}/bin/urb" "${TARGET_HOME}"/modules/*.sh 2>/dev/null

# --- 5. Lanzador ----------------------------------------------------------------------
mkdir -p -- "$BIN_DIR" || { err "Cannot create ${BIN_DIR}"; exit 1; }
if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
    if [[ -L "$LAUNCHER" ]]; then
        cur="$(readlink -- "$LAUNCHER")"
        case "$cur" in
            */bin/urb) : ;;  # instalación previa de URB: se reemplaza
            *) err "${LAUNCHER} is a link to something else (${cur}). Not touching it."; exit 1 ;;
        esac
    else
        err "${LAUNCHER} exists and is not an URB launcher. Remove or rename it first."
        exit 1
    fi
fi
ln -sfn -- "${TARGET_HOME}/bin/urb" "$LAUNCHER" || { err "Cannot create ${LAUNCHER}"; exit 1; }
ok "Launcher: ${LAUNCHER} -> ${TARGET_HOME}/bin/urb"

# --- 6. Configuración y datos (nunca se sobrescriben) ------------------------------
"${TARGET_HOME}/bin/urb" --no-color config init >/dev/null 2>&1 \
    && ok "User config: ${XDG_CONFIG_HOME:-$HOME/.config}/urb-tools/urb.conf (kept if it already existed)" \
    || warn "Could not create user config (urb config init)."
mkdir -p -- "${XDG_DATA_HOME:-$HOME/.local/share}/urb-tools/scans" 2>/dev/null || true

# --- 7. Verificación y PATH -------------------------------------------------------------
if ver="$("${TARGET_HOME}/bin/urb" version 2>&1)"; then ok "Check: ${ver}"
else err "The installed launcher failed: ${ver}"; exit 1; fi

printf '\n'
if [[ ":${PATH}:" == *":${BIN_DIR}:"* ]]; then
    ok "${BIN_DIR} is in your PATH. Run:  urb"
else
    warn "${BIN_DIR} is NOT in your PATH. This installer does not edit your shell files."
    printf '    Add it yourself (Kali uses zsh by default):\n'
    printf '      %secho '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.zshrc && source ~/.zshrc%s\n' "$B" "$R"
    printf '    For bash:\n'
    printf '      %secho '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.bashrc && source ~/.bashrc%s\n' "$B" "$R"
    printf '    Or run it directly:  %s%s%s\n' "$B" "$LAUNCHER" "$R"
fi
printf '\n'
exit 0
