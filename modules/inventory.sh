#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/inventory.sh — CLI de escaneos y servicios de URB Red
#    urb red scans [list|show <latest|S-NNN>]
#    urb red services [list [--all]|show <puerto|host:puerto[/proto]>|refresh]
#  Datos en lib/scans.sh (índice S-NNN) y lib/nmap_services.py (XML → caché).
#  Nunca ejecuta nmap ni genera tráfico de red: solo lee ficheros del lab.
# =============================================================================

[[ -n "${_URB_INVENTORY_LOADED:-}" ]] && return 0
_URB_INVENTORY_LOADED=1

_scn_status_color() {
    case "$1" in
        complete)            printf '%s' "$T_OK" ;;
        incomplete|partial)  printf '%s' "$T_WARN" ;;
        failed)              printf '%s' "$T_BAD" ;;
        *)                   printf '%s' "$T_DIM" ;;
    esac
}

_scn_files_of() {
    local dir="$1" base="$2" e out=""
    for e in nmap xml gnmap log; do [[ -f "${dir}/${base}.${e}" ]] && out+="${e} "; done
    printf '%s' "${out% }"
}

_fmt_epoch() { if is_uint "${1:-}" && (( $1 > 0 )); then printf '%(%Y-%m-%d %H:%M)T' "$1"; else printf 'unknown'; fi; }

red_scans_list() {
    local dir i st n=0 latest=""
    scn_sync "$LAB_ROOT" || { msg_err "$SCN_ERR"; return 1; }
    _scn_read "$LAB_ROOT"
    dir="$(scn_dir "$LAB_ROOT")"
    msg_section "URB RED / SCANS ${G_SEP} $(lab_name "$LAB_ROOT")"
    (( SCN_BAD > 0 )) && msg_warn "scans/.index has ${SCN_BAD} damaged line(s); they were ignored (see: urb red --help)."
    if (( ${#SCN_IDS[@]} == 0 )); then
        msg_dim "  No scans yet. Run: urb red recon initial"
        return 0
    fi
    printf '  %s%-7s %-16s %-18s %-9s %-11s %s%s\n' "$C_BOLD" "ID" "DATE" "TARGET" "PROFILE" "STATUS" "FILES" "$C_RESET"
    for i in "${!SCN_IDS[@]}"; do
        st="$(scn_status "$dir" "${SCN_BASES[i]}")"
        scn_meta "${SCN_BASES[i]}"
        printf '  %s%-7s%s %-16s %-18.18s %-9.9s %s%-11s%s %s%s%s\n' \
            "$T_KEY" "${SCN_IDS[i]}" "$C_RESET" "$(_fmt_epoch "${SCN_EPOCHS[i]}")" "$SCN_TARGET" "$SCN_PROFILE" \
            "$(_scn_status_color "$st")" "$st" "$C_RESET" "$T_DIM" "$(_scn_files_of "$dir" "${SCN_BASES[i]}")" "$C_RESET"
        n=$(( n + 1 ))
    done
    scn_resolve "$LAB_ROOT" latest 2>/dev/null && latest="$SCN_ID"
    printf '\n  %s scan(s) · latest complete: %s\n' "$n" "${latest:-none}"
}

red_scans_show() {
    local ref="${1:-latest}" dir st f
    scn_resolve "$LAB_ROOT" "$ref"; local rc=$?
    (( rc == 0 )) || { msg_err "$SCN_ERR"; return "$rc"; }
    dir="$(scn_dir "$LAB_ROOT")"
    st="$(scn_status "$dir" "$SCN_BASE")"
    scn_meta "$SCN_BASE"
    msg_section "${SCN_ID} ${G_SEP} ${SCN_TARGET} ${G_SEP} $(lab_name "$LAB_ROOT")"
    printf '  %s%-8s%s %s\n' "$T_LABEL" "Date" "$C_RESET" "$(_fmt_epoch "$SCN_EPOCH")"
    printf '  %s%-8s%s %s\n' "$T_LABEL" "Target" "$C_RESET" "$SCN_TARGET"
    printf '  %s%-8s%s %s\n' "$T_LABEL" "Profile" "$C_RESET" "$SCN_PROFILE"
    printf '  %s%-8s%s %s%s%s\n' "$T_LABEL" "Status" "$C_RESET" "$(_scn_status_color "$st")" "$st" "$C_RESET"
    case "$st" in
        incomplete) msg_dim "           The scan did not finish (interrupted): results are partial." ;;
        failed)     msg_dim "           nmap reported an error; see the .log file." ;;
        partial)    msg_dim "           Some files of this run are missing." ;;
        missing)    msg_dim "           The files of this scan no longer exist (the ID is kept)." ;;
    esac
    printf '  %s%-8s%s\n' "$T_LABEL" "Files" "$C_RESET"
    for f in nmap xml gnmap log; do
        [[ -f "${dir}/${SCN_BASE}.${f}" ]] && printf '    scans/%s.%s  %s(%s)%s\n' "$SCN_BASE" "$f" "$T_DIM" "$(fmt_kb $(( ($(stat -c %s -- "${dir}/${SCN_BASE}.${f}") + 1023) / 1024 )))" "$C_RESET"
    done
    if [[ -s "${dir}/${SCN_BASE}.gnmap" ]]; then
        scan_render_table "${dir}/${SCN_BASE}.gnmap"
    fi
    msg_dim "  Link it to a finding: urb red findings evidence F-001 --scan ${SCN_ID}"
    return 0
}

red_scans() {
    local action="${1:-list}"
    (( $# > 0 )) && shift
    case "$action" in -h|--help|help) red_help; return 0 ;; esac
    _red_require_lab || return 1
    case "$action" in
        list|ls) [[ $# -eq 0 ]] || { msg_err "Usage: urb red scans list"; return 2; }; red_scans_list ;;
        show)    (( $# <= 1 )) || { msg_err "Usage: urb red scans show <latest|S-001>"; return 2; }; red_scans_show "${1:-latest}" ;;
        *) msg_err "Unknown scans action: ${action}"; msg_dim "    Usage: urb red scans [list|show <latest|S-001>]"; return 2 ;;
    esac
}

# --- Servicios ----------------------------------------------------------------------
_svc_ensure() {
    local force="${1:-0}" rc
    svc_refresh "$LAB_ROOT" "$force"; rc=$?
    if (( rc != 0 )); then
        msg_err "$SVC_ERR"
        if (( rc != 127 )) && [[ -r "$(svc_cache "$LAB_ROOT")" ]]; then msg_dim "    Showing the previous inventory."; return 0; fi
        return "$rc"
    fi
    return 0
}

_svc_version() {
    local product="$1" version="$2" extra="$3" out
    out="${product}${version:+ ${version}}"
    [[ -n "$extra" ]] && out+="${out:+ }(${extra})"
    printf '%s' "${out:-unknown}"
}

# Lee una línea TSV conservando los campos vacíos (con IFS=$'\t', read
# fundiría tabuladores consecutivos): se separa por \x1f, que no es blanco.
_svc_fields() {
    SF=()
    IFS=$'\x1f' read -r -a SF <<<"${1//$'\t'/$'\x1f'}"
    tag="${SF[0]:-}" host="${SF[1]:-}" proto="${SF[2]:-}" port="${SF[3]:-}" state="${SF[4]:-}"
    service="${SF[5]:-}" product="${SF[6]:-}" version="${SF[7]:-}" extra="${SF[8]:-}" hostname="${SF[9]:-}"
    ls="${SF[10]:-}" le="${SF[11]:-}" lq="${SF[12]:-}" fs="${SF[13]:-}" fe="${SF[14]:-}" hist="${SF[15]:-}"
}

# Avisos de escaneos parciales, incompletos o inválidos
_svc_scan_warnings() {
    local cache line tag id quality hosts detail n=0
    local -a SF
    cache="$(svc_cache "$LAB_ROOT")"
    while IFS= read -r line; do
        SF=(); IFS=$'\x1f' read -r -a SF <<<"${line//$'\t'/$'\x1f'}"
        tag="${SF[0]:-}" id="${SF[1]:-}" quality="${SF[2]:-}" hosts="${SF[3]:-}" detail="${SF[4]:-}"
        [[ "$tag" == "#scan" ]] || continue
        n=$(( n + 1 ))
        case "$quality" in
            ok) : ;;
            partial|incomplete) msg_warn "${id}: ${quality} — ${detail}. Its data is marked with *." ;;
            *) msg_warn "${id}: ${quality} — ${detail}. Ignored." ;;
        esac
    done <"$cache"
    SVC_SCANS_READ=$n
}

red_services_list() {
    local all="${1:-0}" cache tag host proto port state service product version extra hostname ls le lq fs fe hist
    local shown=0 total=0 star col seen
    _svc_ensure || return $?
    cache="$(svc_cache "$LAB_ROOT")"
    [[ -r "$cache" ]] || { msg_dim "  No inventory."; return 0; }
    msg_section "URB RED / SERVICES ${G_SEP} $(lab_name "$LAB_ROOT")"
    _svc_scan_warnings
    if (( SVC_SCANS_READ == 0 )); then
        msg_dim "  No nmap XML results yet. Run: urb red recon initial"
        return 0
    fi
    printf '  %s%-16s %-10s %-14s %-12s %-34s %s%s\n' "$C_BOLD" "HOST" "PORT" "STATE" "SERVICE" "VERSION" "SEEN" "$C_RESET"
    local line; local -a SF
    while IFS= read -r line; do
        _svc_fields "$line"
        [[ "$tag" == "svc" ]] || continue
        total=$(( total + 1 ))
        if (( ! all )) && [[ "$state" != "open" ]]; then continue; fi
        shown=$(( shown + 1 ))
        star=""; [[ "$lq" != "ok" ]] && star="*"
        case "$state" in open) col=$T_OK ;; closed) col=$T_BAD ;; *) col=$T_WARN ;; esac
        seen="${ls}${star}"
        printf '  %-16.16s %s%-10s%s %s%-14.14s%s %-12.12s %-34.34s %s%s%s\n' \
            "$host" "$T_KEY" "${port}/${proto}" "$C_RESET" "$col" "${state:-unknown}" "$C_RESET" \
            "${service:-unknown}" "$(_svc_version "$product" "$version" "$extra")" "$T_DIM" "$seen" "$C_RESET"
    done <"$cache"
    printf '\n'
    if (( shown == 0 )); then
        if (( all )); then msg_dim "  No ports recorded in the scans."
        else msg_dim "  No open ports in the latest observations. See all states: urb red services --all"; fi
    fi
    printf '  %s shown · %s recorded (host+port+protocol) · from %s scan(s)%s\n' "$shown" "$total" "$SVC_SCANS_READ" \
        "$( (( ! all )) && printf ' · --all for every state')"
    msg_dim "  Inventory of what nmap observed: an open port is not a finding."
}

red_services_show() {
    local ref="$1" want_host="" want_port="" want_proto="" n=0 cache
    local tag host proto port state service product version extra hostname ls le lq fs fe hist h st
    if [[ "$ref" =~ ^([0-9]{1,5})(/(tcp|udp|sctp))?$ ]]; then
        want_port="${BASH_REMATCH[1]}"; want_proto="${BASH_REMATCH[3]}"
    elif [[ "$ref" =~ ^(.+):([0-9]{1,5})(/(tcp|udp|sctp))?$ ]]; then
        want_host="${BASH_REMATCH[1]}"; want_port="${BASH_REMATCH[2]}"; want_proto="${BASH_REMATCH[4]}"
    else
        msg_err "Invalid service reference '${ref}'. Use: 8080 | 8080/udp | 10.10.10.3:8080[/tcp]"
        return 2
    fi
    _svc_ensure || return $?
    cache="$(svc_cache "$LAB_ROOT")"
    [[ -r "$cache" ]] || { msg_err "No inventory yet. Run: urb red recon initial"; return 1; }
    local line; local -a SF
    while IFS= read -r line; do
        _svc_fields "$line"
        [[ "$tag" == "svc" && "$port" == "$want_port" ]] || continue
        [[ -z "$want_proto" || "$proto" == "$want_proto" ]] || continue
        [[ -z "$want_host" || "$host" == "$want_host" || "$hostname" == "$want_host" ]] || continue
        n=$(( n + 1 ))
        msg_section "${host}:${port}/${proto}"
        printf '  %s%-10s%s %s\n' "$T_LABEL" "Host" "$C_RESET" "${host}${hostname:+ (${hostname})}"
        printf '  %s%-10s%s %s  %s(latest observation: %s, %s%s)%s\n' "$T_LABEL" "State" "$C_RESET" "${state:-unknown}" \
            "$T_DIM" "$ls" "$(_fmt_epoch "$le")" "$( [[ "$lq" != ok ]] && printf ', %s scan' "$lq")" "$C_RESET"
        printf '  %s%-10s%s %s\n' "$T_LABEL" "Service" "$C_RESET" "${service:-unknown}"
        printf '  %s%-10s%s %s\n' "$T_LABEL" "Version" "$C_RESET" "$(_svc_version "$product" "$version" "$extra")"
        printf '  %s%-10s%s %s (%s)\n' "$T_LABEL" "First seen" "$C_RESET" "$fs" "$(_fmt_epoch "$fe")"
        printf '  %s%-10s%s' "$T_LABEL" "History" "$C_RESET"
        for h in $hist; do st="${h#*:}"; printf ' %s=%s' "${h%%:*}" "$st"; done
        printf '\n'
        msg_dim "  Key for future links: ${host}:${port}/${proto}"
    done <"$cache"
    if (( n == 0 )); then msg_err "No service on '${ref}' in this lab's scans."; msg_dim "    See: urb red services --all"; return 1; fi
    return 0
}

red_services() {
    local action="${1:-list}" rc
    (( $# > 0 )) && shift
    case "$action" in -h|--help|help) red_help; return 0 ;; esac
    _red_require_lab || return 1
    case "$action" in
        list|ls)
            case "${1:-}" in
                "")    [[ $# -eq 0 ]] || return 2; red_services_list 0 ;;
                --all) [[ $# -eq 1 ]] || { msg_err "Usage: urb red services list [--all]"; return 2; }; red_services_list 1 ;;
                *)     msg_err "Usage: urb red services list [--all]"; return 2 ;;
            esac ;;
        --all)   [[ $# -eq 0 ]] || { msg_err "Usage: urb red services --all"; return 2; }; red_services_list 1 ;;
        show)    [[ $# -eq 1 ]] || { msg_err "Usage: urb red services show <port|host:port[/proto]>"; return 2; }; red_services_show "$1" ;;
        refresh)
            [[ $# -eq 0 ]] || { msg_err "Usage: urb red services refresh"; return 2; }
            _svc_ensure 1 || return $?
            local svcs; svcs="$(grep -c '^svc' "$(svc_cache "$LAB_ROOT")" 2>/dev/null)"; rc=$?
            msg_ok "Inventory rebuilt from the lab's nmap XML results: ${svcs:-0} host/port entries." ;;
        *) msg_err "Unknown services action: ${action}"; msg_dim "    Usage: urb red services [list [--all]|show <port>|refresh]"; return 2 ;;
    esac
}
