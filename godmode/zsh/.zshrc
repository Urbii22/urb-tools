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

# --- 2. Identidad de God Mode -----------------------------------------------------------
[[ -r "${URB_GOD_DIR:-}/themes/urb.theme" ]] && source "$URB_GOD_DIR/themes/urb.theme"
: "${URB_C_PRIMARY:=51}" "${URB_C_ELECTRIC:=39}" "${URB_C_GREEN:=48}" "${URB_C_WARN:=220}"
: "${URB_C_BAD:=196}" "${URB_C_WHITE:=255}" "${URB_C_DIM:=242}"

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

PROMPT="%F{$URB_C_ELECTRIC}${_urb_tl}%F{$URB_C_PRIMARY}[%B%F{$URB_C_GREEN}GOD%b%F{$URB_C_PRIMARY}]"
PROMPT+="%F{$URB_C_ELECTRIC}${_urb_h}%F{$URB_C_PRIMARY}[%(!.%F{$URB_C_BAD}.%F{$URB_C_WHITE})%n%F{$URB_C_ELECTRIC}@%F{$URB_C_WHITE}%m%F{$URB_C_PRIMARY}]"
PROMPT+="%F{$URB_C_ELECTRIC}${_urb_h}%F{$URB_C_PRIMARY}[%F{$URB_C_GREEN}%(5~|%-1~/…/%3~|%~)%F{$URB_C_PRIMARY}]"
PROMPT+='${vcs_info_msg_0_}'
PROMPT+=$'\n'"%F{$URB_C_ELECTRIC}${_urb_bl}%(?.%F{$URB_C_GREEN}.%F{$URB_C_BAD})${_urb_arrow}%f "
RPROMPT="%(?..%F{$URB_C_BAD}✘ %?%f)%(1j. %F{$URB_C_WARN}⚙ %j%f.)"
PROMPT2="%F{$URB_C_DIM}${_urb_bl}%_ ${_urb_arrow}%f "

# Mensaje de bienvenida: solo en la primera shell de la sesión
if [[ -z "${URB_GOD_GREETED:-}" ]]; then
    print -P "%F{$URB_C_PRIMARY}◆ URB GOD MODE%f %F{$URB_C_DIM}· %F{$URB_C_WHITE}exit%F{$URB_C_DIM} leave · %F{$URB_C_WHITE}Ctrl+B d%F{$URB_C_DIM} detach · %F{$URB_C_WHITE}urb god --help%f"
    if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
        tmux set-environment URB_GOD_GREETED 1 2>/dev/null
    fi
fi
