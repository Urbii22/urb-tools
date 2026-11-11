#!/usr/bin/env bash
# Pruebas del módulo CTF

test_ctf_create_structure() {
    local urb="$URB_HOME/bin/urb" d="$HOME/labs/htb-lame"
    assert_status 0 "$urb" ctf new htb-lame --dir "$HOME/labs" --target 10.10.10.3
    assert_dir "$d/scans"; assert_dir "$d/exploits"; assert_dir "$d/evidence"; assert_dir "$d/notes"
    assert_file "$d/report.md"; assert_file "$d/.urb-lab"
    assert_contains "$(cat "$d/report.md")" "10.10.10.3"
}

test_ctf_idempotent_keeps_report() {
    local urb="$URB_HOME/bin/urb" d="$HOME/labs/box"
    "$urb" ctf new box --dir "$HOME/labs" >/dev/null
    echo "MY NOTES" >>"$d/report.md"
    rmdir "$d/exploits"
    assert_status 0 "$urb" ctf new box --dir "$HOME/labs"
    assert_contains "$(cat "$d/report.md")" "MY NOTES"
    assert_dir "$d/exploits"
}

test_ctf_rejects_bad_names_and_foreign_dirs() {
    local urb="$URB_HOME/bin/urb"
    assert_status 2 "$urb" ctf new ../evil --dir "$HOME/labs"
    assert_status 2 "$urb" ctf new "a b" --dir "$HOME/labs"
    assert_status 2 "$urb" ctf new
    mkdir -p "$HOME/labs/existing"; echo x >"$HOME/labs/existing/file"
    assert_status 1 "$urb" ctf new existing --dir "$HOME/labs"
}

test_ctf_list_and_path() {
    local urb="$URB_HOME/bin/urb"
    "$urb" ctf new one --dir "$HOME/labs" >/dev/null
    assert_contains "$("$urb" --no-color ctf list --dir "$HOME/labs")" "one"
    assert_eq "$("$urb" ctf path one --dir "$HOME/labs")" "$HOME/labs/one"
    assert_status 1 "$urb" ctf path missing --dir "$HOME/labs"
}

test_ctf_default_dir_from_config() {
    local urb="$URB_HOME/bin/urb"
    "$urb" ctf new deflab >/dev/null
    assert_dir "$HOME/urb-labs/deflab/scans"
}
