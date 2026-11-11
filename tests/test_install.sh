#!/usr/bin/env bash
# Pruebas del instalador / desinstalador en un HOME temporal

test_install_idempotent_and_safe() {
    local out
    out="$(PATH="/usr/bin:/bin" bash "$URB_HOME/install.sh" --yes --no-deps 2>&1)"
    assert_eq "$?" 0 "$out"
    [[ -L "$HOME/.local/bin/urb" ]] || _fail "launcher symlink missing"
    assert_file "$HOME/.local/lib/urb-tools/.urb-install"
    assert_file "$HOME/.config/urb-tools/urb.conf"
    assert_contains "$out" "NOT in your PATH"
    assert_eq "$("$HOME/.local/bin/urb" version)" "URB-Tools 0.1.0"

    # Config personal: no se sobrescribe en una segunda ejecución
    echo 'ANIMATIONS="0"  # mine' >>"$HOME/.config/urb-tools/urb.conf"
    out="$(PATH="$HOME/.local/bin:/usr/bin:/bin" bash "$URB_HOME/install.sh" --yes --no-deps 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$(cat "$HOME/.config/urb-tools/urb.conf")" "# mine"
    assert_contains "$out" "is in your PATH"

    # No se tocan archivos de shell
    [[ ! -e "$HOME/.bashrc" && ! -e "$HOME/.zshrc" ]] || _fail "shell rc files were created/modified"
}

test_install_refuses_foreign_launcher() {
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/sh\necho mine\n' >"$HOME/.local/bin/urb"
    assert_status 1 bash "$URB_HOME/install.sh" --yes --no-deps
    assert_eq "$(cat "$HOME/.local/bin/urb")" $'#!/bin/sh\necho mine'
}

test_uninstall_keeps_personal_data() {
    bash "$URB_HOME/install.sh" --yes --no-deps >/dev/null 2>&1
    "$HOME/.local/bin/urb" ctf new keepme >/dev/null
    local out
    out="$(bash "$URB_HOME/uninstall.sh" --yes 2>&1)"
    assert_eq "$?" 0 "$out"
    [[ ! -e "$HOME/.local/bin/urb" ]] || _fail "launcher not removed"
    [[ ! -e "$HOME/.local/lib/urb-tools" ]] || _fail "app dir not removed"
    assert_file "$HOME/.config/urb-tools/urb.conf"
    assert_dir "$HOME/urb-labs/keepme"
    # Segunda ejecución: nada que hacer, sin error
    assert_status 0 bash "$URB_HOME/uninstall.sh" --yes
}

test_install_link_mode() {
    assert_status 0 bash "$URB_HOME/install.sh" --yes --no-deps --link
    assert_eq "$(readlink "$HOME/.local/bin/urb")" "$URB_HOME/bin/urb"
}
