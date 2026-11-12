#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/diagnose.sh — Diagnóstico contextual de errores (v1: escaneos nmap)
#
#  Solo analiza lo que YA existe: código de salida, registro y salida de la
#  ejecución anterior. No lanza pings, consultas DNS ni reintentos.
#
#  Cada hallazgo indica su certeza:
#    confirmed → nmap/el sistema lo ha informado explícitamente
#    possible  → hipótesis razonable, NO comprobada
#
#  Para ampliar: añade una regla a DIAG_SCAN_RULES con el formato
#    "certeza|texto literal a buscar|qué ha pasado|qué hacer"
#  (más adelante se podrán añadir comprobaciones de DNS, rutas o conectividad
#  como funciones aparte, siempre bajo demanda).
# =============================================================================

[[ -n "${_URB_DIAG_LOADED:-}" ]] && return 0
_URB_DIAG_LOADED=1

DIAG_SCAN_RULES=(
    "confirmed|Failed to resolve|nmap could not resolve the target hostname.|Check the spelling. Lab hostnames (e.g. box.htb) usually need an entry in /etc/hosts: '<ip>  box.htb'."
    "confirmed|requires root privileges|This scan type needs root privileges.|Use --sudo, or a profile that does not need raw packets (default, quick)."
    "confirmed|Operation not permitted|The system refused a raw network operation (permissions).|Raw-packet scans need root: use --sudo."
    "confirmed|Network is unreachable|There is no route from this machine to the target network.|Check the VPN connection and routes (urb network routes)."
    "possible|Host seems down|nmap got no reply to its host-discovery probes.|This does NOT prove the host is offline: it may block ping probes, or the VPN/route may be down. To skip host discovery: nmap -Pn <target>"
)

DIAG_FOUND=0

_diag_print() {
    local level="$1" what="$2" advice="$3" col
    case "$level" in
        confirmed) col="${T_BAD:-}" ;;
        possible)  col="${T_WARN:-}" ;;
        *)         col="${T_DIM:-}" ;;
    esac
    DIAG_FOUND=$(( DIAG_FOUND + 1 ))
    printf '  %s%-10s%s %s\n' "$col" "$level" "${C_RESET:-}" "$what"
    [[ -n "$advice" ]] && printf '  %-10s %s%s %s%s\n' "" "${T_DIM:-}" "${G_ARROW:->}" "$advice" "${C_RESET:-}"
    return 0
}

# diag_scan CÓDIGO BASE [OBJETIVO] → imprime el diagnóstico (si hay algo que decir)
#   BASE: ruta base de los ficheros de nmap (sin extensión), puede estar vacía
diag_scan() {
    local rc="$1" base="${2:-}" target="${3:-}" rule level pattern what advice f
    local -a files=()
    DIAG_FOUND=0
    is_uint "$rc" || rc=1

    for f in "${base}.log" "${base}.nmap"; do
        [[ -n "$base" && -r "$f" ]] && files+=("$f")
    done

    # Nada que decir: éxito y sin avisos conocidos en la salida
    if (( rc == 0 )) && (( ${#files[@]} == 0 )); then return 0; fi

    local header_done=0
    _diag_header() { (( header_done )) || { msg_section "DIAGNOSIS"; header_done=1; }; }

    case "$rc" in
        127) _diag_header; _diag_print confirmed "nmap is not installed." "sudo apt install nmap"; return 0 ;;
        2)   _diag_header; _diag_print confirmed "Invalid input: nothing was scanned." "See the error above (target, ports or profile)."; return 0 ;;
        130) _diag_header; _diag_print confirmed "Scan cancelled by the user." "Results, if any, are partial."; return 0 ;;
    esac

    if (( ${#files[@]} )); then
        for rule in "${DIAG_SCAN_RULES[@]}"; do
            IFS='|' read -r level pattern what advice <<<"$rule"
            if grep -q -F -- "$pattern" "${files[@]}" 2>/dev/null; then
                _diag_header
                _diag_print "$level" "$what" "${advice//<target>/${target:-<target>}}"
            fi
        done
    fi

    # Contexto local (sin tráfico de red): ¿hay alguna interfaz VPN activa?
    if (( DIAG_FOUND > 0 )) && grep -q -F -e "Host seems down" -e "Network is unreachable" "${files[@]}" 2>/dev/null; then
        if declare -F sys_vpn_detect >/dev/null && [[ -z "$(sys_vpn_detect 2>/dev/null)" ]]; then
            _diag_print possible "No VPN interface (tun/wg) is active on this machine." "Lab targets (HTB/THM) are usually only reachable through the VPN."
        fi
    fi

    if (( rc != 0 && DIAG_FOUND == 0 )); then
        _diag_header
        if [[ -n "$base" && -r "${base}.log" ]]; then
            _diag_print unknown "nmap failed (exit ${rc}); the cause is not recognised." "Read the log: ${base}.log"
        else
            _diag_print unknown "The scan could not be completed (exit ${rc})." "See the messages above."
        fi
    fi
    return 0
}
