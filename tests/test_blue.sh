#!/usr/bin/env bash
_URB() { "$URB_HOME/bin/urb" --no-color "$@"; }

test_blue_ingest_detect_cases_persist() {
    command -v python3 >/dev/null || return 0
    local before; before="$(sha256sum "$FIXTURES/blue_windows.csv" | cut -d' ' -f1)"
    assert_status 0 _URB blue workspace new demo
    assert_status 0 _URB blue ingest windows "$FIXTURES/blue_windows.csv"
    assert_contains "$(_URB blue sources)" '9 | 1'
    assert_contains "$(_URB blue sources)" "$before"
    assert_eq "$(sha256sum "$FIXTURES/blue_windows.csv" | cut -d' ' -f1)" "$before"
    assert_contains "$(_URB blue ingest windows "$FIXTURES/blue_windows.csv")" 'already imported'
    assert_status 0 _URB blue ingest linux "$FIXTURES/blue_linux.log"
    assert_contains "$(_URB blue events --id 4625 --limit 20)" '192.0.2.10'
    assert_contains "$(_URB blue detect run)" '1 created'
    assert_contains "$(_URB blue detect run)" '0 created, 0 updated'
    assert_contains "$(_URB blue alerts show A-001)" 'E-001'
    assert_status 0 _URB blue cases new 'Investigate failures'
    assert_status 0 _URB blue cases link C-001 --alert A-001
    assert_status 0 _URB blue cases note C-001 'Check activity'
    assert_status 0 _URB blue cases evidence C-001 "$FIXTURES/blue_linux.log"
    assert_contains "$(_URB blue cases show C-001)" 'A-001'
    assert_contains "$(_URB blue workspace status)" demo
    assert_status 0 _URB blue cases close C-001
    assert_contains "$(_URB blue cases show C-001)" closed
}

test_blue_timezone_and_transaction() {
    command -v python3 >/dev/null || return 0
    _URB blue workspace new demo >/dev/null
    cat >"$HOME/ambiguous.csv" <<'CSV'
Timestamp,EventID,Host,User,IP,Message
2026-11-12 10:00:00,4625,host,user,192.0.2.3,one
2026-11-12 10:01:00,4625,host,user,192.0.2.3,two
2026-11-12 10:02:00,4625,host,user,192.0.2.3,three
2026-11-12 10:03:00,4625,host,user,192.0.2.3,four
2026-11-12 10:04:00,4625,host,user,192.0.2.3,five
CSV
    assert_status 0 _URB blue ingest windows "$HOME/ambiguous.csv"
    assert_contains "$(_URB blue detect run)" '0 created'
    assert_status 1 _URB blue ingest windows "$HOME/ambiguous.csv" --tz +01:00
    _URB blue workspace new timed >/dev/null
    assert_status 0 _URB blue ingest windows "$HOME/ambiguous.csv" --tz +01:00
    assert_contains "$(_URB blue detect run)" '1 created'
    printf 'Timestamp,EventID\n"unfinished' >"$HOME/broken.csv"
    assert_status 1 _URB blue ingest windows "$HOME/broken.csv"
    assert_not_contains "$(_URB blue sources)" broken.csv
    assert_status 1 _URB blue events --since '2026-11-12 10:00'
}

test_blue_rejects_imprecise_times_for_detection() {
    command -v python3 >/dev/null || return 0
    _URB blue workspace new demo >/dev/null
    {
        echo 'Timestamp,EventID,Host,User,IP,Message'
        local i
        for i in 1 2 3 4 5; do echo "2026-11-12T10:00:00.1234567Z,4625,h,u,192.0.2.5,x$i"; done
    } >"$HOME/precision.csv"
    _URB blue ingest windows "$HOME/precision.csv" >/dev/null
    assert_contains "$(_URB blue detect run)" '0 created'
    assert_contains "$(_URB blue events show E-001)" '2026-11-12T10:00:00.1234567Z'
}

test_blue_alert_update_for_extended_burst() {
    command -v python3 >/dev/null || return 0
    _URB blue workspace new demo >/dev/null
    _URB blue ingest windows "$FIXTURES/blue_windows.csv" >/dev/null
    _URB blue detect run >/dev/null
    printf 'Timestamp,EventID,Host,User,IP,Message\n2026-11-12T10:05:00Z,4625,WIN-LAB,alice,192.0.2.10,More failures\n' >"$HOME/more.csv"
    _URB blue ingest windows "$HOME/more.csv" >/dev/null
    assert_contains "$(_URB blue detect run)" '0 created, 1 updated'
    assert_contains "$(_URB blue alerts)" '6 events'
    assert_not_contains "$(_URB blue alerts)" 'A-002'
}

test_blue_shell_context_and_conflicts() {
    command -v zsh >/dev/null || return 0
    printf 'alias events="echo personal"\n' >"$HOME/.zshrc"
    local out
    out="$(URB_GOD_DIR="$URB_HOME/godmode" ZDOTDIR="$URB_HOME/godmode/zsh" URB_PROFILE=blue URB_PROFILE_TAG=BLUE URB_PROFILE_THEME=blue URB_GOD_GREETED=1 zsh -i -c 'whence -w workspace; whence -w events; print -r -- "completion=${_comps[workspace]}"; workspace new demo; status' 2>&1)"
    assert_contains "$out" 'workspace: function'
    assert_contains "$out" 'events: alias'
    assert_contains "$out" "use 'urb blue events'"
    assert_contains "$out" 'completion=_urb_context_complete'
    assert_contains "$out" 'Workspace: demo'
}

test_blue_storage_permissions_and_symlink_rejection() {
    command -v python3 >/dev/null || return 0
    assert_status 0 _URB blue workspace new demo
    assert_eq "$(stat -c '%a' "$HOME/urb-blue/demo")" 700
    assert_eq "$(stat -c '%a' "$HOME/urb-blue/demo/blue.sqlite3")" 600
    assert_status 0 _URB blue ingest windows "$FIXTURES/blue_windows.csv"
    assert_eq "$(stat -c '%a' "$HOME/urb-blue/demo/sources/"*.source)" 400
    mv "$HOME/urb-blue/demo/sources" "$HOME/sources-real"
    ln -s "$HOME/sources-real" "$HOME/urb-blue/demo/sources"
    assert_status 1 _URB blue ingest windows "$FIXTURES/blue_windows.csv"
}

test_blue_three_session_profiles() {
    assert_contains "$(_URB sessions)" 'blue'
    assert_status 0 _URB sessions info blue
    assert_status 0 _URB config set START_MODE blue
    assert_status 0 _URB config set START_MODE dashboard
}

test_blue_burst_bridge_preserves_original_alerts_and_case_links() {
    command -v python3 >/dev/null || return 0
    _URB blue workspace new demo >/dev/null
    {
        echo 'Timestamp,EventID,Host,User,IP,Message'
        local i
        for i in 1 2 3 4 5; do echo "2026-11-12T10:00:00Z,4625,h,u,192.0.2.50,a$i"; done
        for i in 1 2 3 4 5; do echo "2026-11-12T10:18:00Z,4625,h,u,192.0.2.50,b$i"; done
    } >"$HOME/bursts.csv"
    _URB blue ingest windows "$HOME/bursts.csv" >/dev/null
    assert_contains "$(_URB blue detect run)" '2 created'
    _URB blue cases new bridge >/dev/null
    _URB blue cases link C-001 --alert A-002 >/dev/null
    printf 'Timestamp,EventID,Host,User,IP,Message\n2026-11-12T10:09:00Z,4625,h,u,192.0.2.50,bridge\n' >"$HOME/bridge.csv"
    _URB blue ingest windows "$HOME/bridge.csv" >/dev/null
    assert_contains "$(_URB blue detect run)" '1 merged'
    assert_contains "$(_URB blue alerts show A-002)" 'merged_into: 1'
    assert_contains "$(_URB blue cases show C-001)" 'A-002'
    assert_contains "$(_URB blue detect run)" '0 created, 0 updated, 0 merged'
}

test_blue_concurrent_import_is_idempotent() {
    command -v python3 >/dev/null || return 0
    _URB blue workspace new demo >/dev/null
    _URB blue ingest windows "$FIXTURES/blue_windows.csv" >"$HOME/first" 2>&1 & local p1=$!
    _URB blue ingest windows "$FIXTURES/blue_windows.csv" >"$HOME/second" 2>&1 & local p2=$!
    wait "$p1" || _fail 'first import failed'
    wait "$p2" || _fail 'second import failed'
    assert_contains "$(cat "$HOME/first" "$HOME/second")" 'already imported'
    assert_eq "$(_URB blue sources | wc -l | tr -d ' ')" 2
    assert_contains "$(_URB blue status)" 'Events: 9'
}

test_blue_offline_import_and_detection() {
    command -v python3 >/dev/null || return 0
    PYTHONPATH="$URB_HOME/lib" URB_BLUE_ROOT="$HOME/blue" python3 -B - "$FIXTURES/blue_windows.csv" <<'PY'
import socket, sys
def forbid(*args, **kwargs):
    raise AssertionError('network socket opened')
socket.socket = forbid
import blue_cli
for args in (['workspace','new','demo'], ['ingest','windows',sys.argv[1]], ['detect','run'], ['events','--id','4625']):
    sys.argv = ['urb blue', *args]
    blue_cli.main()
PY
    [[ $? -eq 0 ]] || _fail 'offline flow failed'
}
