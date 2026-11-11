#!/usr/bin/env bash
# Pruebas de lib/utils.sh: validación de entradas y configuración

test_ipv4_valid() {
    load_urb
    assert_ok is_ipv4 10.0.0.1
    assert_ok is_ipv4 255.255.255.255
    assert_ok is_ipv4 0.0.0.0
}

test_ipv4_invalid() {
    load_urb
    assert_fail is_ipv4 256.1.1.1
    assert_fail is_ipv4 1.2.3
    assert_fail is_ipv4 "1.2.3.4 "
    assert_fail is_ipv4 "1.2.3.4;id"
    assert_fail is_ipv4 ""
}

test_cidr_and_range() {
    load_urb
    assert_ok is_cidr4 192.168.56.0/24
    assert_ok is_cidr4 10.0.0.0/8
    assert_fail is_cidr4 10.0.0.0/33
    assert_fail is_cidr4 10.0.0/24
    assert_ok is_ipv4_range 10.0.0.1-20
    assert_fail is_ipv4_range 10.0.0.30-20
}

test_targets_reject_injection() {
    load_urb
    assert_ok is_valid_target 10.10.10.5
    assert_ok is_valid_target scanme.lab
    assert_ok is_valid_target dead:beef::1
    assert_fail is_valid_target "-oX"
    assert_fail is_valid_target "--script=evil"
    assert_fail is_valid_target "10.0.0.1 -oN /tmp/x"
    assert_fail is_valid_target 'host;rm -rf ~'
    assert_fail is_valid_target '$(id)'
    assert_fail is_valid_target 999.1.1.1
    assert_fail is_valid_target ""
}

test_private_ranges() {
    load_urb
    assert_ok is_private_ipv4 10.1.2.3
    assert_ok is_private_ipv4 172.16.0.1
    assert_ok is_private_ipv4 192.168.56.0/24
    assert_fail is_private_ipv4 172.32.0.1
    assert_fail is_private_ipv4 8.8.8.8
}

test_port_spec() {
    load_urb
    assert_ok is_port_spec 22
    assert_ok is_port_spec 22,80,443
    assert_ok is_port_spec 1-65535
    assert_fail is_port_spec 0
    assert_fail is_port_spec 70000
    assert_fail is_port_spec 22,,80
    assert_fail is_port_spec "22;id"
    assert_fail is_port_spec 100-10
}

test_safe_names() {
    load_urb
    assert_ok is_safe_name htb-lame
    assert_ok is_safe_name lab_01.v2
    assert_fail is_safe_name ../etc
    assert_fail is_safe_name .hidden
    assert_fail is_safe_name "a/b"
    assert_fail is_safe_name "a b"
}

test_nmap_tokens() {
    load_urb
    assert_ok is_safe_nmap_token -sV
    assert_ok is_safe_nmap_token --top-ports
    assert_fail is_safe_nmap_token -oN
    assert_fail is_safe_nmap_token -iL
    assert_fail is_safe_nmap_token '$(id)'
}

test_config_parser_no_execution() {
    load_urb
    local f="$HOME/evil.conf"
    printf '%s\n' 'ANIMATIONS="0"' 'EVIL=$(touch '"$HOME"'/pwned)' 'rm -rf /' "LABS_DIR='~/labs'" >"$f"
    URB_CONFIG_FILE="$f" urb_load_config 2>/dev/null
    assert_eq "$(cfg ANIMATIONS)" "0"
    assert_eq "$(cfg LABS_DIR)" "~/labs"
    assert_eq "$(cfg EVIL)" "\$(touch $HOME/pwned)"
    [[ ! -e "$HOME/pwned" ]] || _fail "config value was executed"
    assert_eq "$(urb_expand_path "$(cfg LABS_DIR)")" "$HOME/labs"
}

test_config_set_upsert() {
    load_urb
    export URB_CONFIG_FILE="$HOME/u.conf"
    config_set ANIMATIONS 0
    config_set ANIMATIONS 1
    config_set MENU_ENGINE fzf
    assert_eq "$(grep -c '^ANIMATIONS=' "$HOME/u.conf")" "1"
    urb_load_config
    assert_eq "$(cfg ANIMATIONS)" "1"
    assert_eq "$(cfg MENU_ENGINE)" "fzf"
    assert_status 2 config_set ANIMATIONS 'x;rm'
}
