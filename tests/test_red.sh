#!/usr/bin/env bash
# Pruebas de URB Red v0.1 (laboratorios, objetivo, recon initial, diagnóstico,
# Zsh del perfil y aislamiento de sesiones). Nmap se sustituye por un mock.

_URB() { "$URB_HOME/bin/urb" --no-color "$@"; }

test_red_context_commands_and_isolation() {
    command -v zsh >/dev/null || return 0
    mkdir -p "$HOME/mock-urb/bin" "$HOME/mockbin"
    cat >"$HOME/mock-urb/bin/urb" <<'MOCK'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
exit 37
MOCK
    chmod +x "$HOME/mock-urb/bin/urb"
    printf '#!/bin/sh\necho existing\n' >"$HOME/mockbin/services"
    chmod +x "$HOME/mockbin/services"
    printf 'alias findings="echo personal"\n' >"$HOME/.zshrc"
    local out shell_dir="$URB_HOME/godmode/zsh" god_dir="$URB_HOME/godmode"
    out="$(PATH="$HOME/mockbin:$PATH" URB_HOME="$HOME/mock-urb" URB_GOD_DIR="$god_dir" \
        ZDOTDIR="$shell_dir" URB_PROFILE=red URB_PROFILE_TAG=RED URB_GOD_GREETED=1 \
        zsh -i -c 'scan quick "two words" --dry-run; print "rc=$?"; recon initial; print "rc=$?"; report preview; whence -w services; alias findings; print "completion=${_comps[scan]}"; print "report_completion=${_comps[report]}"; print "conflict_completion=${_comps[services]-}"' 2>&1)"
    assert_contains "$out" "<red>"
    assert_contains "$out" "<recon>"
    assert_contains "$out" "<two words>"
    assert_contains "$out" "<--dry-run>"
    assert_contains "$out" "rc=37"
    assert_contains "$out" "services: command"
    assert_contains "$out" "findings='echo personal'"
    assert_contains "$out" "use 'urb red services'"
    assert_contains "$out" "completion=_urb_context_complete"
    assert_contains "$out" "report_completion=_urb_context_complete"
    assert_contains "$out" "<report>"
    assert_contains "$out" "<preview>"
    assert_not_contains "$out" "conflict_completion=_urb_context_complete"
    out="$(URB_GOD_DIR="$URB_HOME/godmode" ZDOTDIR="$URB_HOME/godmode/zsh" URB_PROFILE=god URB_PROFILE_TAG=GOD URB_GOD_GREETED=1 zsh -i -c 'whence -w recon; print "completion=${_comps[recon]-}"' 2>&1)"
    assert_not_contains "$out" "recon: function"
    assert_not_contains "$out" "completion=_urb_context_complete"
    out="$(ZDOTDIR="$HOME" zsh -i -c 'whence -w recon' 2>&1)"
    assert_not_contains "$out" "recon: function"
}

test_red_short_completion_delegates() {
    command -v zsh >/dev/null || return 0
    local out
    out="$(URB_GOD_DIR="$URB_HOME/godmode" ZDOTDIR="$URB_HOME/godmode/zsh" URB_PROFILE=red URB_PROFILE_TAG=RED URB_GOD_GREETED=1 zsh -i -c '
        compadd() { print -r -- "$@"; }
        words=(scan quick ""); CURRENT=3; _urb_context_complete
        words=(findings ""); CURRENT=2; _urb_context_complete
    ' 2>&1)"
    assert_contains "$out" "versions"
    assert_contains "$out" "show"
    assert_contains "$out" "evidence"
}

# nmap simulado: registra la llamada y genera los ficheros -oA según MOCK_NMAP_MODE
_mock_nmap() {
    mkdir -p "$HOME/mockbin"
    cat >"$HOME/mockbin/nmap" <<'MOCK'
#!/usr/bin/env bash
base="" prev="" target=""
for a in "$@"; do
    [[ "$prev" == "-oA" ]] && base="$a"
    [[ "$a" == "-v" && -z "$target" ]] && target="$prev"
    prev="$a"
done
printf '%s\n' "$*" >>"$HOME/nmap_calls.txt"
case "${MOCK_NMAP_MODE:-ok}" in
    ok)
        echo "Discovered open port 22/tcp on ${target}"
        printf '# Nmap mock\nHost: %s ()\tStatus: Up\nHost: %s ()\tPorts: 22/open/tcp//ssh//OpenSSH 9.6p1/\tIgnored State: closed (999)\n' "$target" "$target" >"${base}.gnmap"
        printf 'Nmap scan report for %s\n22/tcp open  ssh  OpenSSH 9.6p1\n' "$target" >"${base}.nmap"
        echo '<nmaprun/>' >"${base}.xml"; exit 0 ;;
    down)
        printf 'Note: Host seems down. If it is really up, but blocking our ping probes, try -Pn\nNmap done: 1 IP address (0 hosts up) scanned\n' | tee "${base}.nmap"
        : >"${base}.gnmap"; echo '<nmaprun/>' >"${base}.xml"; exit 0 ;;
    fail)
        echo "Something unexpected happened"; echo "QUITTING!"; exit 1 ;;
esac
MOCK
    chmod +x "$HOME/mockbin/nmap"
    export PATH="$HOME/mockbin:$PATH"
}

test_red_help_and_arguments() {
    local out
    out="$(_URB red --help)"
    assert_eq "$?" 0
    assert_contains "$out" "urb red lab new"
    assert_contains "$out" "urb red recon initial"
    assert_contains "$(_URB help red)" "urblab"
    assert_contains "$(_URB help)" "red"
    assert_status 2 _URB red bogus
    assert_status 2 _URB red recon deep
    assert_status 2 _URB red recon initial --bogus
    assert_status 2 _URB red lab frobnicate
    assert_status 2 _URB red target set
    assert_status 2 _URB red status extra
}

test_red_lab_new_and_select() {
    local st="$HOME/.local/share/urb-tools/state/active-lab"
    assert_status 0 _URB red lab new box1 --target 10.10.10.20
    assert_file "$HOME/urb-labs/box1/.urb-lab"
    assert_dir "$HOME/urb-labs/box1/scans"
    assert_contains "$(cat "$HOME/urb-labs/box1/.urb-lab")" "target=10.10.10.20"
    assert_eq "$(cat "$st")" "$HOME/urb-labs/box1"
    assert_status 0 _URB red lab new box2
    assert_eq "$(cat "$st")" "$HOME/urb-labs/box2"
    assert_status 0 _URB red lab use box1
    assert_eq "$(cat "$st")" "$HOME/urb-labs/box1"
    assert_contains "$(_URB red lab list)" "Selected: box1"
    assert_eq "$(_URB red lab path)" "$HOME/urb-labs/box1"
    assert_eq "$(_URB red lab path box2)" "$HOME/urb-labs/box2"
    assert_status 1 _URB red lab use nope
    assert_status 2 _URB red lab new '../evil'
    assert_status 2 _URB red lab new ok --target '10.0.0.1;id'
    [[ ! -e "$HOME/urb-labs/ok" ]] || _fail "lab created despite invalid target"
}

test_red_lab_new_existing_keeps_data() {
    _URB red lab new keep --target 10.10.10.5 >/dev/null
    echo "MY NOTES" >>"$HOME/urb-labs/keep/report.md"
    local out
    out="$(_URB red lab new keep --target 10.10.10.99 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "kept"
    assert_contains "$(cat "$HOME/urb-labs/keep/.urb-lab")" "target=10.10.10.5"
    assert_contains "$(cat "$HOME/urb-labs/keep/report.md")" "MY NOTES"
}

test_red_target_persistence_and_atomic_update() {
    _URB red lab new tgt --target 10.10.10.1 >/dev/null
    local f="$HOME/urb-labs/tgt/.urb-lab"
    echo "notes=keep this" >>"$f"
    local created; created="$(grep '^created=' "$f")"
    assert_status 0 _URB red target set 10.10.10.2
    assert_eq "$(_URB red target show)" "10.10.10.2"
    assert_contains "$(cat "$f")" "notes=keep this"
    assert_contains "$(cat "$f")" "$created"
    assert_contains "$(cat "$f")" "name=tgt"
    assert_eq "$(grep -c '^target=' "$f")" "1"
    assert_status 0 _URB red target set box.htb
    assert_eq "$(_URB red target show)" "box.htb"
    compgen -G "$HOME/urb-labs/tgt/.urb-lab.*" >/dev/null && _fail "temporary files left next to .urb-lab"
    # Entradas inválidas: el fichero no cambia
    local before; before="$(cat "$f")"
    assert_status 2 _URB red target set '10.10.10.3;id'
    assert_status 2 _URB red target set '-oX'
    assert_status 2 _URB red target set '$(id)'
    assert_status 2 _URB red target set '999.1.1.1'
    assert_eq "$(cat "$f")" "$before"
}

test_red_workspace_detection_has_priority() {
    _URB red lab new a1 --target 10.10.10.1 >/dev/null
    _URB red lab new a2 --target 10.10.10.2 >/dev/null     # a2 queda seleccionado
    mkdir -p "$HOME/urb-labs/a1/notes/deep"
    assert_eq "$(_URB red target show)" "10.10.10.2"
    assert_eq "$(cd "$HOME/urb-labs/a1/notes/deep" && _URB red target show)" "10.10.10.1"
    assert_eq "$(cd "$HOME/urb-labs/a1/notes/deep" && _URB red lab path)" "$HOME/urb-labs/a1"
    assert_contains "$(cd "$HOME/urb-labs/a1/notes" && _URB red status)" "from current directory"
    assert_contains "$(_URB red status)" "selected with urb red lab use"
    # target set desde dentro de a1 modifica a1, no el seleccionado
    ( cd "$HOME/urb-labs/a1" && _URB red target set 10.10.10.111 >/dev/null )
    assert_contains "$(cat "$HOME/urb-labs/a1/.urb-lab")" "target=10.10.10.111"
    assert_contains "$(cat "$HOME/urb-labs/a2/.urb-lab")" "target=10.10.10.2"
}

test_red_stale_or_malicious_state_is_rejected() {
    local st="$HOME/.local/share/urb-tools/state/active-lab" out
    _URB red lab new gone --target 10.10.10.1 >/dev/null
    rm -rf "$HOME/urb-labs/gone"
    out="$(_URB red target show 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "no longer valid"
    assert_contains "$(_URB red status)" "no longer valid"
    # active-lab y .urb-lab son datos: nunca se ejecutan
    printf '%s\n' '$(touch '"$HOME"'/pwned1)' >"$st"
    _URB red status >/dev/null 2>&1
    _URB red lab new evil >/dev/null
    printf 'name=evil\ntarget=$(touch %s/pwned2)\n' "$HOME" >"$HOME/urb-labs/evil/.urb-lab"
    out="$(_URB red target show 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "not valid"
    _URB red status >/dev/null 2>&1
    bash "$URB_HOME/godmode/hud/status.sh" "$HOME/urb-labs/evil" 150 red >/dev/null 2>&1
    [[ ! -e "$HOME/pwned1" && ! -e "$HOME/pwned2" ]] || _fail "state/metadata content was executed"
}

test_red_recon_uses_lab_target_and_saves_results() {
    command -v script >/dev/null || true
    _mock_nmap
    _URB red lab new rbox --target 10.10.10.40 >/dev/null
    local out
    out="$(_URB red recon initial 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "from lab metadata"
    assert_contains "$out" "10.10.10.40"
    assert_contains "$out" "1 open port(s) found"
    assert_contains "$(cat "$HOME/nmap_calls.txt")" "-sV"
    assert_contains "$(cat "$HOME/nmap_calls.txt")" "10.10.10.40"
    assert_eq "$(wc -l <"$HOME/nmap_calls.txt")" "1"
    ls "$HOME"/urb-labs/rbox/scans/10.10.10.40_default_*.nmap >/dev/null 2>&1 || _fail ".nmap not saved in lab scans/"
    ls "$HOME"/urb-labs/rbox/scans/10.10.10.40_default_*.gnmap >/dev/null 2>&1 || _fail ".gnmap not saved"
    ls "$HOME"/urb-labs/rbox/scans/*.log >/dev/null 2>&1 && _fail "log should be removed after success"
    assert_contains "$(_URB red status)" "Scans     1"
}

test_red_recon_explicit_target_does_not_overwrite() {
    _mock_nmap
    _URB red lab new obox --target 10.10.10.40 >/dev/null
    local out
    out="$(_URB red recon initial --target 10.10.10.99 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "this run only"
    assert_contains "$(cat "$HOME/nmap_calls.txt")" "10.10.10.99"
    assert_not_contains "$(cat "$HOME/nmap_calls.txt")" "10.10.10.40"
    assert_eq "$(_URB red target show)" "10.10.10.40"
}

test_red_recon_input_errors_do_not_run_nmap() {
    _mock_nmap
    assert_status 1 _URB red recon initial                    # sin laboratorio
    _URB red lab new empty >/dev/null
    local out
    out="$(_URB red recon initial 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "has no target"
    assert_status 2 _URB red recon initial --target '10.10.10.1;id'
    assert_status 2 _URB red recon initial --target '-oN'
    [[ ! -e "$HOME/nmap_calls.txt" ]] || _fail "nmap must not run on input errors"
}

test_red_recon_diagnosis_host_down_and_failure() {
    _mock_nmap
    _URB red lab new dbox --target 10.10.10.50 >/dev/null
    local out
    out="$(MOCK_NMAP_MODE=down _URB red recon initial 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "DIAGNOSIS"
    assert_contains "$out" "possible"
    assert_contains "$out" "does NOT prove"
    assert_not_contains "$out" "confirmed  nmap got no reply"
    out="$(MOCK_NMAP_MODE=fail _URB red recon initial 2>&1)"
    assert_eq "$?" 1 "$out"
    assert_contains "$out" "Log kept"
    assert_contains "$out" "unknown"
    ls "$HOME"/urb-labs/dbox/scans/*.log >/dev/null 2>&1 || _fail "log should be kept after a failure"
    # Solo una ejecución de nmap por recon (sin reintentos)
    assert_eq "$(wc -l <"$HOME/nmap_calls.txt")" "2"
}

test_diag_scan_rules() {
    load_urb
    local b="$HOME/diag" out
    out="$(diag_scan 0 "")"; assert_eq "$out" ""
    out="$(diag_scan 127 "")"; assert_contains "$out" "nmap is not installed"
    out="$(diag_scan 130 "")"; assert_contains "$out" "cancelled"
    printf 'Failed to resolve "box.htb".\n' >"${b}.log"
    out="$(diag_scan 1 "$b" box.htb)"
    assert_contains "$out" "confirmed"
    assert_contains "$out" "/etc/hosts"
    printf 'You requested a scan type which requires root privileges.\nQUITTING!\n' >"${b}.log"
    out="$(diag_scan 1 "$b")"; assert_contains "$out" "--sudo"
    printf 'weird\n' >"${b}.log"
    out="$(diag_scan 3 "$b")"; assert_contains "$out" "unknown"; assert_contains "$out" "${b}.log"
}

test_red_zsh_prompt_context_and_urblab() {
    command -v zsh >/dev/null || { echo "zsh not installed: skipped"; return 0; }
    _URB red lab new zbox --target 10.10.10.77 >/dev/null
    mkdir -p "$HOME/elsewhere"
    local out
    out="$(cd "$HOME/elsewhere" && ZDOTDIR="$URB_HOME/godmode/zsh" URB_GOD_DIR="$URB_HOME/godmode" \
           URB_PROFILE_TAG=RED URB_PROFILE_THEME=red URB_GOD_GREETED=1 \
           zsh -i -c '_urb_red_ctx; print -r -- "SEG:$_urb_red_seg"; urblab; print -r -- "PWD:$PWD"; urblab nope 2>/dev/null; print -r -- "RC:$? PWD2:$PWD"; print -rP "$PROMPT"' 2>&1)"
    out="$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g')"
    assert_contains "$out" "zbox"
    assert_contains "$out" "10.10.10.77"
    assert_contains "$out" "PWD:$HOME/urb-labs/zbox"
    assert_contains "$out" "PWD2:$HOME/urb-labs/zbox"
    assert_not_contains "$out" "RC:0 "
    assert_contains "$out" "[RED]"
    # El perfil GOD no define urblab ni muestra RED
    out="$(cd "$HOME" && ZDOTDIR="$URB_HOME/godmode/zsh" URB_GOD_DIR="$URB_HOME/godmode" URB_GOD_GREETED=1 \
           zsh -i -c 'whence -w urblab; print -rP "$PROMPT"' 2>&1 | sed 's/\x1b\[[0-9;]*m//g')"
    assert_contains "$out" "urblab: none"
    assert_contains "$out" "[GOD]"
}

_keys_red_detach() {
    sleep 3
    printf 'echo "$URB_PROFILE" > "$HOME/red_profile.txt"; print -rP "$PROMPT" > "$HOME/red_prompt.txt"\r'; sleep 1.5
    printf '\002d'; sleep 1.5
}
_keys_god_detach() { sleep 3; printf 'echo "${URB_PROFILE:-god}" > "$HOME/god_profile.txt"\r'; sleep 1.2; printf '\002d'; sleep 1.5; }

test_red_and_god_sessions_are_isolated() {
    command -v tmux >/dev/null && command -v zsh >/dev/null && command -v script >/dev/null || { echo "tmux/zsh/script missing: skipped"; return 0; }
    local gs="urbtest-god-$$-$RANDOM" rs="urbtest-red-$$-$RANDOM" urb="$URB_HOME/bin/urb"
    export URB_GOD_SOCKET="$gs" URB_RED_SOCKET="$rs"
    _URB red lab new iso --target 10.10.10.9 >/dev/null
    ( cd "$HOME" && ( _keys_god_detach ) | TERM=xterm-256color timeout 40 script -qfec "stty rows 30 cols 110; $urb --no-color god --no-anim" "$HOME/g.txt" >/dev/null 2>&1 )
    ( cd "$HOME/urb-labs/iso" && ( _keys_red_detach ) | TERM=xterm-256color timeout 40 script -qfec "stty rows 30 cols 110; $urb --no-color red --no-anim" "$HOME/r.txt" >/dev/null 2>&1 )
    assert_eq "$(cat "$HOME/red_profile.txt" 2>/dev/null)" "red"
    assert_eq "$(cat "$HOME/god_profile.txt" 2>/dev/null)" "god"
    assert_contains "$(sed 's/\x1b\[[0-9;]*m//g' "$HOME/red_prompt.txt" 2>/dev/null)" "[RED]"
    assert_contains "$(sed 's/\x1b\[[0-9;]*m//g' "$HOME/red_prompt.txt" 2>/dev/null)" "10.10.10.9"
    tmux -L "$gs" has-session -t god 2>/dev/null || _fail "god session missing"
    tmux -L "$rs" has-session -t red 2>/dev/null || _fail "red session missing"
    assert_contains "$(tmux -L "$rs" show -gv status-left 2>/dev/null)" "URB RED"
    assert_contains "$(tmux -L "$gs" show -gv status-left 2>/dev/null)" "URB GOD"
    assert_contains "$(_URB red --session)" "URB Red session running"
    assert_contains "$(_URB god --status)" "God Mode session running"
    # Terminar RED no afecta a GOD
    assert_status 0 _URB red --kill --yes
    tmux -L "$rs" has-session 2>/dev/null && _fail "red session still alive"
    tmux -L "$gs" has-session -t god 2>/dev/null || _fail "killing RED affected GOD"
    assert_status 0 _URB god --kill --yes
    rm -f -- "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/${gs}" "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/${rs}"
    return 0
}

test_red_existing_commands_unaffected() {
    assert_status 0 _URB ctf new plain
    assert_status 0 _URB ctf list
    assert_eq "$(_URB ctf path plain)" "$HOME/urb-labs/plain"
    assert_contains "$(_URB god --help)" "urb god --kill"
    assert_status 0 _URB version
    assert_status 0 _URB scan profiles
}
