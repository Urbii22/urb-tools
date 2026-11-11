#!/usr/bin/env bash
# Pruebas del módulo LOGS con un auth.log de ejemplo

test_normalize_formats() {
    load_urb
    local out
    out="$(logs_normalize <"$FIXTURES/auth.log")"
    assert_eq "$(printf '%s\n' "$out" | wc -l)" 13
    assert_contains "$out" $'-11-09 08:01:12\tkali\tsshd\tFailed password for root from 10.0.0.5 port 50122 ssh2'
    assert_contains "$out" $'2026-11-11 07:30:00\tkali\tsshd-session\tFailed publickey for root'
    assert_contains "$out" $'\tsudo\tdiego : 1 incorrect password attempt'
}

test_filter_auth_category() {
    load_urb
    local n
    n="$(logs_normalize <"$FIXTURES/auth.log" | logs_filter auth "" "" "" "" "" | wc -l)"
    # 4 Failed password + 1 Invalid user + 1 Failed publickey + sudo pam failure + sudo incorrect
    assert_eq "$n" 8
}

test_filter_ip_user_grep() {
    load_urb
    local out
    out="$(logs_normalize <"$FIXTURES/auth.log" | logs_filter all "" "" "" "10.0.0.5" "")"
    assert_eq "$(printf '%s\n' "$out" | wc -l)" 4
    assert_not_contains "$out" "10.0.0.50"
    out="$(logs_normalize <"$FIXTURES/auth.log" | logs_filter all "" "" "admin" "" "")"
    assert_eq "$(printf '%s\n' "$out" | wc -l)" 2
    out="$(logs_normalize <"$FIXTURES/auth.log" | logs_filter all "" "" "" "" "ACCEPTED")"
    assert_eq "$(printf '%s\n' "$out" | wc -l)" 1
}

test_filter_dates() {
    load_urb
    local out
    out="$(logs_normalize <"$FIXTURES/auth.log" | logs_filter ssh "2026-11-11 00:00:00" "" "" "" "")"
    assert_eq "$(printf '%s\n' "$out" | wc -l)" 2
    assert_eq "$(logs_parse_date 2026-11-01 0)" "2026-11-01 00:00:00"
    assert_eq "$(logs_parse_date 2026-11-01 1)" "2026-11-01 23:59:59"
    assert_eq "$(logs_parse_date '2026-11-01 10:30' 0)" "2026-11-01 10:30:00"
    assert_fail logs_parse_date "01/11/2026" 0
    assert_fail logs_parse_date "2026-11-01;id" 0
}

test_summary_stats() {
    load_urb
    local out
    out="$(logs_normalize <"$FIXTURES/auth.log" | logs_summary_stats)"
    assert_contains "$out" $'STAT\tFailed logins (ssh)\t5'
    assert_contains "$out" $'STAT\tAccepted logins\t1'
    assert_contains "$out" $'STAT\tsudo failures\t2'
    assert_contains "$out" $'IP\t10.0.0.5\t3'
    assert_contains "$out" $'USER\troot\t3'
    assert_contains "$out" $'ACC\tdiego from 192.168.56.20\t1'
}

test_logs_cli_file() {
    local urb="$URB_HOME/bin/urb" out
    out="$("$urb" --no-color logs summary --file "$FIXTURES/auth.log")"
    assert_contains "$out" "Failed logins (ssh)"
    assert_contains "$out" "10.0.0.5"
    out="$("$urb" --no-color logs ssh --file "$FIXTURES/auth.log" --ip 192.168.56.20)"
    assert_contains "$out" "Accepted password for diego"
    assert_status 2 "$urb" logs auth --since "yesterdayish"
    assert_status 2 "$urb" logs auth --ip "1.2.3.4;id"
    assert_status 2 "$urb" logs auth --user 'root$(id)'
    assert_status 1 "$urb" logs auth --file /nonexistent/file
    assert_status 2 "$urb" logs bogus
}
