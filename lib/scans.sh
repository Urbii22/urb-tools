#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/scans.sh — Scan Manager: índice de escaneos de un laboratorio
#
#  Una "ejecución" de nmap = todos los ficheros de scans/ con el mismo nombre
#  base: <base>.nmap .xml .gnmap (.log si nmap falló). Los ficheros originales
#  nunca se mueven ni se copian.
#
#  Índice persistente: <lab>/scans/.index  (DATOS, nunca se ejecuta)
#      S-001|<base>|<epoch>
#  - Solo crece: las líneas existentes no se reescriben ni se renumeran, así
#    que un ID no cambia mientras se conserve el índice, aunque desaparezcan
#    los ficheros de un escaneo (se mostrará como "missing").
#  - Los escaneos nuevos se añaden al consultarlos (o al terminar
#    'urb red recon initial'), ordenados por su hora, con el siguiente número.
#  - Escrituras atómicas bajo el bloqueo del laboratorio (lib/findings.sh).
#  - Si el índice se pierde o se corrompe, se reconstruye desde los ficheros
#    existentes por orden temporal: los IDs nuevos pueden NO coincidir con los
#    originales. Las evidencias de los hallazgos guardan la ruta del fichero,
#    no el ID, así que no se rompen.
#
#  Hora de un escaneo (por fiabilidad): marca temporal del nombre (la pone
#  URB) → atributo start= del XML de nmap → fecha de modificación.
# =============================================================================

[[ -n "${_URB_SCANS_LOADED:-}" ]] && return 0
_URB_SCANS_LOADED=1

SCN_ERR=""

scn_dir()   { printf '%s/scans' "$1"; }
scn_index() { printf '%s/scans/.index' "$1"; }

# Nombres base admitidos (sin barras ni caracteres raros)
_scn_valid_base() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:,+-]{0,200}$ ]]; }

# S-1, s-001, 1 → S-001
scn_normalize_id() {
    local id="${1^^}" n
    id="${id#S-}"
    [[ "$id" =~ ^[0-9]{1,6}$ ]] || return 1
    n=$((10#$id)); (( n >= 1 )) || return 1
    printf 'S-%03d' "$n"
}

# Hora (epoch) de una ejecución
_scn_epoch_of() {
    local dir="$1" base="$2" ts="" e f
    if [[ "$base" =~ _([0-9]{8})-([0-9]{6})(-[0-9]+)?$ ]]; then
        ts="${BASH_REMATCH[1]} ${BASH_REMATCH[2]:0:2}:${BASH_REMATCH[2]:2:2}:${BASH_REMATCH[2]:4:2}"
        e="$(date -d "${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9}" +%s 2>/dev/null)" && is_uint "$e" && { printf '%s' "$e"; return 0; }
    fi
    if [[ -r "${dir}/${base}.xml" ]]; then
        e="$(head -c 4096 -- "${dir}/${base}.xml" | grep -o 'start="[0-9]*"' | head -n 1 | tr -dc '0-9')"
        is_uint "$e" && (( e > 0 )) && { printf '%s' "$e"; return 0; }
    fi
    for f in "${dir}/${base}".{xml,nmap,gnmap,log}; do
        [[ -e "$f" ]] && { stat -c %Y -- "$f" 2>/dev/null; return 0; }
    done
    printf '0'
}

# _scn_read LAB → SCN_IDS[] SCN_BASES[] SCN_EPOCHS[] (líneas válidas del índice)
#                 SCN_BAD (líneas inválidas) SCN_MAX (mayor número usado)
_scn_read() {
    local idx line n b e
    idx="$(scn_index "$1")"
    SCN_IDS=() SCN_BASES=() SCN_EPOCHS=() SCN_BAD=0 SCN_MAX=0
    [[ -r "$idx" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ [[:cntrl:]] ]] || [[ ! "$line" =~ ^S-([0-9]{1,6})\|([^|]+)\|([0-9]{1,12})$ ]]; then
            SCN_BAD=$(( SCN_BAD + 1 )); continue
        fi
        # Guardar las capturas antes de otra comparación (sobrescribe BASH_REMATCH)
        n=$((10#${BASH_REMATCH[1]})); b="${BASH_REMATCH[2]}"; e="${BASH_REMATCH[3]}"
        _scn_valid_base "$b" || { SCN_BAD=$(( SCN_BAD + 1 )); continue; }
        SCN_IDS+=("$(printf 'S-%03d' "$n")"); SCN_BASES+=("$b"); SCN_EPOCHS+=("$e")
        (( n > SCN_MAX )) && SCN_MAX=$n
    done <"$idx"
    return 0
}

# Ejecuciones presentes en scans/ (nombres base únicos)
_scn_discover() {
    local dir f b
    dir="$(scn_dir "$1")"
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/*.nmap "$dir"/*.xml "$dir"/*.gnmap "$dir"/*.log; do
        [[ -f "$f" ]] || continue
        b="${f##*/}"; b="${b%.*}"
        _scn_valid_base "$b" && printf '%s\n' "$b"
    done | sort -u
}

# scn_sync LAB → añade al índice las ejecuciones nuevas (bajo bloqueo, atómico)
scn_sync() {
    local lab="$1" dir idx b e tmp known n
    local -a new=()
    dir="$(scn_dir "$lab")"
    [[ -d "$dir" ]] || return 0
    _scn_read "$lab"
    declare -A known=()
    for b in "${SCN_BASES[@]}"; do known[$b]=1; done
    while IFS= read -r b; do
        [[ -n "${known[$b]:-}" ]] || new+=("$b")
    done < <(_scn_discover "$lab")
    (( ${#new[@]} )) || return 0

    fnd_lock "$lab" || { SCN_ERR="$FND_ERR"; return 1; }
    # Releer con el bloqueo: otro proceso pudo indexar mientras tanto
    _scn_read "$lab"
    known=()
    for b in "${SCN_BASES[@]}"; do known[$b]=1; done
    local -a rows=()
    for b in "${new[@]}"; do
        [[ -n "${known[$b]:-}" ]] && continue
        e="$(_scn_epoch_of "$dir" "$b")"
        rows+=("${e}|${b}")
    done
    if (( ${#rows[@]} == 0 )); then fnd_unlock; return 0; fi
    idx="$(scn_index "$lab")"
    tmp="$(mktemp "${dir}/.tmp.XXXXXX")" || { fnd_unlock; SCN_ERR="cannot write in ${dir}"; return 1; }
    if [[ -f "$idx" ]]; then
        cat -- "$idx" >"$tmp" || { rm -f -- "$tmp"; fnd_unlock; SCN_ERR="cannot read ${idx}"; return 1; }
    fi
    # Asegurar salto de línea final antes de añadir
    [[ -s "$tmp" && -n "$(tail -c 1 -- "$tmp")" ]] && printf '\n' >>"$tmp"
    n=$SCN_MAX
    while IFS='|' read -r e b; do
        n=$(( n + 1 ))
        printf 'S-%03d|%s|%s\n' "$n" "$b" "$e" >>"$tmp"
    done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1n -k2,2)
    if ! mv -f -- "$tmp" "$idx"; then rm -f -- "$tmp"; fnd_unlock; SCN_ERR="could not update ${idx}"; return 1; fi
    fnd_unlock
    return 0
}

# scn_status DIR BASE → complete | incomplete | failed | partial | missing
scn_status() {
    local dir="$1" base="$2" xml="${1}/${2}.xml" tailx
    if [[ ! -e "$xml" && ! -e "${dir}/${base}.nmap" && ! -e "${dir}/${base}.gnmap" && ! -e "${dir}/${base}.log" ]]; then
        printf 'missing'; return 0
    fi
    if [[ -f "$xml" ]]; then
        tailx="$(tail -c 4096 -- "$xml" 2>/dev/null)"
        if [[ "$tailx" == *"<finished"*'exit="success"'* ]]; then
            if [[ -f "${dir}/${base}.nmap" ]]; then printf 'complete'; else printf 'partial'; fi
            return 0
        fi
        if [[ "$tailx" == *"<finished"* ]]; then printf 'failed'; return 0; fi
        if [[ -f "${dir}/${base}.log" ]]; then printf 'failed'; else printf 'incomplete'; fi
        return 0
    fi
    if [[ -f "${dir}/${base}.log" ]]; then printf 'failed'; else printf 'partial'; fi
}

# Objetivo y perfil a partir del nombre base que genera URB (o "unknown")
scn_meta() {
    SCN_TARGET="unknown" SCN_PROFILE="unknown"
    # El perfil puede ser una combinación del Command Engine (quick-versions)
    if [[ "$1" =~ ^(.+)_([A-Za-z0-9]+(-[A-Za-z0-9]+)*)_([0-9]{8}-[0-9]{6})(-[0-9]+)?$ ]]; then
        SCN_TARGET="${BASH_REMATCH[1]}" SCN_PROFILE="${BASH_REMATCH[2]}"
    fi
}

# scn_resolve LAB REF → SCN_ID SCN_BASE SCN_EPOCH  (REF: latest | S-NNN | NNN)
#   latest = escaneo COMPLETO más reciente (los interrumpidos no cuentan)
scn_resolve() {
    local lab="$1" ref="${2:-latest}" i id dir best=-1 be=-1 bn=-1 n st
    SCN_ID="" SCN_BASE="" SCN_EPOCH="" SCN_ERR=""
    scn_sync "$lab" || return 1
    _scn_read "$lab"
    dir="$(scn_dir "$lab")"
    if (( ${#SCN_IDS[@]} == 0 )); then SCN_ERR="no scans in this lab yet (run: urb red recon initial)"; return 1; fi
    if [[ "${ref,,}" == "latest" ]]; then
        for i in "${!SCN_IDS[@]}"; do
            st="$(scn_status "$dir" "${SCN_BASES[i]}")"
            [[ "$st" == "complete" ]] || continue
            n=$((10#${SCN_IDS[i]#S-}))
            if (( SCN_EPOCHS[i] > be || (SCN_EPOCHS[i] == be && n > bn) )); then
                best=$i be=${SCN_EPOCHS[i]} bn=$n
            fi
        done
        (( best >= 0 )) || { SCN_ERR="no complete scan in this lab (incomplete or failed scans are not used for 'latest')"; return 1; }
        SCN_ID="${SCN_IDS[best]}" SCN_BASE="${SCN_BASES[best]}" SCN_EPOCH="${SCN_EPOCHS[best]}"
        return 0
    fi
    id="$(scn_normalize_id "$ref")" || { SCN_ERR="invalid scan reference '${ref}' (use latest or S-001)"; return 2; }
    for i in "${!SCN_IDS[@]}"; do
        if [[ "${SCN_IDS[i]}" == "$id" ]]; then
            SCN_ID="$id" SCN_BASE="${SCN_BASES[i]}" SCN_EPOCH="${SCN_EPOCHS[i]}"
            return 0
        fi
    done
    SCN_ERR="scan ${id} not found in this lab (see: urb red scans)"
    return 1
}

# Sello de la caché de servicios: cambia si cambia el índice o cualquier XML
scn_signature() {
    local lab="$1" dir f
    dir="$(scn_dir "$lab")"
    {
        cat -- "$(scn_index "$lab")" 2>/dev/null
        for f in "$dir"/*.xml; do [[ -f "$f" ]] && stat -c '%n %s %Y' -- "$f"; done
    } | cksum | cut -d' ' -f1
}

# =============================================================================
#  Inventario de servicios (caché derivada; la fuente de verdad son los XML)
#    <lab>/scans/.services   primera línea: "#sig<TAB><sello>"
#  Se reconstruye SOLO al pedirlo ('urb red services' o 'services refresh')
#  y solo si cambió el índice o algún XML. Nunca desde el prompt ni el HUD.
# =============================================================================
SVC_ERR=""

svc_cache() { printf '%s/scans/.services' "$1"; }

svc_python() {
    local p
    if [[ -n "${URB_PYTHON:-}" ]]; then
        [[ -x "$URB_PYTHON" ]] && { printf '%s' "$URB_PYTHON"; return 0; }
        p="$(command -v -- "$URB_PYTHON" 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
        return 1
    fi
    p="$(command -v python3 2>/dev/null)" && [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
    return 1
}

# svc_refresh LAB [forzar] → 0 actualizado | 1 error | 127 falta python3
svc_refresh() {
    local lab="$1" force="${2:-0}" cache sig line py tmp dir i rc
    SVC_ERR="" SVC_REBUILT=0
    scn_sync "$lab" || { SVC_ERR="$SCN_ERR"; return 1; }
    dir="$(scn_dir "$lab")"
    cache="$(svc_cache "$lab")"
    sig="$(scn_signature "$lab")"
    if (( ! force )) && [[ -r "$cache" ]]; then
        IFS= read -r line <"$cache" || line=""
        [[ "$line" == "#sig"$'\t'"$sig" ]] && return 0
    fi
    py="$(svc_python)" || { SVC_ERR="python3 is required to read nmap XML results (sudo apt install python3)"; return 127; }
    _scn_read "$lab"
    fnd_lock "$lab" || { SVC_ERR="$FND_ERR"; return 1; }
    tmp="$(mktemp "${dir}/.tmp.XXXXXX")" || { fnd_unlock; SVC_ERR="cannot write in ${dir}"; return 1; }
    printf '#sig\t%s\n' "$sig" >"$tmp"
    # (el bloque termina en 'true' para que pipefail refleje solo el estado de python)
    {
        for i in "${!SCN_IDS[@]}"; do
            if [[ -f "${dir}/${SCN_BASES[i]}.xml" ]]; then
                printf '%s\t%s\t%s\n' "${SCN_IDS[i]}" "${SCN_EPOCHS[i]}" "${dir}/${SCN_BASES[i]}.xml"
            fi
        done
        true
    } | "$py" -I "${URB_HOME}/lib/nmap_services.py" >>"$tmp"
    rc=$?
    if (( rc != 0 )); then
        rm -f -- "$tmp"; fnd_unlock
        SVC_ERR="the XML parser failed (exit ${rc}); the previous inventory was kept"
        return 1
    fi
    if ! mv -f -- "$tmp" "$cache"; then rm -f -- "$tmp"; fnd_unlock; SVC_ERR="could not write ${cache}"; return 1; fi
    fnd_unlock
    SVC_REBUILT=1
    return 0
}
