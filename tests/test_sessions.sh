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
    assert_status 2 _URB sessions kill red god extra
    assert_status 2 _URB sessions attach red --bogus
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

_keys_parallel_first() {
    sleep 2.5
    printf 'export URB_TEST_SESSION=first; pwd > "$HOME/first.cwd"\r'
    local i
    for (( i=0; i<100; i++ )); do
        [[ -f "$HOME/second.detached" ]] && break
        sleep 0.1
    done
    printf 'echo "$URB_TEST_SESSION" > "$HOME/first.state"\r'
    sleep 0.5
    printf '\002d'
    sleep 0.5
}

_keys_parallel_second() {
    sleep 2.5
    tmux -L "$socket" list-sessions -F '#{session_attached}' >"$HOME/parallel.clients"
    printf 'echo "${URB_TEST_SESSION:-clean}" > "$HOME/second.state"; pwd > "$HOME/second.cwd"\r'
    sleep 0.5
    printf '\002d'
    sleep 0.5
}

_check_parallel_profile_sessions() {
    _have_deps || return 0
    _unique_sockets
    trap _cleanup_sockets EXIT
    local profile="$1" socket_var="URB_${1^^}_SOCKET" socket
    local first second pid i cmd="$URB_HOME/bin/urb --no-color"
    socket="${!socket_var}"
    mkdir "$HOME/first" "$HOME/second"
    ( cd "$HOME/first" && _pty "$HOME/first.pty" "$cmd $profile --no-anim" _keys_parallel_first ) &
    pid=$!
    for (( i=0; i<50; i++ )); do
        [[ -s "$HOME/first.cwd" ]] && break
        sleep 0.1
    done
    first="$(tmux -L "$socket" list-sessions -F '#{session_name}')"
    ( cd "$HOME/second" && _pty "$HOME/second.pty" "$cmd $profile --no-anim" _keys_parallel_second )
    assert_eq "$(tmux -L "$socket" list-sessions -F '#{session_attached}' | sort)" $'0\n1'
    touch "$HOME/second.detached"
    wait "$pid"

    assert_eq "$(cat "$HOME/parallel.clients")" $'1\n1'
    assert_eq "$(cat "$HOME/first.state")" first
    assert_eq "$(cat "$HOME/second.state")" clean
    assert_eq "$(cat "$HOME/first.cwd")" "$HOME/first"
    assert_eq "$(cat "$HOME/second.cwd")" "$HOME/second"
    second="$(tmux -L "$socket" list-sessions -F '#{session_name}' | grep -Fxv "$first")"
    assert_contains "$(_URB sessions)" "$first"
    assert_contains "$(_URB sessions info "$profile" "$second")" "$HOME/second"
    assert_status 2 _URB sessions attach "$profile"
    assert_status 2 _URB "$profile" --kill --yes
    assert_status 1 _URB sessions kill "$profile" "${second%-*}" --yes
    assert_status 0 _URB "$profile" --kill "$second" --yes
    assert_status 1 _URB sessions attach "$profile" kill
    assert_eq "$(tmux -L "$socket" list-sessions -F '#{session_name}')" "$first"
    _pty "$HOME/resume.pty" "$cmd sessions attach $profile $first --no-anim" _keys_exit
    assert_contains "$(cat "$HOME/resume.pty")" "its last shell exited"
    assert_status 1 tmux -L "$socket" has-session
}

test_parallel_red_sessions_start_clean_and_can_be_managed_individually() {
    _check_parallel_profile_sessions red
}

test_parallel_blue_sessions_start_clean_and_can_be_managed_individually() {
    _check_parallel_profile_sessions blue
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
    _pty "$HOME/l2.txt" "$URB_HOME/bin/urb --no-color sessions attach red --no-anim" _keys_exit
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
        tmux -L "$URB_RED_SOCKET" new-session -d -s red-123-00001 'sleep 60'
        out="$(bash "$hud" "$HOME" 160 red)"
        assert_contains "$out" "SES #[fg=colour255]2"
        local calls; calls="$(wc -l <"$log")"
        # Segunda llamada dentro de los 10 s: sale de la caché, sin consultar tmux
        bash "$hud" "$HOME" 160 god >/dev/null
        bash "$hud" "$HOME" 160 red >/dev/null
        assert_eq "$(wc -l <"$log")" "$calls"
        assert_not_contains "$(bash "$hud" "$HOME" 120 red)" "SES"
    fi
    _cleanup_sockets
}

# --- Menú de sesiones (urb sessions menu · Ctrl+B s · S del dashboard) ---------------
_load_menu() {
    load_urb
    # shellcheck source=/dev/null
    source "$URB_HOME/modules/sessions.sh"
}

test_sessions_menu_tree_groups_sessions_by_profile_with_colors() {
    _load_menu
    TERM=xterm-256color urb_init_colors always
    ui_init_theme
    _sm_glyphs
    SMP=(god red)
    SMP_TAG["god"]=GOD SMP_TAG["red"]=RED SMP_LONG["god"]="God Mode" SMP_LONG["red"]="URB Red"
    SMP_SOCK["god"]=s-g SMP_SOCK["red"]=s-r SMP_ERR["god"]="" SMP_ERR["red"]="" SMP_N["god"]=0 SMP_N["red"]=2
    _sm_profile_color god god
    _sm_profile_color red red
    SMS_P=(red red) SMS_N=(red-1-00001 red-2-00002) SMS_ST=(detached attached) SMS_W=(1 3)
    SMS_PATH=("$HOME/labs/box" /tmp) SMS_ACT=(100 100)
    SM_NOW=160 SM_CUR_SOCK=s-r SM_CUR_SESS=red-2-00002
    _sm_rows
    assert_eq "${#SM_ROW_T[@]}" 4
    SM_SEL=2
    local out
    out="$(UI_COLS=100 UI_ROWS=20 _sm_draw "")"
    assert_contains "$out" "GOD (0)"
    assert_contains "$out" "no sessions, n opens one"
    assert_contains "$out" "RED (2)"
    assert_contains "$out" "red-1-00001"
    assert_contains "$out" "~/labs/box"
    assert_contains "$out" "current"
    assert_contains "$out" "1m"
    assert_contains "$out" $'\e[38;5;196m'     # sesiones y cabecera RED en rojo
    assert_contains "$out" $'48;5;196m'        # selección con el color del perfil
    assert_contains "$out" $'\e[38;5;220m'     # GOD en dorado
    # Plegar RED conserva la selección en su cabecera
    SM_FOLD["red"]=1
    _sm_reload 0
    assert_eq "${#SM_ROW_T[@]}" 2
    assert_eq "$SM_SEL" 1
    out="$(UI_COLS=100 UI_ROWS=20 _sm_draw "")"
    assert_not_contains "$out" "red-1-00001"
}

test_sessions_menu_needs_a_terminal() {
    assert_status 1 _URB sessions menu </dev/null
    assert_status 2 _URB sessions menu --bogus
    assert_contains "$(_URB sessions --help)" "sessions menu"
}

# Filas: BLUE · GOD · god (seleccionada) · RED · red-1 → dos veces abajo
_keys_menu_close_first() { sleep 2; printf '\e[B'; sleep 0.3; printf '\e[B'; sleep 0.3; printf 'x'; sleep 0.5; printf 'y'; sleep 1; printf 'q'; sleep 0.5; }

test_sessions_menu_closes_the_selected_session_after_confirming() {
    _have_deps || return 0
    _unique_sockets
    trap _cleanup_sockets EXIT
    tmux -L "$URB_RED_SOCKET" new-session -d -s red-1-00001 'sleep 60'
    tmux -L "$URB_RED_SOCKET" new-session -d -s red-2-00002 'sleep 60'
    tmux -L "$URB_GOD_SOCKET" new-session -d -s god 'sleep 60'
    _pty "$HOME/menu.pty" "$URB_HOME/bin/urb sessions menu" _keys_menu_close_first
    assert_contains "$(cat "$HOME/menu.pty")" "RED (2)"
    assert_contains "$(cat "$HOME/menu.pty")" "Close RED session"
    assert_eq "$(_rc_of "$HOME/menu.pty")" 0
    assert_eq "$(tmux -L "$URB_RED_SOCKET" list-sessions -F '#{session_name}')" red-2-00002
    tmux -L "$URB_GOD_SOCKET" has-session -t =god || _fail "GOD session affected"
}

# Desde dentro de red-1: cambiar a red-2 (mismo perfil) y después a GOD (otro servidor)
_keys_menu_switch() {
    sleep 2
    printf '"$URB_HOME/bin/urb" --no-color sessions menu\r'; sleep 2
    printf '\e[B'; sleep 0.5; printf '\r'; sleep 1.5
    tmux -L "$URB_RED_SOCKET" list-clients -F '#{client_session}' >"$HOME/after-switch"
    printf '"$URB_HOME/bin/urb" --no-color sessions menu\r'; sleep 2
    printf '\e[A\e[A\e[A'; sleep 0.5; printf '\r'; sleep 3
    tmux -L "$URB_GOD_SOCKET" list-clients -F '#{client_session}' >"$HOME/after-jump"
    tmux -L "$URB_RED_SOCKET" list-clients -F '#{client_session}' >"$HOME/red-after-jump"
    printf '\002d'; sleep 1.5
}

test_sessions_menu_switches_inside_a_profile_and_jumps_across_profiles() {
    _have_deps || return 0
    _unique_sockets
    trap _cleanup_sockets EXIT
    local s
    for s in red-1-00001 red-2-00002; do
        tmux -L "$URB_RED_SOCKET" new-session -d -s "$s" -x 110 -y 28 "env URB_HOME='$URB_HOME' bash --norc -i"
    done
    tmux -L "$URB_GOD_SOCKET" new-session -d -s god-1-00001 -x 110 -y 28 'bash --norc -i'
    _pty "$HOME/switch.pty" "tmux -L $URB_RED_SOCKET attach -t =red-1-00001" _keys_menu_switch
    assert_eq "$(cat "$HOME/after-switch")" red-2-00002
    assert_eq "$(cat "$HOME/after-jump")" god-1-00001
    assert_eq "$(cat "$HOME/red-after-jump")" ""
    # Cambiar de sesión nunca termina ninguna
    assert_eq "$(tmux -L "$URB_RED_SOCKET" list-sessions -F '#{session_name}' | sort | tr '\n' ' ')" "red-1-00001 red-2-00002 "
}

# Ctrl+B s y 'sessions' abren el menú flotante dentro de RED; q lo cierra sin tocar nada
_keys_popup() {
    sleep 3
    printf '\002s'; sleep 2.5
    tmux -L "$URB_RED_SOCKET" list-sessions -F '#{session_name}' >"$HOME/popup.sessions"
    printf 'q'; sleep 1
    printf 'sessions\r'; sleep 2.5
    printf 'q'; sleep 1
    printf '\002d'; sleep 1.5
}

test_sessions_popup_opens_from_ctrl_b_s_and_the_sessions_command() {
    _have_deps || return 0
    _unique_sockets
    trap _cleanup_sockets EXIT
    _pty "$HOME/popup.pty" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_popup
    local out
    out="$(cat "$HOME/popup.pty")"
    assert_contains "$out" "URB SESSIONS"
    assert_contains "$out" "RED (1)"
    assert_eq "$(wc -l <"$HOME/popup.sessions")" 1
    assert_status 0 tmux -L "$URB_RED_SOCKET" has-session
}

# --- Portapapeles: lo seleccionado en tmux llega a xclip y la selección se queda ----------
_keys_copy() {
    sleep 2.5; printf 'echo COPIAME\r'; sleep 1
    local t=(tmux -L "$URB_RED_SOCKET") s
    s="$("${t[@]}" list-sessions -F '#{session_name}' | head -n 1)"
    "${t[@]}" show-options -sv copy-command >"$HOME/copy.cmd"
    "${t[@]}" list-keys -T copy-mode MouseDragEnd1Pane >"$HOME/copy.keys"
    "${t[@]}" copy-mode -t "=${s}:"
    "${t[@]}" send-keys -t "=${s}:" -X search-backward 'COPIAME'
    "${t[@]}" send-keys -t "=${s}:" -X begin-selection
    "${t[@]}" send-keys -t "=${s}:" -N 7 -X cursor-right
    "${t[@]}" send-keys -t "=${s}:" -X copy-pipe-no-clear
    sleep 1
    "${t[@]}" display-message -p -t "=${s}:" '#{pane_in_mode}' >"$HOME/copy.mode"
    "${t[@]}" send-keys -t "=${s}:" -X cancel
    sleep 0.5; printf 'exit\r'; sleep 1.5
}

test_god_copies_selection_to_the_desktop_clipboard() {
    _have_deps || return 0
    _unique_sockets
    mkdir -p "$HOME/bin"
    printf '#!/bin/sh\ncat > "$HOME/clip.txt"\n' >"$HOME/bin/xclip"; chmod +x "$HOME/bin/xclip"
    PATH="$HOME/bin:$PATH" DISPLAY=":99" WAYLAND_DISPLAY="" \
        _pty "$HOME/copy.pty" "$URB_HOME/bin/urb --no-color red --no-anim" _keys_copy
    _cleanup_sockets
    assert_eq "$(cat "$HOME/copy.cmd")" "xclip -selection clipboard -in"
    assert_contains "$(cat "$HOME/copy.keys")" "copy-pipe-no-clear"
    assert_eq "$(cat "$HOME/clip.txt" 2>/dev/null)" "COPIAME"
    assert_eq "$(cat "$HOME/copy.mode")" "1" "(la selección sigue en pantalla tras copiar)"
}

# Ctrl+B s en una carpeta con comillas y ';' abre el menú y no ejecuta nada
_keys_popup_quotes() {
    sleep 3
    printf '\002s'; sleep 2.5
    printf 'q'; sleep 1
    printf '\002d'; sleep 1.5
}

test_sessions_popup_is_safe_with_quotes_in_the_folder_name() {
    _have_deps || return 0
    _unique_sockets
    trap _cleanup_sockets EXIT
    local d="$HOME/it's a';touch \$HOME/pwned;'b"
    mkdir -p "$d"
    _pty "$HOME/q.pty" "cd $(printf '%q' "$d") && $URB_HOME/bin/urb --no-color red --no-anim" _keys_popup_quotes
    assert_contains "$(cat "$HOME/q.pty")" "URB SESSIONS"
    [[ ! -e "$HOME/pwned" ]] || _fail "a command in the folder name was executed"
}
