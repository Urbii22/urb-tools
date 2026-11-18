#!/usr/bin/env bash
# Pruebas de urb layout con un busctl falso que imita la interfaz D-Bus de QTerminal.

_URB() { "$URB_HOME/bin/urb" --no-color "$@"; }

# busctl falso: registra cada llamada en $HOME/bus.log y responde como QTerminal 2.4
_fake_busctl() {
    mkdir -p "$HOME/fakebin"
    cat >"$HOME/fakebin/busctl" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "--user" ]] && shift
case "$1" in
    list)       printf 'org.lxqt.QTerminal-4242 4242 qterminal kali :1.6 session-2.scope 2 -\n' ;;
    tree)       printf '/tabs/old\n/terminals/old\n/windows/w1\n' ;;
    introspect) case "$3" in
                    /windows/*)   printf 'org.lxqt.QTerminal.WindowInterface interface - - -\n' ;;
                    /tabs/*)      printf 'org.lxqt.QTerminal.TabInterface interface - - -\n' ;;
                    /terminals/*) printf 'org.lxqt.QTerminal.TerminalInterface interface - - -\n' ;;
                    /)            printf 'org.lxqt.QTerminal.Process interface - - -\n' ;;
                esac ;;
    call)       shift; printf '%s|' "$@" >>"$HOME/bus.log"; printf '\n' >>"$HOME/bus.log"
                case "$2:$4" in
                    /:getActiveWindow)               exit 1 ;;
                    /windows/w1:newTab)              echo 'o "/tabs/t1"' ;;
                    /tabs/t1:getActiveTerminal)      echo 'o "/terminals/a"' ;;
                    /terminals/a:splitHorizontal)    echo 'o "/terminals/b"' ;;
                    /terminals/a:splitVertical)      echo 'o "/terminals/c"' ;;
                    /terminals/b:splitVertical)      echo 'o "/terminals/d"' ;;
                    /terminals/*:sendText)           ;;
                    *) exit 1 ;;
                esac ;;
esac
SH
    chmod +x "$HOME/fakebin/busctl"
}

test_layout_opens_four_panes_with_their_commands() {
    _fake_busctl
    mkdir -p "$HOME/work dir"
    local out log
    out="$(cd "$HOME/work dir" && PATH="$HOME/fakebin:$PATH" _URB layout 2>&1)"
    assert_contains "$out" "Layout opened"
    assert_file "$HOME/.config/urb-tools/layout.conf"
    log="$(cat "$HOME/bus.log")"
    assert_contains "$log" "/windows/w1|org.lxqt.QTerminal.WindowInterface|newTab|a{sv}|0|"
    assert_contains "$log" "/terminals/a|org.lxqt.QTerminal.TerminalInterface|splitHorizontal|"
    assert_contains "$log" "/terminals/b|org.lxqt.QTerminal.TerminalInterface|splitVertical|"
    # Cada panel: cd a la carpeta (con espacios bien escapados) y su comando, con Enter
    assert_contains "$log" "/terminals/a|org.lxqt.QTerminal.TerminalInterface|sendText|s|cd $HOME/work\ dir && claude"$'\n'"|"
    assert_contains "$log" "/terminals/b|org.lxqt.QTerminal.TerminalInterface|sendText|s|cd $HOME/work\ dir && urb blue"
    assert_contains "$log" "/terminals/c|org.lxqt.QTerminal.TerminalInterface|sendText|s|cd $HOME/work\ dir && urb god"
    assert_contains "$log" "/terminals/d|org.lxqt.QTerminal.TerminalInterface|sendText|s|cd $HOME/work\ dir && urb red"
}

test_layout_file_controls_folders_and_commands() {
    _fake_busctl
    mkdir -p "$HOME/.config/urb-tools"
    printf '# mío\ntl ~/notes htop\ntr /srv -\nzz . nada\n' >"$HOME/.config/urb-tools/layout.conf"
    local out log
    out="$(PATH="$HOME/fakebin:$PATH" _URB layout 2>&1)"
    assert_contains "$out" "unknown position 'zz'"
    log="$(cat "$HOME/bus.log")"
    assert_contains "$log" "/terminals/a|org.lxqt.QTerminal.TerminalInterface|sendText|s|cd $HOME/notes && htop"
    assert_contains "$log" "/terminals/b|org.lxqt.QTerminal.TerminalInterface|sendText|s|cd /srv"$'\n'"|"
    assert_contains "$log" "/terminals/c|org.lxqt.QTerminal.TerminalInterface|sendText|s|cd $HOME"$'\n'"|"
}

test_layout_without_qterminal_fails_clearly() {
    mkdir -p "$HOME/fakebin"
    printf '#!/bin/sh\nexit 0\n' >"$HOME/fakebin/busctl"; chmod +x "$HOME/fakebin/busctl"
    local out rc
    out="$(PATH="$HOME/fakebin:$PATH" _URB layout 2>&1)"; rc=$?
    assert_eq "$rc" "1"
    assert_contains "$out" "only works in QTerminal"
}

test_layout_show_reset_and_help() {
    local out
    out="$(_URB layout show)"
    assert_contains "$out" "tr  .  urb blue"
    printf 'tl . vim\n' >"$HOME/.config/urb-tools/layout.conf"
    assert_contains "$(_URB layout reset)" "Default layout restored"
    assert_contains "$(_URB layout show)" "tl  .  claude"
    assert_contains "$(_URB help layout)" "tl (top left)"
    assert_status 2 _URB layout bogus
}
