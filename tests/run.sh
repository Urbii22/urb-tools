#!/usr/bin/env bash
# =============================================================================
#  tests/run.sh — Runner de pruebas mínimo en Bash puro (sin dependencias)
#  Uso: tests/run.sh [patrón]     p.ej.  tests/run.sh logs
#  Cada tests/test_*.sh define funciones test_*; cada una se ejecuta en una
#  subshell aislada con HOME temporal.
# =============================================================================
set -uo pipefail

TESTS_DIR="$(cd -P -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)"
URB_HOME="$(cd -P -- "${TESTS_DIR}/.." && pwd -P)"
export URB_HOME TESTS_DIR
FIXTURES="${TESTS_DIR}/fixtures"
export FIXTURES

if [[ -t 1 ]]; then G=$'\e[32m' RD=$'\e[31m' Y=$'\e[33m' D=$'\e[90m' Z=$'\e[0m'; else G="" RD="" Y="" D="" Z=""; fi

# --- Aserciones -----------------------------------------------------------------
_URB_TEST_FAILS=0
_fail() { _URB_TEST_FAILS=$(( _URB_TEST_FAILS + 1 )); printf '      %sassert:%s %s\n' "$RD" "$Z" "$*" >&2; return 1; }
assert_eq()       { [[ "$1" == "$2" ]] || _fail "expected [$2] got [$1] ${3:-}"; }
assert_ok()       { "$@" || _fail "command failed: $*"; }
assert_fail()     { if "$@"; then _fail "command should fail: $*"; fi; return 0; }
assert_contains() { [[ "$1" == *"$2"* ]] || _fail "[${1:0:300}] does not contain [$2]"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || _fail "output should not contain [$2]"; }
assert_file()     { [[ -f "$1" ]] || _fail "missing file $1"; }
assert_dir()      { [[ -d "$1" ]] || _fail "missing dir $1"; }
assert_status()   { local exp="$1"; shift; "$@" >/dev/null 2>&1; local rc=$?; [[ "$rc" == "$exp" ]] || _fail "expected exit $exp got $rc: $*"; }
export -f _fail assert_eq assert_ok assert_fail assert_contains assert_not_contains assert_file assert_dir assert_status

# Carga las librerías en el entorno de la prueba
load_urb() {
    # shellcheck source=/dev/null
    source "${URB_HOME}/lib/utils.sh"
    for f in lib/ui.sh lib/system.sh lib/lab.sh lib/diagnose.sh lib/findings.sh modules/ctf.sh modules/scan.sh modules/network.sh \
             modules/monitor.sh modules/logs.sh modules/settings.sh modules/red.sh modules/findings.sh; do
        # shellcheck source=/dev/null
        source "${URB_HOME}/${f}"
    done
    urb_init_colors never
    urb_load_config
    ui_init_theme
}
export -f load_urb

pattern="${1:-}"
pass=0 fail=0 total=0
failed_names=()

for file in "${TESTS_DIR}"/test_*.sh; do
    [[ -n "$pattern" && "$file" != *"$pattern"* ]] && continue
    printf '%s%s%s\n' "$Y" "$(basename -- "$file")" "$Z"
    mapfile -t names < <(bash -c "source '$file' && declare -F" | awk '{print $3}' | grep '^test_')
    for name in "${names[@]}"; do
        total=$(( total + 1 ))
        tmp_home="$(mktemp -d)"
        out="$(
            export HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" XDG_DATA_HOME="$tmp_home/.local/share"
            export LANG=C.UTF-8 LC_ALL=C.UTF-8 NO_COLOR=1
            unset URB_CONFIG_FILE
            cd "$tmp_home" || exit 99
            # shellcheck source=/dev/null
            source "$file"
            _URB_TEST_FAILS=0
            "$name" 2>&1
            (( _URB_TEST_FAILS == 0 ))
        )"
        rc=$?
        rm -rf -- "$tmp_home"
        if (( rc == 0 )); then
            pass=$(( pass + 1 )); printf '  %s✔%s %s\n' "$G" "$Z" "$name"
        else
            fail=$(( fail + 1 )); failed_names+=("$name"); printf '  %s✘ %s%s\n' "$RD" "$name" "$Z"
            printf '%s\n' "$out" | sed "s/^/    ${D}/; s/\$/${Z}/" | tail -n 15
        fi
    done
done

printf '\n%d tests: %s%d passed%s, %s%d failed%s\n' "$total" "$G" "$pass" "$Z" "$RD" "$fail" "$Z"
(( fail == 0 ))
