#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
#  godmode/animations/fx.sh — Animaciones de entrada y salida de God Mode
#  Breves (< 1 s), se saltan pulsando cualquier tecla y se desactivan con
#  --no-anim o ANIMATIONS="0". Se dibujan en la pantalla alternativa, así que
#  no dejan rastro en el historial de tu terminal.
#  Requiere: lib/utils.sh y lib/ui.sh (logo, glifos) y themes/urb.theme.
# =============================================================================

[[ -n "${_URB_GOD_FX_LOADED:-}" ]] && return 0
_URB_GOD_FX_LOADED=1

FX_SKIP=0

# Pausa interrumpible: una tecla salta el resto de la animación
_fx_sleep() {
    (( FX_SKIP )) && return 0
    if IFS= read -rsn1 -t "$1" _ </dev/tty 2>/dev/null; then FX_SKIP=1; fi
    return 0
}

_fx_c() { if (( URB_COLOR_ON )); then printf '\e[38;5;%sm' "$1"; fi; }
_fx_at() { printf '\e[%d;%dH' "$1" "$2"; }

# Geometría común: logo centrado en la pantalla de animación
_fx_geometry() {
    ui_term_size
    FX_LW="$(ui_logo_width)"
    FX_ROW=$(( UI_ROWS / 2 - 6 )); (( FX_ROW < 1 )) && FX_ROW=1
    FX_COL=$(( (UI_COLS - FX_LW) / 2 + 1 )); (( FX_COL < 1 )) && FX_COL=1
}

# god_fx_engage "línea de estado real" ...
god_fx_engage() {
    local -a info=("$@")
    local i step len line r w half bar head col
    FX_SKIP=0
    _fx_geometry
    printf '\e[?1049h\e[?25l\e[2J'

    # 1) El logo entra por barrido (3 pasos por línea)
    for i in "${!UI_LOGO[@]}"; do
        line="${UI_LOGO[i]}"; len=${#line}
        for step in 1 2 3; do
            _fx_at $(( FX_ROW + i )) "$FX_COL"
            printf '%s%s\e[0m' "${UI_LOGO_COLORS[i % 6]}" "${line:0:$(( len * step / 3 ))}"
            _fx_sleep 0.012
        done
    done

    # 2) Estela "warp" que se expande desde el centro (decorativa, sin porcentajes)
    r=$(( FX_ROW + ${#UI_LOGO[@]} + 1 ))
    w=$(( UI_COLS - 8 )); (( w > 64 )) && w=64; (( w < 10 )) && w=10
    half=$(( w / 2 ))
    for (( step = 1; step <= 8; step++ )); do
        len=$(( half * step / 8 ))
        ui_repeat bar "$G_H" "$len"
        head="${G_DIAM}"
        _fx_at "$r" $(( (UI_COLS - w) / 2 + 1 ))
        printf '\e[K'
        _fx_at "$r" $(( UI_COLS / 2 - len ))
        printf '%s%s%s%s%s%s\e[0m' "$(_fx_c "${URB_C_DEEP:-27}")" "$bar" "$(_fx_c "${URB_C_PRIMARY:-51}")" "$head" "$(_fx_c "${URB_C_DEEP:-27}")" "$bar"
        _fx_sleep 0.022
    done

    # 3) Comprobaciones reales (versiones, sesión, directorio)
    r=$(( r + 2 ))
    for line in "${info[@]}"; do
        _fx_at "$r" $(( (UI_COLS - w) / 2 + 1 ))
        printf '%s%s %s%s\e[0m' "$(_fx_c "${URB_C_GREEN:-48}")" "$G_OK" "$(_fx_c "${URB_C_TEXT:-252}")" "$line"
        r=$(( r + 1 ))
        _fx_sleep 0.03
    done

    # 4) Destello final
    local msg=" ${FX_TITLE:-GOD MODE} ONLINE "
    for col in "${URB_C_WHITE:-255}" "${URB_C_PRIMARY:-51}"; do
        _fx_at $(( r + 1 )) $(( (UI_COLS - ${#msg}) / 2 + 1 ))
        if (( URB_COLOR_ON )); then printf '\e[1;38;5;%s;48;5;%sm%s\e[0m' "${URB_C_INK:-16}" "$col" "$msg"
        else printf '\e[7m%s\e[0m' "$msg"; fi
        _fx_sleep 0.09
    done
    _fx_sleep 0.12
    printf '\e[0m\e[2J\e[H\e[?25h\e[?1049l'
}

# god_fx_disengage "mensaje"
god_fx_disengage() {
    local msg="${1:-GOD MODE OFF}" i fade
    FX_SKIP=0
    _fx_geometry
    printf '\e[?1049h\e[?25l\e[2J'
    for i in "${!UI_LOGO[@]}"; do
        _fx_at $(( FX_ROW + i )) "$FX_COL"
        printf '%s%s\e[0m' "${UI_LOGO_COLORS[i % 6]}" "${UI_LOGO[i]}"
    done
    # El logo se apaga de arriba abajo
    for fade in "${URB_C_LABEL:-67}" "${URB_C_DIM:-242}" "${URB_C_SEP:-238}"; do
        for i in "${!UI_LOGO[@]}"; do
            _fx_at $(( FX_ROW + i )) "$FX_COL"
            printf '%s%s\e[0m' "$(_fx_c "$fade")" "${UI_LOGO[i]}"
        done
        _fx_at $(( FX_ROW + ${#UI_LOGO[@]} + 1 )) $(( (UI_COLS - ${#msg}) / 2 + 1 ))
        printf '%s%s\e[0m' "$(_fx_c "$fade")" "$msg"
        _fx_sleep 0.08
    done
    _fx_sleep 0.1
    printf '\e[0m\e[2J\e[H\e[?25h\e[?1049l'
}
