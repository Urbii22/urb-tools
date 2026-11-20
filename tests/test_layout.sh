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
    list)       printf 'org.lxqt.QTerminal-4242 4242 qterminal kali :1.6 session-2.scope 2 -\n'
                if [[ -n "${LAYOUT_TEST_ORIGIN_PID:-}" ]]; then
                    service="${LAYOUT_TEST_SERVICE:-org.lxqt.QTerminal-$LAYOUT_TEST_ORIGIN_PID}"
                    printf '%s %s qterminal kali :1.7 session-2.scope 2 -\n' "$service" "$LAYOUT_TEST_ORIGIN_PID"
                fi ;;
    tree)       printf '/tabs/old\n/terminals/old\n/windows/w1\n' ;;
    introspect) case "$3" in
                    /windows/*)   printf 'org.lxqt.QTerminal.WindowInterface interface - - -\n' ;;
                    /tabs/*)      printf 'org.lxqt.QTerminal.TabInterface interface - - -\n' ;;
                    /terminals/*) printf 'org.lxqt.QTerminal.TerminalInterface interface - - -\n' ;;
                    /)            printf 'org.lxqt.QTerminal.Process interface - - -\n' ;;
                esac ;;
    call)       shift; printf '%s|' "$@" >>"$HOME/bus.log"; printf '\n' >>"$HOME/bus.log"
                case "$2:$4" in
                    /:getActiveWindow)               [[ "${LAYOUT_TEST_ACTIVE:-0}" == 1 ]] || exit 1
                                                     echo 'o "/windows/active"' ;;
                    /windows/active:getActiveTab)    echo 'o "/tabs/active"' ;;
                    /tabs/active:getActiveTerminal)  echo 'o "/terminals/focused"' ;;
                    /windows/w1:newTab)              echo 'o "/tabs/t1"' ;;
                    /tabs/t1:getActiveTerminal)      echo 'o "/terminals/a"' ;;
                    /terminals/*:splitHorizontal|/terminals/*:splitVertical)
                        [[ "$2:$4" != "${LAYOUT_TEST_FAIL_SPLIT:-}" ]] || exit 1
                        terminal_ids=(a b c d e f g h i)
                        splits="$(grep -Ec '\|split(Horizontal|Vertical)\|' "$HOME/bus.log")"
                        printf 'o "/terminals/%s"\n' "${terminal_ids[splits]}" ;;
                    /terminals/*:sendText)           [[ "$2" != "${LAYOUT_TEST_FAIL_SEND:-}" ]] ;;
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

test_layout_numbered_sizes_open_one_tab_with_the_requested_commands() {
    _fake_busctl
    local count commands expected first_five
    first_five=$'claude\nurb blue\nurb god\nurb red\nurb dashboard'
    for count in {2..9}; do
        : >"$HOME/bus.log"
        assert_ok env PATH="$HOME/fakebin:$PATH" "$URB_HOME/bin/urb" --no-color layout "$count"
        assert_eq "$(grep -c '|newTab|' "$HOME/bus.log")" 1 "$count-pane layout"
        assert_eq "$(grep -Ec '\|split(Horizontal|Vertical)\|' "$HOME/bus.log")" "$(( count - 1 ))" "$count-pane layout"
        commands="$(awk -F'|' '$4 == "sendText" { if (sub(/^.* && /, "", $6)) print $6; else print "-" }' "$HOME/bus.log")"
        case "$count" in
            2) expected=$'urb god\nurb dashboard' ;;
            3) expected=$'urb god\nurb red\nurb blue' ;;
            4) expected="${first_five%$'\n'*}" ;;
            5) expected="$first_five" ;;
            *) expected+=$'\n-' ;;
        esac
        assert_eq "$commands" "$expected" "$count-pane layout"
    done
}

test_layout_partial_split_failure_only_reports_unavailable_pane() {
    _fake_busctl
    local out rc
    out="$(PATH="$HOME/fakebin:$PATH" LAYOUT_TEST_FAIL_SPLIT='/terminals/b:splitVertical' _URB layout 5 2>&1)"
    rc=$?
    assert_eq "$rc" 1
    assert_contains "$out" 'these panes could not be set up: 4'
    assert_eq "$(grep -c '|sendText|' "$HOME/bus.log")" 4
    assert_contains "$(cat "$HOME/bus.log")" ' && urb dashboard'
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

test_layout_numbered_config_edit_open_and_reset_are_isolated() {
    _fake_busctl
    local dir="$HOME/.config/urb-tools" editor="$HOME/editor"
    mkdir -p "$dir"
    printf 'tl . vim\n' >"$dir/layout.conf"
    cat >"$editor" <<'SH'
#!/usr/bin/env bash
[[ -f "$1" ]] || exit 1
printf '2  "~/other folder"  htop\n' >>"$1"
SH
    chmod +x "$editor"
    assert_ok env VISUAL="$editor" "$URB_HOME/bin/urb" --no-color layout edit 2
    assert_contains "$(_URB layout show 2)" '2  "~/other folder"  htop'
    assert_ok env PATH="$HOME/fakebin:$PATH" "$URB_HOME/bin/urb" --no-color layout 2
    assert_contains "$(cat "$HOME/bus.log")" "cd $HOME/other\ folder && htop"
    assert_ok _URB layout reset 2
    assert_not_contains "$(_URB layout show 2)" 'htop'
    assert_contains "$(_URB layout show 2)" '2  .  urb dashboard'
    assert_eq "$(_URB layout show 4)" 'tl . vim'
}

test_layout_invalid_counts_do_not_open_qterminal() {
    _fake_busctl
    local n
    for n in 0 1 02 10 3.5; do
        assert_status 2 env PATH="$HOME/fakebin:$PATH" "$URB_HOME/bin/urb" --no-color layout "$n"
    done
    assert_status 2 _URB layout show 5 extra
    [[ ! -e "$HOME/bus.log" ]] || _fail 'invalid count contacted QTerminal'
}

test_layout_quoted_folders_unreadable_file_and_clean_stderr() {
    _fake_busctl
    mkdir -p "$HOME/.config/urb-tools"
    printf 'tl "~/mis labs" urb red\ntr "sin cerrar x\n' >"$HOME/.config/urb-tools/layout.conf"
    local out
    out="$(PATH="$HOME/fakebin:$PATH" _URB layout 2>&1)"
    assert_not_contains "$out" "bad array subscript"
    assert_contains "$out" "unclosed quote"
    assert_contains "$(cat "$HOME/bus.log")" "sendText|s|cd $HOME/mis\ labs && urb red"
    assert_contains "$(cat "$HOME/bus.log")" "/|org.lxqt.QTerminal.Process|getActiveWindow|"
    chmod 000 "$HOME/.config/urb-tools/layout.conf"
    if [[ ! -r "$HOME/.config/urb-tools/layout.conf" ]]; then
        assert_status 1 env PATH="$HOME/fakebin:$PATH" "$URB_HOME/bin/urb" --no-color layout
    fi
    chmod 644 "$HOME/.config/urb-tools/layout.conf"
}

test_layout_add_runs_each_app_in_a_new_pane_of_the_active_tab() {
    _fake_busctl
    local app command log origin="$BASHPID"
    mkdir -p "$HOME/work dir"
    for app in god red blue claude codex; do
        : >"$HOME/bus.log"
        case "$app" in god|red|blue) command="urb $app" ;; *) command="$app" ;; esac
        ( cd "$HOME/work dir" && PATH="$HOME/fakebin:$PATH" \
            LAYOUT_TEST_ORIGIN_PID="$origin" LAYOUT_TEST_ACTIVE=1 _URB layout add "$app" ) || _fail "could not add $app"
        log="$(cat "$HOME/bus.log")"
        assert_contains "$log" "org.lxqt.QTerminal-$origin|/windows/active|org.lxqt.QTerminal.WindowInterface|getActiveTab|"
        assert_contains "$log" "/tabs/active|org.lxqt.QTerminal.TabInterface|getActiveTerminal|"
        assert_contains "$log" "/terminals/focused|org.lxqt.QTerminal.TerminalInterface|splitVertical|a{sv}|0|"
        assert_contains "$log" "/terminals/b|org.lxqt.QTerminal.TerminalInterface|sendText|s|cd $HOME/work\ dir && $command"$'\n'"|"
        assert_eq "$(grep -Ec '\|split(Horizontal|Vertical)\|' "$HOME/bus.log")" 1
        assert_eq "$(grep -c '|sendText|' "$HOME/bus.log")" 1
        assert_not_contains "$log" '|newTab|'
    done
    [[ ! -e "$HOME/.config/urb-tools/layout.conf" ]] || _fail 'add wrote a preset file'
}

test_layout_add_finds_qterminal_through_the_tmux_client() {
    _fake_busctl
    local client tmux_bin="$HOME/fakebin/custom-tmux"
    cat >"$tmux_bin" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$HOME/tmux.args"
printf '%s\n' "$LAYOUT_TEST_ORIGIN_PID"
SH
    chmod +x "$tmux_bin"
    sleep 15 & client=$!
    assert_ok env PATH="$HOME/fakebin:$PATH" URB_GOD_TMUX="$tmux_bin" TMUX="/tmp/urb-test,1,2" TMUX_PANE='%4' \
        LAYOUT_TEST_ORIGIN_PID="$client" LAYOUT_TEST_SERVICE=org.lxqt.QTerminal LAYOUT_TEST_ACTIVE=1 \
        "$URB_HOME/bin/urb" --no-color layout add blue
    kill "$client" 2>/dev/null
    wait "$client" 2>/dev/null || true
    assert_eq "$(cat "$HOME/tmux.args")" $'-S\n/tmp/urb-test\ndisplay-message\n-p\n-t\n%4\n#{client_pid}'
    assert_contains "$(cat "$HOME/bus.log")" 'org.lxqt.QTerminal|/terminals/b|org.lxqt.QTerminal.TerminalInterface|sendText|s|'
}

test_layout_add_requires_the_origin_and_an_active_window() {
    _fake_busctl
    local out rc origin="$BASHPID"
    out="$(PATH="$HOME/fakebin:$PATH" LAYOUT_TEST_ACTIVE=1 _URB layout add codex 2>&1)"; rc=$?
    assert_eq "$rc" 1
    assert_contains "$out" 'Could not identify the originating QTerminal'
    [[ ! -e "$HOME/bus.log" ]] || _fail 'add contacted an unrelated QTerminal'

    out="$(PATH="$HOME/fakebin:$PATH" LAYOUT_TEST_ORIGIN_PID="$origin" _URB layout add claude 2>&1)"; rc=$?
    assert_eq "$rc" 1
    assert_contains "$out" 'Could not find the active pane'
    assert_not_contains "$(cat "$HOME/bus.log")" '|getActiveTab|'
}

test_layout_add_rejects_unknown_apps_and_extra_arguments() {
    _fake_busctl
    export PATH="$HOME/fakebin:$PATH"
    assert_status 2 _URB layout add
    assert_status 2 _URB layout add unknown
    assert_status 2 _URB layout add codex extra
    [[ ! -e "$HOME/bus.log" ]] || _fail 'invalid add contacted QTerminal'
}

test_layout_add_reports_a_split_or_send_failure() {
    _fake_busctl
    local out rc origin="$BASHPID"
    export PATH="$HOME/fakebin:$PATH" LAYOUT_TEST_ORIGIN_PID="$origin" LAYOUT_TEST_ACTIVE=1
    out="$(LAYOUT_TEST_FAIL_SPLIT='/terminals/focused:splitVertical' _URB layout add claude 2>&1)"; rc=$?
    assert_eq "$rc" 1
    assert_contains "$out" 'could not split the active pane'
    assert_not_contains "$(cat "$HOME/bus.log")" '|sendText|'

    : >"$HOME/bus.log"
    out="$(LAYOUT_TEST_FAIL_SEND='/terminals/b' _URB layout add claude 2>&1)"; rc=$?
    assert_eq "$rc" 1
    assert_contains "$out" "could not send 'claude'"
}
