#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  modules/serve.sh — 'urb serve': servidor HTTP local (Command Engine)
#  Usa el servidor de la biblioteca estándar de Python (python3 -m http.server).
#  Seguridad: escucha en 127.0.0.1 salvo que se indique otra dirección; una
#  dirección no local exige confirmación (o --yes). No toca el firewall, no
#  necesita root y no instala nada. Sintaxis y parámetros: commands/serve.spec.
# =============================================================================

[[ -n "${_URB_SERVE_LOADED:-}" ]] && return 0
_URB_SERVE_LOADED=1

_serve_is_local() { [[ "$1" == 127.* || "$1" == "::1" || "$1" == "localhost" ]]; }

serve_main() {
    case "${1:-}" in -h|--help|help) eng_help serve; return $? ;; esac
    eng_load serve || { msg_err "$ENG_ERR"; return 2; }
    eng_parse "$@" || { msg_err "$ENG_ERR"; msg_dim "    See: urb help serve"; return 2; }

    local port bind dir py errno rc url
    port="$(eng_value port)"; bind="$(eng_value bind)"; dir="$(eng_value dir)"
    # Los valores de la configuración también se validan
    eng_valid_value port "$port" || { msg_err "Invalid port: '${port}' (1-65535; check SERVE_PORT in your configuration)"; return 2; }
    eng_valid_value ip "$bind"   || { msg_err "Invalid listen address: '${bind}' (check SERVE_BIND in your configuration)"; return 2; }
    port=$((10#$port))
    if (( port < 1024 && EUID != 0 )); then
        msg_err "Port ${port} is privileged (< 1024) and needs root. Use a higher port, e.g. --port 8000."
        return 2
    fi
    dir="$(urb_expand_path "$dir")"
    [[ -d "$dir" ]] || { msg_err "Directory not found: ${dir}"; return 1; }
    [[ -r "$dir" && -x "$dir" ]] || { msg_err "Directory not readable: ${dir}"; return 1; }
    dir="$(cd -P -- "$dir" && pwd -P)" || return 1

    if ! py="$(svc_python)"; then
        msg_err "python3 is required for 'urb serve' (sudo apt install python3)."
        return 127
    fi

    # Dirección no local: los ficheros quedan expuestos a la red
    if ! _serve_is_local "$bind"; then
        msg_warn "Listening on ${bind} exposes every file under ${dir} to other machines that can reach this address."
        msg_dim "    URB does not open firewall ports; reachability depends on your network and firewall."
        if [[ -z "${ENG_GIVEN[yes]+x}" ]] && ! confirm "Serve ${dir} on ${bind}:${port}?" n; then
            msg_info "Cancelled. Use the default local address, or add --yes to confirm."
            return 1
        fi
    fi

    # Comprobación previa del puerto (mismo tipo de socket que usará http.server)
    errno="$("$py" -I -c '
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
fam = socket.AF_INET6 if ":" in host else socket.AF_INET
s = socket.socket(fam, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind((host, port))
except OSError as e:
    print(e.errno or 0)
    sys.exit(1)
finally:
    s.close()
' "$bind" "$port" 2>/dev/null)"; rc=$?
    if (( rc != 0 )); then
        case "$errno" in
            98|48) msg_err "Port ${port} is already in use on ${bind}. Choose another one: urb serve --port $(( port + 1 ))" ;;
            13)    msg_err "Permission denied to listen on ${bind}:${port}." ;;
            99|49) msg_err "Address ${bind} is not configured on this machine (see: urb network interfaces)." ;;
            *)     msg_err "Cannot listen on ${bind}:${port} (errno ${errno:-?})." ;;
        esac
        return 1
    fi

    case "$bind" in
        0.0.0.0) url="http://$(sys_local_ip):${port}/  (all IPv4 interfaces)" ;;
        ::)      url="http://[::1]:${port}/  (all interfaces)" ;;
        *:*)     url="http://[${bind}]:${port}/" ;;
        *)       url="http://${bind}:${port}/" ;;
    esac
    msg_section "URB SERVE"
    printf '  %s%-9s%s %s\n' "$T_LABEL" "Directory" "$C_RESET" "$dir"
    printf '  %s%-9s%s %s\n' "$T_LABEL" "URL" "$C_RESET" "$url"
    printf '  %s%-9s%s %s\n' "$T_LABEL" "Server" "$C_RESET" "python3 -m http.server ${port} --bind ${bind}"
    msg_dim "  Ctrl+C to stop. Requests are logged below."
    printf '\n'

    # Ctrl+C llega también a Python, que se cierra solo; aquí solo se espera
    trap ':' INT
    ( cd -- "$dir" && exec "$py" -I -m http.server "$port" --bind "$bind" )
    rc=$?
    trap - INT
    printf '\n'
    if (( rc == 0 || rc == 130 )); then
        # 0: salida tras Ctrl+C (KeyboardInterrupt); 130: interrumpido por señal
        msg_ok "Server stopped."
        return 0
    fi
    msg_err "The HTTP server ended with an error (exit ${rc})."
    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -uo pipefail
    URB_HOME="$(cd -P -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd -P)" || exit 1
    # shellcheck source=../lib/utils.sh
    source "${URB_HOME}/lib/utils.sh" && urb_standalone_init || exit 1
    # shellcheck source=../lib/engine.sh
    source "${URB_HOME}/lib/engine.sh" || exit 1
    serve_main "$@"
    exit $?
fi
