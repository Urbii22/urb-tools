#!/usr/bin/env bash
# Pruebas del Findings & Investigation Manager (urb red findings / notes)

_URB() { "$URB_HOME/bin/urb" --no-color "$@"; }
_LAB() { printf '%s/urb-labs/%s' "$HOME" "${1:-box}"; }
_newlab() { _URB red lab new "${1:-box}" --target 10.10.10.3 >/dev/null; }

test_findings_create_ids_list_show() {
    _newlab
    local out
    out="$(_URB red findings add "HTTP puerto 80" --desc "Apache en 80")"
    assert_eq "$?" 0
    assert_contains "$out" "F-001 created"
    assert_contains "$(_URB red findings add "FTP anonymous" --status suspected)" "F-002"
    assert_contains "$(_URB red findings add "SSH configuration")" "F-003"
    out="$(_URB red findings)"
    assert_contains "$out" "URB RED / FINDINGS"
    assert_contains "$out" "F-001    pending        HTTP puerto 80"
    assert_contains "$out" "F-002    suspected      FTP anonymous"
    assert_contains "$out" "3 findings · 2 pending · 1 suspected"
    out="$(_URB red findings show f-1)"
    assert_eq "$?" 0
    assert_contains "$out" "F-001"
    assert_contains "$out" "Apache en 80"
    assert_contains "$out" "created (pending)"
    assert_file "$(_LAB)/findings/F-001.finding"
    assert_eq "$(cat "$(_LAB)/findings/.seq")" "3"
    assert_status 1 _URB red findings show F-099
    assert_status 2 _URB red findings show X-1
}

test_findings_status_transitions_and_aliases() {
    _newlab
    _URB red findings add "Login form" >/dev/null
    assert_status 0 _URB red findings status F-001 investigating
    assert_status 0 _URB red findings status F-001 potential
    assert_contains "$(cat "$(_LAB)/findings/F-001.finding")" "status=suspected"
    assert_status 0 _URB red findings status F-001 completed
    assert_contains "$(cat "$(_LAB)/findings/F-001.finding")" "status=checked"
    assert_contains "$(_URB red findings status F-001 checked)" "already checked"
    assert_status 2 _URB red findings status F-001 vulnerable
    assert_status 2 _URB red findings add "x" --status hacked
    local out; out="$(_URB red findings show F-001)"
    assert_contains "$out" "status pending -> investigating"
    assert_contains "$out" "status investigating -> suspected"
    assert_contains "$out" "status suspected -> checked"
    # Ayuda: diferencia entre comprobado, confirmado y vulnerabilidad
    out="$(_URB red --help)"
    assert_contains "$out" "checked (check done, nothing found)"
    assert_contains "$out" "not necessarily a vulnerability"
}

test_findings_text_cannot_inject_fields() {
    _newlab
    _URB red findings add "Base" >/dev/null
    local f; f="$(_LAB)/findings/F-001.finding"
    local before; before="$(cat "$f")"
    assert_status 2 _URB red findings add "$(printf 'evil\nstatus=confirmed')"
    assert_status 2 _URB red findings note F-001 "$(printf 'x\nevidence=/etc/passwd')"
    assert_status 2 _URB red findings note F-001 "$(printf 'tab\there')"
    assert_status 2 _URB red findings add "   "
    assert_status 2 _URB red findings add "$(printf '%0.sa' {1..130})"
    assert_eq "$(cat "$f")" "$before"
    # Caracteres especiales permitidos sin romper el formato
    assert_status 0 _URB red findings note F-001 'pass=admin | user=x; $(id) `id` ñ ü "quoted"'
    assert_contains "$(_URB red findings show F-001)" 'pass=admin | user=x; $(id) `id` ñ ü "quoted"'
    assert_eq "$(grep -c '^status=' "$f")" "1"
    assert_eq "$(grep -c '^evidence=' "$f")" "0"
    [[ ! -e "$HOME/pwned" ]] || _fail "text was executed"
}

test_findings_evidence_rules() {
    _newlab
    local L; L="$(_LAB)"
    _URB red findings add "Web" >/dev/null
    echo data >"$L/scans/initial.nmap"
    echo data >"$L/evidence/http.txt"
    mkdir -p "$L/evidence/sub"
    # Relativa al directorio actual, relativa al laboratorio y absoluta interna
    ( cd "$L/notes" && _URB red findings evidence F-001 ../scans/initial.nmap >/dev/null ) || _fail "relative to cwd failed"
    assert_status 0 _URB red findings evidence F-001 evidence/http.txt
    # Duplicados (aunque se escriban de otra forma)
    assert_contains "$(_URB red findings evidence F-001 "$L/scans/initial.nmap")" "already linked"
    assert_contains "$(cd "$L" && _URB red findings evidence F-001 ./evidence/../evidence/http.txt)" "already linked"
    assert_eq "$(grep -c '^evidence=' "$L/findings/F-001.finding")" "2"
    # Rechazos
    assert_status 1 _URB red findings evidence F-001 evidence/nope.txt
    assert_status 2 _URB red findings evidence F-001 evidence/sub
    assert_status 2 _URB red findings evidence F-001 /etc/hostname
    assert_status 2 _URB red findings evidence F-001 ../../../../etc/hostname
    echo secret >"$HOME/outside.txt"
    ln -s "$HOME/outside.txt" "$L/evidence/out-link.txt"
    assert_status 2 _URB red findings evidence F-001 evidence/out-link.txt
    ln -s "$HOME" "$L/evidence/dirlink"
    assert_status 2 _URB red findings evidence F-001 evidence/dirlink/outside.txt
    assert_status 2 _URB red findings evidence F-001 .urb-lab
    assert_status 2 _URB red findings evidence F-001 findings/F-001.finding
    # Enlace interno: se guarda la ruta real, relativa al laboratorio
    ln -s "$L/evidence/http.txt" "$L/scans/link-in.txt"
    assert_contains "$(_URB red findings evidence F-001 scans/link-in.txt)" "already linked"
    # Nunca se mueve ni modifica la evidencia
    assert_eq "$(cat "$L/evidence/http.txt")" "data"
    # Evidencia borrada después: se muestra como ausente
    rm "$L/evidence/http.txt"
    assert_contains "$(_URB red findings show F-001)" "evidence/http.txt  (missing)"
}

test_findings_persistence_and_monotonic_ids() {
    _newlab
    local d; d="$(_LAB)/findings"
    _URB red findings add "one" >/dev/null; _URB red findings add "two" >/dev/null; _URB red findings add "three" >/dev/null
    # Borrar el último a mano no reutiliza su ID (.seq es monótono)
    rm "$d/F-003.finding"
    assert_contains "$(_URB red findings add "four")" "F-004"
    # .seq corrupto: se avisa y se recupera desde los existentes sin pisar nada
    echo "garbage" >"$d/.seq"
    local out; out="$(_URB red findings add "five" 2>&1)"
    assert_contains "$out" "damaged"
    assert_contains "$out" "F-005"
    # .seq por debajo del máximo existente: manda el máximo
    echo 1 >"$d/.seq"
    assert_contains "$(_URB red findings add "six")" "F-006"
    # .seq perdido: se recupera del mayor existente
    rm "$d/.seq"
    assert_contains "$(_URB red findings add "seven")" "F-007"
    assert_eq "$(cat "$d/F-001.finding" | grep '^title=')" "title=one"
    # Persistencia entre procesos: cada llamada a urb es un proceso nuevo
    assert_contains "$(_URB red findings list)" "6 findings"
}

test_findings_concurrent_creation_and_updates() {
    _newlab
    local i
    for i in $(seq 1 12); do _URB red findings add "parallel ${i}" >"$HOME/par${i}.out" 2>&1 & done
    wait
    assert_eq "$(find "$(_LAB)/findings" -name 'F-*.finding' | wc -l)" "12" "$(grep -h -v created "$HOME"/par*.out)"
    assert_eq "$(cat "$(_LAB)"/findings/F-*.finding | grep -c '^title=parallel')" "12"
    assert_eq "$(cat "$(_LAB)/findings/.seq")" "12"
    for i in $(seq 1 10); do _URB red findings note F-001 "note ${i}" >/dev/null 2>&1 & done
    wait
    assert_eq "$(grep -c '^note=' "$(_LAB)/findings/F-001.finding")" "10"
    for i in $(seq 1 8); do _URB red notes add "general ${i}" >/dev/null 2>&1 & done
    wait
    assert_eq "$(grep -c 'general ' "$(_LAB)/notes/notes.md")" "8"
    [[ ! -e "$(_LAB)/.urb-lock" && ! -L "$(_LAB)/.urb-lock" ]] || _fail "lock left behind"
    compgen -G "$(_LAB)/findings/.tmp.*" >/dev/null && _fail "temporary files left behind"
    return 0
}

test_findings_abandoned_and_busy_locks() {
    _newlab
    local L; L="$(_LAB)"
    _URB red findings add "base" >/dev/null
    # Bloqueo de un proceso que ya no existe → se libera y la orden funciona
    ln -s "999999 ${HOSTNAME:-localhost} $(date +%s)" "$L/.urb-lock"
    local out; out="$(_URB red findings note F-001 "after stale lock" 2>&1)"
    assert_eq "$?" 0 "$out"
    assert_contains "$out" "abandoned lock"
    # Bloqueo vivo y reciente → espera y falla con un mensaje claro (sin tocar datos)
    sleep 30 & local holder=$!
    ln -s "${holder} ${HOSTNAME:-localhost} $(date +%s)" "$L/.urb-lock"
    local before; before="$(cat "$L/findings/F-001.finding")"
    out="$(_URB red findings note F-001 "blocked" 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "locked by another URB command"
    assert_eq "$(cat "$L/findings/F-001.finding")" "$before"
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
    rm -f "$L/.urb-lock"
    # Un bloqueo de hace más de 120 s también se considera abandonado
    ln -s "1 otherhost $(( $(date +%s) - 500 ))" "$L/.urb-lock"
    assert_status 0 _URB red findings note F-001 "after old lock"
}

test_findings_failed_writes_keep_data() {
    (( EUID != 0 )) || { echo "root: permission failures cannot be simulated, skipped"; return 0; }
    _newlab
    local L; L="$(_LAB)"
    _URB red findings add "base" >/dev/null
    local before notes_before
    before="$(cat "$L/findings/F-001.finding")"
    chmod 555 "$L/findings"
    assert_status 1 _URB red findings note F-001 "cannot write"
    assert_status 1 _URB red findings add "cannot create"
    chmod 755 "$L/findings"
    assert_eq "$(cat "$L/findings/F-001.finding")" "$before"
    assert_eq "$(find "$L/findings" -name 'F-*.finding' | wc -l)" "1"
    [[ ! -L "$L/.urb-lock" ]] || _fail "lock left behind after a failed write"
    notes_before="$(cat "$L/notes/notes.md")"
    chmod 555 "$L/notes"
    assert_status 1 _URB red notes add "cannot write"
    chmod 755 "$L/notes"
    assert_eq "$(cat "$L/notes/notes.md")" "$notes_before"
}

test_findings_corrupt_files_are_shown_not_modified() {
    _newlab
    local d; d="$(_LAB)/findings"
    _URB red findings add "good" >/dev/null
    _URB red findings add "will break" >/dev/null
    printf 'id=F-002\ntitle=will break\nstatus=pending\n<<garbage line>>\n' >"$d/F-002.finding"
    printf 'id=F-777\ntitle=wrong id\nstatus=pending\n' >"$d/F-003.finding"
    printf 'id=F-004\ntitle=weird\nstatus=hacked\n' >"$d/F-004.finding"
    : >"$d/F-005.finding"
    local out
    out="$(_URB red findings list)"
    assert_eq "$?" 0
    assert_contains "$out" "F-001    pending"
    assert_contains "$out" "F-002    damaged"
    assert_contains "$out" "F-003    damaged"
    assert_contains "$out" "F-004    damaged"
    assert_contains "$out" "4 damaged"
    out="$(_URB red findings show F-002 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "damaged"
    local before; before="$(cat "$d/F-002.finding")"
    out="$(_URB red findings status F-002 checked 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "was not modified"
    assert_eq "$(cat "$d/F-002.finding")" "$before"
    # Un hallazgo nuevo no pisa ninguno de los dañados
    assert_contains "$(_URB red findings add "new")" "F-006"
    # Claves futuras desconocidas se conservan al reescribir
    printf 'port=80\nservice=http\n' >>"$d/F-001.finding"
    _URB red findings note F-001 "keep reserved keys" >/dev/null
    assert_contains "$(cat "$d/F-001.finding")" "port=80"
    assert_contains "$(cat "$d/F-001.finding")" "service=http"
}

test_findings_lab_isolation_and_context_priority() {
    _newlab one; _URB red findings add "only in one" >/dev/null
    _newlab two; _URB red findings add "only in two" >/dev/null   # two queda seleccionado
    assert_contains "$(_URB red findings)" "only in two"
    assert_not_contains "$(_URB red findings)" "only in one"
    mkdir -p "$(_LAB one)/notes/deep"
    local out; out="$(cd "$(_LAB one)/notes/deep" && _URB red findings)"
    assert_contains "$out" "only in one"
    assert_not_contains "$out" "only in two"
    ( cd "$(_LAB one)" && _URB red findings add "second in one" >/dev/null )
    assert_contains "$(cat "$(_LAB one)/findings/F-002.finding")" "second in one"
    [[ ! -e "$(_LAB two)/findings/F-002.finding" ]] || _fail "finding created in the wrong lab"
}

test_findings_compat_existing_labs_and_notes() {
    # Laboratorio creado con 'urb ctf' (sin findings/): funciona igual
    _URB ctf new oldlab >/dev/null
    local L; L="$(_LAB oldlab)"
    local orig; orig="$(cat "$L/notes/notes.md")"
    ( cd "$L" && _URB red findings ) | grep -q "No findings yet" || _fail "empty list message missing"
    ( cd "$L" && _URB red findings add "works" >/dev/null ) || _fail "add failed in ctf lab"
    ( cd "$L" && _URB red notes add "appended line" >/dev/null )
    assert_contains "$(cat "$L/notes/notes.md")" "$orig"
    assert_contains "$(cat "$L/notes/notes.md")" "appended line"
    assert_eq "$(grep -c 'appended line' "$L/notes/notes.md")" "1"
    # .urb-lab no cambia
    assert_eq "$(grep -c '=' "$L/.urb-lab")" "3"
    # Laboratorio antiguo sin notes.md: se crea al añadir
    rm "$L/notes/notes.md"
    ( cd "$L" && _URB red notes add "recreated" >/dev/null )
    assert_contains "$(cat "$L/notes/notes.md")" "# Notes — oldlab"
    assert_contains "$(cat "$L/notes/notes.md")" "recreated"
    # Fichero sin salto de línea final: la nota va en su propia línea
    printf 'no newline at end' >"$L/notes/notes.md"
    ( cd "$L" && _URB red notes add "own line" >/dev/null )
    assert_eq "$(tail -n 1 "$L/notes/notes.md" | grep -c 'own line')" "1"
    assert_eq "$(head -n 1 "$L/notes/notes.md")" "no newline at end"
    ( cd "$L" && assert_status 2 _URB red notes add "$(printf 'a\nb')" ) || _fail "newline note accepted"
    assert_contains "$(cd "$L" && _URB red status)" "Findings  1 finding · 1 pending"
}

test_findings_outside_lab_and_arguments() {
    local out
    out="$(_URB red findings 2>&1)"
    assert_eq "$?" 1
    assert_contains "$out" "No lab"
    assert_status 1 _URB red notes
    assert_status 1 _URB red findings add "x"
    _newlab
    assert_status 2 _URB red findings add
    assert_status 2 _URB red findings add "a" "b"
    assert_status 2 _URB red findings add "a" --bogus
    assert_status 2 _URB red findings note F-001
    assert_status 2 _URB red findings frobnicate
    assert_status 2 _URB red notes frobnicate
    assert_status 2 _URB red notes add
}

test_findings_no_color_output() {
    _newlab
    _URB red findings add "colour test" --status confirmed >/dev/null
    local out
    out="$("$URB_HOME/bin/urb" --no-color red findings)"
    [[ "$out" != *$'\e['* ]] || _fail "--no-color output contains escape codes"
    out="$(NO_COLOR=1 "$URB_HOME/bin/urb" red findings show F-001)"
    [[ "$out" != *$'\e['* ]] || _fail "NO_COLOR output contains escape codes"
    out="$("$URB_HOME/bin/urb" --color red findings)"
    [[ "$out" == *$'\e['* ]] || _fail "--color output should contain colours"
}
