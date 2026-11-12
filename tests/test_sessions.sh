#!/usr/bin/env bash
# Pruebas de gestión de sesiones: urb sessions, ciclo de vida de GOD/RED
# (detach, exit, Ctrl+D, cierre externo, pérdida del servidor, ventanas nuevas)
# y el indicador SES del HUD. Cada prueba usa sockets tmux exclusivos.

_URB() { "$URB_HOME/bin/urb" --no-color "$@"; }
_have_deps() { command -v tmux >/dev/null && command -v zsh >/dev/null && command -v script >/dev/null; }
_sock_path() { printf '%s/tmux-%s/%s' "${TMUX_TMPDIR:-/tmp}" "$(id -u)" "$1"; }

# Sockets únicos para esta prueba (GOD y RED)
_unique_sockets() {
    export URB_GOD_SOCKET="urbtest-g-$$-$RANDOM" URB_RED_SOCKET="urbtest-r-$$-$RANDOM" URB_BLUE_SOCKET="urbtest-b-$$-$RANDOM"
}
_cleanup_sockets() {
    local s
    for s in "${URB_GOD_SOCKET:-}" "${URB_RED_SOCKET:-}" "${URB_BLUE_SOCKET:-}"; do
        [[ "$s" == urbtest-* ]] || continue
        tmux -L "$s" kill-server 2>/dev/null
        rm -f -- "$(_sock_path "$s")"
    done
    return 0
}

# _pty SALIDA "comando" función_de_teclas
_pty() {
    local out="$1" cmd="$2" keys="$3"
    ( "$keys" ) | TERM=xterm-256color timeout 45 script -qfec "stty rows 30 cols 110; $cmd; echo URB_RC=\$?" "$out" >/dev/null 2>&1
}
_rc_of() { grep -a -o 'URB_RC=[0-9]*' "$1" | tail -n 1 | cut -d= -f2; }

_keys_detach() { sleep 2.5; printf '\002d'; sleep 1.5; }
_keys_exit()   { sleep 2.5; printf 'exit\r'; sleep 1.5; }
_keys_ctrl_d() { sleep 2.5; printf '\004'; sleep 1.5; }
_keys_list_then_detach() { sleep 2.5; printf '"$URB_HOME/bin/urb" --no-color sessions > "$HOME/inside.txt"\r'; sleep 2; printf '\002d'; sleep 1.5; }

test_blue_session_is_independent_of_red_and_god() {
    _have_deps || return 0
    _unique_sockets
    tmux -L "$URB_GOD_SOCKET" new-session -d -s god 'sleep 60'
    tmux -L "$URB_RED_SOCKET" new-session -d -s red 'sleep 60'
    tmux -L "$URB_BLUE_SOCKET" new-session -d -s blue 'sleep 60'
    assert_contains "$(_URB sessions info blue)" detached
    assert_status 0 _URB sessions kill blue --yes
    tmux -L "$URB_GOD_SOCKET" has-session -t god || _fail 'GOD session affected'
    tmux -L "$URB_RED_SOCKET" has-session -t red || _fail 'RED session affected'
    _cleanup_sockets
}

test_sessions_help_and_arguments() {
    assert_status 0 _URB sessions --help
    assert_contains "$(_URB sessions --help)" "attached"
    assert_contains "$(_URB help sessions)" "urb sessions kill"
    assert_contains "$(_URB help)" "sessions"
    assert_status 2 _URB sessions bogus
    assert_status 2 _URB sessions info
    assert_status 2 _URB sessions info nope
    assert_status 2 _URB sessions attach
    assert_status 2 _URB sessions kill
    assert_status 2 _URB sessions kill red --bogus
    assert_status 2 _URB sessions kill red god
}

test_sessions_queries_never_create_sessions() {
    _unique_sockets
    local out
    out="$(_URB sessions)"
    assert_eq "$?" 0
    assert_contains "$out" "god      none"
    assert_contains "$out" "red      none"
    assert_status 0 _URB sessions info god
    assert_status 1 _URB sessions attach red </dev/null
    assert_status 0 _URB sessions kill red --yes
    assert_contains "$(_URB sessions kill god --yes)" "Nothing to do"
    [[ ! -e "$(_sock_path "$URB_GOD_SOCKET")" && ! -e "$(_sock_path "$URB_RED_SOCKET")" ]] || _fail "a query created a tmux socket"
    # god.sh --attach-only nunca crea la sesión (también en una terminal real)
    if _have_deps; then
        _pty "$HOME/ao.txt" "$URB_HOME/godmode/god.sh --profile red --attach-only --no-anim" _keys_detach
        assert_contains "$(cat "$HOME/ao.txt")" "No URB Red session to attach to"
        assert_eq "$(_rc_of "$HOME/ao.txt")" "1"
        tmux -L "$URB_RED_SOCKET" has-session 2>/dev/null && _fail "--attach-only created a session"
    fi
    _cleanup_sockets
}

test_sessions_states_attached_detached_none() {
    _have_deps || { echo "tmux/zsh/script missing: skipped"; return 0; }
    _unique_sockets
    ( cd "$HOME" && _pty "$HOME/r.txt" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_list_then_detach )
    # Desde dentro de la propia sesión: RED conectada, GOD sin sesión
    assert_contains "$(cat "$HOME/inside.txt" 2>/dev/null)" "red      attached"
    assert_contains "$(cat "$HOME/inside.txt" 2>/dev/null)" "god      none"
    # Tras desconectar: RED en segundo plano
    local out; out="$(_URB sessions)"
    assert_contains "$out" "red      detached"
    out="$(_URB sessions info red)"
    assert_contains "$out" "detached"
    assert_contains "$out" "1 window(s), 1 pane(s), 0 client(s)"
    _cleanup_sockets
}

test_sessions_error_state_is_distinct() {
    _unique_sockets
    local out
    out="$(URB_GOD_TMUX=/nonexistent/tmux _URB sessions 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "error"
    assert_contains "$out" "tmux is not installed"
    # tmux responde con un error que no es "no hay servidor" → estado error, no none
    mkdir -p "$HOME/fakebin" "$(dirname "$(_sock_path "$URB_RED_SOCKET")")"
    printf '#!/bin/sh\necho "error connecting to socket (Permission denied)" >&2\nexit 1\n' >"$HOME/fakebin/tmux"
    chmod +x "$HOME/fakebin/tmux"
    : >"$(_sock_path "$URB_RED_SOCKET")"
    out="$(URB_GOD_TMUX="$HOME/fakebin/tmux" _URB sessions 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "red      error"
    assert_contains "$out" "Permission denied"
    out="$(URB_GOD_TMUX="$HOME/fakebin/tmux" _URB sessions info red 2>&1)"
    assert_eq "$?" 1
    rm -f -- "$(_sock_path "$URB_RED_SOCKET")"
    # Socket huérfano (servidor muerto) → none, no error
    : >"$(_sock_path "$URB_RED_SOCKET")"
    assert_contains "$(_URB sessions)" "red      none"
    _cleanup_sockets
}

test_sessions_kill_always_confirms_and_isolates_profiles() {
    _have_deps || return 0
    _unique_sockets
    ( cd "$HOME" && _pty "$HOME/g.txt" "$URB_HOME/bin/urb --no-color god --no-anim" _keys_detach )
    ( cd "$HOME" && _pty "$HOME/r.txt" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_detach )
    local out
    # Sin programas activos y sin --yes: aun así pregunta (sin terminal → no)
    out="$(setsid -w "$URB_HOME/bin/urb" --no-color sessions kill red </dev/null 2>&1)"
    assert_contains "$out" "Cancelled"
    tmux -L "$URB_RED_SOCKET" has-session -t red 2>/dev/null || _fail "kill without confirmation ended the session"
    # Con --yes: termina RED y solo RED
    assert_status 0 _URB sessions kill red --yes
    tmux -L "$URB_RED_SOCKET" has-session 2>/dev/null && _fail "red session still alive"
    tmux -L "$URB_GOD_SOCKET" has-session -t god 2>/dev/null || _fail "killing RED affected GOD"
    assert_contains "$(_URB sessions)" "god      detached"
    assert_status 0 _URB sessions kill god --yes
    _cleanup_sockets
}

test_lifecycle_detach_exit_ctrl_d_external_and_server_loss() {
    _have_deps || return 0
    _unique_sockets
    local cap
    # 1) Ctrl+B d → desconexión: la sesión sigue viva
    ( cd "$HOME" && _pty "$HOME/l1.txt" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_detach )
    assert_contains "$(cat "$HOME/l1.txt")" "Detached from URB Red"
    assert_eq "$(_rc_of "$HOME/l1.txt")" "0"
    tmux -L "$URB_RED_SOCKET" has-session -t red 2>/dev/null || _fail "detach lost the session"
    # 2) exit → la sesión termina normalmente
    _pty "$HOME/l2.txt" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_exit
    cap="$(cat "$HOME/l2.txt")"
    assert_contains "$cap" "URB Red off"
    assert_contains "$cap" "its last shell exited"
    assert_eq "$(_rc_of "$HOME/l2.txt")" "0"
    tmux -L "$URB_RED_SOCKET" has-session 2>/dev/null && _fail "exit should end the session"
    # 3) Ctrl+D también termina la shell (y la sesión): se explica igual
    ( cd "$HOME" && _pty "$HOME/l3.txt" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_ctrl_d )
    assert_contains "$(cat "$HOME/l3.txt")" "its last shell exited"
    tmux -L "$URB_RED_SOCKET" has-session 2>/dev/null && _fail "Ctrl+D should end the session"
    # 4) Cierre externo de la sesión (kill-session) mientras está conectada
    _keys_external() { sleep 2.5; tmux -L "$URB_RED_SOCKET" kill-session -t red; sleep 1.5; }
    ( cd "$HOME" && _pty "$HOME/l4.txt" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_external )
    assert_contains "$(cat "$HOME/l4.txt")" "or it was closed"
    # 5) Pérdida del servidor tmux mientras está conectada → error explícito
    _keys_loss() { sleep 2.5; tmux -L "$URB_RED_SOCKET" kill-server; sleep 1.5; }
    ( cd "$HOME" && _pty "$HOME/l5.txt" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_loss )
    assert_contains "$(cat "$HOME/l5.txt")" "ended unexpectedly"
    assert_eq "$(_rc_of "$HOME/l5.txt")" "1"
    # En ningún caso aparece el error de configuración de la sesión (prefijo "=")
    assert_not_contains "$(cat "$HOME"/l?.txt)" "no such session"
    _cleanup_sockets
}

test_new_windows_inherit_profile_environment() {
    _have_deps || return 0
    _unique_sockets
    ( cd "$HOME" && _pty "$HOME/w.txt" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_detach )
    assert_not_contains "$(cat "$HOME/w.txt")" "no such session"
    assert_eq "$(tmux -L "$URB_RED_SOCKET" show-environment -t red URB_PROFILE 2>&1)" "URB_PROFILE=red"
    assert_contains "$(tmux -L "$URB_RED_SOCKET" show-options -t red default-command 2>&1)" "zsh -i"
    # Una ventana nueva (como Ctrl+B c) recibe la Zsh y el entorno del perfil
    tmux -L "$URB_RED_SOCKET" new-window -d -t red: -c "$HOME"
    sleep 2
    tmux -L "$URB_RED_SOCKET" send-keys -t red:2 'echo "$URB_PROFILE|$URB_PROFILE_TAG" > "$HOME/w2.txt"' Enter
    sleep 1.5
    assert_eq "$(cat "$HOME/w2.txt" 2>/dev/null)" "red|RED"
    _cleanup_sockets
}

test_hud_session_indicator_is_cached_and_hidden_when_narrow() {
    _unique_sockets
    local hud="$URB_HOME/godmode/hud/status.sh" out log="$HOME/tmux_calls.log"
    export XDG_RUNTIME_DIR="$HOME/run"; mkdir -p "$XDG_RUNTIME_DIR"
    # tmux "espía": registra cada invocación y llama al tmux real
    mkdir -p "$HOME/spy"
    printf '#!/bin/sh\necho "$*" >>"%s"\nexec tmux "$@"\n' "$log" >"$HOME/spy/tmux"; chmod +x "$HOME/spy/tmux"
    export URB_GOD_TMUX="$HOME/spy/tmux"
    # Estrecho: sin indicador y sin consultas
    out="$(bash "$hud" "$HOME" 100 god)"
    assert_not_contains "$out" "SES"
    [[ ! -s "$log" ]] || _fail "narrow HUD queried tmux"
    # Ancho, sin sockets: indicador 0 y ninguna llamada a tmux
    out="$(bash "$hud" "$HOME" 160 god)"
    assert_contains "$out" "SES #[fg=colour255]0"
    [[ ! -s "$log" ]] || _fail "HUD called tmux although no socket exists"
    if _have_deps; then
        rm -f "$XDG_RUNTIME_DIR/urb-god-$(id -u)/sessions"
        tmux -L "$URB_RED_SOCKET" new-session -d -s red 'sleep 60'
        out="$(bash "$hud" "$HOME" 160 red)"
        assert_contains "$out" "SES #[fg=colour255]1"
        local calls; calls="$(wc -l <"$log")"
        # Segunda llamada dentro de los 10 s: sale de la caché, sin consultar tmux
        bash "$hud" "$HOME" 160 god >/dev/null
        bash "$hud" "$HOME" 160 red >/dev/null
        assert_eq "$(wc -l <"$log")" "$calls"
        assert_not_contains "$(bash "$hud" "$HOME" 120 red)" "SES"
    fi
    _cleanup_sockets
}
