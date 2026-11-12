#!/usr/bin/env bash
# Pruebas del Command Engine (urb red recon <modificadores>, urb serve), de la
# ayuda (urb help / urb-help / urb manual) y de la cobertura de la documentación.

_URB() { "$URB_HOME/bin/urb" --no-color "$@"; }
_LAB() { printf '%s/urb-labs/%s' "$HOME" "${1:-demo}"; }
_newlab() { _URB red lab new "${1:-demo}" --target 10.10.10.3 >/dev/null; }

# Línea "Command" del dry-run, sin la marca temporal del nombre de fichero
_dry_cmd() { _URB red recon "$@" --dry-run 2>&1 | grep '  Command' | sed -E 's/_[0-9]{8}-[0-9]{6}(-[0-9]+)?/_TS/g'; }

# nmap simulado: registra la llamada y genera -oA
_mock_nmap() {
    mkdir -p "$HOME/mockbin"
    cat >"$HOME/mockbin/nmap" <<'MOCK'
#!/usr/bin/env bash
b=""; p=""; for a in "$@"; do [[ "$p" == "-oA" ]] && b="$a"; p="$a"; done
printf '%s\n' "$*" >>"$HOME/nmap_calls.txt"
printf '<?xml version="1.0"?>\n<nmaprun start="1794480000"><host><address addr="10.10.10.3" addrtype="ipv4"/><ports><port protocol="tcp" portid="80"><state state="open"/><service name="http"/></port></ports></host><runstats><finished exit="success"/></runstats></nmaprun>\n' >"${b}.xml"
printf 'Host: 10.10.10.3 ()\tPorts: 80/open/tcp//http///\n' >"${b}.gnmap"; echo "# Nmap done" >"${b}.nmap"
MOCK
    chmod +x "$HOME/mockbin/nmap"
    export PATH="$HOME/mockbin:$PATH"
}

test_engine_modifier_order_gives_identical_command() {
    _newlab
    local a b c
    a="$(_dry_cmd quick versions)"; b="$(_dry_cmd versions quick)"
    [[ -n "$a" ]] || _fail "no command in dry-run output"
    assert_eq "$a" "$b"
    assert_contains "$a" "nmap -T4 --open --top-ports 100 -sV 10.10.10.3 -v --stats-every 2s -oA"
    assert_contains "$a" "10.10.10.3_quick-versions_TS"
    c="$(_dry_cmd scripts full versions)"
    assert_eq "$c" "$(_dry_cmd full versions scripts)"
    assert_eq "$c" "$(_dry_cmd versions scripts full)"
}

test_engine_rejects_repeated_unknown_and_incompatible() {
    _newlab
    local out
    out="$(_URB red recon quick quick 2>&1)"; assert_eq "$?" 2; assert_contains "$out" "given twice"
    out="$(_URB red recon quick turbo 2>&1)"; assert_eq "$?" 2; assert_contains "$out" "unknown modifier 'turbo'"
    out="$(_URB red recon quick full 2>&1)"; assert_eq "$?" 2; assert_contains "$out" "cannot be combined"
    assert_status 2 _URB red recon udp quick
    assert_status 2 _URB red recon full udp versions
    out="$(_URB red recon quick --target=10.0.0.1 2>&1)"; assert_eq "$?" 2; assert_contains "$out" "with a space"
    assert_status 2 _URB red recon quick --target
    assert_status 2 _URB red recon quick --target '10.0.0.1;id'
    assert_status 2 _URB red recon quick --target -oN
    assert_status 2 _URB red recon quick --bogus
    assert_status 2 _URB red recon quick --dry-run --dry-run
    assert_status 2 _URB red recon --dry-run
    assert_contains "$(_URB red recon)" "MODIFIERS"
}

test_engine_precedence_explicit_config_default() {
    _newlab
    # --target explícito > objetivo del laboratorio (y no lo modifica)
    assert_contains "$(_dry_cmd quick --target 10.10.10.77)" " 10.10.10.77 -v"
    assert_eq "$(_URB red target show)" "10.10.10.3"
    # Configuración del usuario > valores por defecto
    _URB config set RECON_MOD_quick "--top-ports 200" >/dev/null
    assert_contains "$(_dry_cmd quick)" "--top-ports 200"
    _URB config set RECON_BASE "-T3 --open" >/dev/null
    assert_contains "$(_dry_cmd versions)" "nmap -T3 --open -sV"
    # Valores del motor (unidad): explícito > config > defecto
    load_urb
    eng_load serve || _fail "$ENG_ERR"
    eng_parse || _fail "$ENG_ERR"
    assert_eq "$(eng_value port)" "8000"
    URB_CFG[SERVE_PORT]=9001
    assert_eq "$(eng_value port)" "9001"
    eng_parse --port 7000 || _fail "$ENG_ERR"
    assert_eq "$(eng_value port)" "7000"
}

test_engine_slow_replaces_timing_and_config_is_validated() {
    _newlab
    local c
    c="$(_dry_cmd slow versions)"
    assert_contains "$c" "nmap --open -sV -T2 10.10.10.3"
    [[ "$(grep -o -- ' -T[0-9]' <<<"$c" | wc -l)" == "1" ]] || _fail "more than one -T: $c"
    # Configuración manipulada: opciones prohibidas y combinaciones incoherentes
    _URB config set RECON_MOD_versions "-sV -oN /tmp/x" >/dev/null
    assert_status 2 _URB red recon versions --dry-run
    _URB config set RECON_MOD_versions "-sV -T3" >/dev/null
    assert_status 2 _URB red recon versions slow --dry-run          # dos -T en los modificadores
    _URB config set RECON_MOD_versions "-sV -p-" >/dev/null
    assert_status 2 _URB red recon quick versions --dry-run         # dos selecciones de puertos
    _URB config set RECON_MOD_versions "" >/dev/null
    assert_status 2 _URB red recon versions --dry-run               # modificador vacío
}

test_engine_dry_run_has_no_side_effects() {
    _newlab
    rmdir "$(_LAB)/scans" 2>/dev/null
    mkdir -p "$HOME/trap"
    local t; for t in nmap sudo ping curl; do
        printf '#!/bin/sh\necho "%s $*" >>"%s/trap.log"\nexit 1\n' "$t" "$HOME" >"$HOME/trap/$t"; chmod +x "$HOME/trap/$t"
    done
    local out
    out="$(PATH="$HOME/trap:$PATH" _URB red recon quick versions scripts --dry-run)"
    assert_eq "$?" 0
    assert_contains "$out" "nothing was executed"
    out="$(PATH="$HOME/trap:$PATH" _URB red recon udp os --dry-run)"     # necesitaría root: tampoco pide sudo
    assert_contains "$out" "sudo -n nmap"
    [[ ! -e "$HOME/trap.log" ]] || _fail "dry-run executed: $(cat "$HOME/trap.log")"
    [[ ! -e "$(_LAB)/scans" ]] || _fail "dry-run created the scans directory"
    [[ ! -e "$(_LAB)/.urb-lock" && ! -L "$(_LAB)/.urb-lock" ]] || _fail "dry-run left a lock"
}

test_engine_runs_existing_nmap_engine_and_scan_manager() {
    _newlab
    _mock_nmap
    local out
    out="$(_URB red recon versions quick 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "Scan ID: S-001"
    assert_contains "$(cat "$HOME/nmap_calls.txt")" "-T4 --open --top-ports 100 -sV 10.10.10.3"
    ls "$(_LAB)"/scans/10.10.10.3_quick-versions_*.xml >/dev/null 2>&1 || _fail "results not saved with the modifier label"
    out="$(_URB red scans)"
    assert_contains "$out" "quick-versions"
    assert_contains "$out" "complete"
    command -v python3 >/dev/null && assert_contains "$(_URB red services)" "80/tcp"
    # recon initial no cambia: sigue usando el perfil default
    _URB red recon initial >/dev/null 2>&1
    assert_contains "$(tail -n 1 "$HOME/nmap_calls.txt")" "-sV -T4 --open"
    ls "$(_LAB)"/scans/10.10.10.3_default_*.nmap >/dev/null 2>&1 || _fail "recon initial changed"
}

test_engine_interface_is_internal_only() {
    _newlab
    _mock_nmap
    # Variables de entorno con los nombres internos: se ignoran (no son arrays)
    SCAN_ENGINE_ARGS="-sS -oN /tmp/evil" SCAN_ENGINE_LABEL=evil SCAN_ENGINE_OPTS=dry-run \
        _URB scan 127.0.0.1 --profile quick -o "$HOME/out" >/dev/null 2>&1
    assert_contains "$(cat "$HOME/nmap_calls.txt")" "-T4 -F --open"
    assert_not_contains "$(cat "$HOME/nmap_calls.txt")" "evil"
    ls "$HOME"/out/127.0.0.1_quick_* >/dev/null 2>&1 || _fail "urb scan did not run normally"
    # No hay opción pública para pasar argumentos arbitrarios a nmap
    assert_status 2 _URB scan 127.0.0.1 --nmap-args "-sS"
    assert_status 2 _URB scan 127.0.0.1 --profile @engine
}

test_engine_root_modifiers_ask_or_use_sudo() {
    _newlab
    _mock_nmap
    (( EUID != 0 )) || return 0
    local out
    # Sin terminal para preguntar y sin --sudo: no ejecuta nada
    out="$(setsid -w "$URB_HOME/bin/urb" --no-color red recon os </dev/null 2>&1)"
    assert_eq "$?" 1 "$out"
    [[ ! -e "$HOME/nmap_calls.txt" ]] || _fail "nmap ran without root confirmation"
}

# --- urb serve ------------------------------------------------------------------------
_free_port() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }

test_serve_validation_and_errors() {
    local out
    assert_status 2 _URB serve --port 0
    assert_status 2 _URB serve --port 70000
    assert_status 2 _URB serve --port abc
    out="$(_URB serve --port 80 2>&1)"; assert_eq "$?" 2; assert_contains "$out" "privileged"
    assert_status 2 _URB serve --bind 'x;id'
    assert_status 2 _URB serve extra
    assert_status 2 _URB serve --port=8000
    assert_status 1 _URB serve --dir "$HOME/does-not-exist"
    out="$(URB_PYTHON=/nonexistent/python3 _URB serve 2>&1)"; assert_eq "$?" 127; assert_contains "$out" "python3 is required"
    command -v python3 >/dev/null || return 0
    # Dirección no local sin confirmación (sin terminal) → cancelado, sin arrancar nada
    out="$(setsid -w "$URB_HOME/bin/urb" --no-color serve --bind 0.0.0.0 --port "$(_free_port)" </dev/null 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "exposes every file"
    assert_contains "$out" "Cancelled"
    # Configuración inválida también se rechaza
    _URB config set SERVE_PORT 99999 >/dev/null
    assert_status 2 _URB serve
}

test_serve_busy_port() {
    command -v python3 >/dev/null || return 0
    local p; p="$(_free_port)"
    python3 -I -c "import socket,time; s=socket.socket(); s.bind(('127.0.0.1',$p)); s.listen(); time.sleep(20)" &
    local holder=$!
    sleep 0.7
    local out; out="$(_URB serve --port "$p" 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "already in use"
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
    return 0
}

# Arranca 'urb serve' en una pseudo-terminal real, hace una petición HTTP local
# y pulsa Ctrl+C (\x03), como un usuario. (Un proceso lanzado con & desde un
# script tiene SIGINT ignorado, así que no sirve para probar Ctrl+C.)
# _serve_pty SALIDA PUERTO_A_PEDIR args...
_serve_pty() {
    local out="$1" port="$2" q; shift 2
    printf -v q '%q ' "$URB_HOME/bin/urb" --no-color serve "$@"
    (
        sleep 2.5
        python3 -I -c "import urllib.request; open('$HOME/fetched.txt','w').write(urllib.request.urlopen('http://127.0.0.1:${port}/file.txt',timeout=5).read().decode())" 2>/dev/null
        sleep 0.5; printf '\003'; sleep 1.5
    ) | TERM=xterm-256color timeout 30 script -qfec "stty rows 30 cols 110; ${q}; echo SERVE_RC=\$?" "$out" >/dev/null 2>&1
}

test_serve_default_and_custom_port_and_ctrl_c() {
    command -v python3 >/dev/null || return 0
    command -v script >/dev/null || return 0
    mkdir -p "$HOME/share"; echo "hello-urb" >"$HOME/share/file.txt"
    local p; p="$(_free_port)"
    _serve_pty "$HOME/serve.out" "$p" --port "$p" --dir "$HOME/share"
    assert_eq "$(cat "$HOME/fetched.txt" 2>/dev/null)" "hello-urb"
    assert_contains "$(cat "$HOME/serve.out")" "http://127.0.0.1:${p}/"
    assert_contains "$(cat "$HOME/serve.out")" "$HOME/share"
    assert_contains "$(cat "$HOME/serve.out")" "Server stopped"
    assert_contains "$(cat "$HOME/serve.out")" "SERVE_RC=0"
    # Puerto por defecto (8000) y escucha local por defecto, si está libre
    if python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",8000)); s.close()' 2>/dev/null; then
        rm -f "$HOME/fetched.txt"
        ( cd "$HOME/share" && _serve_pty "$HOME/serve2.out" 8000 )
        assert_contains "$(cat "$HOME/serve2.out")" "http://127.0.0.1:8000/"
        assert_eq "$(cat "$HOME/fetched.txt" 2>/dev/null)" "hello-urb"
    fi
    # Dirección no local autorizada explícitamente con --yes
    p="$(_free_port)"
    _serve_pty "$HOME/serve3.out" "$p" --bind 0.0.0.0 --port "$p" --dir "$HOME/share" --yes
    assert_contains "$(cat "$HOME/serve3.out")" "exposes every file"
    assert_contains "$(cat "$HOME/serve3.out")" "all IPv4 interfaces"
    assert_contains "$(cat "$HOME/serve3.out")" "SERVE_RC=0"
    pgrep -f "http.server ${p}" >/dev/null && _fail "server still running after Ctrl+C"
    return 0
}

# --- Ayuda y manual ------------------------------------------------------------------------
test_help_topics_sections_and_urb_help() {
    local out
    assert_status 0 _URB help
    out="$(_URB help 2>&1)"; assert_contains "$out" "serve"; assert_contains "$out" "manual"; assert_contains "$out" "urb-help"
    assert_status 2 _URB help bogus
    assert_contains "$(_URB help red scans)" "SCANS"
    assert_not_contains "$(_URB help red scans)" "FINDINGS"
    assert_contains "$(_URB help red recon)" "MODIFIERS"
    assert_contains "$(_URB help red recon)" "initial"
    assert_contains "$(_URB help serve)" "--bind"
    assert_status 2 _URB help red bogus
    local s; for s in shell lab target recon scans services findings notes context; do
        assert_status 0 _URB help red "$s"
    done
    # urb-help reutiliza exactamente la misma ayuda
    assert_eq "$("$URB_HOME/bin/urb-help" red findings)" "$("$URB_HOME/bin/urb" help red findings)"
    assert_eq "$("$URB_HOME/bin/urb-help" serve)" "$("$URB_HOME/bin/urb" help serve)"
    # --help de cada subcomando apunta a su sección
    assert_contains "$(_URB red scans --help)" "SCANS"
    assert_contains "$(_URB red findings --help)" "FINDINGS"
    assert_contains "$(_URB serve --help)" "urb serve"
}

test_manual_command() {
    local out
    out="$(_URB manual path)"
    assert_contains "$out" "docs/COMMANDS.md"
    assert_contains "$out" "docs/EXAMPLES.md"
    assert_contains "$(_URB manual </dev/null)" "COMMANDS.md"          # sin terminal: muestra la ruta
    assert_contains "$(_URB manual examples </dev/null)" "EXAMPLES.md"
    assert_status 2 _URB manual bogus
    assert_contains "$(_URB help manual)" "urb manual examples"
}

# --- Documentación ---------------------------------------------------------------------------
test_docs_cover_every_command_option_and_config_key() {
    local doc="$URB_HOME/docs/COMMANDS.md" ex="$URB_HOME/docs/EXAMPLES.md" c line key
    assert_file "$doc"; assert_file "$ex"
    local d; d="$(cat "$doc")"
    for c in scan network monitor logs ctf config doctor god red sessions serve manual help version urb-help install.sh uninstall.sh; do
        assert_contains "$d" "$c"
    done
    for c in "urb red lab" "urb red target" "urb red status" "urb red recon initial" "urb red recon <modificador>" \
             "urb red scans" "urb red services" "urb red findings" "urb red notes" "urblab" \
             "urb sessions info" "urb sessions attach" "urb sessions kill" "urb monitor --once" "urb logs" "urb ctf new"; do
        assert_contains "$d" "$c"
    done
    # Todo lo que define cada .spec (modificadores y opciones) está documentado
    for f in "$URB_HOME"/commands/*.spec; do
        while IFS= read -r line; do
            case "$line" in
                modifier=*) c="${line#modifier=}"; c="${c%%|*}"; assert_contains "$d" "\`${c}\`" ;;
                option=*)   c="${line#option=}"; c="${c%%|*}"; assert_contains "$d" "--${c}" ;;
            esac
        done <"$f"
    done
    # Todas las claves de configuración por defecto están documentadas
    while IFS= read -r line; do
        [[ "$line" =~ ^([A-Z][A-Za-z0-9_]*)= ]] || continue
        key="${BASH_REMATCH[1]}"
        [[ "$key" == SCAN_PROFILE_* ]] && key="SCAN_PROFILE_"
        assert_contains "$d" "$key"
    done <"$URB_HOME/config/default.conf"
    # Los estados y secciones de ayuda coinciden con el código
    for c in pending investigating suspected confirmed discarded checked attached detached none complete incomplete failed partial missing; do
        assert_contains "$d" "\`${c}\`"
    done
}

test_examples_use_only_real_commands() {
    local ex="$URB_HOME/docs/EXAMPLES.md" line cmd sub n=0
    local top=" scan network monitor logs ctf config doctor god red sessions serve manual help version "
    local redsub=" lab target status recon findings notes scans services --kill --session --no-anim "
    while IFS= read -r line; do
        [[ "$line" =~ ^(urb|urb-help)[[:space:]]+([^[:space:]]+)([[:space:]]+([^[:space:]]+))? ]] || continue
        [[ "${BASH_REMATCH[1]}" == "urb-help" ]] && continue
        cmd="${BASH_REMATCH[2]}"; sub="${BASH_REMATCH[4]:-}"
        n=$(( n + 1 ))
        [[ "$top" == *" ${cmd} "* ]] || _fail "EXAMPLES.md uses unknown command: urb ${cmd}"
        if [[ "$cmd" == red && -n "$sub" && "$sub" != "#"* ]]; then
            [[ "$redsub" == *" ${sub} "* ]] || _fail "EXAMPLES.md uses unknown red subcommand: urb red ${sub}"
        fi
    done < <(sed -n '/^```bash/,/^```/p' "$ex")
    (( n > 30 )) || _fail "too few examples parsed (${n})"
}

test_engine_specs_are_data_only() {
    load_urb
    local f; f="$URB_HOME/commands/red-recon.spec"
    # Una línea con sustitución de comandos se lee como texto, nunca se ejecuta
    mkdir -p "$HOME/fake/commands"
    printf 'name=x\nsummary=$(touch %s/pwned)\nmodifier=a|||desc\n' "$HOME" >"$HOME/fake/commands/x.spec"
    URB_HOME="$HOME/fake" eng_load x || _fail "$ENG_ERR"
    [[ ! -e "$HOME/pwned" ]] || _fail "spec content was executed"
    printf 'name=x\nbogus=1\n' >"$HOME/fake/commands/y.spec"
    URB_HOME="$HOME/fake" eng_load y && _fail "invalid spec key accepted"
    assert_ok eng_load red-recon
    assert_eq "${ENG_MODS[*]}" "quick full udp versions scripts os slow"
    assert_file "$f"
}
