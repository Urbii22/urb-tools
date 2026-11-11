#!/usr/bin/env bash
# Pruebas del instalador / desinstalador en un HOME temporal

_APP() { printf '%s' "$HOME/.local/lib/urb-tools"; }
_LNK() { printf '%s' "$HOME/.local/bin/urb"; }

# Copia del código fuente con una marca, para simular una versión nueva
_make_source_copy() {
    local dst="$1" tag="$2"
    mkdir -p "$dst"
    cp -R "$URB_HOME/bin" "$URB_HOME/lib" "$URB_HOME/modules" "$URB_HOME/config" \
          "$URB_HOME/install.sh" "$URB_HOME/uninstall.sh" "$dst/"
    printf '# %s\n' "$tag" >>"$dst/config/default.conf"
}

# No deben quedar copias temporales (.new.* / .old.*) tras terminar
_assert_no_leftovers() {
    local left
    left="$(find "$HOME/.local/lib" -maxdepth 1 \( -name 'urb-tools.new.*' -o -name 'urb-tools.old.*' \) 2>/dev/null)"
    [[ -z "$left" ]] || _fail "temporary install dirs left behind: $left"
}

test_first_install() {
    local out
    out="$(PATH="/usr/bin:/bin" bash "$URB_HOME/install.sh" --yes --no-deps 2>&1)"
    assert_eq "$?" 0 "$out"
    [[ -L "$(_LNK)" ]] || _fail "launcher symlink missing"
    assert_eq "$(readlink "$(_LNK)")" "$(_APP)/bin/urb"
    assert_file "$(_APP)/.urb-install"
    assert_file "$HOME/.config/urb-tools/urb.conf"
    assert_contains "$out" "NOT in your PATH"
    assert_eq "$("$(_LNK)" version)" "URB-Tools 0.1.0"
    _assert_no_leftovers
    [[ ! -e "$HOME/.bashrc" && ! -e "$HOME/.zshrc" ]] || _fail "shell rc files were created/modified"
}

test_reinstall_idempotent_keeps_config() {
    bash "$URB_HOME/install.sh" --yes --no-deps >/dev/null 2>&1
    echo 'ANIMATIONS="0"  # mine' >>"$HOME/.config/urb-tools/urb.conf"
    local before; before="$(cat "$HOME/.config/urb-tools/urb.conf")"
    local out
    out="$(PATH="$HOME/.local/bin:/usr/bin:/bin" bash "$URB_HOME/install.sh" --yes --no-deps 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "is in your PATH"
    assert_eq "$(cat "$HOME/.config/urb-tools/urb.conf")" "$before"
    assert_eq "$(readlink "$(_LNK)")" "$(_APP)/bin/urb"
    assert_eq "$("$(_LNK)" version)" "URB-Tools 0.1.0"
    _assert_no_leftovers
}

test_update_existing_installation() {
    bash "$URB_HOME/install.sh" --yes --no-deps >/dev/null 2>&1
    "$(_LNK)" ctf new keep-lab >/dev/null
    echo 'LOGS_LIMIT="42"' >>"$HOME/.config/urb-tools/urb.conf"
    _make_source_copy "$HOME/src-v2" "URB_TEST_V2"
    local out
    out="$(bash "$HOME/src-v2/install.sh" --yes --no-deps 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "Updating existing installation"
    assert_contains "$(cat "$(_APP)/config/default.conf")" "URB_TEST_V2"
    assert_contains "$(cat "$(_APP)/.urb-install")" "source=$HOME/src-v2"
    assert_contains "$(cat "$HOME/.config/urb-tools/urb.conf")" 'LOGS_LIMIT="42"'
    assert_dir "$HOME/urb-labs/keep-lab"
    assert_eq "$("$(_LNK)" version)" "URB-Tools 0.1.0"
    _assert_no_leftovers
}

test_foreign_file_launcher_untouched() {
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/sh\necho mine\n' >"$(_LNK)"
    assert_status 1 bash "$URB_HOME/install.sh" --yes --no-deps
    assert_eq "$(cat "$(_LNK)")" $'#!/bin/sh\necho mine'
    [[ ! -e "$(_APP)" ]] || _fail "app dir must not be created when the launcher is foreign"
}

test_foreign_symlink_ending_in_bin_urb_untouched() {
    # Otra herramienta cuyo binario también se llama .../bin/urb
    mkdir -p "$HOME/othertool/bin" "$HOME/.local/bin"
    printf '#!/bin/sh\necho other\n' >"$HOME/othertool/bin/urb"; chmod +x "$HOME/othertool/bin/urb"
    ln -s "$HOME/othertool/bin/urb" "$(_LNK)"
    assert_status 1 bash "$URB_HOME/install.sh" --yes --no-deps
    assert_eq "$(readlink "$(_LNK)")" "$HOME/othertool/bin/urb"
    assert_status 1 bash "$URB_HOME/install.sh" --yes --no-deps --link
    assert_eq "$(readlink "$(_LNK)")" "$HOME/othertool/bin/urb"
    # Enlace roto ajeno (destino inexistente fuera de la instalación de URB)
    rm -f "$(_LNK)"; ln -s /opt/not-urb/bin/urb "$(_LNK)"
    assert_status 1 bash "$URB_HOME/install.sh" --yes --no-deps
    assert_eq "$(readlink "$(_LNK)")" "/opt/not-urb/bin/urb"
    [[ ! -e "$(_APP)" ]] || _fail "app dir must not be created when the launcher is foreign"
}

test_link_mode_and_switch_back() {
    bash "$URB_HOME/install.sh" --yes --no-deps >/dev/null 2>&1
    # Instalación normal → modo --link: el enlace es de URB y se sustituye
    assert_status 0 bash "$URB_HOME/install.sh" --yes --no-deps --link
    assert_eq "$(readlink "$(_LNK)")" "$URB_HOME/bin/urb"
    assert_eq "$("$(_LNK)" version)" "URB-Tools 0.1.0"
    # Modo --link → instalación normal: el enlace al código fuente también es de URB
    assert_status 0 bash "$URB_HOME/install.sh" --yes --no-deps
    assert_eq "$(readlink "$(_LNK)")" "$(_APP)/bin/urb"
    _assert_no_leftovers
}

test_broken_new_version_does_not_touch_install() {
    bash "$URB_HOME/install.sh" --yes --no-deps >/dev/null 2>&1
    _make_source_copy "$HOME/src-bad" "URB_TEST_BAD"
    printf 'if then fi {\n' >>"$HOME/src-bad/lib/ui.sh"
    local out
    out="$(bash "$HOME/src-bad/install.sh" --yes --no-deps 2>&1)"
    assert_eq "$?" 1 "$out"
    assert_contains "$out" "Verification failed"
    assert_not_contains "$(cat "$(_APP)/config/default.conf")" "URB_TEST_BAD"
    assert_eq "$("$(_LNK)" version)" "URB-Tools 0.1.0"
    _assert_no_leftovers
}

test_failed_update_rolls_back() {
    (( EUID != 0 )) || { echo "running as root: permission-based failure cannot be simulated, skipped"; return 0; }
    bash "$URB_HOME/install.sh" --yes --no-deps >/dev/null 2>&1
    echo 'MENU_ENGINE="fzf"  # mine' >>"$HOME/.config/urb-tools/urb.conf"
    local cfg_before; cfg_before="$(cat "$HOME/.config/urb-tools/urb.conf")"
    _make_source_copy "$HOME/src-v2" "URB_TEST_V2"
    # Fallo simulado DESPUÉS de sustituir la app: no se puede escribir el lanzador
    chmod 555 "$HOME/.local/bin"
    local out rc
    out="$(bash "$HOME/src-v2/install.sh" --yes --no-deps 2>&1)"; rc=$?
    chmod 755 "$HOME/.local/bin"
    assert_eq "$rc" 1 "$out"
    assert_contains "$out" "restoring the previous state"
    assert_contains "$out" "Previous installation restored"
    # Se ha restaurado la versión anterior, íntegra y funcional
    assert_not_contains "$(cat "$(_APP)/config/default.conf")" "URB_TEST_V2"
    assert_contains "$(cat "$(_APP)/.urb-install")" "source=$URB_HOME"
    assert_eq "$(readlink "$(_LNK)")" "$(_APP)/bin/urb"
    assert_eq "$("$(_LNK)" version)" "URB-Tools 0.1.0"
    assert_eq "$(cat "$HOME/.config/urb-tools/urb.conf")" "$cfg_before"
    _assert_no_leftovers
}

test_failed_first_install_leaves_nothing() {
    (( EUID != 0 )) || { echo "running as root: skipped"; return 0; }
    mkdir -p "$HOME/.local/bin"; chmod 555 "$HOME/.local/bin"
    local out rc
    out="$(bash "$URB_HOME/install.sh" --yes --no-deps 2>&1)"; rc=$?
    chmod 755 "$HOME/.local/bin"
    assert_eq "$rc" 1 "$out"
    [[ ! -e "$(_APP)" ]] || _fail "partial install left in $(_APP)"
    [[ ! -e "$(_LNK)" && ! -L "$(_LNK)" ]] || _fail "launcher left behind"
    _assert_no_leftovers
}

test_uninstall_keeps_personal_data() {
    bash "$URB_HOME/install.sh" --yes --no-deps >/dev/null 2>&1
    "$(_LNK)" ctf new keepme >/dev/null
    local out
    out="$(bash "$URB_HOME/uninstall.sh" --yes 2>&1)"
    assert_eq "$?" 0 "$out"
    [[ ! -e "$(_LNK)" ]] || _fail "launcher not removed"
    [[ ! -e "$(_APP)" ]] || _fail "app dir not removed"
    assert_file "$HOME/.config/urb-tools/urb.conf"
    assert_dir "$HOME/urb-labs/keepme"
    # Segunda ejecución: nada que hacer, sin error
    assert_status 0 bash "$URB_HOME/uninstall.sh" --yes
}

test_uninstall_ignores_foreign_symlink() {
    # Sin URB instalado: un enlace ajeno acabado en /bin/urb no cuenta como instalación
    mkdir -p "$HOME/othertool/bin" "$HOME/.local/bin"
    printf '#!/bin/sh\necho other\n' >"$HOME/othertool/bin/urb"; chmod +x "$HOME/othertool/bin/urb"
    ln -s "$HOME/othertool/bin/urb" "$(_LNK)"
    local out
    out="$(bash "$URB_HOME/uninstall.sh" --yes 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "Nothing to do"
    assert_eq "$(readlink "$(_LNK)")" "$HOME/othertool/bin/urb"
    assert_file "$HOME/othertool/bin/urb"
}

test_uninstall_removes_app_but_keeps_foreign_symlink() {
    bash "$URB_HOME/install.sh" --yes --no-deps >/dev/null 2>&1
    # Otro programa ha reemplazado el lanzador después de instalar URB
    mkdir -p "$HOME/othertool/bin"; printf '#!/bin/sh\n' >"$HOME/othertool/bin/urb"
    ln -sfn "$HOME/othertool/bin/urb" "$(_LNK)"
    local out
    out="$(bash "$URB_HOME/uninstall.sh" --yes 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "not an URB launcher, left untouched"
    assert_eq "$(readlink "$(_LNK)")" "$HOME/othertool/bin/urb"
    [[ ! -e "$(_APP)" ]] || _fail "app dir not removed"
}

test_uninstall_link_mode() {
    assert_status 0 bash "$URB_HOME/install.sh" --yes --no-deps --link
    local out
    out="$(bash "$URB_HOME/uninstall.sh" --yes 2>&1)"
    assert_eq "$?" 0 "$out"
    [[ ! -e "$(_LNK)" && ! -L "$(_LNK)" ]] || _fail "--link launcher not removed"
    assert_file "$URB_HOME/bin/urb"
}
