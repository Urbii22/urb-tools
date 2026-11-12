# =============================================================================
#  godmode/zsh/.zshenv — URB God Mode (ZDOTDIR temporal de la sesión)
#  Zsh lee este fichero EN LUGAR de tu ~/.zshenv porque God Mode arranca Zsh
#  con ZDOTDIR apuntando aquí. Lo primero es cargar el tuyo, sin modificarlo.
# =============================================================================
typeset -g _urb_god_zdotdir="$ZDOTDIR"
ZDOTDIR="${URB_USER_ZDOTDIR:-$HOME}"
if [[ -r "$ZDOTDIR/.zshenv" ]]; then
    source "$ZDOTDIR/.zshenv"
fi
# Tu .zshenv puede cambiar ZDOTDIR: se recuerda para cargar después tu .zshrc
typeset -gx URB_USER_ZDOTDIR="$ZDOTDIR"
ZDOTDIR="$_urb_god_zdotdir"
unset _urb_god_zdotdir
# /etc/zsh/zshrc (Debian/Ubuntu) ejecuta compinit con el ZDOTDIR de God Mode y
# escribiría .zcompdump en la carpeta de URB. Se omite aquí; .zshrc lo ejecuta
# después (si tu configuración no lo hace) con TU ZDOTDIR, como tu shell normal.
typeset -g skip_global_compinit=1
