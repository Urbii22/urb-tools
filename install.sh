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
HELP_LAUNCHER="${BIN_DIR}/urb-help"
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
OPTIONAL=("nmap:nmap" "fzf:fzf" "figlet:figlet" "curl:curl" "ping:iputils-ping" "less:less" "tmux:tmux" "zsh:zsh" "python3:python3" "xclip:xclip")
# God Mode (urb god): solo necesita tmux y zsh; sin ellos, el resto funciona igual
GOD_FILES=(bin/urb-help lib/engine.sh modules/serve.sh commands/red-recon.spec commands/serve.spec docs/COMMANDS.md docs/EXAMPLES.md docs/ATAJOS.md godmode/god.sh godmode/session.sh modules/sessions.sh lib/findings.sh modules/findings.sh lib/scans.sh lib/nmap_services.py lib/investigation.py lib/blue_store.py lib/blue_ingest.py lib/blue_detect.py lib/blue_cli.py modules/blue.sh modules/inventory.sh godmode/tmux.conf godmode/zsh/.zshenv godmode/zsh/.zshrc godmode/hud/status.sh godmode/animations/fx.sh godmode/themes/urb.theme godmode/themes/god.theme godmode/themes/red.theme godmode/themes/blue.theme godmode/profiles/god.profile godmode/profiles/red.profile godmode/profiles/blue.profile lib/lab.sh lib/diagnose.sh modules/red.sh modules/layout.sh)
missing_req=() missing_opt=() pkgs=()
for e in "${REQUIRED[@]}"; do has "${e%%:*}" || { missing_req+=("${e%%:*}"); pkgs+=("${e#*:}"); }; done
for e in "${OPTIONAL[@]}"; do has "${e%%:*}" || { missing_opt+=("${e%%:*}"); pkgs+=("${e#*:}"); }; done

if (( ${#missing_req[@]} == 0 )); then ok "Required dependencies: all present"
else err "Missing required: ${missing_req[*]}"; fi
if (( ${#missing_opt[@]} == 0 )); then ok "Optional dependencies: all present"
else warn "Missing optional: ${missing_opt[*]}"
     if [[ " ${missing_opt[*]} " == *" tmux "* || " ${missing_opt[*]} " == *" zsh "* ]]; then
         info "tmux and zsh are only needed for God Mode (urb god); everything else works without them."
     fi
fi

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

# --- 4. Comprobaciones previas (antes de modificar nada) ---------------------------
for f in bin/urb lib/utils.sh lib/ui.sh lib/system.sh lib/dashboard.sh config/default.conf "${GOD_FILES[@]}"; do
    [[ -f "${SRC_DIR}/${f}" ]] || { err "Incomplete source tree: missing ${f}"; exit 1; }
done

# ¿Es <dir> una instalación de URB-Tools (marcador) o un árbol de código de URB-Tools?
is_urb_tree() {
    local dir="$1"
    [[ -f "${dir}/${MARKER}" ]] && return 0
    [[ -f "${dir}/bin/urb" && -f "${dir}/lib/utils.sh" ]] &&
        grep -q '^URB_NAME="URB-Tools"$' "${dir}/lib/utils.sh" 2>/dev/null
}

# Un enlace solo es "nuestro" si apunta a <dir>/bin/<nombre> y <dir> es de
# URB-Tools (instalación normal o modo --link). Un nombre acabado en /bin/urb
# no basta. <nombre>: urb (por defecto) o urb-help.
is_urb_launcher() {
    local link="$1" name="${2:-urb}" target
    [[ -L "$link" ]] || return 1
    target="$(readlink -- "$link")" || return 1
    [[ "$target" == */bin/"$name" ]] || return 1
    [[ "$target" == /* ]] || target="$(dirname -- "$link")/${target}"
    # Enlace roto hacia nuestra propia carpeta de instalación (borrada a mano)
    [[ "$target" == "${APP_DIR}/bin/${name}" ]] && return 0
    is_urb_tree "${target%/bin/"$name"}"
}

PREV_LAUNCHER=""
if [[ -L "$LAUNCHER" ]]; then
    if is_urb_launcher "$LAUNCHER"; then
        PREV_LAUNCHER="$(readlink -- "$LAUNCHER")"
    else
        err "${LAUNCHER} is a link to something that is not URB-Tools ($(readlink -- "$LAUNCHER")). Not touching it."
        exit 1
    fi
elif [[ -e "$LAUNCHER" ]]; then
    err "${LAUNCHER} exists and is not an URB launcher. Remove or rename it first."
    exit 1
fi

# Acceso directo urb-help: si hay algo ajeno con ese nombre, se respeta y se omite
PREV_HELP_LAUNCHER="" SKIP_HELP_LAUNCHER=0
if [[ -L "$HELP_LAUNCHER" ]]; then
    if is_urb_launcher "$HELP_LAUNCHER" urb-help; then PREV_HELP_LAUNCHER="$(readlink -- "$HELP_LAUNCHER")"
    else SKIP_HELP_LAUNCHER=1; warn "${HELP_LAUNCHER} belongs to something else; urb-help will not be installed (use: urb help)."; fi
elif [[ -e "$HELP_LAUNCHER" ]]; then
    SKIP_HELP_LAUNCHER=1; warn "${HELP_LAUNCHER} exists and is not ours; urb-help will not be installed (use: urb help)."
fi

if (( ! LINK_MODE )); then
    if [[ -e "$APP_DIR" && ! -f "${APP_DIR}/${MARKER}" ]]; then
        err "${APP_DIR} exists but was not created by this installer. Not touching it."
        exit 1
    fi
    if [[ "$(readlink -f -- "$APP_DIR" 2>/dev/null)" == "$SRC_DIR" ]]; then
        err "APP_DIR points to the source tree; refusing to overwrite."; exit 1
    fi
fi

# verify_tree DIR [requiere_marcador] → ficheros clave, sintaxis y arranque real
verify_tree() {
    local dir="$1" need_marker="${2:-1}" f
    for f in bin/urb lib/utils.sh lib/ui.sh lib/system.sh lib/dashboard.sh config/default.conf "${GOD_FILES[@]}"; do
        [[ -f "${dir}/${f}" ]] || { err "Verification failed: missing ${f} in ${dir}"; return 1; }
    done
    if (( need_marker )) && [[ ! -f "${dir}/${MARKER}" ]]; then err "Verification failed: missing ${MARKER}"; return 1; fi
    for f in "${dir}/bin/urb" "${dir}"/lib/*.sh "${dir}"/modules/*.sh "${dir}"/godmode/*.sh "${dir}"/godmode/hud/*.sh "${dir}"/godmode/animations/*.sh; do
        bash -n -- "$f" 2>/dev/null || { err "Verification failed: syntax error in ${f}"; return 1; }
    done
    # Configuración Zsh de God Mode (solo si zsh está instalado)
    if has zsh; then
        for f in "${dir}/godmode/zsh/.zshenv" "${dir}/godmode/zsh/.zshrc"; do
            zsh -n -- "$f" 2>/dev/null || { err "Verification failed: zsh syntax error in ${f}"; return 1; }
        done
    fi
    # Analizador de XML de nmap (solo si python3 está instalado)
    if has python3; then
        python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "${dir}/lib/nmap_services.py" 2>/dev/null \
            || { err "Verification failed: syntax error in lib/nmap_services.py"; return 1; }
        python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "${dir}/lib/investigation.py" 2>/dev/null \
            || { err "Verification failed: syntax error in lib/investigation.py"; return 1; }
    fi
    "${dir}/bin/urb" --no-color version >/dev/null 2>&1 || { err "Verification failed: ${dir}/bin/urb does not run"; return 1; }
    "${dir}/bin/urb" --no-color god --help >/dev/null 2>&1 || { err "Verification failed: 'urb god --help' does not run"; return 1; }
    "${dir}/bin/urb" --no-color red --help >/dev/null 2>&1 || { err "Verification failed: 'urb red --help' does not run"; return 1; }
    "${dir}/bin/urb" --no-color help red recon >/dev/null 2>&1 || { err "Verification failed: command specs (commands/*.spec) do not load"; return 1; }
    return 0
}

# --- 5. Instalación transaccional -----------------------------------------------------
# Nada de la instalación anterior se toca hasta que la nueva está copiada y verificada.
# La anterior se conserva como copia temporal y se restaura si falla cualquier paso.
# La configuración y los datos personales (~/.config, ~/.local/share, labs) nunca se tocan.
STAGING="" BACKUP="" TXN=0 NEW_APP=0

rollback() {
    (( TXN )) || return 0
    TXN=0
    trap - INT TERM HUP
    warn "Installation failed: restoring the previous state..."
    if (( NEW_APP )); then
        # Quitar la versión nueva (solo si es nuestra) y devolver la anterior a su sitio
        if [[ -f "${APP_DIR}/${MARKER}" ]]; then rm -rf -- "${APP_DIR:?}"; fi
        if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
            if [[ ! -e "$APP_DIR" ]] && mv -- "$BACKUP" "$APP_DIR"; then ok "Previous installation restored in ${APP_DIR}"
            else err "Could not restore ${APP_DIR}. The previous version is kept in ${BACKUP}"; fi
        fi
    elif [[ -n "$BACKUP" && -d "$BACKUP" && ! -e "$APP_DIR" ]]; then
        mv -- "$BACKUP" "$APP_DIR" && ok "Previous installation restored in ${APP_DIR}"
    fi
    if [[ -n "$PREV_LAUNCHER" ]]; then
        ln -sfn -- "$PREV_LAUNCHER" "$LAUNCHER" 2>/dev/null || err "Could not restore ${LAUNCHER} -> ${PREV_LAUNCHER}"
    elif [[ -L "$LAUNCHER" ]] && is_urb_launcher "$LAUNCHER"; then
        rm -f -- "$LAUNCHER"   # lo creó esta ejecución
    fi
    if (( ! SKIP_HELP_LAUNCHER )); then
        if [[ -n "$PREV_HELP_LAUNCHER" ]]; then
            ln -sfn -- "$PREV_HELP_LAUNCHER" "$HELP_LAUNCHER" 2>/dev/null || err "Could not restore ${HELP_LAUNCHER}"
        elif [[ -L "$HELP_LAUNCHER" ]] && is_urb_launcher "$HELP_LAUNCHER" urb-help; then
            rm -f -- "$HELP_LAUNCHER"
        fi
    fi
    [[ -n "$STAGING" && -d "$STAGING" ]] && rm -rf -- "$STAGING"
    return 0
}
fail() { err "$*"; rollback; exit 1; }

if (( LINK_MODE )); then
    TARGET_HOME="$SRC_DIR"
    info "Developer mode: launcher will point to ${SRC_DIR}"
    chmod +x -- "${SRC_DIR}/bin/urb" "${SRC_DIR}/bin/urb-help" "${SRC_DIR}"/modules/*.sh "${SRC_DIR}"/godmode/god.sh "${SRC_DIR}"/godmode/hud/status.sh 2>/dev/null
    verify_tree "$SRC_DIR" 0 || exit 1
else
    # 5a. Preparar y verificar la nueva versión en una carpeta temporal
    STAGING="${APP_DIR}.new.$$"
    mkdir -p -- "$STAGING" || { err "Cannot create ${STAGING}"; exit 1; }
    if ! cp -R -- "${SRC_DIR}/bin" "${SRC_DIR}/lib" "${SRC_DIR}/modules" "${SRC_DIR}/config" "${SRC_DIR}/godmode" "${SRC_DIR}/commands" "${SRC_DIR}/docs" "$STAGING/"; then
        rm -rf -- "$STAGING"; err "Copy failed."; exit 1
    fi
    for f in README.md LICENSE install.sh uninstall.sh; do
        [[ -f "${SRC_DIR}/${f}" ]] && cp -- "${SRC_DIR}/${f}" "$STAGING/"
    done
    printf 'installed=%s\nsource=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SRC_DIR" >"${STAGING}/${MARKER}"
    chmod +x -- "${STAGING}/bin/urb" "${STAGING}/bin/urb-help" "${STAGING}"/modules/*.sh "${STAGING}"/godmode/god.sh "${STAGING}"/godmode/hud/status.sh 2>/dev/null
    if ! verify_tree "$STAGING" 1; then
        rm -rf -- "$STAGING"; err "New version not installed; the existing installation was not modified."; exit 1
    fi

    # 5b. Sustitución: anterior → copia temporal, nueva → su sitio
    TXN=1
    trap 'rollback; exit 130' INT TERM HUP
    mkdir -p -- "$(dirname -- "$APP_DIR")" || fail "Cannot create $(dirname -- "$APP_DIR")"
    if [[ -d "$APP_DIR" ]]; then
        BACKUP="${APP_DIR}.old.$$"
        mv -- "$APP_DIR" "$BACKUP" || { BACKUP=""; fail "Cannot move the previous installation aside; nothing was changed."; }
        info "Updating existing installation (previous version kept until success)"
    fi
    mv -- "$STAGING" "$APP_DIR" || fail "Cannot move files to ${APP_DIR}"
    STAGING=""
    NEW_APP=1
    TARGET_HOME="$APP_DIR"
    ok "Application installed in ${APP_DIR}"
fi
TXN=1
trap 'rollback; exit 130' INT TERM HUP

# --- 6. Lanzador ------------------------------------------------------------------------
mkdir -p -- "$BIN_DIR" || fail "Cannot create ${BIN_DIR}"
ln -sfn -- "${TARGET_HOME}/bin/urb" "$LAUNCHER" || fail "Cannot create ${LAUNCHER}"
ok "Launcher: ${LAUNCHER} -> ${TARGET_HOME}/bin/urb"
if (( ! SKIP_HELP_LAUNCHER )); then
    ln -sfn -- "${TARGET_HOME}/bin/urb-help" "$HELP_LAUNCHER" || fail "Cannot create ${HELP_LAUNCHER}"
    ok "Launcher: ${HELP_LAUNCHER} -> ${TARGET_HOME}/bin/urb-help"
fi

# --- 7. Verificación final a través del lanzador ----------------------------------------
if ver="$("$LAUNCHER" --no-color version 2>&1)"; then ok "Check: ${ver}"
else fail "The installed launcher failed: ${ver}"; fi

# Éxito: cerrar la transacción y borrar la copia temporal de la versión anterior
TXN=0
trap - INT TERM HUP
if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
    rm -rf -- "$BACKUP" || warn "Could not remove the temporary backup ${BACKUP}; you can delete it."
fi

# --- 8. Configuración y datos (nunca se sobrescriben) ------------------------------
"${TARGET_HOME}/bin/urb" --no-color config init >/dev/null 2>&1 \
    && ok "User config: ${XDG_CONFIG_HOME:-$HOME/.config}/urb-tools/urb.conf (kept if it already existed)" \
    || warn "Could not create user config (urb config init)."
mkdir -p -- "${XDG_DATA_HOME:-$HOME/.local/share}/urb-tools/scans" 2>/dev/null || true

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
