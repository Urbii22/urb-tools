#!/usr/bin/env bash
# Pruebas de URB God Mode (urb god)
# Las pruebas de sesión usan una pseudo-terminal real (`script`) y un socket
# tmux exclusivo por prueba: nunca tocan sesiones tmux reales del usuario.

_have_god_deps() { command -v tmux >/dev/null && command -v zsh >/dev/null && command -v script >/dev/null; }

_god_socket() { printf 'urbtest-%s-%s' "$$" "$RANDOM"; }

# Cierra un servidor tmux CREADO POR LA PRUEBA y borra su fichero de socket
_tmux_cleanup() {
    local sock="$1"
    [[ "$sock" == urbtest-* ]] || return 0
    tmux -L "$sock" kill-server 2>/dev/null
    rm -f -- "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/${sock}"
    return 0
}

# _god_pty SALIDA "comando urb" función_de_teclas
_god_pty() {
    local out="$1" cmd="$2" keys="$3"
    ( "$keys" ) | TERM=xterm-256color timeout 45 script -qfec "stty rows 30 cols 100; $cmd" "$out" >/dev/null 2>&1
}

test_god_help_and_arguments() {
    local urb="$URB_HOME/bin/urb" out
    out="$("$urb" --no-color god --help)"
    assert_eq "$?" 0
    assert_contains "$out" "urb god --kill"
    assert_contains "$out" "Ctrl+B d"
    assert_contains "$out" "Detach"
    assert_contains "$("$urb" --no-color help god)" "URB God Mode"
    assert_contains "$("$urb" --no-color help)" "god"
    assert_status 2 "$urb" god --bogus
    assert_status 2 "$urb" god extra-arg
    URB_GOD_SOCKET='../evil' assert_status 2 "$urb" god --status
}

test_god_dependency_detection() {
    local urb="$URB_HOME/bin/urb" out
    out="$(URB_GOD_TMUX=/nonexistent/tmux "$urb" --no-color god --check 2>&1)"
    assert_eq "$?" 127 "$out"
    assert_contains "$out" "tmux   missing"
    out="$(URB_GOD_ZSH=/nonexistent/zsh "$urb" --no-color god --check 2>&1)"
    assert_eq "$?" 127 "$out"
    assert_contains "$out" "zsh    missing"
    out="$(URB_GOD_TMUX=/nonexistent/tmux "$urb" --no-color god --status 2>&1)"
    assert_eq "$?" 127
    assert_contains "$out" "sudo apt install tmux"
    # El resto de URB-Tools funciona aunque falten tmux/zsh
    assert_eq "$(URB_GOD_TMUX=/nonexistent "$urb" version)" "URB-Tools 0.1.0"
    if _have_god_deps; then
        out="$("$urb" --no-color god --check)"
        assert_eq "$?" 0 "$out"
        assert_contains "$out" "God Mode is ready"
    fi
}

test_god_version_compare() {
    load_urb
    # shellcheck source=/dev/null
    source "$URB_HOME/godmode/god.sh"
    assert_ok god_version_ge "3.6" "3.0"
    assert_ok god_version_ge "3.0a" "3.0"
    assert_ok god_version_ge "next-3.7" "3.0"
    assert_fail god_version_ge "2.9a" "3.0"
    assert_fail god_version_ge "garbage" "3.0"
}

test_god_requires_tty_and_refuses_nesting() {
    local urb="$URB_HOME/bin/urb" out
    out="$("$urb" --no-color god </dev/null 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "interactive terminal"
    command -v script >/dev/null || return 0
    _have_god_deps || return 0
    out="$(TMUX=/tmp/tmux-0/default,1,0 TERM=xterm-256color script -qfec "$urb --no-color god --no-anim" /dev/null </dev/null 2>&1)"
    assert_contains "$out" "inside another tmux session"
}

test_god_zsh_config_syntax() {
    command -v zsh >/dev/null || { echo "zsh not installed: skipped"; return 0; }
    assert_ok zsh -n "$URB_HOME/godmode/zsh/.zshenv"
    assert_ok zsh -n "$URB_HOME/godmode/zsh/.zshrc"
}

test_god_zsh_loads_user_config_without_modifying_it() {
    command -v zsh >/dev/null || return 0
    printf 'alias urbalias="echo FROM_USER"\nexport URB_ENV_MARK=env_ok\n' >"$HOME/.zshrc"
    printf 'export URB_ZSHENV_MARK=zshenv_ok\n' >"$HOME/.zshenv"
    local before out; before="$(cat "$HOME/.zshrc" "$HOME/.zshenv")"
    out="$(cd "$HOME" && ZDOTDIR="$URB_HOME/godmode/zsh" URB_GOD_DIR="$URB_HOME/godmode" URB_GOD_GREETED=1 \
           zsh -i -c 'urbalias; echo "$URB_ENV_MARK $URB_ZSHENV_MARK ZD=$ZDOTDIR"; print -rP "$PROMPT"' 2>&1)"
    assert_contains "$out" "FROM_USER"
    assert_contains "$out" "env_ok zshenv_ok ZD=$HOME"
    out="$(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g')"
    assert_contains "$out" "[GOD]"
    assert_eq "$(cat "$HOME/.zshrc" "$HOME/.zshenv")" "$before"
}

test_god_hud_output() {
    local hud="$URB_HOME/godmode/hud/status.sh" out
    mkdir -p "$HOME/repo" && git -C "$HOME/repo" init -q -b urbtest 2>/dev/null || git -C "$HOME/repo" init -q
    out="$(bash "$hud" "$HOME/repo" 140)"
    assert_eq "$?" 0
    assert_contains "$out" "CPU "
    assert_contains "$out" "RAM "
    assert_contains "$out" "IP "
    assert_contains "$out" "VPN"
    assert_contains "$out" "git:"
    assert_contains "$out" "#[fg=colour"
    out="$(bash "$hud" / 60)"
    assert_not_contains "$out" "IP "
    assert_not_contains "$out" "git:"
    # La caché de CPU es privada del usuario
    local d="${XDG_RUNTIME_DIR:-/tmp}/urb-god-${UID}"
    [[ -d "$d" && -O "$d" ]] || _fail "CPU cache dir not owned by the user"
    assert_eq "$(stat -c '%a' "$d")" "700"
}

_keys_session() {
    sleep 3
    printf 'pwd > "$HOME/pwd.txt"; urbalias > "$HOME/alias.txt"; echo "$URB_GOD" > "$HOME/god.txt"\r'; sleep 1.2
    printf 'sleep 30\r'; sleep 1
    printf '\003'; sleep 1                       # Ctrl+C dentro de God Mode: solo interrumpe sleep
    printf 'echo alive > "$HOME/after_ctrl_c.txt"\r'; sleep 1.2
    printf '\002d'; sleep 1.5                    # Ctrl+B d: desconectar
}
_keys_exit() { sleep 2.5; printf 'exit\r'; sleep 2; }

test_god_session_lifecycle_and_isolation() {
    _have_god_deps || { echo "tmux/zsh/script not available: skipped"; return 0; }
    local urb="$URB_HOME/bin/urb" sock user_sock out
    sock="$(_god_socket)"; user_sock="${sock}-user"
    export URB_GOD_SOCKET="$sock"
    printf 'alias urbalias="echo USER_ALIAS"\n' >"$HOME/.zshrc"
    local zshrc_before; zshrc_before="$(md5sum "$HOME/.zshrc")"
    mkdir -p "$HOME/work dir/start"
    # Un servidor tmux "del usuario" que no debe verse afectado
    tmux -L "$user_sock" new-session -d -s mine 'sleep 300'

    ( cd "$HOME/work dir/start" && _god_pty "$HOME/god1.txt" "$urb --no-color god --no-anim" _keys_session )
    assert_eq "$(cat "$HOME/pwd.txt" 2>/dev/null)" "$HOME/work dir/start"
    assert_eq "$(cat "$HOME/alias.txt" 2>/dev/null)" "USER_ALIAS"
    assert_eq "$(cat "$HOME/god.txt" 2>/dev/null)" "1"
    assert_eq "$(cat "$HOME/after_ctrl_c.txt" 2>/dev/null)" "alive"
    assert_contains "$(cat "$HOME/god1.txt")" "Detached from God Mode"

    # Desconectado: la sesión sigue viva en SU socket
    out="$("$urb" --no-color god --status)"
    assert_contains "$out" "God Mode session running"
    tmux -L "$sock" has-session -t god 2>/dev/null || _fail "god session should survive a detach"

    # Reconectar y salir con exit: la sesión termina y la terminal se restaura
    _god_pty "$HOME/god2.txt" "$urb --no-color god --no-anim" _keys_exit
    assert_contains "$(cat "$HOME/god2.txt")" "God Mode off"
    tmux -L "$sock" has-session 2>/dev/null && _fail "god session should end after exit"
    [[ "$(tail -c 300 "$HOME/god2.txt")" == *$'\e[?1049l'* ]] || _fail "alternate screen not restored at the end"

    # Aislamiento: el servidor del usuario y su .zshrc intactos
    tmux -L "$user_sock" has-session -t mine 2>/dev/null || _fail "user's tmux session was affected"
    assert_eq "$(md5sum "$HOME/.zshrc")" "$zshrc_before"
    [[ ! -e "$HOME/.tmux.conf" ]] || _fail "~/.tmux.conf must not be created"
    _tmux_cleanup "$user_sock"
    _tmux_cleanup "$sock"
    return 0
}

# Un programa en primer plano (sleep) sigue corriendo tras desconectar
_keys_detach_quick() { sleep 2.5; printf 'sleep 300\r'; sleep 1; printf '\002d'; sleep 1.5; }

test_god_kill_only_affects_god_server() {
    _have_god_deps || return 0
    local urb="$URB_HOME/bin/urb" sock user_sock out
    sock="$(_god_socket)"; user_sock="${sock}-user"
    export URB_GOD_SOCKET="$sock"
    tmux -L "$user_sock" new-session -d -s mine 'sleep 300'
    ( cd "$HOME" && _god_pty "$HOME/k1.txt" "$urb --no-color god --no-anim" _keys_detach_quick )
    tmux -L "$sock" has-session -t god 2>/dev/null || _fail "god session not running after detach"
    # Sin confirmación interactiva (no hay tty) y con procesos: no se mata sin --yes
    out="$(setsid -w "$urb" --no-color god --kill </dev/null 2>&1)"
    assert_contains "$out" "Programs still running"
    assert_eq "$("$urb" --no-color god --status | grep -c 'session running')" "1"
    out="$("$urb" --no-color god --kill --yes 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "God Mode session ended"
    tmux -L "$sock" has-session 2>/dev/null && _fail "god server still alive after --kill"
    tmux -L "$user_sock" has-session -t mine 2>/dev/null || _fail "--kill affected another tmux server"
    assert_contains "$("$urb" --no-color god --kill --yes)" "No God Mode session running"
    _tmux_cleanup "$user_sock"
    _tmux_cleanup "$sock"
    return 0
}

test_god_animation_runs_and_restores_terminal() {
    _have_god_deps || return 0
    local urb="$URB_HOME/bin/urb" cap
    URB_GOD_SOCKET="$(_god_socket)"; export URB_GOD_SOCKET
    ( cd "$HOME" && _god_pty "$HOME/anim.txt" "$urb god" _keys_exit_after_anim )
    cap="$(cat "$HOME/anim.txt")"
    assert_contains "$cap" "GOD MODE ONLINE"
    assert_contains "$cap" "GOD MODE OFF"
    [[ "$(tail -c 300 "$HOME/anim.txt")" == *$'\e[?25h'* ]] || _fail "cursor not restored"
    _tmux_cleanup "$URB_GOD_SOCKET"
    return 0
}
_keys_exit_after_anim() { sleep 4; printf 'exit\r'; sleep 2.5; }

test_god_existing_commands_unaffected() {
    local urb="$URB_HOME/bin/urb"
    assert_eq "$("$urb" version)" "URB-Tools 0.1.0"
    assert_status 0 "$urb" scan profiles
    assert_status 0 "$urb" network routes
    assert_status 0 "$urb" monitor --once
    assert_status 0 "$urb" ctf list
    assert_status 0 "$urb" config show
    assert_status 2 "$urb" scan
}
