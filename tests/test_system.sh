#!/usr/bin/env bash
# Pruebas de lib/system.sh y lib/ui.sh con datos de ejemplo y del sistema real

test_meminfo_parse() {
    load_urb
    sys_mem_read "$FIXTURES/meminfo"
    assert_eq "$MEM_TOTAL_KB" 4000000
    assert_eq "$MEM_USED_KB" 3000000
    assert_eq "$MEM_PCT" 75
    assert_eq "$SWAP_PCT" 25
}

test_meminfo_without_available() {
    load_urb
    sys_mem_read "$FIXTURES/meminfo_old"
    assert_eq "$MEM_AVAIL_KB" 500
    assert_eq "$MEM_PCT" 50
}

test_cpu_delta() {
    load_urb
    local -A t1 i1 t2 i2
    sys_cpu_read t1 i1 "$FIXTURES/stat1"
    sys_cpu_read t2 i2 "$FIXTURES/stat2"
    assert_eq "$(cpu_pct "${t1[cpu]}" "${i1[cpu]}" "${t2[cpu]}" "${i2[cpu]}")" 50
    assert_eq "$(cpu_pct "${t1[cpu0]}" "${i1[cpu0]}" "${t2[cpu0]}" "${i2[cpu0]}")" 100
    assert_eq "$(cpu_pct "${t1[cpu1]}" "${i1[cpu1]}" "${t2[cpu1]}" "${i2[cpu1]}")" 0
    assert_eq "$(cpu_pct 10 5 10 5)" 0
}

test_format_helpers() {
    load_urb
    assert_eq "$(fmt_kb 512)" "512K"
    assert_eq "$(fmt_kb 1536)" "1.5M"
    assert_eq "$(fmt_kb 4000000)" "3.8G"
    assert_eq "$(fmt_duration 59)" "0m"
    assert_eq "$(fmt_duration 3700)" "1h 1m"
    assert_eq "$(fmt_duration 90061)" "1d 1h 1m"
}

test_os_release() {
    load_urb
    assert_eq "$(sys_os "$FIXTURES/os-release")" "Kali GNU/Linux Rolling"
    assert_eq "$(sys_os_id "$FIXTURES/os-release")" "kali"
}

test_ip_br_and_vpn() {
    load_urb
    local out
    out="$(sys_parse_ip_br <"$FIXTURES/ip-br.txt")"
    assert_contains "$out" "eth0|UP|10.0.2.15/24|fe80::a00:27ff:fe4e:66a1/64"
    assert_contains "$out" "veth1|UP||"
    sys_parse_ip_br <"$FIXTURES/ip-br.txt" >"$HOME/parsed"
    assert_eq "$(sys_vpn_detect "$HOME/parsed")" "tun0 10.10.14.7/23"
}

test_real_system_values() {
    load_urb
    sys_mem_read
    (( MEM_TOTAL_KB > 0 )) || _fail "MemTotal should be > 0 on a real system"
    sys_disk_read /
    (( DISK_TOTAL_KB > 0 )) || _fail "disk total should be > 0"
    local cpu; cpu="$(sys_cpu_usage_once 0.2)"
    is_uint "$cpu" || _fail "cpu usage not numeric: $cpu"
    [[ -n "$(sys_uptime)" ]] || _fail "uptime empty"
    [[ "$(sys_local_ip)" != "" ]] || _fail "local ip empty"
}

test_ui_fit_and_bar() {
    load_urb
    local s
    ui_fit s "hello" 8;      assert_eq "$s" "hello   "
    ui_fit s "hello world" 5; assert_eq "${#s}" 5
    ui_bar s 50 10
    assert_eq "$s" "█████░░░░░"
    ui_bar s 150 4
    assert_eq "$s" "████"
}

test_net_cidr_network() {
    load_urb
    assert_eq "$(net_cidr_network 10.0.2.15/24)" "10.0.2.0/24"
    assert_eq "$(net_cidr_network 172.20.31.200/20)" "172.20.16.0/20"
    assert_eq "$(net_cidr_network 192.168.1.77/32)" "192.168.1.77/32"
}
