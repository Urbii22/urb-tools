#!/usr/bin/env bash
# Pruebas de la CLI principal y de los subcomandos no interactivos

test_version_and_help() {
    local urb="$URB_HOME/bin/urb"
    assert_eq "$("$urb" version)" "URB-Tools 0.1.0"
    assert_eq "$("$urb" --version)" "URB-Tools 0.1.0"
    assert_contains "$("$urb" --no-color help)" "USAGE"
    assert_contains "$("$urb" --no-color help scan)" "urb scan"
    assert_contains "$("$urb" --no-color help logs)" "--since"
}

test_unknown_commands() {
    local urb="$URB_HOME/bin/urb"
    assert_status 2 "$urb" frobnicate
    assert_status 2 "$urb" --bogus
    assert_status 2 "$urb" network bogus
    assert_status 2 "$urb" monitor --bogus
    assert_status 2 "$urb" config bogus
}

test_dashboard_requires_tty() {
    local out
    out="$("$URB_HOME/bin/urb" --no-color </dev/null 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "interactive terminal"
}

test_network_subcommands() {
    local urb="$URB_HOME/bin/urb" out
    out="$("$urb" --no-color network)"
    assert_contains "$out" "NETWORK SUMMARY"
    assert_contains "$out" "Local IP"
    assert_contains "$("$urb" --no-color network interfaces)" "lo"
    assert_status 0 "$urb" network routes
    assert_status 0 "$urb" network connections --listen
    assert_status 2 "$urb" network discover 8.8.8.0/24
    assert_status 2 "$urb" network discover 10.0.0.0/8
    assert_status 2 "$urb" network discover 'x;id'
    assert_status 2 "$urb" network ping '-c'
}

test_monitor_once() {
    local out
    out="$("$URB_HOME/bin/urb" --no-color monitor --once)"
    assert_contains "$out" "CPU"
    assert_contains "$out" "RAM"
    assert_contains "$out" "TOP PROCESSES"
    assert_contains "$("$URB_HOME/bin/urb" --no-color monitor procs -n 3)" "PID"
}

test_config_commands() {
    local urb="$URB_HOME/bin/urb"
    assert_status 0 "$urb" config init
    assert_file "$HOME/.config/urb-tools/urb.conf"
    echo 'ANIMATIONS="0"' >>"$HOME/.config/urb-tools/urb.conf"
    assert_status 0 "$urb" config init
    assert_contains "$(cat "$HOME/.config/urb-tools/urb.conf")" 'ANIMATIONS="0"'
    assert_status 0 "$urb" config set REFRESH_INTERVAL 3
    assert_contains "$("$urb" --no-color config show)" "REFRESH_INTERVAL"
    assert_status 2 "$urb" config set 'bad key' 1
}

test_modules_run_standalone() {
    assert_contains "$(bash "$URB_HOME/modules/network.sh" routes 2>&1)" "ROUTES"
    assert_contains "$(bash "$URB_HOME/modules/ctf.sh" help 2>&1)" "urb ctf"
    assert_contains "$(bash "$URB_HOME/modules/monitor.sh" --once 2>&1)" "RAM"
    assert_contains "$(bash "$URB_HOME/modules/logs.sh" summary --file "$FIXTURES/auth.log" 2>&1)" "AUTH SUMMARY"
    assert_contains "$(bash "$URB_HOME/modules/scan.sh" profiles 2>&1)" "quick"
}

test_symlinked_launcher_resolves_home() {
    mkdir -p "$HOME/bin"
    ln -s "$URB_HOME/bin/urb" "$HOME/bin/urb"
    assert_eq "$("$HOME/bin/urb" version)" "URB-Tools 0.1.0"
}

test_manual_atajos_opens_the_shortcuts_guide() {
    local out
    out="$("$URB_HOME/bin/urb" --no-color manual atajos)"
    assert_eq "$out" "$URB_HOME/docs/ATAJOS.md"
    assert_contains "$(cat "$out")" "Ctrl+B s"
    assert_contains "$("$URB_HOME/bin/urb" --no-color manual path)" "docs/ATAJOS.md"
    assert_contains "$("$URB_HOME/bin/urb" --no-color manual --help)" "urb manual atajos"
}
