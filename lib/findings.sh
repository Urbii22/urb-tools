#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/findings.sh — Findings & Investigation Manager (capa de datos)
#
#  Almacenamiento (dentro del laboratorio, sin dependencias ni procesos):
#    <lab>/findings/F-001.finding   un fichero por hallazgo
#    <lab>/findings/.seq            último número asignado (monótono)
#    <lab>/notes/notes.md           notas generales (las de 'urb ctf')
#    <lab>/.urb-lock/               bloqueo de escritura del laboratorio
#
#  Formato de un hallazgo: una línea por campo, "clave=valor" (DATOS: se leen
#  línea a línea y nunca se ejecutan). Claves de un solo valor:
#    id title status created updated desc
#  Claves repetibles (en orden cronológico):
#    note=<YYYY-MM-DD HH:MM:SS>|<texto>       nota del hallazgo
#    log=<YYYY-MM-DD HH:MM:SS>|<evento>       historial (cambios de estado)
#    evidence=<ruta relativa al laboratorio>  referencia a un fichero
#  Reservadas para futuras importaciones (se conservan intactas al reescribir):
#    host port service url source ...
#
#  Integridad del formato:
#   - Ningún valor puede contener caracteres de control (incluidos saltos de
#     línea, CR y tabuladores): se validan antes de escribir, así que un texto
#     no puede crear líneas ni claves falsas. '=' y '|' sí se permiten: la
#     clave termina en el PRIMER '=' y la fecha de note/log tiene longitud fija.
#   - Las líneas que no siguen el formato se conservan tal cual al reescribir,
#     pero el fichero se marca como dañado y no se modifica (no se pierde nada).
# =============================================================================

[[ -n "${_URB_FINDINGS_LOADED:-}" ]] && return 0
_URB_FINDINGS_LOADED=1

FND_STATUSES=(pending investigating suspected confirmed discarded checked)
FND_ERR=""
FND_LOCK_HELD=""

# --- Validación ------------------------------------------------------------------
# fnd_valid_text TEXTO MÁX → sin caracteres de control, no vacío, longitud acotada
fnd_valid_text() {
    local t="$1" max="${2:-200}"
    [[ -n "${t//[[:space:]]/}" ]] || { FND_ERR="text is empty"; return 1; }
    [[ "$t" =~ [[:cntrl:]] ]] && { FND_ERR="text contains control characters (newlines, tabs...)"; return 1; }
    (( ${#t} <= max )) || { FND_ERR="text is too long (max ${max} characters)"; return 1; }
    return 0
}

# Normaliza un estado (acepta los alias potential→suspected, completed→checked)
fnd_status_canonical() {
    local s="${1,,}"
    case "$s" in
        potential) s="suspected" ;;
        completed|done) s="checked" ;;
    esac
    local x; for x in "${FND_STATUSES[@]}"; do [[ "$s" == "$x" ]] && { printf '%s' "$s"; return 0; }; done
    return 1
}

# F-1, f-001, 1 → F-001
fnd_normalize_id() {
    local id="${1^^}" n
    id="${id#F-}"
    [[ "$id" =~ ^[0-9]{1,6}$ ]] || return 1
    n=$((10#$id))
    (( n >= 1 )) || return 1
    printf 'F-%03d' "$n"
}

fnd_dir()  { printf '%s/findings' "$1"; }
fnd_file() { printf '%s/findings/%s.finding' "$1" "$2"; }

# --- Bloqueo del laboratorio --------------------------------------------------------
# El bloqueo es un ENLACE SIMBÓLICO <lab>/.urb-lock cuyo destino es la
# información del dueño ("pid host epoch"). Crear un enlace simbólico es
# atómico e incluye su contenido: nunca existe un bloqueo "a medias" que otro
# proceso pueda confundir con uno abandonado.
# Abandonado = proceso inexistente en este host, o más de 120 s de antigüedad.
fnd_lock() {
    local lab="$1" lock owner pid host ts now tries=0 info
    lock="${lab}/.urb-lock"
    [[ -d "$lab" ]] || { FND_ERR="lab directory not found"; return 1; }
    info="$$ ${HOSTNAME:-localhost} $(printf '%(%s)T' -1)"
    while ! ln -s -- "$info" "$lock" 2>/dev/null; do
        owner="$(readlink -- "$lock" 2>/dev/null)" || owner=""
        if [[ -n "$owner" ]]; then
            IFS=' ' read -r pid host ts <<<"$owner"
            now="$(printf '%(%s)T' -1)"
            if { [[ "$pid" =~ ^[0-9]+$ && "$host" == "${HOSTNAME:-localhost}" ]] && ! kill -0 "$pid" 2>/dev/null; } \
               || { [[ "$ts" =~ ^[0-9]+$ ]] && (( now - ts > 120 )); }; then
                # Se vuelve a comprobar justo antes de borrar: solo ese mismo bloqueo
                if [[ "$(readlink -- "$lock" 2>/dev/null)" == "$owner" ]]; then
                    msg_warn "Removing abandoned lock (owner: process ${pid:-?}, no longer active)." >&2
                    rm -f -- "$lock"
                fi
                continue
            fi
        elif [[ -e "$lock" && ! -L "$lock" ]]; then
            FND_ERR="${lock} exists and is not an URB lock; remove it by hand"
            return 1
        fi
        tries=$(( tries + 1 ))
        if (( tries > 100 )); then
            FND_ERR="the lab is locked by another URB command (${lock}); try again"
            return 1
        fi
        sleep 0.1
    done
    FND_LOCK_HELD="$lock"
    FND_LOCK_INFO="$info"
    # El bloqueo se libera aunque el proceso se interrumpa o termine con error
    trap 'fnd_unlock; exit 130' INT TERM
    trap 'fnd_unlock' EXIT
    return 0
}

fnd_unlock() {
    [[ -n "$FND_LOCK_HELD" ]] || return 0
    # Solo se borra si sigue siendo NUESTRO bloqueo
    [[ "$(readlink -- "$FND_LOCK_HELD" 2>/dev/null)" == "${FND_LOCK_INFO:-}" ]] && rm -f -- "$FND_LOCK_HELD"
    FND_LOCK_HELD="" FND_LOCK_INFO=""
    trap - INT TERM EXIT
    return 0
}

# --- Lectura ---------------------------------------------------------------------------
# fnd_read FICHERO → F_ID F_TITLE F_STATUS F_CREATED F_UPDATED F_DESC
#                    F_NOTES[] F_LOGS[] F_EVIDENCE[] F_LINES[] F_DAMAGED F_PROBLEM
fnd_read() {
    local f="$1" line k v base
    F_ID="" F_TITLE="" F_STATUS="" F_CREATED="" F_UPDATED="" F_DESC=""
    F_NOTES=() F_LOGS=() F_EVIDENCE=() F_SERVICES=() F_LINES=() F_DAMAGED=0 F_PROBLEM=""
    [[ -f "$f" && -r "$f" ]] || { F_DAMAGED=1; F_PROBLEM="unreadable file"; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        F_LINES+=("$line")
        # Primero los caracteres de control (este test sobrescribe BASH_REMATCH)
        if [[ "$line" =~ [[:cntrl:]] ]] || [[ ! "$line" =~ ^([a-z][a-z0-9_]{0,31})=(.*)$ ]]; then
            [[ -n "$line" ]] && { F_DAMAGED=1; F_PROBLEM="invalid line: ${line:0:40}"; }
            continue
        fi
        k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
        case "$k" in
            id)       F_ID="$v" ;;
            title)    F_TITLE="$v" ;;
            status)   F_STATUS="$v" ;;
            created)  F_CREATED="$v" ;;
            updated)  F_UPDATED="$v" ;;
            desc)     F_DESC="$v" ;;
            note)     F_NOTES+=("$v") ;;
            log)      F_LOGS+=("$v") ;;
            evidence) F_EVIDENCE+=("$v") ;;
            service_link) F_SERVICES+=("$v") ;;
            *) : ;;   # claves reservadas/futuras: se conservan en F_LINES
        esac
    done <"$f"
    base="${f##*/}"; base="${base%.finding}"
    if [[ "$F_ID" != "$base" ]]; then F_DAMAGED=1; F_PROBLEM="id does not match file name"
    elif [[ -z "$F_TITLE" ]]; then F_DAMAGED=1; F_PROBLEM="missing title"
    elif ! fnd_status_canonical "$F_STATUS" >/dev/null; then F_DAMAGED=1; F_PROBLEM="unknown status '${F_STATUS}'"
    fi
    (( F_DAMAGED )) && return 1
    return 0
}

# Lista de ficheros de hallazgos ordenada por número
fnd_files() {
    local d f
    d="$(fnd_dir "$1")"
    [[ -d "$d" ]] || return 0
    for f in "$d"/F-*.finding; do
        [[ -e "$f" ]] || continue
        [[ "${f##*/}" =~ ^F-([0-9]+)\.finding$ ]] && printf '%d\t%s\n' "$((10#${BASH_REMATCH[1]}))" "$f"
    done | sort -n | cut -f2-
}

# --- Escritura -------------------------------------------------------------------------
# _fnd_write FICHERO líneas... → reescritura atómica (temporal + mv)
_fnd_write() {
    local f="$1" tmp; shift
    tmp="$(mktemp "${f%/*}/.tmp.XXXXXX")" || { FND_ERR="cannot write in ${f%/*}"; return 1; }
    if printf '%s\n' "$@" >"$tmp" && mv -f -- "$tmp" "$f"; then return 0; fi
    rm -f -- "$tmp"; FND_ERR="could not write ${f}"; return 1
}

# Siguiente número: max(.seq, mayor ID existente) + 1. Se llama con el bloqueo.
_fnd_next_number() {
    local lab="$1" seq=0 max=0 f n d
    d="$(fnd_dir "$lab")"
    if [[ -f "${d}/.seq" ]]; then
        IFS= read -r seq <"${d}/.seq" || seq=""
        if [[ ! "$seq" =~ ^[0-9]{1,9}$ ]]; then
            msg_warn "findings/.seq was damaged; recovering the counter from existing findings." >&2
            seq=0
        fi
        seq=$((10#$seq))
    fi
    while IFS= read -r f; do
        [[ "${f##*/}" =~ ^F-([0-9]+)\.finding$ ]] && { n=$((10#${BASH_REMATCH[1]})); (( n > max )) && max=$n; }
    done < <(fnd_files "$lab")
    (( max > seq )) && seq=$max
    printf '%d' $(( seq + 1 ))
}

# fnd_create LAB TÍTULO [DESC] [ESTADO] → FND_NEW_ID
fnd_create() {
    local lab="$1" title="$2" desc="${3:-}" status="${4:-pending}" d n id f tmp now
    fnd_valid_text "$title" 120 || { FND_ERR="title: ${FND_ERR}"; return 2; }
    if [[ -n "$desc" ]]; then fnd_valid_text "$desc" 1000 || { FND_ERR="description: ${FND_ERR}"; return 2; }; fi
    status="$(fnd_status_canonical "$status")" || { FND_ERR="invalid status"; return 2; }
    d="$(fnd_dir "$lab")"
    mkdir -p -- "$d" || { FND_ERR="cannot create ${d}"; return 1; }
    fnd_lock "$lab" || return 1
    now="$(urb_now)"
    n="$(_fnd_next_number "$lab")"
    while :; do
        id="$(printf 'F-%03d' "$n")"; f="$(fnd_file "$lab" "$id")"
        [[ -e "$f" ]] || break
        n=$(( n + 1 ))
    done
    tmp="$(mktemp "${d}/.tmp.XXXXXX")" || { fnd_unlock; FND_ERR="cannot write in ${d}"; return 1; }
    {
        printf 'id=%s\ntitle=%s\nstatus=%s\ncreated=%s\nupdated=%s\n' "$id" "$title" "$status" "$now" "$now"
        [[ -n "$desc" ]] && printf 'desc=%s\n' "$desc"
        printf 'log=%s|created (%s)\n' "$now" "$status"
    } >"$tmp" || { rm -f -- "$tmp"; fnd_unlock; FND_ERR="could not write the finding"; return 1; }
    # ln falla si el destino existe: nunca se sobrescribe un hallazgo
    if ! ln -- "$tmp" "$f" 2>/dev/null; then
        rm -f -- "$tmp"; fnd_unlock; FND_ERR="${id} already exists; nothing was overwritten"; return 1
    fi
    rm -f -- "$tmp"
    local seqtmp
    seqtmp="$(mktemp "${d}/.tmp.XXXXXX")" && printf '%d\n' "$n" >"$seqtmp" && mv -f -- "$seqtmp" "${d}/.seq" \
        || { rm -f -- "${seqtmp:-}"; msg_warn "Could not update findings/.seq (the finding was saved)." >&2; }
    fnd_unlock
    FND_NEW_ID="$id"
    return 0
}

# _fnd_modify LAB ID OPERACIÓN VALOR → actualiza con bloqueo; nunca toca ficheros dañados
#   OPERACIÓN: status | note | evidence
_fnd_modify() {
    local lab="$1" id="$2" op="$3" val="$4" f now line out=() old
    f="$(fnd_file "$lab" "$id")"
    [[ -f "$f" ]] || { FND_ERR="finding ${id} not found"; return 1; }
    fnd_lock "$lab" || return 1
    if ! fnd_read "$f"; then
        fnd_unlock; FND_ERR="${id} is damaged (${F_PROBLEM}); it was not modified. Fix the file by hand: ${f}"
        return 1
    fi
    now="$(urb_now)"
    case "$op" in
        status)
            old="$(fnd_status_canonical "$F_STATUS")"
            if [[ "$old" == "$val" ]]; then fnd_unlock; FND_ERR="${id} is already ${val}"; return 3; fi
            for line in "${F_LINES[@]}"; do
                case "$line" in
                    status=*)  out+=("status=${val}") ;;
                    updated=*) out+=("updated=${now}") ;;
                    *)         out+=("$line") ;;
                esac
            done
            out+=("log=${now}|status ${old} -> ${val}") ;;
        link|unlink)
            local found=0 item
            for item in "${F_SERVICES[@]}"; do [[ "$item" == "$val" ]] && found=1; done
            if [[ "$op" == link && $found == 1 ]]; then fnd_unlock; FND_ERR="service already linked to ${id}"; return 3; fi
            if [[ "$op" == unlink && $found == 0 ]]; then fnd_unlock; FND_ERR="service is not linked to ${id}"; return 1; fi
            for line in "${F_LINES[@]}"; do
                [[ "$op" == unlink && "$line" == "service_link=$val" ]] && continue
                if [[ "$line" == updated=* ]]; then out+=("updated=${now}"); else out+=("$line"); fi
            done
            [[ "$op" == link ]] && out+=("service_link=${val}")
            out+=("log=${now}|service ${op}: ${val}") ;;
        note|evidence)
            if [[ "$op" == "evidence" ]]; then
                local e; for e in "${F_EVIDENCE[@]}"; do
                    [[ "$e" == "$val" ]] && { fnd_unlock; FND_ERR="${val} is already linked to ${id}"; return 3; }
                done
            fi
            for line in "${F_LINES[@]}"; do
                if [[ "$line" == updated=* ]]; then out+=("updated=${now}"); else out+=("$line"); fi
            done
            if [[ "$op" == "note" ]]; then out+=("note=${now}|${val}")
            else out+=("evidence=${val}"); fi ;;
        *) fnd_unlock; FND_ERR="internal: unknown operation"; return 1 ;;
    esac
    _fnd_write "$f" "${out[@]}" || { fnd_unlock; return 1; }
    fnd_unlock
    return 0
}

fnd_set_status() {
    local s
    s="$(fnd_status_canonical "$3")" || { FND_ERR="invalid status '${3}' (valid: ${FND_STATUSES[*]})"; return 2; }
    _fnd_modify "$1" "$2" status "$s"
}

fnd_add_note() {
    fnd_valid_text "$3" 1000 || { FND_ERR="note: ${FND_ERR}"; return 2; }
    _fnd_modify "$1" "$2" note "$3"
}

# fnd_resolve_evidence LAB RUTA → FND_EVIDENCE_REL (ruta verificada, relativa al lab)
# Reglas: debe existir, ser un fichero normal y su ruta REAL (enlaces resueltos)
# quedar dentro del laboratorio. Relativa: primero al directorio actual, después
# a la raíz del laboratorio. Nunca se lee, copia ni mueve el fichero.
fnd_resolve_evidence() {
    local lab="$1" p="$2" cand="" real labreal rel
    FND_EVIDENCE_REL=""
    [[ -n "$p" ]] || { FND_ERR="missing file path"; return 2; }
    [[ "$p" =~ [[:cntrl:]] ]] && { FND_ERR="the path contains control characters"; return 2; }
    if [[ "$p" == /* ]]; then cand="$p"
    elif [[ -e "${PWD%/}/${p}" ]]; then cand="${PWD%/}/${p}"
    else cand="${lab%/}/${p}"
    fi
    [[ -e "$cand" ]] || { FND_ERR="file not found: ${p}"; return 1; }
    real="$(readlink -f -- "$cand")" || { FND_ERR="cannot resolve ${p}"; return 1; }
    labreal="$(readlink -f -- "$lab")" || { FND_ERR="cannot resolve the lab path"; return 1; }
    [[ -f "$real" ]] || { FND_ERR="not a regular file: ${p}"; return 2; }
    if [[ "$real" != "${labreal}/"* ]]; then
        # Incluye enlaces simbólicos (o directorios enlazados) que apuntan fuera
        FND_ERR="${p} is outside the lab (real path: ${real}); copy it into ${labreal}/evidence/ first"
        return 2
    fi
    rel="${real#"${labreal}/"}"
    case "$rel" in
        .urb-lab|.urb-lock/*|findings/*) FND_ERR="URB metadata cannot be used as evidence"; return 2 ;;
    esac
    (( ${#rel} <= 512 )) || { FND_ERR="path too long"; return 2; }
    FND_EVIDENCE_REL="$rel"
    return 0
}

fnd_add_evidence() {
    fnd_resolve_evidence "$1" "$3" || return $?
    _fnd_modify "$1" "$2" evidence "$FND_EVIDENCE_REL"
}

# fnd_counts LAB → FND_TOTAL FND_DAMAGED_N y FND_COUNT[estado]
fnd_counts() {
    local lab="$1" f s
    declare -gA FND_COUNT=()
    FND_TOTAL=0 FND_DAMAGED_N=0
    for s in "${FND_STATUSES[@]}"; do FND_COUNT[$s]=0; done
    while IFS= read -r f; do
        FND_TOTAL=$(( FND_TOTAL + 1 ))
        if fnd_read "$f"; then
            s="$(fnd_status_canonical "$F_STATUS")"
            FND_COUNT[$s]=$(( ${FND_COUNT[$s]} + 1 ))
        else
            FND_DAMAGED_N=$(( FND_DAMAGED_N + 1 ))
        fi
    done < <(fnd_files "$lab")
    return 0
}

# --- Notas generales (notes/notes.md) ---------------------------------------------------
fnd_notes_file() { printf '%s/notes/notes.md' "$1"; }

fnd_notes_ensure() {
    local lab="$1" f
    f="$(fnd_notes_file "$lab")"
    [[ -f "$f" ]] && return 0
    mkdir -p -- "${f%/*}" || { FND_ERR="cannot create ${f%/*}"; return 1; }
    printf '# Notes — %s\n\n' "$(lab_name "$lab")" >"$f" || { FND_ERR="cannot create ${f}"; return 1; }
}

# fnd_notes_add LAB TEXTO → añade "- fecha  texto" sin perder el contenido existente
fnd_notes_add() {
    local lab="$1" text="$2" f tmp
    fnd_valid_text "$text" 1000 || { FND_ERR="note: ${FND_ERR}"; return 2; }
    fnd_notes_ensure "$lab" || return 1
    f="$(fnd_notes_file "$lab")"
    fnd_lock "$lab" || return 1
    tmp="$(mktemp "${f%/*}/.tmp.XXXXXX")" || { fnd_unlock; FND_ERR="cannot write in ${f%/*}"; return 1; }
    # Copia íntegra + nueva línea; si el fichero no acaba en salto de línea, se añade uno
    if cat -- "$f" >"$tmp" \
       && { [[ ! -s "$f" || -z "$(tail -c 1 -- "$f")" ]] || printf '\n' >>"$tmp"; } \
       && printf -- '- %s  %s\n' "$(urb_now)" "$text" >>"$tmp"; then
        chmod --reference="$f" "$tmp" 2>/dev/null || true
        if mv -f -- "$tmp" "$f"; then fnd_unlock; return 0; fi
    fi
    rm -f -- "$tmp"; fnd_unlock; FND_ERR="could not write ${f}"; return 1
}
