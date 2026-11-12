#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/lab.sh — Contexto de laboratorio y objetivo (compartido por CTF y RED)
#
#  Datos (nunca se ejecutan, solo se leen línea a línea y se validan):
#   - <lab>/.urb-lab        metadatos del laboratorio: name=, created=, target=
#   - <data>/state/active-lab   SOLO una referencia (ruta) al lab seleccionado
#
#  Prioridad del contexto: un .urb-lab en el directorio actual o en un padre
#  manda sobre la selección global (active-lab).
#  Escrituras atómicas: fichero temporal en el mismo directorio + mv.
#
#  Objetivos: v0.1 guarda un objetivo principal (target=). La API
#  (lab_target_get/lab_target_set) es el único punto de acceso, de modo que
#  más adelante pueda añadirse una lista (p. ej. targets=) sin cambiar a los
#  llamadores.
# =============================================================================

[[ -n "${_URB_LAB_LOADED:-}" ]] && return 0
_URB_LAB_LOADED=1

LAB_MARKER=".urb-lab"
LAB_ROOT="" LAB_SOURCE="" LAB_ERR=""

lab_state_file() { printf '%s/state/active-lab' "${URB_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/urb-tools}"; }

_lab_valid_key()   { [[ "$1" =~ ^[a-z][a-z0-9_]{0,31}$ ]]; }
# Valores: texto de una línea sin caracteres de control ni barras invertidas
_lab_valid_value() { [[ "$1" =~ ^[A-Za-z0-9._:/@%+,\ -]*$ ]] && (( ${#1} <= 255 )); }

# lab_find_root [ruta] → raíz del laboratorio que contiene la ruta (o fallo)
lab_find_root() {
    local d="${1:-$PWD}"
    [[ "$d" == /* ]] || d="${PWD%/}/${d}"
    while [[ -n "$d" ]]; do
        if [[ -f "${d}/${LAB_MARKER}" ]]; then printf '%s' "$d"; return 0; fi
        [[ "$d" == "/" ]] && break
        d="${d%/*}"; [[ -z "$d" ]] && d="/"
    done
    return 1
}

# lab_is_lab DIR → 0 si DIR es la raíz de un laboratorio de URB
lab_is_lab() { [[ -n "${1:-}" && "$1" == /* && -d "$1" && -f "${1}/${LAB_MARKER}" ]]; }

# lab_meta_get DIR CLAVE → valor (solo datos; primera aparición)
lab_meta_get() {
    local dir="$1" key="$2" line
    _lab_valid_key "$key" || return 2
    [[ -r "${dir}/${LAB_MARKER}" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" == "${key}="* ]]; then printf '%s' "${line#"${key}="}"; return 0; fi
    done <"${dir}/${LAB_MARKER}"
    return 1
}

# lab_meta_set DIR CLAVE VALOR → actualiza o añade la clave; conserva el resto
lab_meta_set() {
    local dir="$1" key="$2" val="$3" file tmp
    _lab_valid_key "$key" || { msg_err "Invalid metadata key: ${key}"; return 2; }
    _lab_valid_value "$val" || { msg_err "Invalid metadata value for ${key}"; return 2; }
    file="${dir}/${LAB_MARKER}"
    [[ -f "$file" ]] || { msg_err "Not an URB lab (no ${LAB_MARKER}): ${dir}"; return 1; }
    tmp="$(mktemp "${file}.XXXXXX")" || { msg_err "Cannot write in ${dir}"; return 1; }
    if awk -v k="$key" -v v="$val" '
            BEGIN { done = 0 }
            index($0, k "=") == 1 { if (!done) { print k "=" v; done = 1 }; next }
            { print }
            END { if (!done) print k "=" v }
        ' "$file" >"$tmp"; then
        chmod --reference="$file" "$tmp" 2>/dev/null || chmod 644 "$tmp" 2>/dev/null
        mv -f -- "$tmp" "$file" && return 0
    fi
    rm -f -- "$tmp"
    msg_err "Could not update ${file}"
    return 1
}

lab_name() {
    local n
    n="$(lab_meta_get "$1" name 2>/dev/null)" || n=""
    is_safe_name "$n" || n="${1##*/}"
    printf '%s' "$n"
}

# --- Selección activa (solo una referencia) ------------------------------------------
# Nota: las funciones *_read asignan variables (LAB_ACTIVE, LAB_TARGET, LAB_ERR)
# sin subshell, para que el motivo de un error llegue al llamador. Las *_get
# son atajos que imprimen el valor.

# _lab_active_read → LAB_ACTIVE (ruta validada del lab seleccionado) o LAB_ERR
_lab_active_read() {
    local f path=""
    f="$(lab_state_file)"
    LAB_ACTIVE="" LAB_ERR=""
    [[ -r "$f" ]] || { LAB_ERR="no lab selected"; return 1; }
    IFS= read -r path <"$f" || true
    path="${path%$'\r'}"
    if [[ -z "$path" ]]; then LAB_ERR="no lab selected"; return 1; fi
    if [[ "$path" != /* ]] || ! lab_is_lab "$path"; then
        LAB_ERR="selected lab is no longer valid: ${path}"
        return 1
    fi
    LAB_ACTIVE="$path"
}

lab_active_get() { _lab_active_read && printf '%s' "$LAB_ACTIVE"; }

lab_active_set() {
    local path="$1" f dir tmp
    lab_is_lab "$path" || { msg_err "Not an URB lab: ${path}"; return 1; }
    f="$(lab_state_file)"; dir="${f%/*}"
    mkdir -p -- "$dir" || { msg_err "Cannot create ${dir}"; return 1; }
    tmp="$(mktemp "${f}.XXXXXX")" || { msg_err "Cannot write ${f}"; return 1; }
    printf '%s\n' "$path" >"$tmp" && mv -f -- "$tmp" "$f" && return 0
    rm -f -- "$tmp"; msg_err "Could not save the active lab"; return 1
}

# lab_resolve [dir] → LAB_ROOT y LAB_SOURCE (directory|active); LAB_ERR si no hay
lab_resolve() {
    local root
    LAB_ROOT="" LAB_SOURCE="" LAB_ERR=""
    if root="$(lab_find_root "${1:-$PWD}")"; then
        LAB_ROOT="$root" LAB_SOURCE="directory"; return 0
    fi
    if _lab_active_read; then
        LAB_ROOT="$LAB_ACTIVE" LAB_SOURCE="active"; return 0
    fi
    [[ -z "$LAB_ERR" ]] && LAB_ERR="no lab selected"
    return 1
}

# lab_by_name NOMBRE → ruta del lab dentro de LABS_DIR (validada)
lab_by_name() {
    local name="$1" path
    is_safe_name "$name" || { LAB_ERR="invalid lab name: ${name}"; return 2; }
    path="$(urb_labs_dir)/${name}"
    lab_is_lab "$path" || { LAB_ERR="lab not found: ${name} (in $(urb_labs_dir))"; return 1; }
    printf '%s' "$path"
}

# --- Objetivo principal ------------------------------------------------------------------
# lab_target_read LAB → LAB_TARGET (vacío si no hay); falla con LAB_ERR si el
# valor guardado no es un objetivo válido (p. ej. editado a mano)
lab_target_read() {
    local t
    LAB_TARGET="" LAB_ERR=""
    t="$(lab_meta_get "$1" target 2>/dev/null)" || t=""
    if [[ -n "$t" ]] && ! is_valid_target "$t"; then
        LAB_ERR="stored target in $(lab_name "$1") is not valid: ${t//[^A-Za-z0-9._:\/-]/?}"
        return 1
    fi
    LAB_TARGET="$t"
}

lab_target_get() { lab_target_read "$1" && printf '%s' "$LAB_TARGET"; }

lab_target_set() {
    local lab="$1" target="$2"
    is_valid_target "$target" || { msg_err "Invalid target: '${target}'"; msg_dim "    Expected an IPv4/IPv6 address, CIDR, range or hostname."; return 2; }
    lab_meta_set "$lab" target "$target"
}
