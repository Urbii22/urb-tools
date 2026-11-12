#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/red.sh — URB Red v0.1: perfil para laboratorios de ciberseguridad
#
#  Piezas (separadas a propósito):
#   - Perfil visual (shell): godmode/god.sh --profile red  → `urb red`
#   - Contexto de laboratorio y objetivo: lib/lab.sh (.urb-lab + active-lab)
#   - Ejecución: `recon initial` envuelve scan_main (modules/scan.sh)
#   - Registro de resultados: carpeta scans/ del laboratorio
#   - Diagnóstico: lib/diagnose.sh
#
#  No lanza nada en segundo plano, no usa root por defecto y no ejecuta datos.
# =============================================================================

[[ -n "${_URB_RED_LOADED:-}" ]] && return 0
_URB_RED_LOADED=1

red_help() {
    cat <<EOF
${C_BOLD}urb red${C_RESET} — URB Red: lab-focused shell profile (v0.1)

${C_BOLD}SHELL${C_RESET}
  urb red                         Open URB Red (real zsh + tmux, red HUD and prompt)
  urb red --no-anim               Open without animations
  urb red --kill [--yes]          End the URB Red session (God Mode is not affected)
  urb red --session               Show whether a URB Red session is running

${C_BOLD}LABS${C_RESET} (same workspaces as 'urb ctf')
  urb red lab new <name> [--target <ip|host>]   Create a lab and select it
  urb red lab use <name>                        Select an existing lab
  urb red lab list                              List labs (* = selected)
  urb red lab path [<name>]                     Print a lab path
  urb red status                                Lab, target, scans, VPN and session

${C_BOLD}TARGET${C_RESET}
  urb red target set <ip|host>    Save the lab's main target (.urb-lab)
  urb red target show             Show it

${C_BOLD}RECON${C_RESET}
  urb red recon initial [--target <ip|host>]
                                  nmap 'default' profile (-sV) against the lab target;
                                  results go to <lab>/scans/. --target overrides the
                                  saved target for this run only (it is not saved).

${C_BOLD}FINDINGS${C_RESET} (one file per finding in <lab>/findings/)
  urb red findings [list]                       Compact list with a summary
  urb red findings add "<title>" [--desc "<text>"] [--status <state>]
  urb red findings show F-001                   Details, notes, evidence and history
  urb red findings status F-001 <state>         Change state (recorded in the history)
  urb red findings note F-001 "<text>"          Timestamped note on that finding
  urb red findings evidence F-001 <file>        Link a file inside the lab (reference only)
  urb red findings evidence F-001 --scan latest Link the .nmap of a scan (latest | S-001)

  States: pending · investigating · suspected (hypothesis, not verified)
          confirmed (verified with evidence; not necessarily a vulnerability)
          discarded (hypothesis tested and ruled out)
          checked (check done, nothing found)

${C_BOLD}SCANS${C_RESET} (nmap results already saved in <lab>/scans/; nothing is re-run)
  urb red scans [list]                          Scans with stable IDs (S-001...)
  urb red scans show [latest|S-001]             Details, files and ports
  latest = most recent COMPLETE scan (interrupted or failed scans are not used)

${C_BOLD}SERVICES${C_RESET} (inventory built from the nmap XML files; no network traffic)
  urb red services [list] [--all]               Open ports by default; --all for every state
  urb red services show <port|host:port[/proto]>
  urb red services refresh                      Rebuild the inventory from the XML files
  An open port is inventory, not a finding.

${C_BOLD}NOTES${C_RESET} (the lab's notes/notes.md)
  urb red notes                                 Show the general notes
  urb red notes add "<text>"                    Append a timestamped line
  urb red notes edit                            Open notes.md in \$EDITOR

${C_BOLD}CONTEXT RULES${C_RESET}
  The lab is taken from the current directory (a .urb-lab in it or a parent);
  if there is none, from the lab selected with 'urb red lab use'.
  Inside URB Red, ${T_KEY}urblab${C_RESET} [name] changes the shell's directory to the lab.

${T_WARN}Only scan systems you are explicitly authorized to test.${C_RESET}
EOF
}

# Describe de dónde sale el laboratorio
_red_lab_source_txt() {
    case "$LAB_SOURCE" in
        directory) printf 'from current directory' ;;
        active)    printf 'selected with urb red lab use' ;;
        *)         printf '%s' "$LAB_SOURCE" ;;
    esac
}

# Exige un laboratorio resuelto; explica qué hacer si no lo hay
_red_require_lab() {
    if lab_resolve "$PWD"; then return 0; fi
    if [[ "$LAB_ERR" == "selected lab is no longer valid"* ]]; then
        msg_err "The ${LAB_ERR#selected }"
        msg_dim "    Select another lab: urb red lab use <name>  (or: urb red lab list)"
    else
        msg_err "No lab: you are not inside a lab and none is selected."
        msg_dim "    Create one:  urb red lab new <name> --target <ip>"
        msg_dim "    Or select:   urb red lab use <name>"
    fi
    return 1
}

_red_kv() { printf '  %s%-9s%s %s\n' "$T_LABEL" "$1" "$C_RESET" "$2"; }

# --- Laboratorios ------------------------------------------------------------------------
red_lab() {
    local action="${1:-}" name="" target="" base path old
    (( $# > 0 )) && shift
    base="$(urb_labs_dir)"
    case "$action" in
        new|create)
            while (( $# > 0 )); do
                case "$1" in
                    --target) [[ $# -ge 2 ]] || { msg_err "--target needs a value"; return 2; }; target="$2"; shift 2 ;;
                    --dir)    [[ $# -ge 2 ]] || { msg_err "--dir needs a value"; return 2; }; base="$(urb_expand_path "$2")"; shift 2 ;;
                    -*) msg_err "Unknown option: $1"; return 2 ;;
                    *)  [[ -z "$name" ]] || { msg_err "Unexpected argument: $1"; return 2; }; name="$1"; shift ;;
                esac
            done
            [[ -n "$name" ]] || { msg_err "Missing lab name. Usage: urb red lab new <name> --target <ip>"; return 2; }
            if [[ -n "$target" ]] && ! is_valid_target "$target"; then msg_err "Invalid target: '${target}'"; return 2; fi
            path="${base%/}/${name}"
            # Un lab existente conserva su objetivo: no se sobrescribe aquí
            if lab_is_lab "$path"; then
                old="$(lab_target_get "$path" 2>/dev/null)" || old=""
            fi
            ctf_create "$base" "$name" "$target" || return $?
            path="$(cd -P -- "$path" && pwd -P)" || return 1
            if [[ -n "$target" ]]; then
                old="$(lab_target_get "$path" 2>/dev/null)" || old=""
                if [[ -z "$old" ]]; then
                    lab_target_set "$path" "$target" || return $?
                elif [[ "$old" != "$target" ]]; then
                    msg_warn "Lab already had target ${old}: kept. To change it: urb red target set ${target}"
                fi
            fi
            lab_active_set "$path" || return 1
            msg_ok "Active lab: $(lab_name "$path")$(t="$(lab_target_get "$path" 2>/dev/null)"; [[ -n "$t" ]] && printf ' · target %s' "$t")"
            ;;
        use|select)
            [[ $# -eq 1 ]] || { msg_err "Usage: urb red lab use <name>"; return 2; }
            path="$(lab_by_name "$1")" || { msg_err "${LAB_ERR}"; msg_dim "    See: urb red lab list"; return 1; }
            lab_active_set "$path" || return 1
            msg_ok "Active lab: $(lab_name "$path") (${path})"
            old="$(lab_target_get "$path" 2>/dev/null)" || old=""
            _red_kv "Target" "${old:-not set (urb red target set <ip>)}"
            ;;
        list|ls)
            [[ $# -eq 0 ]] || { msg_err "Usage: urb red lab list"; return 2; }
            ctf_list "$base"
            if _lab_active_read; then msg_dim "  Selected: $(lab_name "$LAB_ACTIVE")  (${LAB_ACTIVE})"
            elif [[ "$LAB_ERR" == "selected lab is no longer valid"* ]]; then msg_warn "The ${LAB_ERR#selected }"
            fi
            ;;
        path)
            (( $# <= 1 )) || { msg_err "Usage: urb red lab path [<name>]"; return 2; }
            if [[ $# -eq 1 ]]; then
                path="$(lab_by_name "$1")" || { msg_err "${LAB_ERR}"; return 1; }
            else
                _red_require_lab || return 1
                path="$LAB_ROOT"
            fi
            printf '%s\n' "$path"
            ;;
        ""|-h|--help|help) red_help; return 0 ;;
        *) msg_err "Unknown lab action: ${action}"; msg_dim "    See: urb red --help"; return 2 ;;
    esac
}

# --- Objetivo ------------------------------------------------------------------------------
red_target() {
    local action="${1:-}" t old
    (( $# > 0 )) && shift
    case "$action" in
        set)
            [[ $# -eq 1 ]] || { msg_err "Usage: urb red target set <ip|host>"; return 2; }
            is_valid_target "$1" || { msg_err "Invalid target: '${1}'"; msg_dim "    Expected an IPv4/IPv6 address, CIDR, range or hostname."; return 2; }
            _red_require_lab || return 1
            old="$(lab_target_get "$LAB_ROOT" 2>/dev/null)" || old=""
            lab_target_set "$LAB_ROOT" "$1" || return $?
            msg_ok "Target for lab $(lab_name "$LAB_ROOT"): $1${old:+ (was: ${old})}"
            ;;
        show|"")
            [[ $# -eq 0 ]] || { msg_err "Usage: urb red target show"; return 2; }
            _red_require_lab || return 1
            lab_target_read "$LAB_ROOT" || { msg_err "${LAB_ERR}"; msg_dim "    Fix it: urb red target set <ip>"; return 1; }
            t="$LAB_TARGET"
            if [[ -z "$t" ]]; then
                msg_warn "Lab $(lab_name "$LAB_ROOT") has no target. Set it: urb red target set <ip>"
                return 1
            fi
            printf '%s\n' "$t"
            ;;
        -h|--help|help) red_help ;;
        *) msg_err "Unknown target action: ${action}"; return 2 ;;
    esac
}

# --- Estado --------------------------------------------------------------------------------
red_status() {
    local t vpn n latest sess="not running" sock="${URB_RED_SOCKET:-urb-red}"
    msg_section "URB RED STATUS"
    if lab_resolve "$PWD"; then
        _red_kv "Lab" "$(lab_name "$LAB_ROOT")  ${T_DIM}($(_red_lab_source_txt))${C_RESET}"
        _red_kv "Path" "$LAB_ROOT"
        if lab_target_read "$LAB_ROOT"; then
            t="$LAB_TARGET"
            _red_kv "Target" "${t:-${T_DIM}not set — urb red target set <ip>${C_RESET}}"
        else
            _red_kv "Target" "${T_BAD}${LAB_ERR}${C_RESET}"
        fi
        n=0 latest=""
        if declare -F scn_sync >/dev/null && scn_sync "$LAB_ROOT"; then
            _scn_read "$LAB_ROOT"; n=${#SCN_IDS[@]}
            scn_resolve "$LAB_ROOT" latest 2>/dev/null && latest="latest complete: ${SCN_ID}, $(printf '%(%Y-%m-%d %H:%M)T' "$SCN_EPOCH")"
        fi
        _red_kv "Scans" "${n}${latest:+  ${T_DIM}(${latest})${C_RESET}}"
        if declare -F fnd_counts >/dev/null; then
            fnd_counts "$LAB_ROOT"
            _red_kv "Findings" "$(red_findings_summary)"
        fi
    else
        if [[ "$LAB_ERR" == "selected lab is no longer valid"* ]]; then _red_kv "Lab" "${T_BAD}${LAB_ERR}${C_RESET}"
        else _red_kv "Lab" "${T_DIM}none — urb red lab new <name> --target <ip>${C_RESET}"; fi
    fi
    vpn="$(sys_vpn_detect 2>/dev/null | head -n 1)"
    if [[ -n "$vpn" ]]; then _red_kv "VPN" "${T_OK}${G_DOT} ${vpn}${C_RESET}"; else _red_kv "VPN" "${T_DIM}${G_RING} inactive${C_RESET}"; fi
    if [[ "$sock" =~ ^[A-Za-z0-9_-]{1,64}$ ]] && has_cmd tmux && tmux -L "$sock" has-session -t "=red" 2>/dev/null; then
        sess="running (urb red to reconnect)"
    fi
    _red_kv "Session" "$sess"
    return 0
}

# --- Reconocimiento --------------------------------------------------------------------------
red_recon() {
    local kind="${1:-}" target="" tsrc rc
    (( $# > 0 )) && shift
    case "$kind" in
        initial) ;;
        ""|-h|--help|help) red_help; return 0 ;;
        *) msg_err "Unknown recon type: ${kind} (v0.1 supports: initial)"; return 2 ;;
    esac
    while (( $# > 0 )); do
        case "$1" in
            --target) [[ $# -ge 2 ]] || { msg_err "--target needs a value"; return 2; }; target="$2"; shift 2 ;;
            *) msg_err "Unknown option: $1"; msg_dim "    Usage: urb red recon initial [--target <ip|host>]"; return 2 ;;
        esac
    done
    if [[ -n "$target" ]] && ! is_valid_target "$target"; then
        msg_err "Invalid target: '${target}'"; return 2
    fi

    _red_require_lab || return 1
    if [[ -n "$target" ]]; then
        tsrc="--target (this run only; the lab's saved target is not changed)"
    else
        lab_target_read "$LAB_ROOT" || { msg_err "${LAB_ERR}"; msg_dim "    Fix it: urb red target set <ip>"; return 1; }
        target="$LAB_TARGET"
        if [[ -z "$target" ]]; then
            msg_err "Lab $(lab_name "$LAB_ROOT") has no target."
            msg_dim "    Set it: urb red target set <ip>   or run: urb red recon initial --target <ip>"
            return 1
        fi
        tsrc="lab metadata"
    fi

    # Contexto explícito ANTES de cualquier operación de red
    msg_section "URB RED ${G_SEP} RECON INITIAL"
    _red_kv "Lab" "$(lab_name "$LAB_ROOT")  ${T_DIM}($(_red_lab_source_txt): ${LAB_ROOT})${C_RESET}"
    _red_kv "Target" "${target}  ${T_DIM}(from ${tsrc})${C_RESET}"
    _red_kv "Output" "${LAB_ROOT}/scans/"

    mkdir -p -- "${LAB_ROOT}/scans" || { msg_err "Cannot create ${LAB_ROOT}/scans"; return 1; }
    scan_main "$target" --profile default -o "${LAB_ROOT}/scans"; rc=$?
    diag_scan "$rc" "${SCAN_LAST_BASE:-}" "$target"
    # Registrar el escaneo en el índice del laboratorio y mostrar su ID corto
    if [[ -n "${SCAN_LAST_BASE:-}" ]] && declare -F scn_sync >/dev/null && scn_sync "$LAB_ROOT"; then
        local i b="${SCAN_LAST_BASE##*/}"
        _scn_read "$LAB_ROOT"
        for i in "${!SCN_BASES[@]}"; do
            if [[ "${SCN_BASES[i]}" == "$b" ]]; then
                msg_info "Scan ID: ${SCN_IDS[i]}  (urb red scans show ${SCN_IDS[i]} · urb red services)"
                break
            fi
        done
    fi
    if (( rc == 0 )) && [[ -n "${SCAN_LAST_BASE:-}" ]]; then
        msg_dim "  Files: ${SCAN_LAST_BASE}.{nmap,xml,gnmap}"
    fi
    return "$rc"
}

# --- Entrada ----------------------------------------------------------------------------------
# El perfil visual es God Mode con --profile red (proceso propio, sin duplicar código)
_red_shell() {
    local god="${URB_HOME}/godmode/god.sh"
    [[ -f "$god" ]] || { msg_err "URB Red needs God Mode files (${god} not found). Reinstall URB-Tools."; return 1; }
    URB_COLOR="${color_mode:-${URB_COLOR:-auto}}" exec bash "$god" --profile red "$@"
}

red_main() {
    case "${1:-}" in
        "")                 _red_shell ;;
        --no-anim)          _red_shell --no-anim ;;
        --kill)             shift; _red_shell --kill "$@" ;;
        --session)          _red_shell --status ;;
        --check)            _red_shell --check ;;
        lab|labs)           shift; red_lab "$@" ;;
        target)             shift; red_target "$@" ;;
        status)             shift; [[ $# -eq 0 ]] || { msg_err "Usage: urb red status"; return 2; }; red_status ;;
        recon)              shift; red_recon "$@" ;;
        findings|finding)   shift; red_findings "$@" ;;
        scans|scan)         shift; red_scans "$@" ;;
        services|service)   shift; red_services "$@" ;;
        notes|note)         shift; red_notes "$@" ;;
        -h|--help|help)     red_help ;;
        *) msg_err "Unknown red command: $1"; msg_dim "    See: urb red --help"; return 2 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    URB_HOME="$(cd -P -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)" || exit 1
    # shellcheck source=../lib/utils.sh
    source "${URB_HOME}/lib/utils.sh" && urb_standalone_init || exit 1
    # shellcheck source=findings.sh
    source "${URB_HOME}/modules/findings.sh" || exit 1
    # shellcheck source=inventory.sh
    source "${URB_HOME}/modules/inventory.sh" || exit 1
    red_main "$@"
    exit $?
fi
