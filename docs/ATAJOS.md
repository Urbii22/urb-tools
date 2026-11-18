# Atajos de teclado — QTerminal, tmux (GOD/RED/BLUE) y Zsh

Manual para moverte por la terminal sin ratón. No explica los comandos de URB (para eso: `urb help`, `urb manual`); explica **las teclas**.

Ábrelo en cualquier momento con `urb manual atajos` (`/` busca, `n` siguiente, `q` sale).

---

## 0. Las tres capas: quién se come cada tecla

Cuando estás dentro de GOD/RED/BLUE hay tres programas uno dentro de otro. Cada uno tiene sus atajos:

```
┌─ QTerminal (la ventana) ──────────────────────────────────────────┐
│  Pestañas, paneles de la ventana, copiar/pegar, zoom, pantalla    │
│  Atajos con Ctrl+Shift+…, Ctrl+PgUp/PgDn, Alt+flechas             │
│                                                                   │
│  ┌─ tmux (la sesión URB: GOD/RED/BLUE) ───────────────────────┐   │
│  │  Ventanas y paneles DENTRO de la sesión, desplazar, copiar  │  │
│  │  Atajos: primero Ctrl+B, se sueltan, y luego otra tecla     │  │
│  │                                                             │  │
│  │  ┌─ Zsh (la shell, donde escribes) ──────────────────────┐  │  │
│  │  │  Editar la línea, historial, autocompletar            │  │  │
│  │  │  Atajos: Ctrl+R, Ctrl+A, Ctrl+E, Tab, Alt+. …         │  │  │
│  │  └───────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

Regla rápida:

- **Ctrl+Shift+algo** → QTerminal (la ventana).
- **Ctrl+B y luego algo** → tmux (solo dentro de GOD/RED/BLUE).
- **Ctrl+algo / Alt+algo** sin más → Zsh (la línea que escribes).

> **Pestaña de QTerminal ≠ ventana de tmux.** `Ctrl+Shift+T` abre una pestaña nueva de QTerminal (otra terminal, fuera de tu sesión). `Ctrl+B c` abre una ventana nueva *dentro* de tu sesión GOD (aparece en la barra del HUD como `2:zsh`). Las ventanas de tmux sobreviven aunque cierres QTerminal; las pestañas no.

---

## 1. QTerminal (la ventana)

Son los atajos por defecto de QTerminal. Puedes ver y cambiar todos en **File → Preferences → Shortcuts** (o clic derecho → Preferences). Si alguno no te responde, mira ahí cuál tiene asignado tu versión.

### Pestañas

| Tecla | Qué hace |
|---|---|
| `Ctrl+Shift+T` | Pestaña nueva |
| `Ctrl+Shift+W` | Cerrar la pestaña actual |
| `Ctrl+PgDn` / `Ctrl+PgUp` | Pestaña siguiente / anterior |
| `Ctrl+Shift+PgDn` / `Ctrl+Shift+PgUp` † | Mover la pestaña a la derecha / izquierda |
| `Alt+1` … `Alt+9` † | Ir a la pestaña 1…9 |

### Paneles de la ventana (subterminales)

Son las divisiones que usa `urb layout`. Se crean desde el menú **Actions → Split Terminal Horizontally / Vertically** o con clic derecho.

| Tecla | Qué hace |
|---|---|
| `Alt+←` `Alt+→` `Alt+↑` `Alt+↓` † | Saltar al panel de la izquierda / derecha / arriba / abajo |
| Arrastrar la línea separadora | Cambiar el tamaño |
| Actions → Close Subterminal | Cerrar solo ese panel |

> Dentro de GOD/RED/BLUE, `Alt+flechas` puede llegar a tmux o a Zsh si QTerminal no lo captura. Si no salta de panel, haz clic en el panel con el ratón.

### Ventanas, copiar y vista

| Tecla | Qué hace |
|---|---|
| `Ctrl+Shift+N` | Ventana nueva de QTerminal |
| `Ctrl+Shift+Q` † | Cerrar la ventana |
| `Ctrl+Shift+C` | Copiar lo seleccionado |
| `Ctrl+Shift+V` | Pegar |
| `Shift+Insert` | Pegar la selección (lo último que marcaste) |
| Botón central del ratón | Pegar la selección |
| `Ctrl+Shift+F` | Buscar texto en la salida |
| `Ctrl++` / `Ctrl+-` / `Ctrl+0` | Agrandar / reducir / restablecer la letra |
| `F11` | Pantalla completa |
| `Ctrl+Shift+M` † | Mostrar / ocultar la barra de menús |

† Cambia entre versiones de QTerminal: confírmalo en **Preferences → Shortcuts** y, si no está, asígnalo ahí.

> **Ojo:** dentro de una terminal `Ctrl+C` **no copia**: interrumpe el programa que se está ejecutando. Copiar es `Ctrl+Shift+C`.

### Escritorio (Kali Xfce)

| Tecla | Qué hace |
|---|---|
| `Ctrl+Alt+T` | Abrir una terminal nueva |
| `Super` (tecla Windows) | Menú de aplicaciones |
| `Alt+Tab` | Cambiar de ventana |

---

## 2. tmux dentro de GOD / RED / BLUE

### Cómo se pulsa el prefijo

Todos los atajos de tmux empiezan por **el prefijo `Ctrl+B`**:

1. Pulsa `Ctrl+B` y **suelta las dos teclas**.
2. Pulsa la tecla del atajo (por ejemplo `c`).

Se escribe `Ctrl+B c`. No es una combinación de tres teclas a la vez.

`Ctrl+B ?` muestra **la lista completa** de atajos activos (con `q` sales). Si olvidas algo, empieza por ahí.

### Sesión, ventana y panel

```
Sesión GOD (god-1234-56789)          ← lo que ves en Ctrl+B s
 ├─ Ventana 1  "zsh"                 ← pestañas del HUD: 1:zsh  2:nmap …
 │   ├─ Panel 1  ┌─────────┬────────┐
 │   └─ Panel 2  │ panel 1 │ panel 2│ ← divisiones dentro de la ventana
 │               └─────────┴────────┘
 └─ Ventana 2  "nmap"
```

### Lo que URB añade o cambia

| Tecla / acción | Qué hace |
|---|---|
| `Ctrl+B s` | **Menú de sesiones URB**: todas las GOD/RED/BLUE con sus colores; Enter entra, `n` abre, `x` cierra |
| `sessions` (comando) | Lo mismo que `Ctrl+B s` |
| `Ctrl+B c` | Ventana nueva **en la carpeta actual** |
| `Ctrl+B %` / `Ctrl+B "` | Dividir en la **carpeta actual** (izq/der · arriba/abajo) |
| Rueda del ratón | Desplaza la salida; al bajar del todo (o con `q`) vuelves al prompt |
| Arrastrar con el ratón | Selecciona y **copia al portapapeles** al soltar; queda marcado; clic o `q` para salir |
| `Shift` + arrastrar | Selección normal de QTerminal (sin tmux) |
| Clic en un panel | Lo activa |

### Sesiones

| Tecla | Qué hace |
|---|---|
| `Ctrl+B d` | **Salir dejando la sesión viva** (detach). Vuelves con `urb god` o `Ctrl+B s` |
| `Ctrl+B $` | Renombrar la sesión |
| `Ctrl+B (` / `Ctrl+B )` | Sesión anterior / siguiente **del mismo perfil** |
| `Ctrl+B L` | Volver a la última sesión usada (mismo perfil) |
| `exit` o `Ctrl+D` en la última shell | Cierra la sesión del todo |

> Para saltar entre perfiles (de RED a GOD) usa `Ctrl+B s`: `(` `)` y `L` solo ven las sesiones del perfil actual.

### Ventanas (las pestañas del HUD)

| Tecla | Qué hace |
|---|---|
| `Ctrl+B c` | Ventana nueva |
| `Ctrl+B 1` … `Ctrl+B 9` | Ir a la ventana 1…9 (en URB empiezan en 1) |
| `Ctrl+B n` / `Ctrl+B p` | Ventana siguiente / anterior |
| `Ctrl+B l` | Volver a la última ventana usada (alternar entre dos) |
| `Ctrl+B w` | Lista de ventanas y paneles con vista previa (flechas + Enter) |
| `Ctrl+B ,` | Renombrar la ventana (p. ej. `nmap`, `web`, `notas`) |
| `Ctrl+B '` | Pedir el número de ventana (para la 10 en adelante) |
| `Ctrl+B .` | Mover la ventana a otro número |
| `Ctrl+B f` | Buscar una ventana por el texto que contiene |
| `Ctrl+B &` | Cerrar la ventana (pide confirmación) |

### Paneles

| Tecla | Qué hace |
|---|---|
| `Ctrl+B %` | Dividir izquierda / derecha |
| `Ctrl+B "` | Dividir arriba / abajo |
| `Ctrl+B ←↑→↓` | Ir al panel en esa dirección |
| `Ctrl+B o` | Ir al siguiente panel |
| `Ctrl+B ;` | Volver al panel anterior |
| `Ctrl+B q` | Mostrar los números de panel; pulsa el número para saltar |
| `Ctrl+B z` | **Zoom**: el panel ocupa toda la ventana; repetir para volver |
| `Ctrl+B x` | Cerrar el panel (pide confirmación) |
| `Ctrl+B !` | Sacar el panel a una ventana propia |
| `Ctrl+B {` / `Ctrl+B }` | Intercambiar con el panel anterior / siguiente |
| `Ctrl+B Espacio` | Cambiar entre las distribuciones predefinidas |
| `Ctrl+B Alt+1` … `Alt+5` | Distribución: columnas iguales · filas iguales · principal arriba · principal izquierda · cuadrícula |
| `Ctrl+B Ctrl+←↑→↓` | Redimensionar 1 celda (mantén Ctrl y repite la flecha) |
| `Ctrl+B Alt+←↑→↓` | Redimensionar 5 celdas |
| `Ctrl+B m` / `Ctrl+B M` | Marcar / desmarcar un panel (para `join-pane`, ver §2.7) |
| `Ctrl+B t` | Reloj grande (cualquier tecla lo quita) |

Puedes encadenar: tras `Ctrl+B`, las flechas para moverte y redimensionar admiten repetir sin volver a pulsar el prefijo durante un segundo.

### Desplazar, buscar y copiar con teclado (modo copia)

| Tecla | Qué hace |
|---|---|
| `Ctrl+B [` | Entrar en modo copia (también `Ctrl+B PgUp`, que además sube una página) |
| `q` o `Esc` | Salir del modo copia |

Dentro del modo copia hay dos juegos de teclas. tmux usa **vi** si tu `$EDITOR` o `$VISUAL` contiene `vi` y **emacs** en otro caso. Para saber cuál tienes:

```bash
tmux -L urb-god show -gw mode-keys
```

| Acción | emacs (por defecto en Kali) | vi |
|---|---|---|
| Moverse | flechas, `PgUp`/`PgDn` | `h j k l`, `Ctrl+U`/`Ctrl+D` |
| Inicio / fin del historial | `Alt+<` / `Alt+>` | `g` / `G` |
| Buscar hacia atrás / adelante | `Ctrl+R` / `Ctrl+S` | `?` / `/` |
| Siguiente resultado | repetir `Ctrl+R` / `Ctrl+S` | `n` (`N` al revés) |
| Empezar a seleccionar | `Ctrl+Espacio` | `Espacio` |
| Selección rectangular | `R` | `v` (tras empezar) |
| Copiar y salir | `Alt+W` | `Enter` |

Lo que copies así **también va al portapapeles** (igual que con el ratón).

| Tecla | Qué hace |
|---|---|
| `Ctrl+B ]` | Pegar lo último copiado en tmux |
| `Ctrl+B =` | Elegir entre todo lo copiado antes (historial de copias) |

Ejemplo: buscar el puerto 445 en una salida larga de nmap → `Ctrl+B [`, `Ctrl+R`, escribe `445`, Enter; `Ctrl+R` otra vez para el anterior; `q` para salir.

### La línea de comandos de tmux: `Ctrl+B :`

Abre un prompt abajo para escribir órdenes de tmux (Tab autocompleta). Las más útiles:

| Escribe tras `Ctrl+B :` | Para qué |
|---|---|
| `setw synchronize-panes on` | **Escribir en todos los paneles a la vez** (p. ej. el mismo comando en 3 máquinas). `off` para desactivar |
| `kill-pane -a` | Cerrar todos los paneles menos el actual |
| `select-layout tiled` | Cuadrícula con todos los paneles |
| `resize-pane -D 10` | Bajar el borde 10 líneas (`-U` `-L` `-R`) |
| `swap-window -t 1` | Poner la ventana actual en la posición 1 |
| `move-window -r` | Renumerar ventanas sin huecos |
| `join-pane -s 2` | Traer la ventana 2 como panel de esta (al revés que `Ctrl+B !`) |
| `capture-pane -S - ; save-buffer ~/salida.txt` | **Guardar toda la salida del panel** en un fichero |
| `pipe-pane -o 'cat >> ~/panel.log'` | Grabar desde ya todo lo que salga en el panel (repetir para parar) |
| `setw monitor-activity on` | Marcar en el HUD la ventana cuando tenga salida nueva (útil con escaneos largos) |
| `setw monitor-silence 30` | Avisar cuando una ventana lleve 30 s sin salida (el escaneo terminó) |
| `rename-window web` | Renombrar sin `Ctrl+B ,` |

---

## 3. Zsh: editar la línea y el historial

Tu Zsh de URB carga tu `~/.zshrc` de Kali, así que tienes sus atajos (modo emacs) más las sugerencias en gris.

### Moverse y borrar en la línea

| Tecla | Qué hace |
|---|---|
| `Ctrl+A` / `Ctrl+E` | Ir al principio / final de la línea (también `Inicio` / `Fin`) |
| `Ctrl+←` / `Ctrl+→` | Palabra anterior / siguiente (también `Alt+B` / `Alt+F`) |
| `Ctrl+W` | Borrar la palabra anterior |
| `Alt+D` | Borrar la palabra siguiente |
| `Ctrl+U` | Borrar desde el cursor hasta el principio |
| `Ctrl+K` | Borrar desde el cursor hasta el final |
| `Ctrl+Y` | Pegar lo último borrado con `Ctrl+W/U/K` |
| `Ctrl+_` | Deshacer |
| `Ctrl+L` | Limpiar la pantalla (sin borrar la línea que escribes) |

### Historial

| Tecla | Qué hace |
|---|---|
| `↑` / `↓` | Comando anterior / siguiente |
| `Ctrl+R` | **Buscar en el historial** escribiendo un trozo; `Ctrl+R` de nuevo = más antiguo; Enter ejecuta, `→` lo deja para editar |
| `→` o `Fin` | **Aceptar la sugerencia gris** (autosuggestions de Kali) |
| `Alt+.` | Pegar el **último argumento** del comando anterior (repetir = de los anteriores) |
| `!!` | Repetir el comando anterior (`sudo !!` = el anterior con sudo) |
| `!$` | Último argumento del comando anterior |
| `history 20` | Ver los últimos 20 comandos |

### Autocompletar

| Tecla | Qué hace |
|---|---|
| `Tab` | Completar comando, ruta u opción; dos veces = menú |
| `Tab` en el menú | Recorrer opciones (flechas también); Enter elige |
| `Shift+Tab` | Opción anterior en el menú |
| `urb ` + `Tab` | Subcomandos de URB (`red`, `sessions`, `layout`…) |

### Controlar procesos

| Tecla | Qué hace |
|---|---|
| `Ctrl+C` | Interrumpir el programa |
| `Ctrl+Z` | Pausarlo y volver al prompt |
| `fg` / `bg` | Reanudarlo delante / en segundo plano |
| `jobs` | Ver lo que tienes pausado o en segundo plano |
| `Ctrl+D` | Fin de entrada; en un prompt vacío, cierra la shell (y la sesión si es la última) |
| `Ctrl+S` / `Ctrl+Q` | Congelar / descongelar la salida (si la terminal "se cuelga", prueba `Ctrl+Q`) |

---

## 4. Recetas para el día a día

**Escaneo largo sin perderlo de vista**
`Ctrl+B c` → lanza el escaneo → `Ctrl+B ,` lo nombras `nmap` → `Ctrl+B :` `setw monitor-silence 30` → vuelves a tu ventana con `Ctrl+B l`. Cuando el escaneo termine, la ventana `nmap` se marca en el HUD.

**Ver dos cosas grandes, una a una**
`Ctrl+B %` para dividir, trabajas en las dos y `Ctrl+B z` para ampliar la que necesites en cada momento.

**Mismo comando en varias máquinas**
Un panel por máquina (`Ctrl+B %` / `"`), entra por SSH en cada una, `Ctrl+B :` `setw synchronize-panes on`, escribe una vez, `off` al terminar.

**Guardar la salida como evidencia**
`Ctrl+B :` `capture-pane -S - ; save-buffer ~/evidencia.txt` y luego `urb red findings evidence F-001 ~/evidencia.txt`.

**Cerrar QTerminal sin perder nada**
Cierra la ventana o `Ctrl+B d`: la sesión sigue. Vuelve con `urb god` / `urb red` / `urb blue` (o `urb sessions menu`).

**Abrir todo tu entorno de golpe**
`urb layout` → pestaña con Claude, BLUE, GOD y RED. Pasa de panel con `Alt+flechas` o con el ratón.

**Copiar un comando o una IP**
Arrastra con el ratón (se copia al soltar) y pega con `Ctrl+Shift+V`. O doble clic sobre una palabra.

---

## 5. Chuleta mínima (lo primero que aprender)

| Para… | Pulsa |
|---|---|
| Ver todos los atajos de tmux | `Ctrl+B ?` |
| Cambiar de sesión URB | `Ctrl+B s` |
| Salir dejando la sesión viva | `Ctrl+B d` |
| Ventana nueva / ir a la 2 | `Ctrl+B c` / `Ctrl+B 2` |
| Dividir | `Ctrl+B %` · `Ctrl+B "` |
| Cambiar de panel | `Ctrl+B ←↑→↓` |
| Ampliar un panel | `Ctrl+B z` |
| Subir por la salida | rueda o `Ctrl+B [` |
| Buscar en el historial de comandos | `Ctrl+R` |
| Reutilizar el último argumento | `Alt+.` |
| Pestaña nueva / cambiar de pestaña | `Ctrl+Shift+T` / `Ctrl+PgUp/PgDn` |
| Copiar / pegar en la terminal | `Ctrl+Shift+C` / `Ctrl+Shift+V` |

**Para aprenderlos:** una semana con solo esta chuleta (sobre todo `Ctrl+B z`, `Ctrl+R` y `Alt+.`), y la siguiente añade ventanas con nombre y el modo copia por teclado.
