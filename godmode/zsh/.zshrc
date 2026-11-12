# =============================================================================
#  godmode/zsh/.zshrc — Zsh de URB God Mode
#  1. Carga TU configuración (~/.zshrc): alias, autocompletado, historial,
#     plugins de Kali... sin modificarla.
#  2. Encima aplica la identidad de God Mode: prompt URB con Git y estado.
#  Es una Zsh real: todo lo que funciona en tu terminal funciona aquí.
# =============================================================================

# --- 1. Configuración personal ----------------------------------------------------
# Durante la carga, ZDOTDIR vuelve a ser el tuyo (compdump, HISTFILE, plugins...)
ZDOTDIR="${URB_USER_ZDOTDIR:-$HOME}"
if [[ -r "$ZDOTDIR/.zshrc" ]]; then
    source "$ZDOTDIR/.zshrc"
fi
# Se queda así: una `zsh` abierta dentro de God Mode se comporta como la tuya.
export ZDOTDIR

# Mínimos razonables si tu configuración no los define
[[ -n "${HISTFILE:-}" ]] || HISTFILE="$ZDOTDIR/.zsh_history"
(( ${HISTSIZE:-0} >= 1000 )) || HISTSIZE=10000
(( ${SAVEHIST:-0} >= 1000 )) || SAVEHIST=10000
if (( ! $+functions[compdef] )); then
    # Mismo fichero de caché que tu shell normal ($ZDOTDIR/.zcompdump)
    autoload -Uz compinit
    compinit -i
fi

# --- 2. Identidad del perfil (god / red) --------------------------------------------------
# Los temas son DATOS (URB_*=números): se leen y validan, nunca se ejecutan.
_urb_read_theme() {
    local line
    [[ -r "$1" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ '^URB_[A-Z0-9_]+=[0-9][0-9 ]*$' ]] && typeset -g "${line%%=*}=${line#*=}"
    done <"$1"
}
_urb_read_theme "${URB_GOD_DIR:-}/themes/urb.theme"
[[ "${URB_PROFILE_THEME:-urb}" =~ '^[a-z]+$' && "${URB_PROFILE_THEME:-urb}" != urb ]] && \
    _urb_read_theme "${URB_GOD_DIR:-}/themes/${URB_PROFILE_THEME}.theme"
: "${URB_C_PRIMARY:=51}" "${URB_C_ELECTRIC:=39}" "${URB_C_GREEN:=48}" "${URB_C_WARN:=220}"
: "${URB_C_BAD:=196}" "${URB_C_WHITE:=255}" "${URB_C_DIM:=242}"
_urb_tag="${URB_PROFILE_TAG:-GOD}"
[[ "$_urb_tag" =~ '^[A-Z]{1,8}$' ]] || _urb_tag="GOD"
_urb_cmd="urb ${(L)_urb_tag}"

setopt PROMPT_SUBST
autoload -Uz vcs_info add-zsh-hook

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '+'
zstyle ':vcs_info:git:*' unstagedstr '*'
zstyle ':vcs_info:git:*' formats "%F{$URB_C_ELECTRIC}─%F{$URB_C_PRIMARY}[%F{$URB_C_WARN}git:%b%F{$URB_C_BAD}%c%u%F{$URB_C_PRIMARY}]"
zstyle ':vcs_info:git:*' actionformats "%F{$URB_C_ELECTRIC}─%F{$URB_C_PRIMARY}[%F{$URB_C_WARN}git:%b|%a%F{$URB_C_BAD}%c%u%F{$URB_C_PRIMARY}]"

_urb_god_precmd() { vcs_info 2>/dev/null; }
add-zsh-hook precmd _urb_god_precmd

if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" == *[Uu][Tt][Ff]*8* ]]; then
    _urb_tl='╭─' _urb_bl='╰─' _urb_arrow='❯' _urb_h='─'
else
    _urb_tl='+-' _urb_bl='`-' _urb_arrow='>' _urb_h='-'
fi

PROMPT="%F{$URB_C_ELECTRIC}${_urb_tl}%F{$URB_C_PRIMARY}[%B%F{$URB_C_GREEN}${_urb_tag}%b%F{$URB_C_PRIMARY}]"
if [[ "$_urb_tag" == RED ]]; then
    # RED: laboratorio ▸ objetivo en lugar de usuario@host
    PROMPT+='${_urb_red_seg}'
else
    PROMPT+="%F{$URB_C_ELECTRIC}${_urb_h}%F{$URB_C_PRIMARY}[%(!.%F{$URB_C_BAD}.%F{$URB_C_WHITE})%n%F{$URB_C_ELECTRIC}@%F{$URB_C_WHITE}%m%F{$URB_C_PRIMARY}]"
fi
PROMPT+="%F{$URB_C_ELECTRIC}${_urb_h}%F{$URB_C_PRIMARY}[%F{$URB_C_GREEN}%(5~|%-1~/…/%3~|%~)%F{$URB_C_PRIMARY}]"
PROMPT+='${vcs_info_msg_0_}'
PROMPT+=$'\n'"%F{$URB_C_ELECTRIC}${_urb_bl}%(?.%F{$URB_C_GREEN}.%F{$URB_C_BAD})${_urb_arrow}%f "
RPROMPT="%(?..%F{$URB_C_BAD}✘ %?%f)%(1j. %F{$URB_C_WARN}⚙ %j%f.)"
PROMPT2="%F{$URB_C_DIM}${_urb_bl}%_ ${_urb_arrow}%f "

# --- 3. URB Red: contexto de laboratorio y navegación --------------------------------------
if [[ "$_urb_tag" == RED ]]; then
    # Laboratorio del directorio actual (o el seleccionado) y su objetivo.
    # Zsh nativo: unas pocas comprobaciones de fichero por prompt, sin procesos.
    _urb_red_ctx() {
        local d="$PWD" root="" line name="" tgt="" st
        while :; do
            [[ -f "$d/.urb-lab" ]] && { root="$d"; break; }
            [[ "$d" == / || -z "$d" ]] && break
            d="${d:h}"
        done
        if [[ -z "$root" ]]; then
            st="${XDG_DATA_HOME:-$HOME/.local/share}/urb-tools/state/active-lab"
            if [[ -r "$st" ]]; then
                IFS= read -r root <"$st"
                [[ "$root" == /* && -f "$root/.urb-lab" ]] || root=""
            fi
        fi
        if [[ -z "$root" ]]; then
            _urb_red_seg="%F{$URB_C_ELECTRIC}${_urb_h}%F{$URB_C_PRIMARY}[%F{$URB_C_DIM}no lab%F{$URB_C_PRIMARY}]"
            return
        fi
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                name=*)   name="${line#name=}" ;;
                target=*) tgt="${line#target=}" ;;
            esac
        done <"$root/.urb-lab"
        [[ -n "$name" ]] || name="${root:t}"
        # Datos de fichero: solo caracteres seguros en el prompt (sin % ni $)
        name="${name//[^A-Za-z0-9._-]/?}"; tgt="${tgt//[^A-Za-z0-9._:\/-]/?}"
        _urb_red_seg="%F{$URB_C_ELECTRIC}${_urb_h}%F{$URB_C_PRIMARY}[%F{$URB_C_WHITE}${name}"
        if [[ -n "$tgt" ]]; then _urb_red_seg+=" %F{$URB_C_ELECTRIC}▸ %F{$URB_C_GREEN}${tgt}"
        else _urb_red_seg+=" %F{$URB_C_DIM}▸ no target"; fi
        _urb_red_seg+="%F{$URB_C_PRIMARY}]"
    }
    add-zsh-hook precmd _urb_red_ctx

    # urblab [nombre] → cd al laboratorio (el del directorio actual o el seleccionado).
    # Es una función de ESTA shell: cambia su directorio sin abrir otra.
    urblab() {
        local dest
        if (( $# > 1 )); then print -u2 "usage: urblab [lab-name]"; return 2; fi
        dest="$("${URB_HOME:-}/bin/urb" red lab path "$@")" || return $?
        [[ -n "$dest" && -d "$dest" ]] || { print -u2 "urblab: lab directory not found"; return 1; }
        builtin cd -- "$dest"
    }
fi

# Contextual commands are registered per profile, after the user's configuration.
# A conflict leaves the existing command untouched; the full CLI remains available.
typeset -ga _urb_context_commands
_urb_context_commands=()
_urb_register_context_command() {
    local name="$1" subcommand="$2"
    if (( $+aliases[$name] || $+galiases[$name] || $+saliases[$name] )) || whence -w "$name" >/dev/null 2>&1; then
        print -u2 -r -- "URB ${URB_PROFILE:u}: '$name' already exists; use 'urb ${URB_PROFILE} $subcommand' instead."
        return
    fi
    functions[$name]='"${URB_HOME}/bin/urb" red '"$subcommand"' "$@"'
    _urb_context_commands+=("$name")
}
if [[ "${URB_PROFILE:-}" == red ]]; then
    _urb_register_context_command scan recon
    for _urb_context_name in recon services scans findings notes target lab status; do
        _urb_register_context_command "$_urb_context_name" "$_urb_context_name"
    done
    unset _urb_context_name
fi
unfunction _urb_register_context_command

# --- 4. Autocompletado de 'urb' (GOD y RED) -------------------------------------------------
# Ligero: listas fijas y lectura directa de los índices del laboratorio
# (findings/F-*.finding, scans/.index, scans/.services). Nunca ejecuta nmap,
# no analiza XML ni reconstruye inventarios, y no lanza procesos al pulsar Tab.
if (( $+functions[compdef] )); then
    # Raíz del laboratorio: el del directorio actual o el seleccionado → $REPLY
    _urb_lab_root() {
        local d="$PWD" st r
        while :; do
            [[ -f "$d/.urb-lab" ]] && { REPLY="$d"; return 0; }
            [[ "$d" == / || -z "$d" ]] && break
            d="${d:h}"
        done
        st="${XDG_DATA_HOME:-$HOME/.local/share}/urb-tools/state/active-lab"
        [[ -r "$st" ]] || return 1
        IFS= read -r r <"$st"
        [[ "$r" == /* && -f "$r/.urb-lab" ]] || return 1
        REPLY="$r"
    }
    _urb_complete() {
        local -a ids lines
        local REPLY line
        if (( CURRENT == 2 )); then
            compadd -- scan network monitor logs ctf config doctor god red sessions serve manual help version
            return
        fi
        case "${words[2]}" in
            red)
                if (( CURRENT == 3 )); then
                    compadd -- lab target status recon findings notes scans services --no-anim --kill --session --help
                    return
                fi
                case "${words[3]}" in
                    lab)
                        if (( CURRENT == 4 )); then compadd -- new use list path
                        elif [[ "${words[4]}" == (use|path) ]]; then compadd -- ${HOME}/urb-labs/*(N/:t)
                        fi ;;
                    target)  (( CURRENT == 4 )) && compadd -- set show ;;
                    recon)
                        # Modificadores leídos del .spec (datos) con Zsh nativo: sin procesos
                        ids=()
                        if [[ -r "${URB_HOME:-}/commands/red-recon.spec" ]]; then
                            lines=("${(@f)$(<"${URB_HOME}/commands/red-recon.spec")}")
                            for line in "${lines[@]}"; do
                                [[ "$line" == modifier=* ]] && ids+=("${${line#modifier=}%%|*}")
                            done
                        fi
                        if (( CURRENT == 4 )); then compadd -- initial "${ids[@]}" --dry-run --target --sudo
                        elif [[ "${words[4]}" != initial ]]; then
                            compadd -- "${ids[@]:|words}" --dry-run --target --sudo
                        else compadd -- --target
                        fi ;;
                    notes)   (( CURRENT == 4 )) && compadd -- add edit ;;
                    findings)
                        if (( CURRENT == 4 )); then
                            compadd -- list add show status note evidence
                        elif (( CURRENT == 5 )) && [[ "${words[4]}" == (show|status|note|evidence) ]]; then
                            _urb_lab_root && compadd -- "$REPLY"/findings/F-*.finding(N:t:r)
                        elif [[ "${words[4]}" == status ]] && (( CURRENT == 6 )); then
                            compadd -- pending investigating suspected confirmed discarded checked
                        elif [[ "${words[4]}" == evidence && "${words[CURRENT-1]}" == --scan ]]; then
                            ids=(latest)
                            if _urb_lab_root && [[ -r "$REPLY/scans/.index" ]]; then
                                lines=("${(@f)$(<"$REPLY/scans/.index")}")
                                for line in "${lines[@]}"; do [[ "$line" == S-* ]] && ids+=("${line%%|*}"); done
                            fi
                            compadd -- "${ids[@]}"
                        elif [[ "${words[4]}" == evidence ]] && (( CURRENT == 6 )); then
                            compadd -- --scan; _files
                        fi ;;
                    scans)
                        if (( CURRENT == 4 )); then compadd -- list show
                        elif [[ "${words[4]}" == show ]] && (( CURRENT == 5 )); then
                            ids=(latest)
                            if _urb_lab_root && [[ -r "$REPLY/scans/.index" ]]; then
                                lines=("${(@f)$(<"$REPLY/scans/.index")}")
                                for line in "${lines[@]}"; do [[ "$line" == S-* ]] && ids+=("${line%%|*}"); done
                            fi
                            compadd -- "${ids[@]}"
                        fi ;;
                    services)
                        if (( CURRENT == 4 )); then compadd -- list show refresh --all
                        elif [[ "${words[4]}" == show ]] && (( CURRENT == 5 )); then
                            # Puertos de la caché ya construida (no se reconstruye aquí)
                            if _urb_lab_root && [[ -r "$REPLY/scans/.services" ]]; then
                                lines=("${(@f)$(<"$REPLY/scans/.services")}")
                                for line in "${lines[@]}"; do
                                    [[ "$line" == svc$'\t'* ]] && ids+=("${${(ps:\t:)line}[4]}")
                                done
                                compadd -- "${(u)ids[@]}"
                            fi
                        fi ;;
                esac ;;
            sessions)
                if (( CURRENT == 3 )); then compadd -- list info attach kill
                elif (( CURRENT == 4 )); then compadd -- god red
                fi ;;
            god)     compadd -- --no-anim --status --kill --check --help ;;
            network) (( CURRENT == 3 )) && compadd -- summary interfaces routes gateway connections discover ping check ;;
            monitor) compadd -- --once --interval procs ;;
            logs)    (( CURRENT == 3 )) && compadd -- summary auth ssh errors search ;;
            ctf)     (( CURRENT == 3 )) && compadd -- new list path ;;
            config)  (( CURRENT == 3 )) && compadd -- show path init edit set ;;
            scan)    (( CURRENT == 3 )) && compadd -- profiles results; _files ;;
            help)
                if (( CURRENT == 3 )); then compadd -- scan network monitor logs ctf config god red sessions serve manual
                elif [[ "${words[3]}" == red ]] && (( CURRENT == 4 )); then
                    compadd -- shell lab target recon scans services findings notes context
                fi ;;
            serve)   compadd -- --port --bind --dir --yes ;;
            manual)  (( CURRENT == 3 )) && compadd -- commands examples path ;;
        esac
    }
    compdef _urb_complete urb
    # Present the short command as `urb red <subcommand>` to the same completer.
    _urb_context_complete() {
        local -a words=(urb red "${words[1]}" "${words[@]:1}")
        local CURRENT=$(( CURRENT + 2 ))
        [[ "${words[3]}" == scan ]] && words[3]=recon
        _urb_complete
    }
    if [[ "${URB_PROFILE:-}" == red ]] && (( ${#_urb_context_commands} )); then
        compdef _urb_context_complete "${_urb_context_commands[@]}"
    fi
fi

# Mensaje de bienvenida: solo en la primera shell de la sesión
if [[ -z "${URB_GOD_GREETED:-}" ]]; then
    if [[ "$_urb_tag" == RED ]]; then
        print -P "%F{$URB_C_PRIMARY}◆ URB RED%f %F{$URB_C_DIM}· %F{$URB_C_WHITE}urb red status%F{$URB_C_DIM} · %F{$URB_C_WHITE}urblab%F{$URB_C_DIM} go to lab · %F{$URB_C_WHITE}urb red recon initial%F{$URB_C_DIM} · %F{$URB_C_WHITE}exit%F{$URB_C_DIM} leave%f"
    else
        print -P "%F{$URB_C_PRIMARY}◆ URB GOD MODE%f %F{$URB_C_DIM}· %F{$URB_C_WHITE}exit%F{$URB_C_DIM} leave · %F{$URB_C_WHITE}Ctrl+B d%F{$URB_C_DIM} detach · %F{$URB_C_WHITE}urb god --help%f"
    fi
    if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
        tmux set-environment URB_GOD_GREETED 1 2>/dev/null
    fi
fi
unset _urb_cmd
