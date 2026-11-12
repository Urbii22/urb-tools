#!/usr/bin/env bash
# Pruebas del Scan Manager (urb red scans), del inventario de servicios
# (urb red services) y de 'findings evidence --scan'. Sin nmap ni red: los
# resultados se generan como ficheros.

_URB() { "$URB_HOME/bin/urb" --no-color "$@"; }
_LAB() { printf '%s/urb-labs/%s' "$HOME" "${1:-demo}"; }
_newlab() { _URB red lab new "${1:-demo}" --target 127.0.0.1 >/dev/null; }

# _xml FICHERO EPOCH FINALIZADO(1|0) "host|proto|puerto|estado|servicio|producto|versión" ...
_xml() {
    local f="$1" start="$2" fin="$3" spec cur="" host proto port state svc prod ver
    shift 3
    {
        printf '<?xml version="1.0"?>\n<nmaprun scanner="nmap" args="nmap -sV" start="%s" version="7.98">\n' "$start"
        for spec in "$@"; do
            IFS='|' read -r host proto port state svc prod ver <<<"$spec"
            if [[ "$host" != "$cur" ]]; then
                [[ -n "$cur" ]] && printf '</ports></host>\n'
                printf '<host><status state="up"/><address addr="%s" addrtype="ipv4"/><hostnames><hostname name="h-%s"/></hostnames><ports>\n' "$host" "${host##*.}"
                cur="$host"
            fi
            printf '<port protocol="%s" portid="%s"><state state="%s"/>' "$proto" "$port" "$state"
            if [[ -n "$svc" ]]; then
                printf '<service name="%s"%s%s/>' "$svc" "${prod:+ product=\"$prod\"}" "${ver:+ version=\"$ver\"}"
            fi
            printf '</port>\n'
        done
        [[ -n "$cur" ]] && printf '</ports></host>\n'
        (( fin )) && printf '<runstats><finished time="%s" exit="success"/></runstats>\n' "$(( start + 5 ))"
        (( fin )) && printf '</nmaprun>\n'
    } >"$f"
}

# _run BASE EPOCH FINALIZADO specs... → crea .xml, .nmap y .gnmap de una ejecución
_run() {
    local base="$1" start="$2" fin="$3"; shift 3
    local d; d="$(_LAB "${RUN_LAB:-demo}")/scans"
    _xml "${d}/${base}.xml" "$start" "$fin" "$@"
    printf '# Nmap scan\n%s\n' "$( (( fin )) && echo '# Nmap done')" >"${d}/${base}.nmap"
    : >"${d}/${base}.gnmap"
}

test_investigation_links_and_reports() {
    command -v python3 >/dev/null || return 0
    _newlab
    _run t_default_20261110-090000 1794300000 1 "127.0.0.1|tcp|8080|open|http|Server|1" "127.0.0.2|tcp|8080|open|http|Server|1"
    _URB red findings add "Check HTTP" >/dev/null
    assert_status 1 _URB red findings link F-001 --service 8080
    assert_status 1 _URB red findings link F-001 --service 9999
    assert_status 0 _URB red findings link F-001 --service 127.0.0.1:8080/tcp
    assert_status 0 _URB red findings link F-001 --service 127.0.0.1:8080/tcp
    assert_eq "$(grep -c '^service_link=' "$(_LAB)/findings/F-001.finding")" 1
    assert_contains "$(_URB red findings show F-001)" '127.0.0.1:8080/tcp'
    local out; out="$(_URB red report preview)"
    assert_contains "$out" 'Check HTTP'
    assert_contains "$out" 'Evidence: none linked'
    assert_contains "$out" '127.0.0.1:8080/tcp'
    local original; original="$(cat "$(_LAB)/report.md")"
    assert_status 0 _URB red report generate --output "$HOME/result.md"
    assert_status 1 _URB red report generate --output "$HOME/result.md"
    assert_eq "$(cat "$(_LAB)/report.md")" "$original"
    assert_status 0 _URB red report generate
    assert_status 0 _URB red findings unlink F-001 --service 127.0.0.1:8080/tcp
    assert_not_contains "$(cat "$(_LAB)/findings/F-001.finding")" 'service_link=127.0.0.1:8080/tcp'
}

test_investigation_diff_observations() {
    command -v python3 >/dev/null || return 0
    _newlab
    mkdir -p "$HOME/mockbin"
    printf '#!/bin/sh\ntouch "$HOME/network-called"\nexit 99\n' >"$HOME/mockbin/nmap"
    chmod +x "$HOME/mockbin/nmap"
    export PATH="$HOME/mockbin:$PATH"
    _run t_quick_20261110-090000 1794300000 1 "127.0.0.1|tcp|80|open|http|Server|1" "127.0.0.1|tcp|22|open|ssh||"
    _run t_full_20261111-090000 1794390000 1 "127.0.0.1|tcp|80|closed|https|Server|2" "127.0.0.1|tcp|443|open|https||"
    local out; out="$(_URB red scans diff S-001 S-002)"
    assert_contains "$out" 'explicit state change | open | closed'
    assert_contains "$out" 'not observed after | open | not observed'
    assert_contains "$out" 'newly observed open'
    assert_contains "$out" 'UNCERTAIN'
    assert_contains "$out" 'version | Server 1 | Server 2'
    assert_contains "$out" 'service identification | http | https'
    _URB red report preview >/dev/null
    [[ ! -e "$HOME/network-called" ]] || _fail "investigation unexpectedly ran nmap"
    printf 'broken' >"$(_LAB)/scans/t_full_20261111-090000.xml"
    assert_status 1 _URB red scans diff S-001 S-002
}

test_investigation_empty_missing_evidence_and_partial() {
    command -v python3 >/dev/null || return 0
    _newlab
    local out
    out="$(_URB red report preview)"
    assert_contains "$out" 'No scans recorded'
    assert_contains "$out" 'No findings recorded'
    _run t_default_20261110-090000 1794300000 1 "127.0.0.1|tcp|80|open|http||"
    _run t_default_20261111-090000 1794390000 0 "127.0.0.1|tcp|80|closed|http||"
    out="$(_URB red scans diff S-001 S-002)"
    assert_contains "$out" 'UNCERTAIN'
    _URB red findings add "Evidence check" >/dev/null
    printf 'evidence' >"$(_LAB)/evidence/check.txt"
    _URB red findings evidence F-001 "$(_LAB)/evidence/check.txt" >/dev/null
    rm "$(_LAB)/evidence/check.txt"
    assert_contains "$(_URB red report preview)" 'missing or outside lab'
    assert_contains "$(_URB red report preview)" 'Scan quality:'
}

test_investigation_concurrent_links_and_stale_key() {
    command -v python3 >/dev/null || return 0
    _newlab
    _run t_default_20261110-090000 1794300000 1 "127.0.0.1|tcp|80|open|http||" "127.0.0.1|tcp|443|open|https||"
    _URB red findings add "Legacy compatible" >/dev/null
    _URB red services >/dev/null
    _URB red findings link F-001 --service 80 >/dev/null & local p1=$!
    _URB red findings link F-001 --service 443 >/dev/null & local p2=$!
    wait "$p1" || _fail 'first concurrent link failed'
    wait "$p2" || _fail 'second concurrent link failed'
    assert_eq "$(grep -c '^service_link=' "$(_LAB)/findings/F-001.finding")" 2
    rm "$(_LAB)/scans/t_default_20261110-090000.xml"
    assert_contains "$(_URB red findings show F-001)" 'not in current inventory'
    assert_status 0 _URB red findings unlink F-001 --service 127.0.0.1:80/tcp
}

test_scans_index_existing_runs_by_time_and_stable_ids() {
    _newlab
    # Escaneos "antiguos" sin índice, creados en desorden
    _run 127.0.0.1_default_20261110-090000 1794300000 1 "127.0.0.1|tcp|22|open|ssh||"
    _run 127.0.0.1_quick_20261108-100000 1794130000 1 "127.0.0.1|tcp|80|open|http||"
    _run 10.10.10.3_full_20261109-120000 1794210000 1 "10.10.10.3|tcp|21|open|ftp||"
    local out; out="$(_URB red scans)"
    assert_eq "$?" 0
    assert_contains "$out" "S-001   2026-11-08"
    assert_contains "$out" "S-002   2026-11-09"
    assert_contains "$out" "S-003   2026-11-10"
    assert_contains "$out" "latest complete: S-003"
    local idx; idx="$(cat "$(_LAB)/scans/.index")"
    # Un escaneo nuevo (aunque su fecha sea anterior) recibe el siguiente ID
    _run 127.0.0.1_default_20261101-080000 1793520000 1 "127.0.0.1|tcp|25|open|smtp||"
    _URB red scans >/dev/null
    assert_contains "$(cat "$(_LAB)/scans/.index")" "$idx"
    assert_contains "$(cat "$(_LAB)/scans/.index")" "S-004|127.0.0.1_default_20261101-080000"
    # Repetir no cambia nada
    local again; again="$(cat "$(_LAB)/scans/.index")"
    _URB red scans >/dev/null; _URB red scans list >/dev/null
    assert_eq "$(cat "$(_LAB)/scans/.index")" "$again"
}

test_scans_latest_status_and_missing_files() {
    _newlab
    local d; d="$(_LAB)/scans"
    _run t_default_20261110-090000 1794300000 1 "127.0.0.1|tcp|22|open|ssh||"
    _run t_default_20261111-090000 1794390000 0 "127.0.0.1|tcp|80|open|http||"     # interrumpido
    _run t_default_20261112-090000 1794480000 1 "127.0.0.1|tcp|443|open|https||"
    printf 'nmap error\n' >"$d/t_default_20261112-090000.log"                           # falló
    rm "$d/t_default_20261112-090000.xml"
    local out; out="$(_URB red scans)"
    assert_contains "$out" "S-001"
    assert_contains "$out" "complete"
    assert_contains "$out" "incomplete"
    assert_contains "$out" "failed"
    # latest = el último COMPLETO (S-001), no el interrumpido ni el fallido
    assert_contains "$(_URB red scans show latest)" "S-001"
    assert_contains "$(_URB red scans show S-002)" "did not finish"
    # Ficheros borrados: el ID se conserva y se marca como missing
    rm "$d"/t_default_20261110-090000.*
    out="$(_URB red scans)"
    assert_contains "$out" "missing"
    assert_contains "$out" "latest complete: none"
    assert_contains "$(_URB red scans show S-001)" "no longer exist"
    out="$(_URB red scans show latest 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "no complete scan"
    assert_status 2 _URB red scans show X-1
    assert_status 1 _URB red scans show S-050
}

test_scans_index_corruption_and_concurrency() {
    _newlab
    local i d; d="$(_LAB)/scans"
    for i in 1 2 3 4 5; do _run "t_default_2026111${i}-090000" "179430000${i}" 1 "127.0.0.1|tcp|2${i}|open|x||"; done
    for i in 1 2 3 4 5 6; do _URB red scans >/dev/null 2>&1 & done
    wait
    assert_eq "$(grep -c '^S-' "$d/.index")" "5"
    assert_eq "$(cut -d'|' -f2 "$d/.index" | sort -u | wc -l)" "5"
    compgen -G "$d/.tmp.*" >/dev/null && _fail "temporary files left"
    # Línea dañada: se avisa, se ignora y el resto se conserva
    printf 'garbage|||\n' >>"$d/.index"
    local out; out="$(_URB red scans 2>&1)"
    assert_contains "$out" "damaged line"
    assert_contains "$out" "S-005"
    # Índice perdido: se reconstruye desde los ficheros (los IDs pueden cambiar)
    rm "$d/.index"
    _URB red scans >/dev/null
    assert_eq "$(grep -c '^S-' "$d/.index")" "5"
}

test_findings_evidence_by_scan_reference() {
    _newlab
    _run t_default_20261110-090000 1794300000 1 "127.0.0.1|tcp|22|open|ssh||"
    _run t_default_20261111-090000 1794390000 1 "127.0.0.1|tcp|80|open|http||"
    _URB red findings add "HTTP" >/dev/null
    local out f
    f="$(_LAB)/findings/F-001.finding"
    out="$(_URB red findings evidence F-001 --scan latest)"
    assert_eq "$?" 0
    assert_contains "$out" "S-002 → scans/t_default_20261111-090000.nmap"
    assert_contains "$(_URB red findings evidence F-001 --scan S-2)" "already linked"
    assert_status 0 _URB red findings evidence F-001 --scan S-001
    assert_eq "$(grep -c '^evidence=' "$f")" "2"
    # Forma anterior intacta y sin duplicar la misma ruta
    assert_contains "$(_URB red findings evidence F-001 scans/t_default_20261110-090000.nmap)" "already linked"
    assert_status 1 _URB red findings evidence F-001 --scan S-099
    assert_status 2 _URB red findings evidence F-001 --scan bogus
    # Escaneo sin .nmap
    rm "$(_LAB)/scans/t_default_20261111-090000.nmap"
    assert_status 1 _URB red findings evidence F-001 --scan S-002
    # Laboratorio sin escaneos
    _newlab empty; _URB red findings add "x" >/dev/null
    out="$(_URB red findings evidence F-001 --scan latest 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "no scans in this lab"
}

test_scans_are_isolated_per_lab() {
    _newlab one; RUN_LAB=one _run a_default_20261110-090000 1794300000 1 "10.0.0.1|tcp|22|open|ssh||"
    _newlab two; RUN_LAB=two _run b_default_20261110-090000 1794300000 1 "10.0.0.2|tcp|80|open|http||"
    assert_contains "$(_URB red scans)" "b"
    assert_not_contains "$(_URB red scans)" "a  "
    assert_contains "$(cd "$(_LAB one)" && _URB red scans)" "S-001"
    assert_contains "$(cd "$(_LAB one)" && _URB red services)" "10.0.0.1"
    assert_not_contains "$(cd "$(_LAB one)" && _URB red services)" "10.0.0.2"
    assert_not_contains "$(_URB red services)" "10.0.0.1"
}

test_services_inventory_multi_host_tcp_udp_unknown_versions() {
    command -v python3 >/dev/null || { echo "python3 missing: skipped"; return 0; }
    _newlab
    _run t_default_20261110-090000 1794300000 1 \
        "10.0.0.5|tcp|22|open|ssh|OpenSSH|9.6" "10.0.0.5|udp|161|open|snmp||" "10.0.0.5|tcp|8080|open|http||" \
        "10.0.0.9|tcp|22|open|ssh|OpenSSH|8.9" "10.0.0.9|tcp|3306|filtered|mysql||" "10.0.0.9|tcp|9999|open|||"
    local out; out="$(_URB red services)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "10.0.0.5         22/tcp"
    assert_contains "$out" "161/udp"
    assert_contains "$out" "OpenSSH 9.6"
    assert_contains "$out" "OpenSSH 8.9"
    assert_contains "$out" "8080/tcp   open           http         unknown"
    assert_contains "$out" "9999/tcp   open           unknown"
    assert_not_contains "$out" "3306"
    assert_contains "$(_URB red services --all)" "3306/tcp   filtered"
    assert_contains "$(_URB red services show 161/udp)" "snmp"
    assert_contains "$(_URB red services show 10.0.0.9:22)" "OpenSSH 8.9"
    assert_eq "$(_URB red services show 22 | grep -c 'Host ')" "2"
    assert_status 1 _URB red services show 1234
    assert_status 2 _URB red services show 'x;id'
}

test_services_latest_observation_wins_and_absence_is_not_closed() {
    command -v python3 >/dev/null || return 0
    _newlab
    _run t_default_20261110-090000 1794300000 1 "10.0.0.5|tcp|80|open|http|Apache|2.4.1" "10.0.0.5|tcp|21|open|ftp||"
    _run t_default_20261111-090000 1794390000 1 "10.0.0.5|tcp|80|closed|http||"
    _run t_default_20261112-090000 1794480000 1 "10.0.0.5|tcp|22|open|ssh||"
    local out
    out="$(_URB red services)"
    # 80 se vio cerrado después: no se presenta como abierto
    assert_not_contains "$out" "80/tcp"
    # 21 no aparece en escaneos posteriores: sigue con su última observación (open)
    assert_contains "$out" "21/tcp     open"
    assert_contains "$out" "22/tcp     open"
    out="$(_URB red services --all)"
    assert_contains "$out" "80/tcp     closed"
    out="$(_URB red services show 80)"
    assert_contains "$out" "latest observation: S-002"
    assert_contains "$out" "S-001=open S-002=closed"
    assert_contains "$out" "First seen S-001"
    # Sin duplicados: una fila por host+puerto+protocolo
    assert_eq "$(grep -c $'^svc\t10.0.0.5\ttcp\t80\t' "$(_LAB)/scans/.services")" "1"
}

test_services_partial_and_invalid_xml_do_not_break_others() {
    command -v python3 >/dev/null || return 0
    _newlab
    local d; d="$(_LAB)/scans"
    _run good_default_20261110-090000 1794300000 1 "10.0.0.1|tcp|22|open|ssh||"
    # Truncado a mitad: el primer host completo debe recuperarse
    _xml "$d/trunc_default_20261111-090000.xml" 1794390000 1 "10.0.0.2|tcp|80|open|http||" "10.0.0.3|tcp|443|open|https||"
    head -c "$(( $(grep -b -o '<host><status' "$d/trunc_default_20261111-090000.xml" | tail -n 1 | cut -d: -f1) + 30 ))" \
        "$d/trunc_default_20261111-090000.xml" >"$d/t.tmp" && mv "$d/t.tmp" "$d/trunc_default_20261111-090000.xml"
    printf 'this is not xml at all\n' >"$d/broken_default_20261112-090000.xml"
    local out; out="$(_URB red services 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "10.0.0.1"
    assert_contains "$out" "10.0.0.2"
    assert_not_contains "$out" "10.0.0.3"
    assert_contains "$out" "S-002: partial"
    assert_contains "$out" "S-003: invalid"
    assert_contains "$out" "S-002*"
    assert_contains "$(_URB red scans)" "incomplete"
}

test_services_cache_refresh_and_no_rebuild_when_unchanged() {
    command -v python3 >/dev/null || return 0
    _newlab
    _run t_default_20261110-090000 1794300000 1 "10.0.0.1|tcp|22|open|ssh||"
    # python3 "espía" para contar reconstrucciones
    mkdir -p "$HOME/spy"
    printf '#!/bin/sh\necho run >>"%s/py.log"\nexec python3 "$@"\n' "$HOME" >"$HOME/spy/python3"; chmod +x "$HOME/spy/python3"
    export URB_PYTHON="$HOME/spy/python3"
    _URB red services >/dev/null; _URB red services >/dev/null; _URB red services show 22 >/dev/null
    assert_eq "$(wc -l <"$HOME/py.log")" "1"
    # Un XML nuevo invalida la caché
    _run t_default_20261111-090000 1794390000 1 "10.0.0.1|tcp|80|open|http||"
    assert_contains "$(_URB red services)" "80/tcp"
    assert_eq "$(wc -l <"$HOME/py.log")" "2"
    # refresh fuerza la reconstrucción
    assert_contains "$(_URB red services refresh)" "Inventory rebuilt"
    assert_eq "$(wc -l <"$HOME/py.log")" "3"
    # Caché borrada o corrupta: se reconstruye
    printf 'garbage\n' >"$(_LAB)/scans/.services"
    assert_contains "$(_URB red services)" "22/tcp"
}

test_services_no_network_no_nmap_and_missing_python() {
    _newlab
    _run t_default_20261110-090000 1794300000 1 "10.0.0.1|tcp|22|open|ssh||"
    # Trampas: si se ejecuta nmap, ping o curl, queda registrado
    mkdir -p "$HOME/trap"
    local t; for t in nmap ping curl nc; do
        printf '#!/bin/sh\necho "%s $*" >>"%s/trap.log"\nexit 1\n' "$t" "$HOME" >"$HOME/trap/$t"; chmod +x "$HOME/trap/$t"
    done
    if command -v python3 >/dev/null; then
        PATH="$HOME/trap:$PATH" _URB red services >/dev/null
        PATH="$HOME/trap:$PATH" _URB red services refresh >/dev/null
        PATH="$HOME/trap:$PATH" _URB red scans >/dev/null
        PATH="$HOME/trap:$PATH" _URB red scans show latest >/dev/null
        _URB red findings add "x" >/dev/null
        PATH="$HOME/trap:$PATH" _URB red findings evidence F-001 --scan latest >/dev/null
        [[ ! -e "$HOME/trap.log" ]] || _fail "a network tool was executed: $(cat "$HOME/trap.log")"
    fi
    # Sin python3: mensaje claro y código 127 (escaneos siguen funcionando)
    rm -f "$(_LAB)/scans/.services"
    local out; out="$(URB_PYTHON=/nonexistent/python3 _URB red services 2>&1)"
    assert_eq "$?" 127
    assert_contains "$out" "python3 is required"
    assert_status 0 env URB_PYTHON=/nonexistent/python3 "$URB_HOME/bin/urb" --no-color red scans
}

test_scans_services_outside_lab_and_arguments() {
    assert_status 1 _URB red scans
    assert_status 1 _URB red services
    _newlab
    assert_contains "$(_URB red scans)" "No scans yet"
    assert_status 2 _URB red scans bogus
    assert_status 2 _URB red scans show a b
    assert_status 2 _URB red services bogus
    assert_status 2 _URB red services list --bogus
    assert_status 2 _URB red services show
    assert_contains "$(_URB red --help)" "urb red findings evidence F-001 --scan latest"
}

test_recon_initial_registers_scan_id() {
    _newlab
    mkdir -p "$HOME/mockbin"
    cat >"$HOME/mockbin/nmap" <<'MOCK'
#!/usr/bin/env bash
b=""; p=""; for a in "$@"; do [[ "$p" == "-oA" ]] && b="$a"; p="$a"; done
printf '<?xml version="1.0"?>\n<nmaprun start="1794480000"><host><address addr="127.0.0.1" addrtype="ipv4"/><ports><port protocol="tcp" portid="8080"><state state="open"/><service name="http"/></port></ports></host><runstats><finished exit="success"/></runstats></nmaprun>\n' >"${b}.xml"
printf 'Host: 127.0.0.1 ()\tPorts: 8080/open/tcp//http///\n' >"${b}.gnmap"; echo "# Nmap done" >"${b}.nmap"
MOCK
    chmod +x "$HOME/mockbin/nmap"
    local out; out="$(PATH="$HOME/mockbin:$PATH" _URB red recon initial 2>&1)"
    assert_contains "$out" "Scan ID: S-001"
    command -v python3 >/dev/null && assert_contains "$(_URB red services)" "8080/tcp"
    assert_contains "$(_URB red status)" "latest complete: S-001"
}

test_zsh_completion_is_registered_and_cheap() {
    command -v zsh >/dev/null || return 0
    _newlab
    _run t_default_20261110-090000 1794300000 1 "10.0.0.1|tcp|22|open|ssh||"
    _URB red scans >/dev/null
    local out
    out="$(cd "$(_LAB)" && ZDOTDIR="$URB_HOME/godmode/zsh" URB_GOD_DIR="$URB_HOME/godmode" URB_PROFILE_TAG=RED \
           URB_GOD_GREETED=1 zsh -i -c 'print -r -- "comp=${_comps[urb]}"; _urb_lab_root && print -r -- "root=$REPLY"' 2>&1)"
    assert_contains "$out" "comp=_urb_complete"
    assert_contains "$out" "root=$(_LAB)"
    # El autocompletado no usa nmap, python ni ningún comando externo
    assert_not_contains "$(sed -n '/_urb_complete() {/,/^    }/p' "$URB_HOME/godmode/zsh/.zshrc")" "python"
    assert_not_contains "$(sed -n '/_urb_complete() {/,/^    }/p' "$URB_HOME/godmode/zsh/.zshrc")" "nmap "
    assert_not_contains "$(sed -n '/_urb_complete() {/,/^    }/p' "$URB_HOME/godmode/zsh/.zshrc")" '$(urb'
}
