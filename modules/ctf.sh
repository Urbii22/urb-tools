#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/ctf.sh — CTF: gestión de laboratorios
#  Crea:  <LABS_DIR>/<nombre>/{scans,exploits,evidence,notes}/ + report.md + .urb-lab
#  CLI:   urb ctf new <nombre> [--dir BASE] [--target IP] | list | path <nombre>
# =============================================================================

[[ -n "${_URB_CTF_LOADED:-}" ]] && return 0
_URB_CTF_LOADED=1

CTF_SUBDIRS=(scans exploits evidence notes)

ctf_help() {
    cat <<EOF
${C_BOLD}urb ctf${C_RESET} — CTF / laboratory workspaces

${C_BOLD}USAGE${C_RESET}
  urb ctf new <name> [--dir BASE] [--target IP]   Create a lab workspace
  urb ctf list [--dir BASE]                       List labs
  urb ctf path <name> [--dir BASE]                Print a lab path (cd "\$(urb ctf path box)")

${C_BOLD}STRUCTURE${C_RESET}
  <name>/
  ├── scans/      (urb scan saves here when run inside the lab)
  ├── exploits/
  ├── evidence/
  ├── notes/
  └── report.md

Base folder: $(urb_labs_dir)  (config: LABS_DIR)
Names: letters, numbers, '.', '_' and '-' (max 64 chars).
EOF
}

# Busca hacia arriba la raíz de un laboratorio (.urb-lab) desde una ruta.
# La lógica vive en lib/lab.sh (compartida con URB Red).
ctf_find_lab_root() { lab_find_root "$@"; }

_ctf_report_template() {
    local name="$1" target="$2" date="$3"
    cat <<EOF
# Lab report — ${name}

| Field | Value |
|-------|-------|
| Created | ${date} |
| Target(s) | ${target:-_pending_} |
| Platform | _HTB / THM / VulnHub / local lab_ |
| Scope & authorization | _describe the authorized scope_ |

## 1. Summary

_Short description of the box/challenge and the final result._

## 2. Reconnaissance

- Scans: see \`scans/\`

## 3. Enumeration

## 4. Exploitation

- Exploits / PoCs: see \`exploits/\`

## 5. Privilege escalation

## 6. Flags & evidence

| Flag | Value | Evidence |
|------|-------|----------|
| user | | \`evidence/\` |
| root | | \`evidence/\` |

## 7. Lessons learned

EOF
}

# ctf_create BASE NOMBRE [TARGET] → crea o completa el laboratorio (idempotente)
ctf_create() {
    local base="$1" name="$2" target="${3:-}" dir sub created=0 now
    is_safe_name "$name" || { msg_err "Invalid lab name: '${name}'"; msg_dim "    Allowed: letters, numbers, '.', '_', '-' (max 64, no '..')"; return 2; }
    if [[ -n "$target" ]] && ! is_valid_target "$target"; then msg_err "Invalid target: '${target}'"; return 2; fi
    dir="${base%/}/${name}"
    if [[ -e "$dir" && ! -d "$dir" ]]; then msg_err "${dir} exists and is not a directory."; return 1; fi
    if [[ -d "$dir" && ! -f "$dir/.urb-lab" ]] && [[ -n "$(ls -A -- "$dir" 2>/dev/null)" ]]; then
        msg_err "${dir} already exists and is not an URB lab. Choose another name."
        return 1
    fi
    [[ -d "$dir" ]] || created=1
    mkdir -p -- "$dir" || { msg_err "Cannot create ${dir}"; return 1; }
    for sub in "${CTF_SUBDIRS[@]}"; do
        mkdir -p -- "${dir}/${sub}" || { msg_err "Cannot create ${dir}/${sub}"; return 1; }
    done
    now="$(urb_now)"
    if [[ ! -f "${dir}/report.md" ]]; then
        _ctf_report_template "$name" "$target" "$now" >"${dir}/report.md" || { msg_err "Cannot write report.md"; return 1; }
    fi
    if [[ ! -f "${dir}/notes/notes.md" ]]; then
        printf '# Notes — %s\n\n- %s  lab created\n' "$name" "$now" >"${dir}/notes/notes.md"
    fi
    if [[ ! -f "${dir}/.urb-lab" ]]; then
        printf 'name=%s\ncreated=%s\ntarget=%s\n' "$name" "$now" "$target" >"${dir}/.urb-lab"
    fi
    if (( created )); then msg_ok "Lab created: ${dir}"; else msg_info "Lab already existed; missing parts completed: ${dir}"; fi
    _ctf_tree "$dir"
    return 0
}

_ctf_tree() {
    local dir="$1" sub b="├──" l="└──"
    urb_is_utf8 || { b="|--"; l="\`--"; }
    printf '  %s%s/%s\n' "$T_TITLE" "$(basename -- "$dir")" "$C_RESET"
    for sub in "${CTF_SUBDIRS[@]}"; do printf '  %s %s%s/%s\n' "$b" "$T_KEY" "$sub" "$C_RESET"; done
    printf '  %s report.md\n' "$l"
    printf '\n  %scd %q%s\n' "$T_DIM" "$dir" "$C_RESET"
}

ctf_list() {
    local base="$1" d n=0 created target
    msg_section "LABS (${base})"
    if [[ ! -d "$base" ]]; then msg_dim "  No labs yet. Create one: urb ctf new <name>"; return 0; fi
    for d in "$base"/*/; do
        [[ -f "${d}.urb-lab" ]] || continue
        created="$(sed -n 's/^created=//p' "${d}.urb-lab" 2>/dev/null)"
        target="$(sed -n 's/^target=//p' "${d}.urb-lab" 2>/dev/null)"
        local ns; ns="$(find "${d}scans" -maxdepth 1 -name '*.nmap' 2>/dev/null | wc -l)"
        printf '  %s%-24s%s %s%s%s  target: %-16s scans: %s\n' "$T_KEY" "$(basename -- "$d")" "$C_RESET" "$T_DIM" "${created:--}" "$C_RESET" "${target:--}" "$ns"
        n=$(( n + 1 ))
    done
    (( n )) || msg_dim "  No labs yet. Create one: urb ctf new <name>"
    return 0
}

ctf_main() {
    local action="${1:-}" name="" base target=""
    (( $# > 0 )) && shift
    base="$(urb_labs_dir)"
    case "$action" in
        -h|--help|help|"") ctf_help; return 0 ;;
    esac
    while (( $# > 0 )); do
        case "$1" in
            --dir)    [[ $# -ge 2 ]] || { msg_err "--dir needs a value"; return 2; }; base="$(urb_expand_path "$2")"; shift 2 ;;
            --target) [[ $# -ge 2 ]] || { msg_err "--target needs a value"; return 2; }; target="$2"; shift 2 ;;
            -*) msg_err "Unknown option: $1"; return 2 ;;
            *)  if [[ -n "$name" ]]; then msg_err "Unexpected argument: $1"; return 2; fi; name="$1"; shift ;;
        esac
    done
    case "$action" in
        new|create)
            [[ -n "$name" ]] || { msg_err "Missing lab name. Usage: urb ctf new <name>"; return 2; }
            ctf_create "$base" "$name" "$target" ;;
        list|ls) ctf_list "$base" ;;
        path)
            [[ -n "$name" ]] || { msg_err "Missing lab name."; return 2; }
            is_safe_name "$name" || { msg_err "Invalid lab name: '${name}'"; return 2; }
            [[ -f "${base}/${name}/.urb-lab" ]] || { msg_err "Lab not found: ${name}"; return 1; }
            printf '%s\n' "${base}/${name}" ;;
        *) msg_err "Unknown ctf action: ${action}"; msg_dim "    See: urb help ctf"; return 2 ;;
    esac
}

ctf_menu() {
    local name target
    while :; do
        ui_menu "CTF" "Laboratory Management" \
            "New lab|Create a lab workspace" \
            "List labs|Show existing labs" \
            "Back|Return to dashboard" || return 0
        case "$UI_CHOICE" in
            0) msg_section "NEW LAB"
               ui_prompt name "Lab name (e.g. htb-lame)" || continue
               [[ -z "$name" ]] && continue
               ui_prompt target "Target IP/host (optional)" || continue
               ctf_create "$(urb_labs_dir)" "$name" "$target" ;;
            1) ctf_list "$(urb_labs_dir)" ;;
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
    ctf_main "$@"
    exit $?
fi
