#!/usr/bin/env bash
# Pruebas del módulo RECON (sin lanzar escaneos reales salvo a localhost)

test_gnmap_parse() {
    load_urb
    local out
    out="$(scan_parse_gnmap "$FIXTURES/sample.gnmap")"
    assert_eq "$(printf '%s\n' "$out" | wc -l)" 4
    assert_contains "$out" $'10.0.0.10\t22\ttcp\topen\tssh\tOpenSSH 9.6p1 Ubuntu 3ubuntu13 (Ubuntu Linux; protocol 2.0)'
    assert_contains "$out" $'10.0.0.10\t443\ttcp\tfiltered\thttps\t'
    assert_contains "$out" $'10.0.0.11\t3306\ttcp\topen\tmysql\tMySQL 8.0.36'
    assert_eq "$(scan_hosts_up "$FIXTURES/sample.gnmap" | wc -l)" 2
}

test_progress_parse() {
    load_urb
    assert_ok scan_parse_progress "SYN Stealth Scan Timing: About 45.30% done; ETC: 12:01 (0:00:15 remaining)"
    assert_eq "$SCAN_PHASE" "SYN Stealth Scan"
    assert_eq "$SCAN_PCT" "45.30"
    assert_eq "$SCAN_ETA" "0:00:15"
    assert_ok scan_parse_progress "Service scan Timing: About 50.00% done; ETC: 10:31 (0:00:06 remaining)"
    assert_eq "$SCAN_PHASE" "Service scan"
    assert_fail scan_parse_progress "Discovered open port 22/tcp on 10.0.0.1"
}

test_profiles_from_config() {
    load_urb
    local p; p="$(scan_profiles | tr '\n' ' ')"
    assert_contains "$p" "default"
    assert_contains "$p" "quick"
    scan_profile_args quick
    assert_eq "${SCAN_ARGS[*]}" "-T4 -F --open"
    assert_ok scan_needs_root -sS
    assert_fail scan_needs_root -sV -T4
}

test_profile_with_output_option_rejected() {
    load_urb
    # shellcheck disable=SC2154
    URB_CFG[SCAN_PROFILE_bad]="-sV -oN /tmp/x"
    assert_status 2 scan_profile_args bad
    assert_status 2 scan_profile_args 'x;id'
    assert_status 2 scan_profile_args nonexistent
}

test_scan_cli_validation() {
    local urb="$URB_HOME/bin/urb"
    assert_status 2 "$urb" scan
    assert_status 2 "$urb" scan "-oX"
    assert_status 2 "$urb" scan '10.0.0.1;id'
    assert_status 2 "$urb" scan 10.0.0.1 --profile nope
    assert_status 2 "$urb" scan 10.0.0.1 -p 99999
    assert_status 2 "$urb" scan 10.0.0.1 10.0.0.2
    assert_status 0 "$urb" scan profiles
}

test_scan_localhost_real() {
    command -v nmap >/dev/null || { echo "nmap not installed: skipped"; return 0; }
    local out dir="$HOME/scans"
    out="$("$URB_HOME/bin/urb" --no-color scan 127.0.0.1 --profile quick -o "$dir" 2>&1)"
    local rc=$?
    assert_eq "$rc" 0 "$out"
    assert_contains "$out" "Results saved"
    ls "$dir"/127.0.0.1_quick_*.gnmap >/dev/null 2>&1 || _fail "gnmap not saved"
    ls "$dir"/127.0.0.1_quick_*.xml >/dev/null 2>&1 || _fail "xml not saved"
    ls "$dir"/*.log >/dev/null 2>&1 && _fail "log file should be removed"
    return 0
}

test_scan_inside_lab_uses_lab_dir() {
    command -v nmap >/dev/null || return 0
    "$URB_HOME/bin/urb" ctf new box1 --dir "$HOME/labs" >/dev/null
    ( cd "$HOME/labs/box1/notes" && "$URB_HOME/bin/urb" --no-color scan 127.0.0.1 --profile quick -p 1-100 >/dev/null 2>&1 )
    ls "$HOME"/labs/box1/scans/127.0.0.1_quick_*.nmap >/dev/null 2>&1 || _fail "scan not saved into lab scans/"
}
