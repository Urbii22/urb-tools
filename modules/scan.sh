#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/scan.sh — RECON: interfaz amigable sobre Nmap
#  - Perfiles configurables (config: SCAN_PROFILE_<nombre>)
#  - Progreso REAL: se lee de los informes de nmap (--stats-every)
#  - Resultados en tabla y guardados en .nmap / .xml / .gnmap
#  CLI:  urb scan <objetivo> [--profile P] [-p PUERTOS] [-o DIR] [--no-save] [--sudo]
# =============================================================================

[[ -n "${_URB_SCAN_LOADED:-}" ]] && return 0
_URB_SCAN_LOADED=1

scan_help() {
    cat <<EOF
${C_BOLD}urb scan${C_RESET} — network scanning with nmap

${C_BOLD}USAGE${C_RESET}
  urb scan <target> [options]
  urb scan profiles              List configured scan profiles
  urb scan results               List saved scan results

${C_BOLD}TARGET${C_RESET}
  IPv4 (10.10.10.5), CIDR (192.168.56.0/24), range (10.0.0.1-20),
  IPv6 or hostname (lab.local)

${C_BOLD}OPTIONS${C_RESET}
  -P, --profile NAME   Scan profile (default: $(cfg SCAN_DEFAULT_PROFILE default))
  -p, --ports SPEC     Ports: 22 | 22,80,443 | 1-1024
  -o, --output DIR     Save results in DIR
      --no-save        Do not keep result files
      --sudo           Run nmap through sudo (needed for -sS, -sU, -O)
  -h, --help           Show this help

${C_BOLD}RESULTS${C_RESET}
  Saved as .nmap, .xml and .gnmap. Inside a CTF lab (urb ctf new) results go
  to the lab's scans/ folder; otherwise to: $(urb_scan_dir)

${T_WARN}Only scan targets you own or have explicit written authorization to test.${C_RESET}
EOF
}

# --- Perfiles ------------------------------------------------------------------
scan_profiles() {
    local k
    for k in "${!URB_CFG[@]}"; do
        [[ "$k" == SCAN_PROFILE_* ]] && printf '%s\n' "${k#SCAN_PROFILE_}"
    done | sort
}

# scan_profile_args NOMBRE → rellena el array global SCAN_ARGS (validado)
scan_profile_args() {
    local name="$1" raw tok
    SCAN_ARGS=()
    [[ "$name" =~ ^[A-Za-z0-9_]+$ ]] || { msg_err "Invalid profile name: ${name}"; return 2; }
    raw="${URB_CFG[SCAN_PROFILE_$name]-}"
    if [[ -z "$raw" ]]; then
        msg_err "Unknown scan profile: ${name}"
        msg_dim "    Available: $(scan_profiles | tr '\n' ' ')"
        return 2
    fi
    read -ra SCAN_ARGS <<<"$raw"
    for tok in "${SCAN_ARGS[@]}"; do
        if ! is_safe_nmap_token "$tok"; then
            msg_err "Profile '${name}' contains a disallowed option: ${tok}"
            msg_dim "    File input/output options (-o*, -i*) are managed by URB."
            return 2
        fi
    done
    return 0
}

# ¿Requieren las opciones privilegios de root?
scan_needs_root() {
    local a
    for a in "$@"; do
        case "$a" in
            -sS|-sU|-sA|-sW|-sM|-sN|-sF|-sX|-sY|-sZ|-sO|-O|--traceroute|-PR) return 0 ;;
        esac
    done
    return 1
}

# --- Parseo de resultados --------------------------------------------------------
# scan_parse_gnmap FICHERO → TSV: host  puerto  proto  estado  servicio  versión
scan_parse_gnmap() {
    awk -F'\t' '
        /^Host: / && /Ports: / {
            split($1, h, " "); host = h[2]
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Ports: /) {
                    p = substr($i, 8)
                    n = split(p, ports, /, /)
                    for (j = 1; j <= n; j++) {
                        split(ports[j], f, "/")
                        ver = f[7]; gsub(/\|/, "/", ver)
                        print host "\t" f[1] "\t" f[3] "\t" f[2] "\t" f[5] "\t" ver
                    }
                }
            }
        }' "$1"
}

# Hosts activos según el .gnmap
scan_hosts_up() { awk '/^Host: .*Status: Up/ { print $2 }' "$1" | sort -u; }

# scan_parse_progress "línea" → SCAN_PHASE SCAN_PCT SCAN_ETA (retorna 0 si es línea de progreso)
scan_parse_progress() {
    local line="$1"
    if [[ "$line" =~ ^(.+)[[:space:]]Timing:[[:space:]]About[[:space:]]([0-9]+(\.[0-9]+)?)%[[:space:]]done(\;[[:space:]]ETC:[[:space:]]([0-9:]+)[[:space:]]\(([0-9:]+)[[:space:]]remaining\))? ]]; then
        SCAN_PHASE="${BASH_REMATCH[1]}"
        SCAN_PCT="${BASH_REMATCH[2]}"
        SCAN_ETA="${BASH_REMATCH[6]:-}"
        return 0
    fi
    return 1
}

# Tabla de resultados
scan_render_table() {
    local gnmap="$1" host port proto state service version cur="" n_open=0 col line
    local -a rows
    mapfile -t rows < <(scan_parse_gnmap "$gnmap")
    if (( ${#rows[@]} == 0 )); then
        local up; up="$(scan_hosts_up "$gnmap" | wc -l)"
        if (( up > 0 )); then msg_warn "No open ports reported by nmap (${up} host(s) up)."
        else msg_warn "No open ports reported by nmap (with --open, hosts without open ports are not listed)."
        fi
        return 0
    fi
    for line in "${rows[@]}"; do
        IFS=$'\t' read -r host port proto state service version <<<"$line"
        if [[ "$host" != "$cur" ]]; then
            cur="$host"
            msg_section "HOST ${host}"
            printf '  %s%-11s %-15s %-16s %s%s\n' "$C_BOLD" "PORT" "STATE" "SERVICE" "VERSION" "$C_RESET"
        fi
        case "$state" in
            open)            col=$T_OK; n_open=$(( n_open + 1 )) ;;
            filtered|open\|filtered) col=$T_WARN ;;
            *)               col=$T_BAD ;;
        esac
        printf '  %s%-11s%s %s%-15s%s %s%-16s%s %s\n' \
            "$T_KEY" "${port}/${proto}" "$C_RESET" "$col" "$state" "$C_RESET" \
            "$T_VALUE" "${service:--}" "$C_RESET" "${version:-}"
    done
    printf '\n'
    msg_ok "${n_open} open port(s) found."
}

# --- Ejecución de nmap con progreso real -------------------------------------------
_scan_pid=""
_scan_cancelled=0

_scan_on_int() {
    _scan_cancelled=1
    [[ -n "$_scan_pid" ]] && kill -INT "$_scan_pid" 2>/dev/null
}

# scan_build_cmd BASE USE_SUDO args... objetivo → SCAN_CMD (array con el comando EXACTO)
# Única función que construye el comando de nmap: la usan la ejecución real y
# la previsualización (--dry-run), así que nunca pueden diferir.
scan_build_cmd() {
    local base="$1" use_sudo="$2"; shift 2
    local every; every="$(cfg SCAN_STATS_EVERY 2s)"
    [[ "$every" =~ ^[0-9]+(ms|s|m)?$ ]] || every="2s"
    SCAN_CMD=(nmap "$@" -v --stats-every "$every" -oA "$base")
    if (( use_sudo )); then SCAN_CMD=(sudo -n "${SCAN_CMD[@]}"); fi
    return 0
}

# scan_run_nmap BASE USE_SUDO args... objetivo → código de salida de nmap
scan_run_nmap() {
    local base="$1" use_sudo="$2"; shift 2
    scan_build_cmd "$base" "$use_sudo" "$@"
    local -a cmd=("${SCAN_CMD[@]}")
    local log="${base}.log" fd line partial="" spin=0 start=$SECONDS rc pct_int bar
    local tty=0; [[ -t 1 ]] && tty=1
    SCAN_PHASE="" SCAN_PCT="" SCAN_ETA=""
    local last_pct=""

    : >"$log" || { msg_err "Cannot write ${log}"; return 1; }
    _scan_cancelled=0
    trap '_scan_on_int' INT
    "${cmd[@]}" >"$log" 2>&1 &
    _scan_pid=$!
    exec {fd}<"$log"

    while :; do
        # Leer todas las líneas completas disponibles
        while IFS= read -r line <&"$fd"; do
            line="${partial}${line}"; partial=""
            if [[ "$line" =~ ^Discovered\ open\ port\ ([^ ]+)\ on\ (.+)$ ]]; then
                (( tty )) && printf '\r\e[K'
                printf '  %s%s%s open port %s%-10s%s on %s\n' "$T_OK" "$G_OK" "$C_RESET" "$T_KEY" "${BASH_REMATCH[1]}" "$C_RESET" "${BASH_REMATCH[2]}"
            elif scan_parse_progress "$line"; then
                if (( ! tty )) && [[ "$SCAN_PCT" != "$last_pct" ]]; then
                    printf '  progress: %s %s%%%s\n' "$SCAN_PHASE" "$SCAN_PCT" "${SCAN_ETA:+ (${SCAN_ETA} remaining)}"
                fi
                last_pct="$SCAN_PCT"
            elif [[ "$line" =~ ^(QUITTING|Failed|WARNING|You\ requested|.*requires\ root) ]]; then
                (( tty )) && printf '\r\e[K'
                printf '  %s%s%s\n' "$T_WARN" "$line" "$C_RESET"
            fi
        done
        partial+="$line"
        if (( tty )); then
            local el=$(( SECONDS - start )) fr; fr="$(ui_spinner_frame "$spin")"
            if [[ -n "$SCAN_PCT" ]]; then
                pct_int="${SCAN_PCT%%.*}"
                ui_bar bar "$pct_int" 24
                printf '\r\e[K  %s%s%s %-22.22s %s %s%5s%%%s  %s' "$T_ACCENT" "$fr" "$C_RESET" "$SCAN_PHASE" "$bar" \
                    "$T_VALUE" "$SCAN_PCT" "$C_RESET" "${T_DIM}${SCAN_ETA:+ETA ${SCAN_ETA}  }${el}s${C_RESET}"
            else
                printf '\r\e[K  %s%s%s nmap running %s(%ss elapsed, waiting for nmap progress report)%s' \
                    "$T_ACCENT" "$fr" "$C_RESET" "$T_DIM" "$el" "$C_RESET"
            fi
            spin=$(( spin + 1 ))
        fi
        kill -0 "$_scan_pid" 2>/dev/null || break
        sleep 0.3
    done
    # Vaciar lo que quede
    while IFS= read -r line <&"$fd"; do :; done
    exec {fd}<&-
    wait "$_scan_pid"; rc=$?
    _scan_pid=""
    trap - INT
    (( tty )) && printf '\r\e[K'
    (( _scan_cancelled )) && rc=130
    return "$rc"
}

# Carpeta de salida: laboratorio CTF actual (si existe) o SCAN_DIR
scan_default_outdir() {
    local lab
    if lab="$(ctf_find_lab_root "$PWD")"; then printf '%s/scans' "$lab"; else urb_scan_dir; fi
}

scan_list_results() {
    local dir; dir="$(scan_default_outdir)"
    msg_section "SAVED SCANS (${dir})"
    if [[ ! -d "$dir" ]]; then msg_dim "  No results yet."; return 0; fi
    local found=0 f
    while IFS= read -r f; do
        found=1
        printf '  %s%s%s\n' "$T_VALUE" "${f#"$dir"/}" "$C_RESET"
    done < <(find "$dir" -maxdepth 2 -name '*.nmap' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 20 | cut -d' ' -f2-)
    (( found )) || msg_dim "  No results yet."
    return 0
}

# scan_dry_run OBJETIVO PERFIL CARPETA USE_SUDO args... → previsualización sin efectos:
# no ejecuta nmap, no pide sudo, no crea carpetas ni ficheros y no genera tráfico.
scan_dry_run() {
    local target="$1" profile="$2" outdir="$3" use_sudo="$4"; shift 4
    local -a args=("$@")
    local root=0 base safe stem n=2 q
    [[ -z "$outdir" ]] && outdir="$(scan_default_outdir)"
    outdir="$(urb_expand_path "$outdir")"
    safe="${target//[^A-Za-z0-9._-]/_}"
    base="${outdir}/${safe}_${profile}_$(urb_timestamp)"
    stem="$base"
    while [[ -e "${base}.nmap" || -e "${base}.gnmap" || -e "${base}.xml" || -e "${base}.log" ]]; do
        base="${stem}-${n}"; n=$(( n + 1 ))
    done
    if scan_needs_root "${args[@]}" && (( EUID != 0 )); then root=1; fi
    scan_build_cmd "$base" "$(( use_sudo || root ))" "${args[@]}" "$target"
    printf -v q '%q ' "${SCAN_CMD[@]}"
    msg_section "RECON ${G_SEP} DRY RUN"
    printf '  %s%-8s%s %s\n' "$T_LABEL" "Target" "$C_RESET" "$target"
    printf '  %s%-8s%s %s  %s(%s)%s\n' "$T_LABEL" "Profile" "$C_RESET" "$profile" "$T_DIM" "${args[*]}" "$C_RESET"
    printf '  %s%-8s%s %s.{nmap,xml,gnmap}\n' "$T_LABEL" "Output" "$C_RESET" "$base"
    printf '  %s%-8s%s %s\n' "$T_LABEL" "Command" "$C_RESET" "${q% }"
    if (( root && ! use_sudo )); then
        msg_warn "These options need root: nmap would run through sudo (add --sudo to skip the question)."
    fi
    has_cmd nmap || msg_warn "nmap is not installed (sudo apt install nmap): the real run would fail."
    msg_dim "  Dry run: nothing was executed, no files were created, no traffic was sent."
    return 0
}

# --- CLI ------------------------------------------------------------------------------
scan_main() {
    local target="" profile ports="" outdir="" save=1 use_sudo=0
    profile="$(cfg SCAN_DEFAULT_PROFILE default)"
    # Información de la última ejecución (para diagnósticos como lib/diagnose.sh)
    SCAN_LAST_BASE="" SCAN_LAST_RC=""

    case "${1:-}" in
        profiles)
            msg_section "SCAN PROFILES"
            local p
            while IFS= read -r p; do
                printf '  %s%-10s%s %s\n' "$T_KEY" "$p" "$C_RESET" "${URB_CFG[SCAN_PROFILE_$p]}"
            done < <(scan_profiles)
            return 0 ;;
        results) scan_list_results; return $? ;;
        -h|--help|help) scan_help; return 0 ;;
    esac

    while (( $# > 0 )); do
        case "$1" in
            -P|--profile) [[ $# -ge 2 ]] || { msg_err "--profile needs a value"; return 2; }; profile="$2"; shift 2 ;;
            -p|--ports)   [[ $# -ge 2 ]] || { msg_err "--ports needs a value"; return 2; }; ports="$2"; shift 2 ;;
            -o|--output)  [[ $# -ge 2 ]] || { msg_err "--output needs a value"; return 2; }; outdir="$2"; shift 2 ;;
            --no-save)    save=0; shift ;;
            --sudo)       use_sudo=1; shift ;;
            -h|--help)    scan_help; return 0 ;;
            --) shift; [[ $# -gt 0 ]] && { target="$1"; shift; } ;;
            -*) msg_err "Unknown option: $1"; msg_dim "    See: urb help scan"; return 2 ;;
            *)
                if [[ -n "$target" ]]; then msg_err "Only one target is allowed (got '$target' and '$1')"; return 2; fi
                target="$1"; shift ;;
        esac
    done

    if [[ -z "$target" ]]; then
        msg_err "Missing target."
        msg_dim "    Usage: urb scan <target> [--profile NAME] [-p PORTS]"
        return 2
    fi
    if ! is_valid_target "$target"; then
        msg_err "Invalid target: '${target}'"
        msg_dim "    Expected an IPv4/IPv6 address, CIDR, range (10.0.0.1-20) or hostname."
        return 2
    fi
    if [[ -n "$ports" ]] && ! is_port_spec "$ports"; then
        msg_err "Invalid port specification: '${ports}'"
        return 2
    fi
    # Interfaz INTERNA del Command Engine (lib/engine.sh). No es accesible desde la
    # CLI ni desde el entorno: requiere un ARRAY de Bash definido en este mismo
    # proceso (las variables de entorno no pueden ser arrays).
    #   SCAN_ENGINE_ARGS[]  argumentos de nmap ya resueltos (se validan otra vez)
    #   SCAN_ENGINE_LABEL   etiqueta del perfil para el nombre de fichero
    #   SCAN_ENGINE_OPTS[]  "dry-run" → mostrar el comando y no ejecutar nada
    local engine=0 dry=0 tok
    if [[ "$(declare -p SCAN_ENGINE_ARGS 2>/dev/null)" == "declare -a"* ]] \
       && [[ "${SCAN_ENGINE_LABEL:-}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        engine=1
        [[ "$(declare -p SCAN_ENGINE_OPTS 2>/dev/null)" == "declare -a"* && " ${SCAN_ENGINE_OPTS[*]} " == *" dry-run "* ]] && dry=1
    fi
    local -a args=()
    if (( engine )); then
        for tok in "${SCAN_ENGINE_ARGS[@]}"; do
            is_safe_nmap_token "$tok" || { msg_err "Disallowed nmap option from the command engine: ${tok}"; return 2; }
        done
        args=("${SCAN_ENGINE_ARGS[@]}")
        profile="$SCAN_ENGINE_LABEL"
    else
        scan_profile_args "$profile" || return 2
        args=("${SCAN_ARGS[@]}")
    fi
    [[ -n "$ports" ]] && args+=(-p "$ports")
    is_ipv6 "$target" && args+=(-6)

    if (( dry )); then
        scan_dry_run "$target" "$profile" "$outdir" "$use_sudo" "${args[@]}"
        return $?
    fi

    require_cmd nmap || return 127

    # Privilegios: solo se usa sudo para nmap, y solo si hace falta
    if scan_needs_root "${args[@]}" && (( EUID != 0 )); then
        if (( ! use_sudo )); then
            msg_warn "Profile '${profile}' uses options that require root (raw packets)."
            if confirm "Run nmap with sudo?" n; then use_sudo=1
            else msg_dim "    Re-run with --sudo, or choose a profile like 'default' or 'quick'."; return 1
            fi
        fi
        require_cmd sudo || return 127
        msg_info "sudo authentication (only nmap will run as root)..."
        sudo -v || { msg_err "sudo authentication failed."; return 1; }
    else
        use_sudo=0
    fi

    # Carpeta de salida
    local tmpdir=""
    if (( save )); then
        [[ -z "$outdir" ]] && outdir="$(scan_default_outdir)"
        outdir="$(urb_expand_path "$outdir")"
        mkdir -p -- "$outdir" || { msg_err "Cannot create output directory: ${outdir}"; return 1; }
    else
        tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/urb-scan.XXXXXX")" || { msg_err "Cannot create temp dir"; return 1; }
        outdir="$tmpdir"
    fi
    local safe="${target//[^A-Za-z0-9._-]/_}"
    local base; base="${outdir}/${safe}_${profile}_$(urb_timestamp)"
    # Nunca sobrescribir resultados anteriores (dos escaneos en el mismo segundo)
    local stem="$base" n=2
    while [[ -e "${base}.nmap" || -e "${base}.gnmap" || -e "${base}.xml" || -e "${base}.log" ]]; do
        base="${stem}-${n}"; n=$(( n + 1 ))
    done
    SCAN_LAST_BASE="$base"

    msg_section "RECON ${G_SEP} NMAP"
    printf '  %sTarget%s   %s\n'  "$T_LABEL" "$C_RESET" "$target"
    printf '  %sProfile%s  %s  %s(%s)%s\n' "$T_LABEL" "$C_RESET" "$profile" "$T_DIM" "${args[*]}" "$C_RESET"
    (( save )) && printf '  %sOutput%s   %s.{nmap,xml,gnmap}\n' "$T_LABEL" "$C_RESET" "$base"
    (( use_sudo )) && printf '  %sMode%s     sudo (root)\n' "$T_LABEL" "$C_RESET"
    printf '  %sOnly scan systems you are authorized to test.%s\n\n' "$T_DIM" "$C_RESET"

    local rc
    scan_run_nmap "$base" "$use_sudo" "${args[@]}" "$target"; rc=$?
    SCAN_LAST_RC="$rc"

    if (( use_sudo )); then
        sudo -n chown -- "$(id -u):$(id -g)" "${base}".* 2>/dev/null || true
    fi

    if (( rc == 130 )); then
        msg_warn "Scan cancelled by user."
    elif (( rc != 0 )); then
        msg_err "nmap exited with code ${rc}. Last lines of the log:"
        tail -n 8 -- "${base}.log" 2>/dev/null | sed 's/^/    /'
    fi

    if [[ -s "${base}.gnmap" ]]; then
        scan_render_table "${base}.gnmap"
    fi

    if (( save )); then
        # El registro se conserva solo si nmap falló (útil para diagnosticar)
        if (( rc == 0 )); then rm -f -- "${base}.log"
        elif [[ -s "${base}.log" ]]; then msg_dim "    Log kept: ${base}.log"
        fi
        [[ -e "${base}.nmap" ]] && msg_ok "Results saved: ${base}.nmap (also .xml, .gnmap)"
    else
        rm -rf -- "$tmpdir"
    fi
    return "$rc"
}

# --- Menú interactivo (desde el dashboard) ------------------------------------------
scan_menu() {
    local target profile ports
    local -a profs items
    while :; do
        ui_menu "RECON" "Network Scanning" \
            "New scan|Scan an authorized target with nmap" \
            "Profiles|Show configured nmap profiles" \
            "Results|List saved scan results" \
            "Back|Return to dashboard" || return 0
        case "$UI_CHOICE" in
            0)
                has_cmd nmap || { require_cmd nmap; ui_pause; continue; }
                msg_section "NEW SCAN"
                msg_dim "  Target: IP, CIDR, range or hostname. Empty = cancel."
                ui_prompt target "Target" || continue
                [[ -z "$target" ]] && continue
                if ! is_valid_target "$target"; then msg_err "Invalid target: ${target}"; ui_pause; continue; fi
                mapfile -t profs < <(scan_profiles)
                items=()
                for profile in "${profs[@]}"; do items+=("${profile}|${URB_CFG[SCAN_PROFILE_$profile]}"); done
                ui_menu "RECON" "Choose a profile for ${target}" "${items[@]}" || continue
                profile="${profs[UI_CHOICE]}"
                ui_prompt ports "Ports (optional, e.g. 22,80 or 1-1024)" || continue
                if [[ -n "$ports" ]] && ! is_port_spec "$ports"; then msg_err "Invalid ports: ${ports}"; ui_pause; continue; fi
                if ! confirm "I confirm I am authorized to scan ${target}" n; then continue; fi
                if [[ -n "$ports" ]]; then scan_main "$target" --profile "$profile" -p "$ports"
                else scan_main "$target" --profile "$profile"
                fi
                ui_pause ;;
            1) scan_main profiles; ui_pause ;;
            2) scan_list_results; ui_pause ;;
            *) return 0 ;;
        esac
    done
}

# --- Ejecución independiente: bash modules/scan.sh <args> -----------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    URB_HOME="$(cd -P -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)" || exit 1
    # shellcheck source=../lib/utils.sh
    source "${URB_HOME}/lib/utils.sh" && urb_standalone_init || exit 1
    scan_main "$@"
    exit $?
fi
