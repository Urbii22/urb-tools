#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/settings.sh — SETTINGS: configuración de usuario y diagnóstico
#  CLI: urb config [show|path|init|edit|set CLAVE VALOR]  ·  urb doctor
# =============================================================================

[[ -n "${_URB_SETTINGS_LOADED:-}" ]] && return 0
_URB_SETTINGS_LOADED=1

settings_help() {
    cat <<EOF
${C_BOLD}urb config${C_RESET} — configuration

${C_BOLD}USAGE${C_RESET}
  urb config show            Effective configuration (defaults + yours)
  urb config path            Paths used by URB-Tools
  urb config init            Create your config file from the defaults (never overwrites)
  urb config edit            Open your config in \$EDITOR (nano / vi fallback)
  urb config set KEY VALUE   Change one value in your config
  urb doctor                 Check dependencies and environment

User config: ${URB_CONFIG_FILE:-$URB_USER_CONFIG}
EOF
}

settings_paths() {
    msg_section "PATHS"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "Install" "$C_RESET" "$URB_HOME"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "Defaults" "$C_RESET" "${URB_HOME}/config/default.conf"
    printf '  %s%-14s%s %s %s\n' "$T_LABEL" "User config" "$C_RESET" "${URB_CONFIG_FILE:-$URB_USER_CONFIG}" \
        "$( [[ -f "${URB_CONFIG_FILE:-$URB_USER_CONFIG}" ]] && printf '%s(exists)%s' "$T_OK" "$C_RESET" || printf '%s(not created)%s' "$T_DIM" "$C_RESET")"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "Scan results" "$C_RESET" "$(urb_scan_dir)"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "CTF labs" "$C_RESET" "$(urb_labs_dir)"
}

settings_show() {
    local k
    msg_section "CONFIGURATION"
    while IFS= read -r k; do
        printf '  %s%-24s%s %s\n' "$T_KEY" "$k" "$C_RESET" "${URB_CFG[$k]}"
    done < <(printf '%s\n' "${!URB_CFG[@]}" | sort)
}

settings_init() {
    local f="${URB_CONFIG_FILE:-$URB_USER_CONFIG}"
    if [[ -e "$f" ]]; then msg_info "Config already exists (not modified): ${f}"; return 0; fi
    mkdir -p -- "$(dirname -- "$f")" || { msg_err "Cannot create $(dirname -- "$f")"; return 1; }
    {
        printf '# URB-Tools — user configuration (overrides %s)\n' "${URB_HOME}/config/default.conf"
        printf '# Uncomment and change what you need.\n\n'
        sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' -e 's/^/# /' "${URB_HOME}/config/default.conf"
    } >"$f" || { msg_err "Cannot write ${f}"; return 1; }
    msg_ok "Config created: ${f}"
}

settings_edit() {
    local f="${URB_CONFIG_FILE:-$URB_USER_CONFIG}" ed="${VISUAL:-${EDITOR:-}}"
    [[ -e "$f" ]] || settings_init || return 1
    if [[ -z "$ed" ]]; then
        if has_cmd nano; then ed="nano"; elif has_cmd vi; then ed="vi"; else msg_err "No editor found. Set \$EDITOR."; return 1; fi
    fi
    # $EDITOR puede llevar argumentos ("code -w"): se separan sin eval
    local -a cmd
    read -ra cmd <<<"$ed"
    has_cmd "${cmd[0]}" || { msg_err "Editor not found: ${cmd[0]}"; return 1; }
    "${cmd[@]}" "$f"
}

urb_doctor() {
    local t pkg ok=0 miss=0
    msg_section "URB DOCTOR"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "Version" "$C_RESET" "$URB_VERSION"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "Bash" "$C_RESET" "$BASH_VERSION"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "OS" "$C_RESET" "$(sys_os)$(sys_is_wsl && printf ' (WSL)')"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "Terminal" "$C_RESET" "${TERM:-unknown} $( [[ -t 1 ]] && printf '%sx%s' "$(tput cols 2>/dev/null)" "$(tput lines 2>/dev/null)")"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "Locale UTF-8" "$C_RESET" "$(urb_is_utf8 && echo yes || echo 'no (ASCII mode)')"
    printf '  %s%-14s%s %s\n' "$T_LABEL" "Colors" "$C_RESET" "$( (( URB_256 )) && echo 256 || echo basic)"
    msg_section "DEPENDENCIES"
    local -a req=("ip:iproute2" "ss:iproute2" "ps:procps" "df:coreutils" "awk:mawk" "tput:ncurses-bin")
    local -a opt=("nmap:nmap:RECON scans, host discovery" "fzf:fzf:alternative menu engine" "figlet:figlet:figlet logo style" \
                  "curl:curl:HTTPS connectivity check" "ping:iputils-ping:ping / gateway checks" "journalctl:systemd:log analysis without auth.log" \
                  "less:less:log paging" "sudo:sudo:privileged nmap profiles" \
                  "tmux:tmux:God Mode (urb god)" "zsh:zsh:God Mode (urb god)" \
                  "python3:python3:URB Red service inventory (urb red services)")
    for t in "${req[@]}"; do
        pkg="${t#*:}"; t="${t%%:*}"
        if has_cmd "$t"; then ok=$(( ok + 1 )); printf '  %s%s%s %-12s %srequired%s\n' "$T_OK" "$G_OK" "$C_RESET" "$t" "$T_DIM" "$C_RESET"
        else miss=$(( miss + 1 )); printf '  %s%s%s %-12s %srequired — sudo apt install %s%s\n' "$T_BAD" "$G_BAD" "$C_RESET" "$t" "$T_BAD" "$pkg" "$C_RESET"; fi
    done
    local desc
    for t in "${opt[@]}"; do
        desc="${t##*:}"; pkg="${t#*:}"; pkg="${pkg%%:*}"; t="${t%%:*}"
        if has_cmd "$t"; then printf '  %s%s%s %-12s %s%s%s\n' "$T_OK" "$G_OK" "$C_RESET" "$t" "$T_DIM" "$desc" "$C_RESET"
        else printf '  %s-%s %-12s %soptional: %s (sudo apt install %s)%s\n' "$T_WARN" "$C_RESET" "$t" "$T_DIM" "$desc" "$pkg" "$C_RESET"; fi
    done
    msg_section "PATH"
    if [[ ":${PATH}:" == *":${HOME}/.local/bin:"* ]]; then msg_ok "~/.local/bin is in PATH"
    else msg_warn "~/.local/bin is NOT in PATH (see README: 'Añadir ~/.local/bin al PATH')"; fi
    printf '\n'
    (( miss == 0 )) && msg_ok "All required dependencies present." || msg_err "${miss} required dependency(ies) missing."
    return $(( miss > 0 ))
}

settings_main() {
    local action="${1:-show}"
    (( $# > 0 )) && shift
    case "$action" in
        show)  settings_paths; settings_show ;;
        path|paths) settings_paths ;;
        init)  settings_init ;;
        edit)  settings_edit ;;
        set)
            [[ $# -eq 2 ]] || { msg_err "Usage: urb config set KEY VALUE"; return 2; }
            config_set "$1" "$2" && msg_ok "${1}=\"${2}\" saved in ${URB_CONFIG_FILE:-$URB_USER_CONFIG}" ;;
        -h|--help|help) settings_help ;;
        *) msg_err "Unknown config action: ${action}"; msg_dim "    See: urb help config"; return 2 ;;
    esac
}

settings_menu() {
    local anim
    while :; do
        if cfg_bool ANIMATIONS 1; then anim="on"; else anim="off"; fi
        ui_menu "SETTINGS" "Configuration" \
            "Show config|Effective configuration and paths" \
            "Edit config|Open your config file in \$EDITOR" \
            "Animations|Toggle animations (now: ${anim})" \
            "Menu engine|Toggle builtin / fzf (now: $(cfg MENU_ENGINE builtin))" \
            "Doctor|Check dependencies and environment" \
            "Back|Return to dashboard" || return 0
        case "$UI_CHOICE" in
            0) settings_paths; settings_show ;;
            1) settings_edit; urb_load_config; continue ;;
            2) if [[ "$anim" == "on" ]]; then config_set ANIMATIONS 0; else config_set ANIMATIONS 1; fi
               msg_ok "Animations: $( cfg_bool ANIMATIONS 1 && echo on || echo off). Applies to the dashboard on next start." ;;
            3) if [[ "$(cfg MENU_ENGINE builtin)" == "fzf" ]]; then config_set MENU_ENGINE builtin
               elif has_cmd fzf; then config_set MENU_ENGINE fzf
               else msg_warn "fzf is not installed (sudo apt install fzf)."; fi
               msg_ok "Menu engine: $(cfg MENU_ENGINE builtin)" ;;
            4) urb_doctor ;;
            *) return 0 ;;
        esac
        ui_pause
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    URB_HOME="$(cd -P -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)" || exit 1
    # shellcheck source=../lib/utils.sh
    source "${URB_HOME}/lib/utils.sh" && urb_standalone_init || exit 1
    settings_main "$@"
    exit $?
fi
