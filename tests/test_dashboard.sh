#!/usr/bin/env bash
# Pruebas del dashboard 2.0 (centro de control): opciones, navegación, tamaños,
# transiciones a GOD / RED / Zsh normal y vuelta, sesiones, señales, estado de
# la terminal y START_MODE.
# Todas las transiciones se prueban en una pseudo-terminal REAL (`script`) con
# sockets tmux exclusivos por prueba (urbtest-*): nunca tocan sesiones reales.
# Nota: esto verifica el flujo de bytes y el estado del pty, no un QTerminal real.

_URB() { "$URB_HOME/bin/urb" --no-color "$@"; }
_dhave() { command -v tmux >/dev/null && command -v zsh >/dev/null && command -v script >/dev/null; }
_dhave_script() { command -v script >/dev/null; }
_dsock_path() { printf '%s/tmux-%s/%s' "${TMUX_TMPDIR:-/tmp}" "$(id -u)" "$1"; }

_dsockets() { export URB_GOD_SOCKET="urbtest-dg-$$-$RANDOM" URB_RED_SOCKET="urbtest-dr-$$-$RANDOM" URB_BLUE_SOCKET="urbtest-db-$$-$RANDOM"; }
_dcleanup() {
    local s
    for s in "${URB_GOD_SOCKET:-}" "${URB_RED_SOCKET:-}" "${URB_BLUE_SOCKET:-}"; do
        [[ "$s" == urbtest-* ]] || continue
        tmux -L "$s" kill-server 2>/dev/null
        rm -f -- "$(_dsock_path "$s")"
    done
    return 0
}

# _dpty SALIDA "argumentos de urb" función_de_teclas [filas] [columnas]
# Guarda el stty antes y después de urb para comprobar que se restaura.
_dpty() {
    local out="$1" args="$2" keys="$3" rows="${4:-34}" cols="${5:-110}"
    ( "$keys" ) | TERM=xterm-256color timeout 90 script -qfec \
        "stty rows $rows cols $cols; stty -g > \"\$HOME/stty.before\"; $URB_HOME/bin/urb $args; echo URB_RC=\$?; stty -g > \"\$HOME/stty.after\"" \
        "$out" >/dev/null 2>&1
}
_drc() { grep -a -o 'URB_RC=[0-9]*' "$1" | tail -n 1 | cut -d= -f2; }
_dstty_same() {
    if [[ ! -s "$HOME/stty.before" ]] || ! cmp -s "$HOME/stty.before" "$HOME/stty.after"; then
        _fail "stty not restored: $(cat "$HOME/stty.before" 2>/dev/null) vs $(cat "$HOME/stty.after" 2>/dev/null)"
    fi
}
# Al terminar urb: pantalla principal y cursor visible (la última secuencia gana)
_dscreen_restored() {
    local cap; cap="$(cat "$1")"
    cap="${cap%URB_RC=*}"
    [[ "${cap##*$'\e[?1049'}" == l* ]] || _fail "alternate screen still active at the end"
    [[ "${cap##*$'\e[?25'}" == h* ]] || _fail "cursor left hidden at the end"
}

_k_quit()      { sleep 2; printf 'q'; sleep 1; }

# --- Contenido y navegación -----------------------------------------------------
test_dashboard_lists_all_sections_and_options() {
    _dhave_script || return 0
    _dpty "$HOME/all.txt" "--no-color --no-anim" _k_quit 40 120
    local cap; cap="$(cat "$HOME/all.txt")"
    local s
    for s in "TERMINAL ENVIRONMENTS" "CYBERSECURITY TOOLS" "SYSTEM " \
             "GOD MODE" "RED MODE" "BLUE MODE" "NORMAL SHELL" \
             "RECON" "NETWORK" "MONITOR" "LOGS" "CTF" "SETTINGS" "SESSIONS" "HELP" "EXIT" \
             "[G]" "[R]" "[B]" "[Z]" "[1]" "[5]" "[6]" "[S]" "[H]" "[Q]" "RESOURCES" "URB Terminal closed"; do
        assert_contains "$cap" "$s"
    done
    assert_eq "$(_drc "$HOME/all.txt")" "0"
    _dstty_same
    _dscreen_restored "$HOME/all.txt"
}

test_dashboard_navigation_order_keys_and_blue_enabled() {
    load_urb
    # shellcheck source=/dev/null
    source "$URB_HOME/lib/dashboard.sh"
    _dash_parse
    local last=$(( ${#DASH_ITEMS[@]} - 1 ))
    assert_eq "${DI_LABEL[2]}" "BLUE MODE"
    assert_ok dash_selectable 2
    assert_ok dash_selectable 0
    dash_move 0 1;  assert_eq "$DASH_SEL" 1          # GOD → RED
    dash_move 1 1;  assert_eq "$DASH_SEL" 2
    dash_move 3 -1; assert_eq "$DASH_SEL" 2
    dash_move "$last" 1; assert_eq "$DASH_SEL" 0     # vuelta al principio
    dash_move 0 -1; assert_eq "$DASH_SEL" "$last"    # vuelta al final
    dash_key_index g; assert_eq "$DASH_KIDX" 0
    dash_key_index R; assert_eq "$DASH_KIDX" 1
    dash_key_index z; assert_eq "$DASH_KIDX" 3
    dash_key_index 1; assert_eq "${DI_LABEL[DASH_KIDX]}" "RECON"
    dash_key_index 6; assert_eq "${DI_LABEL[DASH_KIDX]}" "SETTINGS"
    dash_key_index s; assert_eq "${DI_LABEL[DASH_KIDX]}" "SESSIONS"
    dash_key_index h; assert_eq "${DI_LABEL[DASH_KIDX]}" "HELP"
    dash_key_index q; assert_eq "${DI_LABEL[DASH_KIDX]}" "EXIT"
    assert_fail dash_key_index x
    # Las herramientas conservan sus números y funciones de siempre
    assert_eq "${DI_TARGET[4]}|${DI_TARGET[5]}|${DI_TARGET[6]}|${DI_TARGET[7]}|${DI_TARGET[8]}" \
              "scan_menu|network_menu|monitor_live|logs_menu|ctf_menu"
    # Cada sección aparece una vez y cada elemento exactamente una vez
    assert_eq "$(printf '%s\n' "${DASH_ROWS[@]}" | grep -c '^S|')" "3"
    assert_eq "$(printf '%s\n' "${DASH_ROWS[@]}" | grep -c '^I|')" "${#DASH_ITEMS[@]}"
}

_k_blue() { sleep 2; printf 'b'; sleep 4; printf '\002d'; sleep 2; printf 'q'; sleep 1; }
test_dashboard_blue_launches_and_detaches() {
    _dhave || return 0
    _dsockets
    _dpty "$HOME/blue.txt" "--no-color --no-anim" _k_blue
    assert_contains "$(cat "$HOME/blue.txt")" "BLUE"
    assert_eq "$(_drc "$HOME/blue.txt")" "0"
    tmux -L "$URB_BLUE_SOCKET" has-session -t blue 2>/dev/null || _fail "BLUE should remain detached"
    _dcleanup
}

_k_scroll() { sleep 2; local i; for (( i = 0; i < 12; i++ )); do printf 'j'; sleep 0.15; done; sleep 0.6; printf 'q'; sleep 1; }
test_dashboard_adaptive_sizes_never_hide_options() {
    _dhave_script || return 0
    local sz r c cap
    for sz in 50x140 34x110 24x80 16x60 12x50; do
        r="${sz%x*}" c="${sz#*x}"
        _dpty "$HOME/sz.txt" "--no-color --no-anim" _k_scroll "$r" "$c"
        cap="$(cat "$HOME/sz.txt")"
        assert_contains "$cap" "GOD MODE" "($sz)"
        assert_contains "$cap" "EXIT" "($sz)"
        assert_contains "$cap" "SESSIONS" "($sz)"
        assert_not_contains "$cap" "needs at least"
        assert_eq "$(_drc "$HOME/sz.txt")" "0"
    done
    # En pantallas pequeñas el menú se desplaza (indicador) en lugar de recortarse
    _dpty "$HOME/small.txt" "--no-color --no-anim" _k_scroll 16 60
    assert_contains "$(cat "$HOME/small.txt")" "more"
    # Demasiado pequeña: aviso claro y salida limpia con q
    _dpty "$HOME/tiny.txt" "--no-color --no-anim" _k_quit 10 40
    assert_contains "$(cat "$HOME/tiny.txt")" "needs at least 50x12"
    assert_eq "$(_drc "$HOME/tiny.txt")" "0"
}

# --- NORMAL SHELL -------------------------------------------------------------------
_k_shell() {
    sleep 2; printf 'z'; sleep 2.5
    printf 'pwd > "$HOME/z_pwd"; urbal > "$HOME/z_alias"; print -r -- "${URB_GOD:-none}|${ZDOTDIR:-unset}|${URB_ASSUME_YES:-no}|${URB_PROFILE:-none}" > "$HOME/z_env"\r'
    sleep 1.2
    printf 'sleep 30\r'; sleep 1
    printf '\003'; sleep 1                      # Ctrl+C: solo interrumpe sleep
    printf 'echo alive > "$HOME/z_alive"; exit\r'; sleep 2.5
    printf 'q'; sleep 1
}
test_dashboard_normal_shell_exit_returns_to_dashboard() {
    _dhave || return 0
    printf 'alias urbal="echo USER_ALIAS"\n' >"$HOME/.zshrc"
    local before; before="$(md5sum "$HOME/.zshrc")"
    mkdir -p "$HOME/work dir"
    ( cd "$HOME/work dir" && _dpty "$HOME/sh.txt" "--no-color --no-anim -y" _k_shell )
    local cap; cap="$(cat "$HOME/sh.txt")"
    assert_eq "$(cat "$HOME/z_pwd" 2>/dev/null)" "$HOME/work dir"
    assert_eq "$(cat "$HOME/z_alias" 2>/dev/null)" "USER_ALIAS"
    # Sin variables de GOD/RED ni opciones globales de urb (-y) heredadas
    assert_eq "$(cat "$HOME/z_env" 2>/dev/null)" "none|unset|no|none"
    assert_eq "$(cat "$HOME/z_alive" 2>/dev/null)" "alive"
    assert_contains "$cap" "Normal zsh (opened from URB)"
    assert_contains "$cap" "Normal shell closed"
    assert_contains "$cap" "URB Terminal closed"
    assert_eq "$(_drc "$HOME/sh.txt")" "0"
    # La Zsh se ejecuta en la pantalla PRINCIPAL (la TUI salió antes de lanzarla)
    local pre="${cap%%Normal zsh (opened from URB)*}"
    [[ "${pre##*$'\e[?1049'}" == l* ]] || _fail "zsh started while the alternate screen was active"
    # Y al volver, la TUI vuelve a entrar en su pantalla
    local post="${cap#*Normal zsh (opened from URB)}"
    assert_contains "$post" $'\e[?1049h'
    _dstty_same
    _dscreen_restored "$HOME/sh.txt"
    assert_eq "$(md5sum "$HOME/.zshrc")" "$before"
}

_k_shell_env() { sleep 2; printf 'z'; sleep 2.5; printf 'print -r -- "${URB_GOD:-none}|${ZDOTDIR:-unset}|${URB_PROFILE:-none}" > "$HOME/z_env2"; exit\r'; sleep 2; printf 'q'; sleep 1; }
test_dashboard_normal_shell_from_inside_god_uses_user_config() {
    _dhave || return 0
    printf 'export FROM_USER_ZSHRC=yes\n' >"$HOME/.zshrc"
    # Simula un urb abierto desde una shell de GOD (sin TMUX: no hace falta)
    ( export URB_GOD=1 ZDOTDIR="$URB_HOME/godmode/zsh" URB_USER_ZDOTDIR="$HOME" URB_PROFILE=god URB_PROFILE_TAG=GOD
      cd "$HOME" && _dpty "$HOME/shg.txt" "--no-color --no-anim" _k_shell_env )
    assert_eq "$(cat "$HOME/z_env2" 2>/dev/null)" "none|unset|none"
    assert_not_contains "$(cat "$HOME/shg.txt")" "[GOD]"
}

_k_shell_quick() { sleep 2; printf 'z'; sleep 1.5; printf 'q'; sleep 1; }
test_dashboard_normal_shell_errors_keep_dashboard() {
    _dhave_script || return 0
    # zsh ausente
    URB_GOD_ZSH=/nonexistent/zsh _dpty "$HOME/nz.txt" "--no-color --no-anim" _k_shell_quick
    assert_contains "$(cat "$HOME/nz.txt")" "zsh is not installed"
    assert_contains "$(cat "$HOME/nz.txt")" "URB Terminal closed"
    assert_eq "$(_drc "$HOME/nz.txt")" "0"
    # zsh que termina al arrancar con error (p. ej. un .zshrc roto)
    command -v zsh >/dev/null || return 0
    printf 'exit 3\n' >"$HOME/.zshrc"
    _dpty "$HOME/bz.txt" "--no-color --no-anim" _k_shell_quick
    assert_contains "$(cat "$HOME/bz.txt")" "zsh exited right after starting (exit 3)"
    assert_eq "$(_drc "$HOME/bz.txt")" "0"
    _dstty_same
}

# --- GOD / RED desde el menú ------------------------------------------------------------
_k_god_detach() {
    sleep 2; printf 'g'; sleep 3.5
    printf 'cd "$HOME"; sleep 300\r'; sleep 1
    printf '\002d'; sleep 2.5                   # Ctrl+B d
    printf 'q'; sleep 1
}
_k_god_reconnect_exit() {
    sleep 2; printf 'g'; sleep 3.5
    tmux -L "$URB_GOD_SOCKET" display -p -t god '#{session_created}' >"$HOME/created2" 2>/dev/null
    tmux -L "$URB_GOD_SOCKET" list-sessions 2>/dev/null | wc -l >"$HOME/nsess"
    printf '\003'; sleep 1                      # Ctrl+C: termina el sleep de la sesión
    printf 'echo "$URB_PROFILE" > "$HOME/g2"; exit\r'; sleep 2.5
    printf 'q'; sleep 1
}
test_dashboard_god_detach_keeps_processes_reconnect_and_exit() {
    _dhave || return 0
    _dsockets
    ( cd "$HOME" && _dpty "$HOME/g1.txt" "--no-color --no-anim" _k_god_detach )
    local cap; cap="$(cat "$HOME/g1.txt")"
    assert_contains "$cap" "God Mode detached: your programs keep running"
    assert_contains "$cap" "URB Terminal closed"
    assert_eq "$(_drc "$HOME/g1.txt")" "0"
    # Volver al dashboard por detach NO termina la sesión ni sus procesos
    tmux -L "$URB_GOD_SOCKET" has-session -t god 2>/dev/null || _fail "detach must keep the GOD session"
    assert_contains "$(tmux -L "$URB_GOD_SOCKET" list-panes -s -t god -F '#{pane_current_command}' 2>/dev/null)" "sleep"
    # Tras tmux se apagan los modos de ratón y se restaura la terminal
    assert_contains "$cap" $'\e[?1000l'
    _dstty_same
    _dscreen_restored "$HOME/g1.txt"
    local created1; created1="$(tmux -L "$URB_GOD_SOCKET" display -p -t god '#{session_created}')"

    # Reconectar desde el menú: la MISMA sesión (sin duplicados); exit la termina
    ( cd "$HOME" && _dpty "$HOME/g2.txt" "--no-color --no-anim" _k_god_reconnect_exit )
    assert_eq "$(cat "$HOME/created2" 2>/dev/null)" "$created1"
    assert_eq "$(tr -d ' ' <"$HOME/nsess")" "1"
    assert_eq "$(cat "$HOME/g2" 2>/dev/null)" "god"
    cap="$(cat "$HOME/g2.txt")"
    assert_contains "$cap" "God Mode session ended (exit)"
    assert_contains "$cap" "URB Terminal closed"
    assert_eq "$(_drc "$HOME/g2.txt")" "0"
    tmux -L "$URB_GOD_SOCKET" has-session 2>/dev/null && _fail "exit should end the GOD session"
    _dstty_same
    _dcleanup
}

_k_red_detach() {
    sleep 2; printf 'r'; sleep 3.5
    printf 'echo "$URB_PROFILE|$URB_PROFILE_TAG" > "$HOME/r1"\r'; sleep 1
    printf '\002d'; sleep 2.5
    printf 'q'; sleep 1
}
test_dashboard_red_from_menu_is_isolated_from_god() {
    _dhave || return 0
    _dsockets
    mkdir -p "$HOME/labs"
    ( cd "$HOME" && _dpty "$HOME/r.txt" "--no-color --no-anim" _k_red_detach )
    assert_eq "$(cat "$HOME/r1" 2>/dev/null)" "red|RED"
    assert_contains "$(cat "$HOME/r.txt")" "URB Red detached"
    tmux -L "$URB_RED_SOCKET" has-session -t red 2>/dev/null || _fail "RED session should survive the detach"
    [[ -e "$(_dsock_path "$URB_GOD_SOCKET")" ]] && _fail "opening RED must not start a GOD server"
    # El gestor global la ve igual que siempre
    assert_contains "$(_URB sessions)" "detached"
    _URB sessions kill red --yes >/dev/null
    _dcleanup
}

_k_sessions_attach() {
    sleep 2; printf 's'; sleep 1.5
    printf 'j\r'; sleep 3.5                    # BLUE, después GOD: reconectar
    printf 'echo joined > "$HOME/s1"\r'; sleep 1
    printf '\002d'; sleep 2.5
    printf 'q'; sleep 1
}
_k_detach_only() { sleep 3; printf '\002d'; sleep 2; }
test_dashboard_sessions_reconnects_existing_session() {
    _dhave || return 0
    _dsockets
    ( cd "$HOME" && _dpty "$HOME/pre.txt" "--no-color god --no-anim" _k_detach_only )
    tmux -L "$URB_GOD_SOCKET" has-session -t god 2>/dev/null || { _fail "setup: no GOD session"; return 1; }
    ( cd "$HOME" && _dpty "$HOME/s.txt" "--no-color --no-anim" _k_sessions_attach )
    local cap; cap="$(cat "$HOME/s.txt")"
    assert_contains "$cap" "detached (1 window(s)): Enter reconnects"
    assert_eq "$(cat "$HOME/s1" 2>/dev/null)" "joined"
    assert_contains "$cap" "God Mode detached"
    assert_eq "$(_drc "$HOME/s.txt")" "0"
    tmux -L "$URB_GOD_SOCKET" has-session -t god 2>/dev/null || _fail "SESSIONS must never end a session"
    _dcleanup
}

# Una sesión conectada en otra terminal: se comparte (como `urb god`), no se roba
_k_long_attach() { sleep 11; printf '\002d'; sleep 2; }
_k_join_shared() {
    sleep 4; printf 'g'; sleep 3
    tmux -L "$URB_GOD_SOCKET" list-clients -t god 2>/dev/null | wc -l >"$HOME/clients"
    printf '\002d'; sleep 2.5
    printf 'q'; sleep 1
}
test_dashboard_shared_session_is_not_taken_over() {
    _dhave || return 0
    _dsockets
    ( cd "$HOME" && TERM=xterm-256color timeout 60 script -qfec "stty rows 30 cols 100; $URB_HOME/bin/urb --no-color god --no-anim; echo URB_RC=\$?" "$HOME/a.txt" \
        < <(_k_long_attach) >/dev/null 2>&1 ) &
    local apid=$!
    ( cd "$HOME" && _dpty "$HOME/b.txt" "--no-color --no-anim" _k_join_shared )
    wait "$apid"
    assert_eq "$(tr -d ' ' <"$HOME/clients")" "2"
    assert_contains "$(cat "$HOME/b.txt")" "still attached in another terminal"
    # La otra terminal siguió conectada hasta su propio detach
    assert_contains "$(cat "$HOME/a.txt")" "Detached from God Mode"
    assert_eq "$(_drc "$HOME/a.txt")" "0"
    tmux -L "$URB_GOD_SOCKET" has-session -t god 2>/dev/null || _fail "session must survive"
    _dcleanup
}

_k_g_quit() { sleep 2; printf 'g'; sleep 1.5; printf 'r'; sleep 1.5; printf 'q'; sleep 1; }
test_dashboard_refuses_nested_tmux_safely() {
    _dhave || return 0
    _dsockets
    TMUX="/tmp/tmux-0/default,1,0" _dpty "$HOME/n.txt" "--no-color --no-anim" _k_g_quit
    local cap; cap="$(cat "$HOME/n.txt")"
    assert_contains "$cap" "cannot start inside another tmux session"
    assert_contains "$cap" "URB Terminal closed"
    assert_eq "$(_drc "$HOME/n.txt")" "0"
    [[ -e "$(_dsock_path "$URB_GOD_SOCKET")" || -e "$(_dsock_path "$URB_RED_SOCKET")" ]] && _fail "no tmux server may start when nested"
    # Dentro del propio GOD: se avisa, sin lanzar nada
    TMUX="$(_dsock_path "$URB_GOD_SOCKET"),1,0" _dpty "$HOME/n2.txt" "--no-color --no-anim" _k_g_quit
    assert_contains "$(cat "$HOME/n2.txt")" "already inside God Mode"
    _dcleanup
}

_k_g_fail() { sleep 2; printf 'g'; sleep 2.5; printf ' '; sleep 1.5; printf 'q'; sleep 1; }
test_dashboard_start_errors_return_to_dashboard() {
    _dhave_script || return 0
    _dsockets
    URB_GOD_TMUX=/nonexistent/tmux _dpty "$HOME/e.txt" "--no-color --no-anim" _k_g_fail
    local cap; cap="$(cat "$HOME/e.txt")"
    assert_contains "$cap" "God Mode needs: tmux"
    assert_contains "$cap" "Press any key to return to the URB dashboard"
    assert_contains "$cap" "God Mode failed (exit 127)"
    assert_contains "$cap" "URB Terminal closed"
    assert_eq "$(_drc "$HOME/e.txt")" "0"
    _dstty_same
    _dscreen_restored "$HOME/e.txt"
}

# --- Señales -----------------------------------------------------------------------------
_k_ctrl_c()  { sleep 2; printf '\003'; sleep 1; }
_k_ctrl_bs() { sleep 2; printf '\034'; sleep 1; }
_k_ctrl_z()  { sleep 2; printf '\032'; sleep 1; printf 'q'; sleep 1; }
test_dashboard_signals_always_restore_terminal() {
    _dhave_script || return 0
    _dpty "$HOME/c.txt" "--no-color --no-anim" _k_ctrl_c
    assert_eq "$(_drc "$HOME/c.txt")" "130"
    _dstty_same; _dscreen_restored "$HOME/c.txt"
    _dpty "$HOME/bs.txt" "--no-color --no-anim" _k_ctrl_bs
    assert_eq "$(_drc "$HOME/bs.txt")" "131"
    _dstty_same; _dscreen_restored "$HOME/bs.txt"
    # Ctrl+Z no suspende la TUI (dejaría la shell en la pantalla alternativa)
    _dpty "$HOME/z.txt" "--no-color --no-anim" _k_ctrl_z
    assert_eq "$(_drc "$HOME/z.txt")" "0"
    assert_contains "$(cat "$HOME/z.txt")" "URB Terminal closed"
    _dstty_same; _dscreen_restored "$HOME/z.txt"
}

# Un hijo que MUERE por SIGINT (sin control de trabajos: comparte el grupo de
# procesos con el dashboard, así que ambos reciben Ctrl+C). El hijo debe morir
# y el dashboard seguir vivo, volver a su pantalla y salir con q.
_k_child_sigint() { sleep 2; printf 'z'; sleep 2; printf '\003'; sleep 2; printf 'q'; sleep 1; }
test_dashboard_survives_child_killed_by_sigint() {
    _dhave_script || return 0
    printf '#!/bin/sh\necho FAKE_SHELL_RUNNING\nexec sleep 30\n' >"$HOME/fakezsh"
    chmod +x "$HOME/fakezsh"
    URB_GOD_ZSH="$HOME/fakezsh" _dpty "$HOME/si.txt" "--no-color --no-anim" _k_child_sigint
    local cap; cap="$(cat "$HOME/si.txt")"
    assert_contains "$cap" "FAKE_SHELL_RUNNING"
    assert_contains "$cap" "Normal shell closed (last exit status 130)"
    assert_contains "$cap" "URB Terminal closed"
    assert_eq "$(_drc "$HOME/si.txt")" "0"
    pgrep -f "$HOME/fakezsh" >/dev/null && _fail "the child should have been interrupted"
    _dstty_same; _dscreen_restored "$HOME/si.txt"
}

# --- START_MODE -------------------------------------------------------------------------
test_start_mode_config_validation() {
    local conf="$HOME/.config/urb-tools/urb.conf" out
    assert_status 0 _URB config set START_MODE god
    assert_contains "$(cat "$conf")" 'START_MODE="god"'
    assert_status 0 _URB config set START_MODE red
    assert_status 0 _URB config set START_MODE dashboard
    assert_status 0 _URB config set START_MODE blue
    assert_status 0 _URB config set START_MODE dashboard
    out="$(_URB config set START_MODE bogus 2>&1)"; assert_eq "$?" 2
    assert_contains "$out" "Valid values: dashboard god red blue"
    assert_status 2 _URB config set START_MODE 'god;id'
    assert_contains "$(cat "$conf")" 'START_MODE="dashboard"'
    # El valor por defecto sigue siendo el dashboard
    assert_contains "$(_URB config show)" "START_MODE"
    assert_contains "$(grep START_MODE "$URB_HOME/config/default.conf")" 'START_MODE="dashboard"'
}

test_start_mode_launches_and_recovers() {
    _dhave || return 0
    _dsockets
    local conf="$HOME/.config/urb-tools/urb.conf"
    mkdir -p "${conf%/*}"
    # Inválido (editado a mano): error claro y el dashboard se abre igualmente
    printf 'START_MODE="bogus"\n' >"$conf"
    _dpty "$HOME/m1.txt" "--no-color --no-anim" _k_quit
    assert_contains "$(cat "$HOME/m1.txt")" "Invalid START_MODE 'bogus'"
    assert_contains "$(cat "$HOME/m1.txt")" "MAIN MENU"
    assert_eq "$(_drc "$HOME/m1.txt")" "0"
    # god: entra directamente en GOD (igual que urb god); el detach vuelve a la shell
    printf 'START_MODE="god"\n' >"$conf"
    ( cd "$HOME" && _dpty "$HOME/m2.txt" "--no-color --no-anim" _k_detach_only )
    assert_contains "$(cat "$HOME/m2.txt")" "Detached from God Mode"
    assert_not_contains "$(cat "$HOME/m2.txt")" "MAIN MENU"
    assert_eq "$(_drc "$HOME/m2.txt")" "0"
    tmux -L "$URB_GOD_SOCKET" has-session -t god 2>/dev/null || _fail "START_MODE=god should leave the session detached"
    # urb dashboard abre siempre el menú
    _dpty "$HOME/m3.txt" "--no-color --no-anim dashboard" _k_quit
    assert_contains "$(cat "$HOME/m3.txt")" "MAIN MENU"
    # god sin tmux: error y recuperación en el dashboard
    URB_GOD_TMUX=/nonexistent/tmux _dpty "$HOME/m4.txt" "--no-color --no-anim" _k_quit
    assert_contains "$(cat "$HOME/m4.txt")" "could not open (exit 127)"
    assert_contains "$(cat "$HOME/m4.txt")" "URB Terminal closed"
    # red: entra directamente en RED
    printf 'START_MODE="red"\n' >"$conf"
    ( cd "$HOME" && _dpty "$HOME/m5.txt" "--no-color --no-anim" _k_detach_only )
    assert_contains "$(cat "$HOME/m5.txt")" "Detached from URB Red"
    _dcleanup
}

# --- Ayuda y compatibilidad -----------------------------------------------------------------
_k_help() { sleep 2; printf 'h'; sleep 2; printf 'q'; sleep 1.5; printf 'q'; sleep 1; }
test_dashboard_help_and_cli_compatibility() {
    local out
    out="$(_URB help)"
    assert_contains "$out" "DASHBOARD"
    assert_contains "$out" "normal zsh"
    assert_contains "$out" "Ctrl+B d"
    assert_contains "$out" "START_MODE"
    assert_contains "$(_URB help config)" "START_MODE"
    # Los comandos directos siguen igual
    assert_contains "$(_URB god --help)" "urb god --kill"
    assert_contains "$(_URB red --help)" "urb red"
    assert_status 0 _URB sessions
    assert_status 2 _URB sessions attach
    if _dhave_script && command -v less >/dev/null; then
        _dpty "$HOME/h.txt" "--no-color --no-anim" _k_help
        assert_contains "$(cat "$HOME/h.txt")" "COMMANDS"
        assert_contains "$(cat "$HOME/h.txt")" "URB Terminal closed"
        assert_eq "$(_drc "$HOME/h.txt")" "0"
    fi
}
