#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/findings.sh — CLI de findings y notas de URB Red
#    urb red findings [list|add|show|status|note|evidence]
#    urb red notes [add|edit]
#  Datos y reglas en lib/findings.sh. El laboratorio se resuelve con
#  lib/lab.sh (directorio actual > laboratorio seleccionado). No depende de
#  tmux ni del HUD: funciona dentro y fuera de 'urb red'.
# =============================================================================

[[ -n "${_URB_FINDINGS_CLI_LOADED:-}" ]] && return 0
_URB_FINDINGS_CLI_LOADED=1

_fnd_status_color() {
    case "$1" in
        pending)       printf '%s' "$T_DIM" ;;
        investigating) printf '%s' "$T_WARN" ;;
        suspected)     printf '%s' "$T_KEY" ;;
        confirmed)     printf '%s' "$T_BAD" ;;
        discarded)     printf '%s' "$T_DIM" ;;
        checked)       printf '%s' "$T_OK" ;;
        *)             printf '%s' "$T_BAD" ;;
    esac
}

# Resumen "3 findings · 1 pending · ..." a partir de fnd_counts
red_findings_summary() {
    local s out
    if (( FND_TOTAL == 0 )); then printf 'none yet'; return 0; fi
    out="${FND_TOTAL} finding$( (( FND_TOTAL != 1 )) && printf 's')"
    for s in "${FND_STATUSES[@]}"; do
        (( ${FND_COUNT[$s]:-0} > 0 )) && out+=" · ${FND_COUNT[$s]} ${s}"
    done
    (( FND_DAMAGED_N > 0 )) && out+=" · ${FND_DAMAGED_N} damaged"
    printf '%s' "$out"
}

_fnd_require_id() {
    local id
    [[ -n "${1:-}" ]] || { msg_err "Missing finding ID (e.g. F-001)."; return 2; }
    id="$(fnd_normalize_id "$1")" || { msg_err "Invalid finding ID: '${1}' (expected F-001)"; return 2; }
    [[ -f "$(fnd_file "$LAB_ROOT" "$id")" ]] || { msg_err "Finding ${id} not found in lab $(lab_name "$LAB_ROOT")."; msg_dim "    See: urb red findings list"; return 1; }
    FND_ID="$id"
}

red_findings_list() {
    local f cols tw st title id n=0
    cols="$(tput cols 2>/dev/null)"; is_uint "$cols" || cols=100
    tw=$(( cols - 28 )); (( tw < 20 )) && tw=20
    msg_section "URB RED / FINDINGS ${G_SEP} $(lab_name "$LAB_ROOT")"
    fnd_counts "$LAB_ROOT"
    if (( FND_TOTAL == 0 )); then
        msg_dim "  No findings yet. Add one: urb red findings add \"HTTP on port 80\""
        return 0
    fi
    printf '  %s%-8s %-14s %s%s\n' "$C_BOLD" "ID" "STATUS" "TITLE" "$C_RESET"
    while IFS= read -r f; do
        n=$(( n + 1 ))
        if fnd_read "$f"; then
            st="$(fnd_status_canonical "$F_STATUS")"; id="$F_ID"; title="$F_TITLE"
        else
            id="${f##*/}"; id="${id%.finding}"; st="damaged"; title="${F_TITLE:-(${F_PROBLEM})}"
        fi
        (( ${#title} > tw )) && title="${title:0:tw-1}${G_ELL}"
        printf '  %s%-8s%s %s%-14s%s %s\n' "$T_KEY" "$id" "$C_RESET" "$(_fnd_status_color "$st")" "$st" "$C_RESET" "$title"
    done < <(fnd_files "$LAB_ROOT")
    printf '\n  %s\n' "$(red_findings_summary)"
}

red_findings_show() {
    _fnd_require_id "${1:-}" || return $?
    local f entry ts txt e mark ok=0
    f="$(fnd_file "$LAB_ROOT" "$FND_ID")"
    fnd_read "$f" && ok=1
    msg_section "${FND_ID} ${G_SEP} ${F_TITLE:-?}"
    if (( ! ok )); then
        msg_warn "This finding is damaged (${F_PROBLEM}). Showing what could be read; it will not be modified."
        msg_dim "    File: ${f}"
    fi
    local st; st="$(fnd_status_canonical "$F_STATUS" 2>/dev/null)" || st="${F_STATUS:-?}"
    printf '  %s%-9s%s %s%s%s\n' "$T_LABEL" "Status" "$C_RESET" "$(_fnd_status_color "$st")" "$st" "$C_RESET"
    printf '  %s%-9s%s %s\n' "$T_LABEL" "Created" "$C_RESET" "${F_CREATED:--}"
    printf '  %s%-9s%s %s\n' "$T_LABEL" "Updated" "$C_RESET" "${F_UPDATED:--}"
    printf '  %s%-9s%s %s\n' "$T_LABEL" "Lab" "$C_RESET" "$(lab_name "$LAB_ROOT")"
    [[ -n "$F_DESC" ]] && printf '  %s%-9s%s %s\n' "$T_LABEL" "Desc" "$C_RESET" "$F_DESC"

    msg_section "LINKED SERVICES"
    if (( ${#F_SERVICES[@]} == 0 )); then msg_dim "  none"; fi
    if (( ${#F_SERVICES[@]} )); then
        local cache_line tag host proto port state service product version extra hostname ls le lq fs fe hist match cache_ok=0
        local -a SF
        _svc_ensure >/dev/null 2>&1 && cache_ok=1
        for e in "${F_SERVICES[@]}"; do
            match=0
            if (( cache_ok )); then
                while IFS= read -r cache_line; do
                    _svc_fields "$cache_line"
                    [[ "$tag" == svc && "${host}:${port}/${proto}" == "$e" ]] && { match=1; break; }
                done <"$(svc_cache "$LAB_ROOT")"
            fi
            if (( ! cache_ok )); then printf '  %s (inventory unavailable)\n' "$e"
            elif (( ! match )); then printf '  %s (not in current inventory)\n' "$e"
            else printf '  %s (latest state: %s; source: %s)\n' "$e" "${state:-unknown}" "$ls"; fi
        done
    fi
    (( ${#F_SERVICES[@]} )) && msg_dim "  Keys refer to observations; a link does not establish a vulnerability."

    msg_section "NOTES"
    if (( ${#F_NOTES[@]} == 0 )); then msg_dim "  none — urb red findings note ${FND_ID} \"...\""; fi
    for entry in "${F_NOTES[@]}"; do
        ts="${entry%%|*}"; txt="${entry#*|}"
        printf '  %s%s%s  %s\n' "$T_DIM" "$ts" "$C_RESET" "$txt"
    done

    msg_section "EVIDENCE"
    if (( ${#F_EVIDENCE[@]} == 0 )); then msg_dim "  none — urb red findings evidence ${FND_ID} <file>"; fi
    for e in "${F_EVIDENCE[@]}"; do
        if [[ -f "${LAB_ROOT}/${e}" ]]; then mark="${T_OK}${G_OK}${C_RESET}"
        else mark="${T_BAD}${G_BAD}${C_RESET}"; e+="  ${T_DIM}(missing)${C_RESET}"; fi
        printf '  %s %s\n' "$mark" "$e"
    done

    if (( ${#F_LOGS[@]} )); then
        msg_section "HISTORY"
        for entry in "${F_LOGS[@]}"; do
            printf '  %s%s%s  %s\n' "$T_DIM" "${entry%%|*}" "$C_RESET" "${entry#*|}"
        done
    fi
    (( ok )) || return 1
    return 0
}

red_findings() {
    local action="${1:-list}" title="" desc="" status="pending" rc
    (( $# > 0 )) && shift
    case "$action" in -h|--help|help) red_help findings; return 0 ;; esac
    _red_require_lab || return 1
    case "$action" in
        list|ls)
            [[ $# -eq 0 ]] || { msg_err "Usage: urb red findings list"; return 2; }
            red_findings_list ;;
        add|new)
            while (( $# > 0 )); do
                case "$1" in
                    --desc)   [[ $# -ge 2 ]] || { msg_err "--desc needs a value"; return 2; }; desc="$2"; shift 2 ;;
                    --status) [[ $# -ge 2 ]] || { msg_err "--status needs a value"; return 2; }; status="$2"; shift 2 ;;
                    --) shift; [[ $# -gt 0 ]] && { title="$1"; shift; } ;;
                    -*) msg_err "Unknown option: $1"; return 2 ;;
                    *)  [[ -z "$title" ]] || { msg_err "Quote the title: urb red findings add \"<title>\""; return 2; }; title="$1"; shift ;;
                esac
            done
            [[ -n "$title" ]] || { msg_err "Missing title. Usage: urb red findings add \"<title>\""; return 2; }
            fnd_status_canonical "$status" >/dev/null || { msg_err "Invalid status '${status}'. Valid: ${FND_STATUSES[*]}"; return 2; }
            fnd_create "$LAB_ROOT" "$title" "$desc" "$status"; rc=$?
            (( rc == 0 )) || { msg_err "$FND_ERR"; return "$rc"; }
            msg_ok "${FND_NEW_ID} created in lab $(lab_name "$LAB_ROOT"): ${title} ($(fnd_status_canonical "$status"))" ;;
        show|info)
            [[ $# -eq 1 ]] || { msg_err "Usage: urb red findings show F-001"; return 2; }
            red_findings_show "$1" ;;
        link|unlink)
            [[ $# -eq 3 && "$2" == --service ]] || { msg_err "Usage: urb red findings ${action} F-001 --service <host:port/protocol>"; return 2; }
            _fnd_require_id "$1" || return $?
            local key="$3"
            if [[ "$action" == link ]]; then
                _svc_resolve_key "$3" || return $?
                key="$SVC_KEY"
            else
                # Exact stored keys remain removable even when no longer in inventory.
                fnd_read "$(fnd_file "$LAB_ROOT" "$FND_ID")" || { msg_err "Finding is damaged"; return 1; }
                local candidate matches=0
                for candidate in "${F_SERVICES[@]}"; do
                    if [[ "$candidate" == "$3" || "${candidate##*:}" == "$3" || "${candidate##*:}" == "$3/"* ]]; then key="$candidate"; matches=$((matches+1)); fi
                done
                (( matches == 1 )) || { msg_err "Service link not found or ambiguous; specify host:port/protocol."; return 1; }
            fi
            _fnd_modify "$LAB_ROOT" "$FND_ID" "$action" "$key"; rc=$?
            if (( rc == 3 )); then msg_info "$FND_ERR"; return 0; fi
            (( rc == 0 )) || { msg_err "$FND_ERR"; return "$rc"; }
            msg_ok "${action}: ${FND_ID} ${key}" ;;
        status|set)
            [[ $# -eq 2 ]] || { msg_err "Usage: urb red findings status F-001 <state>  (${FND_STATUSES[*]})"; return 2; }
            _fnd_require_id "$1" || return $?
            fnd_set_status "$LAB_ROOT" "$FND_ID" "$2"; rc=$?
            if (( rc == 3 )); then msg_info "$FND_ERR"; return 0; fi
            (( rc == 0 )) || { msg_err "$FND_ERR"; return "$rc"; }
            msg_ok "${FND_ID} → $(fnd_status_canonical "$2")" ;;
        note)
            [[ $# -eq 2 ]] || { msg_err "Usage: urb red findings note F-001 \"<text>\""; return 2; }
            _fnd_require_id "$1" || return $?
            fnd_add_note "$LAB_ROOT" "$FND_ID" "$2"; rc=$?
            (( rc == 0 )) || { msg_err "$FND_ERR"; return "$rc"; }
            msg_ok "Note added to ${FND_ID}." ;;
        evidence|ev)
            if [[ $# -eq 3 && "$2" == "--scan" ]]; then
                # Referencia corta a un escaneo del laboratorio: latest | S-001
                _fnd_require_id "$1" || return $?
                scn_resolve "$LAB_ROOT" "$3"; rc=$?
                (( rc == 0 )) || { msg_err "$SCN_ERR"; return "$rc"; }
                local nmapf; nmapf="$(scn_dir "$LAB_ROOT")/${SCN_BASE}.nmap"
                [[ -f "$nmapf" ]] || { msg_err "${SCN_ID} has no .nmap file to link ($(scn_status "$(scn_dir "$LAB_ROOT")" "$SCN_BASE") scan)."; return 1; }
                fnd_add_evidence "$LAB_ROOT" "$FND_ID" "$nmapf"; rc=$?
                if (( rc == 3 )); then msg_info "${SCN_ID}: ${FND_ERR}"; return 0; fi
                (( rc == 0 )) || { msg_err "$FND_ERR"; return "$rc"; }
                msg_ok "Evidence linked to ${FND_ID}: ${SCN_ID} → ${FND_EVIDENCE_REL}"
                return 0
            fi
            [[ $# -eq 2 ]] || { msg_err "Usage: urb red findings evidence F-001 <file inside the lab> | --scan <latest|S-001>"; return 2; }
            _fnd_require_id "$1" || return $?
            fnd_add_evidence "$LAB_ROOT" "$FND_ID" "$2"; rc=$?
            if (( rc == 3 )); then msg_info "$FND_ERR"; return 0; fi
            (( rc == 0 )) || { msg_err "$FND_ERR"; return "$rc"; }
            msg_ok "Evidence linked to ${FND_ID}: ${FND_EVIDENCE_REL}" ;;
        *) msg_err "Unknown findings action: ${action}"; msg_dim "    See: urb red --help"; return 2 ;;
    esac
}

red_notes() {
    local action="${1:-show}" f rc ed
    (( $# > 0 )) && shift
    case "$action" in -h|--help|help) red_help notes; return 0 ;; esac
    _red_require_lab || return 1
    f="$(fnd_notes_file "$LAB_ROOT")"
    case "$action" in
        show|list|cat)
            [[ $# -eq 0 ]] || { msg_err "Usage: urb red notes"; return 2; }
            msg_section "URB RED / NOTES ${G_SEP} $(lab_name "$LAB_ROOT")"
            if [[ -f "$f" ]]; then sed 's/^/  /' -- "$f"; else msg_dim "  No notes yet. Add one: urb red notes add \"...\""; fi
            msg_dim "  ${f}" ;;
        add)
            [[ $# -eq 1 ]] || { msg_err "Usage: urb red notes add \"<text>\""; return 2; }
            fnd_notes_add "$LAB_ROOT" "$1"; rc=$?
            (( rc == 0 )) || { msg_err "$FND_ERR"; return "$rc"; }
            msg_ok "Note added to $(lab_name "$LAB_ROOT") (notes/notes.md)." ;;
        edit)
            [[ $# -eq 0 ]] || { msg_err "Usage: urb red notes edit"; return 2; }
            fnd_notes_ensure "$LAB_ROOT" || { msg_err "$FND_ERR"; return 1; }
            ed="${VISUAL:-${EDITOR:-}}"
            if [[ -z "$ed" ]]; then
                if has_cmd nano; then ed="nano"; elif has_cmd vi; then ed="vi"; else msg_err "No editor found. Set \$EDITOR."; return 1; fi
            fi
            local -a cmd; read -ra cmd <<<"$ed"
            has_cmd "${cmd[0]}" || { msg_err "Editor not found: ${cmd[0]}"; return 1; }
            "${cmd[@]}" "$f" ;;
        *) msg_err "Unknown notes action: ${action}"; msg_dim "    See: urb red --help"; return 2 ;;
    esac
}
