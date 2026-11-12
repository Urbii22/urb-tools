#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  lib/engine.sh — URB Command Engine v0.1
#
#  Cada comando gestionado por el motor se describe en commands/<nombre>.spec
#  (DATOS clave=valor: se leen línea a línea y se validan; nunca se ejecutan):
#
#    name=red recon                          nombre del comando
#    summary=...                             descripción de una línea
#    usage=...                               sintaxis
#    requires=nmap                           herramientas necesarias (informativo)
#    group=<grupo>|<explicación>             grupo de modificadores excluyentes
#    modifier=<nombre>|<grupo>|<flags>|<descripción>
#             flags: root (necesita privilegios) o vacío
#    option=<nombre>|<tipo>|<defecto>|<clave de config>|<descripción>
#             tipos: flag target port ip dir
#    note=<texto>   example=<texto>
#
#  Reglas del análisis (eng_parse):
#   - Los modificadores (palabras sin "--") pueden ir en cualquier orden; se
#     normalizan al orden del .spec, así "quick versions" = "versions quick".
#   - Modificador desconocido, repetido o dos del mismo grupo → error (código 2).
#   - Las opciones con valor usan siempre "--opción valor" (inequívoco).
#   - Precedencia de valores: explícito > configuración del usuario > defecto.
#
#  Cada comando aporta su propio manejador (cómo construir y ejecutar); el motor
#  solo analiza, valida y documenta. Añadir una herramienta = un .spec + un
#  manejador, sin tocar este fichero.
# =============================================================================

[[ -n "${_URB_ENGINE_LOADED:-}" ]] && return 0
_URB_ENGINE_LOADED=1

ENG_ERR=""

eng_spec_file() { printf '%s/commands/%s.spec' "$URB_HOME" "$1"; }

# eng_load NOMBRE → ENG_NAME ENG_SUMMARY ENG_USAGE ENG_REQUIRES
#   ENG_MODS[] ENG_MOD_GROUP[n] ENG_MOD_FLAGS[n] ENG_MOD_DESC[n] ENG_GROUP_DESC[g]
#   ENG_OPTS[] ENG_OPT_TYPE[n] ENG_OPT_DEFAULT[n] ENG_OPT_CFG[n] ENG_OPT_DESC[n]
#   ENG_NOTES[] ENG_EXAMPLES[]
eng_load() {
    local id="$1" f line k v n g fl d t def ck
    [[ "$id" =~ ^[a-z][a-z0-9-]{0,40}$ ]] || { ENG_ERR="invalid command spec name"; return 2; }
    f="$(eng_spec_file "$id")"
    [[ -r "$f" ]] || { ENG_ERR="command spec not found: ${f}"; return 2; }
    ENG_NAME="" ENG_SUMMARY="" ENG_USAGE="" ENG_REQUIRES=""
    ENG_MODS=() ENG_OPTS=() ENG_NOTES=() ENG_EXAMPLES=()
    declare -gA ENG_MOD_GROUP=() ENG_MOD_FLAGS=() ENG_MOD_DESC=() ENG_GROUP_DESC=()
    declare -gA ENG_OPT_TYPE=() ENG_OPT_DEFAULT=() ENG_OPT_CFG=() ENG_OPT_DESC=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ "$line" =~ [[:cntrl:]] ]] || [[ ! "$line" =~ ^([a-z]+)=(.*)$ ]]; then
            ENG_ERR="invalid line in ${f}: ${line:0:40}"; return 2
        fi
        k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
        case "$k" in
            name)     ENG_NAME="$v" ;;
            summary)  ENG_SUMMARY="$v" ;;
            usage)    ENG_USAGE="$v" ;;
            requires) ENG_REQUIRES="$v" ;;
            note)     ENG_NOTES+=("$v") ;;
            example)  ENG_EXAMPLES+=("$v") ;;
            group)
                IFS='|' read -r g d <<<"$v"
                [[ "$g" =~ ^[a-z]{1,20}$ ]] || { ENG_ERR="invalid group in ${f}"; return 2; }
                ENG_GROUP_DESC[$g]="$d" ;;
            modifier)
                IFS='|' read -r n g fl d <<<"$v"
                [[ "$n" =~ ^[a-z][a-z0-9]{0,20}$ ]] || { ENG_ERR="invalid modifier name in ${f}: ${n}"; return 2; }
                [[ -z "$g" || "$g" =~ ^[a-z]{1,20}$ ]] || { ENG_ERR="invalid group for ${n} in ${f}"; return 2; }
                [[ -z "$fl" || "$fl" == "root" ]] || { ENG_ERR="invalid flags for ${n} in ${f}"; return 2; }
                ENG_MODS+=("$n"); ENG_MOD_GROUP[$n]="$g"; ENG_MOD_FLAGS[$n]="$fl"; ENG_MOD_DESC[$n]="$d" ;;
            option)
                IFS='|' read -r n t def ck d <<<"$v"
                [[ "$n" =~ ^[a-z][a-z0-9-]{0,20}$ ]] || { ENG_ERR="invalid option name in ${f}: ${n}"; return 2; }
                [[ "$t" =~ ^(flag|target|port|ip|dir)$ ]] || { ENG_ERR="invalid type for --${n} in ${f}"; return 2; }
                [[ -z "$ck" || "$ck" =~ ^[A-Z][A-Z0-9_]{0,40}$ ]] || { ENG_ERR="invalid config key for --${n} in ${f}"; return 2; }
                ENG_OPTS+=("$n"); ENG_OPT_TYPE[$n]="$t"; ENG_OPT_DEFAULT[$n]="$def"; ENG_OPT_CFG[$n]="$ck"; ENG_OPT_DESC[$n]="$d" ;;
            *) ENG_ERR="unknown key '${k}' in ${f}"; return 2 ;;
        esac
    done <"$f"
    [[ -n "$ENG_NAME" ]] || { ENG_ERR="missing name in ${f}"; return 2; }
    for n in "${ENG_MODS[@]}"; do
        g="${ENG_MOD_GROUP[$n]}"
        [[ -z "$g" || -n "${ENG_GROUP_DESC[$g]+x}" ]] || { ENG_ERR="modifier ${n} uses undeclared group ${g}"; return 2; }
    done
    return 0
}

# Validación de un valor según su tipo
eng_valid_value() {
    local type="$1" v="$2"
    case "$type" in
        target) is_valid_target "$v" ;;
        port)   [[ "$v" =~ ^[0-9]{1,5}$ ]] && (( 10#$v >= 1 && 10#$v <= 65535 )) ;;
        ip)     is_ipv4 "$v" || is_ipv6 "$v" || [[ "$v" == "localhost" ]] ;;
        dir)    [[ -n "$v" && "$v" != -* && ! "$v" =~ [[:cntrl:]] ]] ;;
        flag)   [[ "$v" == "1" ]] ;;
        *)      return 1 ;;
    esac
}

# eng_parse args... → ENG_SEL[] (modificadores en orden canónico), ENG_GIVEN[op]=valor
eng_parse() {
    local a n name g other i
    local -A seen=() group_owner=()
    declare -gA ENG_GIVEN=()
    ENG_SEL=() ENG_ERR=""
    while (( $# > 0 )); do
        a="$1"; shift
        if [[ "$a" == --*=* ]]; then
            ENG_ERR="use '${a%%=*} ${a#*=}' (with a space), not '${a}'"; return 2
        elif [[ "$a" == --* ]]; then
            name="${a#--}"
            [[ -n "${ENG_OPT_TYPE[$name]+x}" ]] || { ENG_ERR="unknown option: ${a} (valid: $(printf -- '--%s ' "${ENG_OPTS[@]}"))"; return 2; }
            [[ -z "${ENG_GIVEN[$name]+x}" ]] || { ENG_ERR="option ${a} given twice"; return 2; }
            if [[ "${ENG_OPT_TYPE[$name]}" == "flag" ]]; then
                ENG_GIVEN[$name]=1
            else
                (( $# > 0 )) && [[ "$1" != --* ]] || { ENG_ERR="option ${a} needs a value"; return 2; }
                eng_valid_value "${ENG_OPT_TYPE[$name]}" "$1" || { ENG_ERR="invalid value for ${a}: '${1}' (expected ${ENG_OPT_TYPE[$name]})"; return 2; }
                ENG_GIVEN[$name]="$1"; shift
            fi
        elif [[ "$a" == -* ]]; then
            ENG_ERR="unknown option: ${a}"; return 2
        else
            n="${a,,}"
            (( ${#ENG_MODS[@]} )) || { ENG_ERR="unexpected argument '${a}' (this command takes only --options)"; return 2; }
            [[ -n "${ENG_MOD_GROUP[$n]+x}" ]] || { ENG_ERR="unknown modifier '${a}' (valid: ${ENG_MODS[*]})"; return 2; }
            [[ -z "${seen[$n]:-}" ]] || { ENG_ERR="modifier '${n}' given twice"; return 2; }
            seen[$n]=1
            g="${ENG_MOD_GROUP[$n]}"
            if [[ -n "$g" ]]; then
                other="${group_owner[$g]:-}"
                if [[ -n "$other" ]]; then
                    ENG_ERR="'${other}' and '${n}' cannot be combined: ${ENG_GROUP_DESC[$g]:-same group}"
                    return 2
                fi
                group_owner[$g]="$n"
            fi
        fi
    done
    # Orden canónico (el del .spec): el orden de escritura no importa
    for i in "${ENG_MODS[@]}"; do [[ -n "${seen[$i]:-}" ]] && ENG_SEL+=("$i"); done
    return 0
}

# eng_value OPCIÓN → valor efectivo: explícito > configuración > defecto
eng_value() {
    local n="$1" ck
    if [[ -n "${ENG_GIVEN[$n]+x}" ]]; then printf '%s' "${ENG_GIVEN[$n]}"; return 0; fi
    ck="${ENG_OPT_CFG[$n]:-}"
    if [[ -n "$ck" && -n "${URB_CFG[$ck]:-}" ]]; then printf '%s' "${URB_CFG[$ck]}"; return 0; fi
    printf '%s' "${ENG_OPT_DEFAULT[$n]:-}"
}

# ¿Necesita privilegios alguno de los modificadores elegidos?
eng_needs_root() { local m; for m in "${ENG_SEL[@]}"; do [[ "${ENG_MOD_FLAGS[$m]}" == "root" ]] && return 0; done; return 1; }

# Ayuda generada desde el .spec (única definición de sintaxis y parámetros)
eng_help() {
    local n d def ck g
    eng_load "$1" || { msg_err "$ENG_ERR"; return 2; }
    printf '%s%s%s — %s\n\n' "$C_BOLD" "urb ${ENG_NAME}" "$C_RESET" "$ENG_SUMMARY"
    printf '%sUSAGE%s\n  %s\n' "$C_BOLD" "$C_RESET" "$ENG_USAGE"
    if (( ${#ENG_MODS[@]} )); then
        printf '\n%sMODIFIERS%s (any order; "a b" = "b a")\n' "$C_BOLD" "$C_RESET"
        for n in "${ENG_MODS[@]}"; do
            d="${ENG_MOD_DESC[$n]}"
            [[ "${ENG_MOD_FLAGS[$n]}" == "root" ]] && d+=" [root]"
            [[ -n "${ENG_MOD_GROUP[$n]}" ]] && d+=" {${ENG_MOD_GROUP[$n]}}"
            printf '  %s%-10s%s %s\n' "$T_KEY" "$n" "$C_RESET" "$d"
        done
        for g in "${!ENG_GROUP_DESC[@]}"; do
            printf '  %s{%s}: only one per command — %s%s\n' "$T_DIM" "$g" "${ENG_GROUP_DESC[$g]}" "$C_RESET"
        done
    fi
    if (( ${#ENG_OPTS[@]} )); then
        printf '\n%sOPTIONS%s\n' "$C_BOLD" "$C_RESET"
        for n in "${ENG_OPTS[@]}"; do
            def="${ENG_OPT_DEFAULT[$n]}"; ck="${ENG_OPT_CFG[$n]}"
            d="${ENG_OPT_DESC[$n]}"
            [[ -n "$def" ]] && d+=" (default: ${def}${ck:+; config ${ck}})"
            [[ -z "$def" && -n "$ck" ]] && d+=" (config ${ck})"
            if [[ "${ENG_OPT_TYPE[$n]}" == "flag" ]]; then printf '  %s--%-14s%s %s\n' "$T_KEY" "$n" "$C_RESET" "$d"
            else printf '  %s--%-14s%s %s\n' "$T_KEY" "${n} <${ENG_OPT_TYPE[$n]}>" "$C_RESET" "$d"; fi
        done
    fi
    if (( ${#ENG_NOTES[@]} )); then
        printf '\n%sNOTES%s\n' "$C_BOLD" "$C_RESET"
        for d in "${ENG_NOTES[@]}"; do printf '  %s\n' "$d"; done
    fi
    if (( ${#ENG_EXAMPLES[@]} )); then
        printf '\n%sEXAMPLES%s\n' "$C_BOLD" "$C_RESET"
        for d in "${ENG_EXAMPLES[@]}"; do printf '  %s\n' "$d"; done
    fi
    [[ -n "$ENG_REQUIRES" ]] && printf '\n%sRequires: %s%s\n' "$T_DIM" "$ENG_REQUIRES" "$C_RESET"
    return 0
}
