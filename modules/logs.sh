#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/logs.sh — LOGS: análisis de registros de seguridad (v1)
#  Fuentes: /var/log/auth.log, /var/log/syslog o journald (journalctl).
#  Todas las líneas se normalizan a: FECHA HORA <tab> host <tab> programa <tab> mensaje
#  CLI: urb logs [summary|auth|ssh|errors|search] [filtros]
# =============================================================================

[[ -n "${_URB_LOGS_LOADED:-}" ]] && return 0
_URB_LOGS_LOADED=1

logs_help() {
    cat <<EOF
${C_BOLD}urb logs${C_RESET} — security log analysis

${C_BOLD}USAGE${C_RESET}
  urb logs [action] [filters]

${C_BOLD}ACTIONS${C_RESET}
  summary        Failed/accepted logins, top source IPs and users (default)
  auth           Authentication failures (ssh, sudo, su, login)
  ssh            All SSH daemon events
  errors         System errors (journal priority err..emerg / syslog)
  search         Free search combined with filters

${C_BOLD}FILTERS${C_RESET}
  --since DATE   YYYY-MM-DD, "YYYY-MM-DD HH:MM", today, yesterday
  --until DATE   Same formats
  --user NAME    Lines mentioning a user
  --ip ADDR      Lines mentioning an IP address
  --grep TEXT    Case-insensitive literal text
  -n N           Show the last N matches (default: $(cfg LOGS_LIMIT 200))
  --file PATH    Analyse a specific log file (e.g. evidence from a lab)
  --sudo         Read system logs through sudo (if your user lacks access)

${T_DIM}Reading system logs needs root or membership of the 'adm' / 'systemd-journal' groups.${C_RESET}
EOF
}

# --- Normalización (awk portable: mawk/gawk) -------------------------------------
# logs_normalize < log  → "YYYY-MM-DD HH:MM:SS\thost\tprog\tmsg"
logs_normalize() {
    local year month
    year="$(printf '%(%Y)T' -1)"; month="$(printf '%(%m)T' -1)"
    awk -v year="$year" -v curmon="$month" '
        BEGIN {
            split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " ")
            for (i = 1; i <= 12; i++) mon[m[i]] = sprintf("%02d", i)
        }
        {
            if ($1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/) {
                d = substr($1, 1, 10); t = substr($1, 12, 8); host = $2; skip = 2
            } else if (($1 in mon) && $2 ~ /^[0-9]+$/) {
                y = year; if (mon[$1] + 0 > curmon + 0) y = year - 1
                d = sprintf("%s-%s-%02d", y, mon[$1], $2); t = $3; host = $4; skip = 4
            } else next
            prog = $(skip + 1); sub(/:$/, "", prog); sub(/\[.*$/, "", prog)
            msg = $0
            for (i = 0; i <= skip; i++) sub(/^[^ ]+ +/, "", msg)
            print d " " t "\t" host "\t" prog "\t" msg
        }'
}

# --- Filtro + categoría ------------------------------------------------------------
# logs_filter CATEGORIA SINCE UNTIL USER IP GREP  < normalizado
logs_filter() {
    local cat="$1" since="$2" until="$3" user="$4" ip="$5" grep="$6"
    local ure="" ire=""
    if [[ -n "$user" ]]; then ure="${user//./\\.}"; fi
    if [[ -n "$ip" ]]; then ire="${ip//./\\.}"; fi
    awk -F'\t' -v cat="$cat" -v since="$since" -v until="$until" -v ure="$ure" -v ire="$ire" -v g="$grep" '
        BEGIN { g = tolower(g) }
        {
            ts = $1; prog = $3; msg = $4
            if (since != "" && ts < since) next
            if (until != "" && ts > until) next
            if (cat == "auth") {
                if (msg !~ /Failed password|Failed publickey|authentication failure|Invalid user|invalid user|FAILED SU|incorrect password attempt|maximum authentication attempts|BREAK-IN|Failed none/) next
            } else if (cat == "ssh") {
                if (prog !~ /^sshd/) next
            } else if (cat == "errors") {
                l = tolower(msg)
                if (l !~ /error|fail|critical|panic|segfault|oom|denied|fatal/) next
            }
            if (ure != "" && msg !~ ("(for|user|user=|ruser=|USER=|by) *(invalid user )?" ure "([^A-Za-z0-9._-]|$)")) next
            if (ire != "" && msg !~ ("(^|[^0-9.])" ire "([^0-9.]|$)")) next
            if (g != "" && index(tolower($0), g) == 0) next
            print
        }'
}

# Resumen: contadores y top de IPs / usuarios
logs_summary_stats() {
    awk -F'\t' '
        {
            msg = $4
            if (msg ~ /Failed password|Failed publickey/) {
                failed++
                u = msg; sub(/.*Failed (password|publickey) for (invalid user )?/, "", u); sub(/ .*/, "", u); fu[u]++
                if (match(msg, /from [0-9a-fA-F:.]+/)) { ip = substr(msg, RSTART + 5, RLENGTH - 5); fip[ip]++ }
            }
            if (msg ~ /Invalid user/) invalid++
            if (msg ~ /Accepted (password|publickey|keyboard-interactive)/) {
                accepted++
                if (match(msg, /for [^ ]+ from [0-9a-fA-F:.]+/)) acc[substr(msg, RSTART + 4, RLENGTH - 4)]++
            }
            if ($3 == "sudo" && msg ~ /incorrect password attempt|authentication failure/) sudofail++
            if ($3 == "sudo" && msg ~ /COMMAND=/) sudocmd++
            if (msg ~ /FAILED SU|su: .*authentication failure/) sufail++
            if (first == "") first = $1
            last = $1; total++
        }
        END {
            printf "STAT\tLines analysed\t%d\n", total
            printf "STAT\tPeriod\t%s -> %s\n", (first == "" ? "-" : first), (last == "" ? "-" : last)
            printf "STAT\tFailed logins (ssh)\t%d\n", failed
            printf "STAT\tInvalid users\t%d\n", invalid
            printf "STAT\tAccepted logins\t%d\n", accepted
            printf "STAT\tsudo failures\t%d\n", sudofail
            printf "STAT\tsudo commands\t%d\n", sudocmd
            printf "STAT\tsu failures\t%d\n", sufail
            for (k in fip) printf "IP\t%s\t%d\n", k, fip[k]
            for (k in fu)  printf "USER\t%s\t%d\n", k, fu[k]
            for (k in acc) printf "ACC\t%s\t%d\n", k, acc[k]
        }'
}

# --- Fuentes ------------------------------------------------------------------------
_logs_can_read_journal() {
    (( EUID == 0 )) && return 0
    local g
    for g in $(id -nG 2>/dev/null); do
        case "$g" in adm|systemd-journal|wheel) return 0 ;; esac
    done
    return 1
}

# logs_fetch TIPO(auth|errors) SINCE UNTIL SUDO FILE → líneas crudas por stdout
logs_fetch() {
    local kind="$1" since="$2" until="$3" use_sudo="$4" file="$5"
    local -a pre=()
    (( use_sudo )) && (( EUID != 0 )) && pre=(sudo)
    if [[ -n "$file" ]]; then
        case "$file" in
            *.gz) "${pre[@]}" zcat -- "$file" ;;
            *)    "${pre[@]}" cat -- "$file" ;;
        esac
        return $?
    fi
    local f
    if [[ "$kind" == "auth" ]]; then
        for f in /var/log/auth.log /var/log/secure; do
            if [[ -f "$f" ]]; then
                if [[ -r "$f" ]] || (( ${#pre[@]} )); then
                    [[ -f "${f}.1" ]] && "${pre[@]}" cat -- "${f}.1" 2>/dev/null
                    "${pre[@]}" cat -- "$f"; return $?
                fi
            fi
        done
    else
        for f in /var/log/syslog /var/log/messages; do
            if [[ -f "$f" ]] && { [[ -r "$f" ]] || (( ${#pre[@]} )); }; then "${pre[@]}" cat -- "$f"; return $?; fi
        done
    fi
    if has_cmd journalctl; then
        local -a jargs=(--no-pager -q -o short-iso)
        [[ -n "$since" ]] && jargs+=(--since "$since")
        [[ -n "$until" ]] && jargs+=(--until "$until")
        if [[ "$kind" == "auth" ]]; then jargs+=(SYSLOG_FACILITY=4 SYSLOG_FACILITY=10)
        else jargs+=(-p err)
        fi
        if (( ${#pre[@]} == 0 )) && ! _logs_can_read_journal; then
            msg_warn "Your user cannot read the system journal (not in 'adm' or 'systemd-journal')."
            msg_dim "    Use --sudo, or: sudo usermod -aG adm \$USER  (then log in again)"
        fi
        "${pre[@]}" journalctl "${jargs[@]}" 2>/dev/null
        return 0
    fi
    msg_err "No readable log source found (auth.log / syslog / journalctl)."
    return 1
}

# Convierte fechas de usuario a "YYYY-MM-DD HH:MM:SS" (vacío = sin filtro)
logs_parse_date() {
    local d="$1" end="$2"
    case "$d" in
        "") printf ''; return 0 ;;
        today)     d="$(printf '%(%Y-%m-%d)T' -1)" ;;
        yesterday) d="$(date -d yesterday +%F 2>/dev/null)" || return 1 ;;
    esac
    if [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        if (( end )); then printf '%s 23:59:59' "$d"; else printf '%s 00:00:00' "$d"; fi
    elif [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
        if (( end )); then printf '%s:59' "$d"; else printf '%s:00' "$d"; fi
    elif [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        printf '%s' "$d"
    else
        return 1
    fi
}

# Pinta líneas normalizadas con colores
logs_print() {
    local ts host prog msg col n=0
    while IFS=$'\t' read -r ts host prog msg; do
        n=$(( n + 1 ))
        col=$T_VALUE
        case "$msg" in
            *Failed*|*Invalid\ user*|*failure*|*FAILED*|*incorrect*|*BREAK-IN*|*error*|*Error*) col=$T_BAD ;;
            *Accepted*|*session\ opened*) col=$T_OK ;;
            *Disconnected*|*closed*) col=$T_DIM ;;
        esac
        printf '%s%s%s %s%-14.14s%s %s%s%s\n' "$T_DIM" "$ts" "$C_RESET" "$T_KEY" "$prog" "$C_RESET" "$col" "$msg" "$C_RESET"
    done
    return 0
}

_logs_print_summary() {
    local type k v
    local -a ips=() users=() accs=()
    msg_section "AUTH SUMMARY"
    while IFS=$'\t' read -r type k v; do
        case "$type" in
            STAT) printf '  %s%-22s%s %s\n' "$T_LABEL" "$k" "$C_RESET" "$v" ;;
            IP)   ips+=("${v}"$'\t'"${k}") ;;
            USER) users+=("${v}"$'\t'"${k}") ;;
            ACC)  accs+=("${v}"$'\t'"${k}") ;;
        esac
    done
    _logs_top() {
        local title="$1"; shift
        (( $# )) || return 0
        msg_section "$title"
        printf '%s\n' "$@" | sort -t$'\t' -k1,1nr | head -n 8 | while IFS=$'\t' read -r v k; do
            printf '  %s%6d%s  %s\n' "$T_BAD" "$v" "$C_RESET" "$k"
        done
    }
    _logs_top "TOP SOURCE IPs (failed logins)" "${ips[@]}"
    _logs_top "TOP TARGETED USERS" "${users[@]}"
    if (( ${#accs[@]} )); then
        msg_section "ACCEPTED LOGINS (user from ip)"
        printf '%s\n' "${accs[@]}" | sort -t$'\t' -k1,1nr | head -n 8 | while IFS=$'\t' read -r v k; do
            printf '  %s%6d%s  %s\n' "$T_OK" "$v" "$C_RESET" "$k"
        done
    fi
    return 0
}

# --- CLI --------------------------------------------------------------------------------
logs_main() {
    local action="summary"
    case "${1:-}" in
        summary|auth|ssh|errors|search) action="$1"; shift ;;
        -h|--help|help) logs_help; return 0 ;;
        -*|"") ;;
        *) msg_err "Unknown logs action: $1"; msg_dim "    See: urb help logs"; return 2 ;;
    esac
    local since="" until="" user="" ip="" grep="" limit file="" use_sudo=0
    limit="$(cfg LOGS_LIMIT 200)"
    while (( $# > 0 )); do
        case "$1" in
            --since|--until|--user|--ip|--grep|-n|--file)
                [[ $# -ge 2 ]] || { msg_err "$1 needs a value"; return 2; } ;;
        esac
        case "$1" in
            --since) since="$2"; shift 2 ;;
            --until) until="$2"; shift 2 ;;
            --user)  user="$2"; shift 2 ;;
            --ip)    ip="$2"; shift 2 ;;
            --grep)  grep="$2"; shift 2 ;;
            -n)      limit="$2"; shift 2 ;;
            --file)  file="$2"; shift 2 ;;
            --sudo)  use_sudo=1; shift ;;
            *) msg_err "Unknown option: $1"; msg_dim "    See: urb help logs"; return 2 ;;
        esac
    done

    # Validación de filtros
    local s u
    s="$(logs_parse_date "$since" 0)" || { msg_err "Invalid --since date: '${since}' (use YYYY-MM-DD [HH:MM], today, yesterday)"; return 2; }
    u="$(logs_parse_date "$until" 1)" || { msg_err "Invalid --until date: '${until}'"; return 2; }
    if [[ -n "$user" ]] && ! is_username "$user"; then msg_err "Invalid user name: '${user}'"; return 2; fi
    if [[ -n "$ip" ]] && ! is_ipv4 "$ip" && ! is_ipv6 "$ip"; then msg_err "Invalid IP address: '${ip}'"; return 2; fi
    if (( ${#grep} > 200 )); then msg_err "--grep text too long"; return 2; fi
    is_uint "$limit" && (( limit >= 1 )) || { msg_err "-n needs a positive number"; return 2; }
    if [[ -n "$file" ]]; then
        file="$(urb_expand_path "$file")"
        [[ -f "$file" ]] || { msg_err "File not found: ${file}"; return 1; }
        [[ -r "$file" ]] || (( use_sudo )) || { msg_err "Cannot read ${file} (try --sudo)"; return 1; }
    fi
    (( use_sudo )) && (( EUID != 0 )) && { require_cmd sudo || return 127; sudo -v || return 1; }

    local kind="auth" cat="$action"
    [[ "$action" == "errors" ]] && kind="errors"
    [[ "$action" == "search" ]] && cat="all"
    [[ "$action" == "summary" ]] && cat="all"

    local -a lines
    mapfile -t lines < <(logs_fetch "$kind" "${s:0:19}" "${u:0:19}" "$use_sudo" "$file" | logs_normalize | logs_filter "$cat" "$s" "$u" "$user" "$ip" "$grep")

    if [[ "$action" == "summary" ]]; then
        if (( ${#lines[@]} == 0 )); then msg_warn "No authentication log lines found for the given filters."; return 0; fi
        printf '%s\n' "${lines[@]}" | logs_summary_stats | _logs_print_summary
        return 0
    fi

    msg_section "LOGS ${G_SEP} ${action^^}"
    local filt=""
    [[ -n "$s" ]] && filt+=" since=${s}"; [[ -n "$u" ]] && filt+=" until=${u}"
    [[ -n "$user" ]] && filt+=" user=${user}"; [[ -n "$ip" ]] && filt+=" ip=${ip}"; [[ -n "$grep" ]] && filt+=" grep=\"${grep}\""
    [[ -n "$filt" ]] && msg_dim "  Filters:${filt}"
    if (( ${#lines[@]} == 0 )); then msg_warn "No matching entries."; return 0; fi
    local start=0
    (( ${#lines[@]} > limit )) && start=$(( ${#lines[@]} - limit ))
    printf '%s\n' "${lines[@]:start}" | logs_print
    printf '\n'
    msg_info "${#lines[@]} matching line(s)$( (( start > 0 )) && printf ', showing last %d (-n to change)' "$limit")."
    return 0
}

logs_menu() {
    local a v
    local -a extra
    while :; do
        ui_menu "LOGS" "Security Log Analysis" \
            "Summary|Failed / accepted logins, top IPs and users" \
            "Auth failures|ssh, sudo, su and login failures" \
            "SSH events|All sshd activity" \
            "System errors|Errors from journal / syslog" \
            "Search|Filter by date, user, IP or text" \
            "Back|Return to dashboard" || return 0
        extra=()
        _logs_can_read_journal || { [[ -r /var/log/auth.log ]] || extra+=(--sudo); }
        case "$UI_CHOICE" in
            0) a=summary ;; 1) a=auth ;; 2) a=ssh ;; 3) a=errors ;;
            4) a=search
               msg_section "SEARCH"; msg_dim "  Leave a field empty to skip it."
               ui_prompt v "Since (YYYY-MM-DD / today)"; [[ -n "$v" ]] && extra+=(--since "$v")
               ui_prompt v "Until (YYYY-MM-DD)";        [[ -n "$v" ]] && extra+=(--until "$v")
               ui_prompt v "User";                      [[ -n "$v" ]] && extra+=(--user "$v")
               ui_prompt v "IP address";                [[ -n "$v" ]] && extra+=(--ip "$v")
               ui_prompt v "Text";                      [[ -n "$v" ]] && extra+=(--grep "$v") ;;
            *) return 0 ;;
        esac
        if [[ " ${extra[*]} " == *" --sudo "* ]]; then
            msg_warn "Your user cannot read system logs directly; sudo will be used for reading only."
            sudo -v || { msg_err "sudo authentication failed."; ui_pause; continue; }
        fi
        if has_cmd less; then
            logs_main "$a" "${extra[@]}" 2>&1 | less -R -F -X
        else
            logs_main "$a" "${extra[@]}"
        fi
        ui_pause
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    URB_HOME="$(cd -P -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)" || exit 1
    # shellcheck source=../lib/utils.sh
    source "${URB_HOME}/lib/utils.sh" && urb_standalone_init || exit 1
    logs_main "$@"
    exit $?
fi
