# URB-Tools — Manual de comandos

Referencia completa de todos los comandos de URB-Tools: sintaxis, parámetros, valores por defecto, ejemplos, efectos, ficheros y errores frecuentes.

- Ayuda rápida en la terminal: `urb help`, `urb help <tema>`, `urb help red <sección>` o su acceso directo `urb-help`.
- Abrir este manual: `urb manual`. Los flujos completos están en `urb manual examples` ([EXAMPLES.md](EXAMPLES.md)).
- Convenciones: `<valor>` es obligatorio, `[valor]` es opcional y `a|b` significa una cosa u otra.

> Usa URB-Tools solo contra sistemas propios o con autorización explícita por escrito.

## Índice

1. [Instalación y configuración](#1-instalación-y-configuración)
2. [Dashboard y ayuda general](#2-dashboard-y-ayuda-general)
3. [God Mode](#3-god-mode)
4. [URB Red](#4-urb-red)
5. [Laboratorios y objetivos](#5-laboratorios-y-objetivos)
6. [Reconocimiento](#6-reconocimiento)
7. [Scan Manager](#7-scan-manager)
8. [Inventario de servicios](#8-inventario-de-servicios)
9. [Findings, notas y evidencias](#9-findings-notas-y-evidencias)
10. [Sesiones tmux](#10-sesiones-tmux)
11. [Network, Monitor y Logs](#11-network-monitor-y-logs)
12. [CTF](#12-ctf)
13. [Command Engine](#13-command-engine)
14. [Diagnóstico y errores frecuentes](#14-diagnóstico-y-errores-frecuentes)

**Opciones globales** (van antes del comando, por ejemplo `urb --no-color red findings`):

| Opción | Efecto |
|---|---|
| `--no-color` | Sin colores (también con la variable `NO_COLOR`) |
| `--color` | Fuerza los colores aunque la salida no sea una terminal |
| `--ascii` | Usa caracteres ASCII en lugar de Unicode en los recuadros |
| `--no-anim` | Desactiva las animaciones (dashboard, God Mode, URB Red) |
| `-y`, `--yes` | Responde «sí» a las confirmaciones (uso no interactivo) |

**Códigos de salida** comunes: `0` = correcto; `1` = error de ejecución (fichero inexistente, sin laboratorio…); `2` = uso incorrecto (opción o valor inválido); `127` = falta una herramienta (nmap, python3, tmux…); `130` = cancelado con Ctrl+C.

---

## 1. Instalación y configuración

### `./install.sh`
Instala URB-Tools para tu usuario, sin root.

- **Sintaxis:** `./install.sh [--yes] [--no-deps] [--link]`
- **Parámetros:**
  - `--yes`: no pregunta nada (también acepta instalar paquetes).
  - `--no-deps`: no ofrece instalar paquetes del sistema.
  - `--link`: modo desarrollo. `urb` apunta al repositorio y los cambios se aplican al momento.
- **Requisitos:** Bash ≥ 4.4. Obligatorios: `iproute2`, `procps`, `coreutils`, `awk`, `sed`, `findutils` y `ncurses-bin`. Opcionales: `nmap`, `python3`, `tmux`, `zsh`, `fzf`, `figlet`, `curl`, `iputils-ping` y `less`.
- **Efectos:**
  - Copia la aplicación a `~/.local/lib/urb-tools`.
  - Crea los enlaces `~/.local/bin/urb` y `~/.local/bin/urb-help`.
  - Crea `~/.config/urb-tools/urb.conf` si no existe.
  - **No** modifica `.bashrc`, `.zshrc` ni ninguna otra configuración personal. Si `~/.local/bin` no está en el `PATH`, te dice cómo añadirlo.
- **Seguridad:**
  - La versión nueva se prepara y se verifica antes de sustituir la instalada. Si algo falla, se restaura la anterior.
  - Nunca sustituye un `urb` o un `urb-help` que no sean de URB-Tools: con `urb-help` ajeno, simplemente no lo instala.
- **Se puede repetir** cuando quieras: así es como se actualiza (`git pull && ./install.sh`).
- **Ejemplos:** `./install.sh` · `./install.sh --yes --no-deps` · `./install.sh --link`

### `./uninstall.sh`
- **Sintaxis:** `./uninstall.sh [--yes]`
- **Efectos:** borra los lanzadores `urb` y `urb-help` (solo si son de URB-Tools) y `~/.local/lib/urb-tools`.
- **Conserva:** `~/.config/urb-tools`, `~/.local/share/urb-tools` (escaneos y estado) y tus laboratorios (`~/urb-labs`).
- **Sesiones:** si hay una sesión de God Mode o URB Red abierta, avisa, pero **no** la cierra.

### `urb config`
Configuración del usuario: `~/.config/urb-tools/urb.conf`, que se superpone a `config/default.conf`. Solo se leen pares `CLAVE="valor"`; nada se ejecuta.

| Comando | Qué hace |
|---|---|
| `urb config` / `urb config show` | Rutas y configuración efectiva |
| `urb config path` | Rutas que usa URB-Tools |
| `urb config init` | Crea tu fichero a partir de los valores por defecto (nunca sobrescribe) |
| `urb config edit` | Lo abre en `$VISUAL`/`$EDITOR` (si no, `nano` o `vi`) |
| `urb config set CLAVE VALOR` | Cambia un valor en tu fichero (escritura atómica) |

Claves principales (valores por defecto entre paréntesis):

| Clave | Uso |
|---|---|
| `ANIMATIONS` (`1`) | Animaciones del dashboard, God Mode y URB Red |
| `REFRESH_INTERVAL` (`2`) | Segundos entre refrescos del dashboard (también `Ctrl+L`) |
| `LOGO_STYLE` (`block`), `LOGO_FONT` (`slant`) | Logo incluido o de `figlet` |
| `MENU_ENGINE` (`builtin`) | Menús propios o `fzf` |
| `START_MODE` (`dashboard`) | Qué abre `urb` sin comando: `dashboard`, `god` o `red` (§2) |
| `SCAN_DIR` (`~/.local/share/urb-tools/scans`) | Resultados de `urb scan` fuera de un laboratorio |
| `LABS_DIR` (`~/urb-labs`) | Carpeta de los laboratorios |
| `SCAN_DEFAULT_PROFILE` (`default`), `SCAN_PROFILE_<nombre>` | Perfiles de `urb scan` |
| `SCAN_STATS_EVERY` (`2s`) | Cada cuánto informa nmap de su progreso |
| `RECON_BASE` (`-T4 --open`), `RECON_MOD_<mod>` | Opciones de nmap del Command Engine (§13) |
| `SERVE_PORT` (`8000`), `SERVE_BIND` (`127.0.0.1`) | Valores por defecto de `urb serve` |
| `CHECK_PING_HOST`, `CHECK_DNS_NAME`, `CHECK_HTTP_URL` | Destinos de `urb network check` |
| `DISCOVER_PRIVATE_ONLY` (`1`) | Descubrimiento solo en redes privadas |
| `MONITOR_INTERVAL` (`2`), `MONITOR_PROCS` (`12`) | Monitor |
| `LOGS_LIMIT` (`200`) | Líneas máximas de `urb logs` |
| `GOD_HUD_POSITION` (`top`), `GOD_MOUSE` (`1`) | HUD y ratón de God Mode / URB Red. Con `1` la rueda desplaza la salida (seleccionar texto: Shift + arrastrar); con `0` la rueda envía ↑/↓ y recorre el historial de Zsh. Se aplica al abrir o reconectar |

**Precedencia:** valor explícito en el comando > tu configuración > valor por defecto.

### `urb doctor`
Comprueba Bash, sistema, terminal, UTF-8, dependencias (obligatorias y opcionales, con el paquete a instalar) y si `~/.local/bin` está en el `PATH`. Devuelve `1` si falta alguna obligatoria.

---

## 2. Dashboard y ayuda general

### `urb`
Abre URB Terminal, el **centro de control**: un dashboard con datos reales (host, SO, IP, gateway, VPN, interfaces, CPU, RAM y disco) desde el que se abren directamente, sin submenús, los entornos de terminal, las herramientas y las opciones del sistema. Qué abre `urb` sin comando lo decide `START_MODE` (por defecto, el dashboard).

| Sección | Tecla | Opción | Qué hace |
|---|---|---|---|
| TERMINAL ENVIRONMENTS | `G` | GOD MODE | Lo mismo que `urb god`: reconecta la sesión si existe o crea una nueva en el directorio actual |
| | `R` | RED MODE | Lo mismo que `urb red`: laboratorio, objetivo y HUD rojo persistentes |
| | `B` | BLUE MODE | `COMING SOON`: aparece atenuado y no se puede ejecutar |
| | `Z` | NORMAL SHELL | Tu Zsh de siempre (`zsh -i`, tu `~/.zshrc`, alias, historial), sin tema ni HUD de URB |
| CYBERSECURITY TOOLS | `1`–`5` | RECON, NETWORK, MONITOR, LOGS, CTF | Los módulos de siempre, con los mismos números |
| SYSTEM | `6` | SETTINGS | Configuración |
| | `S` | SESSIONS | Estado de GOD/RED y reconexión (como `urb sessions attach`; nunca termina sesiones) |
| | `H` | HELP | `urb help` (con `less`) |
| | `Q` / `Esc` | EXIT | Cerrar el dashboard y volver a la terminal |

- **Otras teclas:** `↑↓`/`j k` mover (BLUE se salta) · `Enter`/`→` abrir · `Ctrl+L` refrescar datos. Las letras valen en mayúscula o minúscula.
- **Volver al dashboard:** al salir de lo que abriste vuelves al menú, no se cierra la terminal.

  | Desde | Acción | Resultado |
  |---|---|---|
  | GOD / RED | `Ctrl+B d` (detach) | Vuelves al menú; la sesión y sus programas **siguen en marcha** (el menú marca `● detached`). Su tecla reconecta la misma sesión. |
  | GOD / RED | `exit` / `Ctrl+D` en la última shell | La sesión termina; vuelves al menú. La próxima vez se crea una nueva. |
  | GOD / RED | error al arrancar (falta tmux, servidor caído…) | Se muestra el error, *Press any key to return to the URB dashboard* y vuelves al menú. |
  | NORMAL SHELL | `exit` | Vuelves al menú. |

- **Sesiones conectadas en otra terminal:** si GOD/RED ya está abierto en otra ventana, el dashboard se une como un cliente más (igual que `urb god`): no la desconecta ni se la apropia. Al salir, el menú indica `attached` (sigue conectada allí).
- **Dentro de tmux:** si `urb` se ejecuta dentro de otra sesión tmux, GOD/RED no se abren (no se anidan) y el menú explica por qué; la Zsh normal y las herramientas siguen disponibles.
- **Terminal:** antes de abrir GOD, RED, la Zsh o la ayuda, el dashboard sale por completo de su pantalla (pantalla principal, cursor visible, `stty` original). Al volver, tras GOD/RED desactiva los modos de informe de ratón que tmux pudiera haber dejado, restaura el `stty` y descarta teclas pendientes. `Ctrl+C`, `Ctrl+\` y `Ctrl+Z` en un programa abierto llegan a ese programa; el dashboard sigue vivo. En el propio menú, `Ctrl+C` sale (código `130`) restaurando la terminal y `Ctrl+Z` se ignora.
- **Tamaño:** mínimo 50×12. Alineado arriba a la izquierda; con poco alto se ocultan primero los paneles de información y el menú se desplaza (indicadores `↑ more` / `↓ more`) en lugar de recortar opciones. Desde 100 columnas, menú y paneles lado a lado.
- **Requisitos:** una terminal interactiva. Sin terminal, termina con el código `1` y sugiere comandos no interactivos. GOD/RED necesitan `tmux` ≥ 3.0 y `zsh`; la Zsh normal, `zsh`.
- **Alias:** `urb dashboard` (abre siempre el menú, sea cual sea `START_MODE`), `urb tui`.

### Modo de inicio (`START_MODE`)

```bash
urb config set START_MODE dashboard   # por defecto: el menú principal
urb config set START_MODE god         # 'urb' entra directamente en GOD (como 'urb god')
urb config set START_MODE red         # 'urb' entra directamente en RED (como 'urb red')
```

- Con `god`/`red`, un detach o un `exit` te devuelven a tu terminal (igual que `urb god`/`urb red`); `urb dashboard` sigue abriendo el menú.
- Si el entorno no puede abrirse (falta tmux, estás dentro de otro tmux…), se informa y se abre el dashboard con el motivo en la línea de estado.
- `urb config set` solo acepta `dashboard`, `god` o `red` (código `2` en otro caso; `blue` aún no está disponible). Si el fichero contiene otro valor (editado a mano), `urb` lo indica y abre el dashboard. El valor es un dato: nunca se ejecuta.

### `urb help` · `urb-help`
- **Sintaxis:** `urb help [tema [sección]]`. Es equivalente a `urb-help [tema [sección]]`: `urb-help` es solo un acceso directo que ejecuta `urb help` (misma ayuda, sin duplicados).
- **Temas:** `scan`, `network`, `monitor`, `logs`, `ctf`, `config` (también `doctor`), `god`, `red`, `sessions`, `serve` y `manual`.
- **Secciones de `red`:** `shell`, `lab`, `target`, `recon`, `scans`, `services`, `findings`, `notes` y `context`.
- **Ejemplos:** `urb help red scans` · `urb-help red recon` · `urb-help serve`
- **Error:** con un tema inexistente devuelve el código `2` y la lista de temas.

### `urb manual`
- **Sintaxis:** `urb manual [commands|examples|path]`
- **Efecto:** abre este manual (o `EXAMPLES.md`) con `less`. Si no hay terminal o falta `less`, muestra la ruta del fichero. `path` imprime las dos rutas.
- **Alias:** `urb man`.

### `urb version`
Muestra `URB-Tools <versión>`.

---

## 3. God Mode

### `urb god`
Convierte la ventana de terminal en un espacio de trabajo avanzado: una **Zsh real** (carga tu `~/.zshrc` sin modificarlo) dentro de un tmux propio, con HUD (CPU, RAM, IP, VPN, Git) y prompt URB.

| Comando | Efecto |
|---|---|
| `urb god` | Activa God Mode o reconecta con la sesión existente |
| `urb god --no-anim` | Sin animaciones |
| `urb god --status` | ¿Hay una sesión abierta? Muestra sus paneles |
| `urb god --kill [--yes]` | Termina la sesión (pregunta si hay programas en marcha) |
| `urb god --check` | Comprueba `tmux` (≥ 3.0) y `zsh` |
| `urb god --help` | Ayuda |

- **Requisitos:** `tmux` ≥ 3.0 y `zsh`. Sin ellos, el código de salida es `127` y el resto de URB-Tools funciona igual.
- **Dentro de God Mode:**
  - `exit` cierra la shell. Si era la última, la sesión termina.
  - `Ctrl+B d` **desconecta**: los programas siguen ejecutándose y `urb god` vuelve a ellos. Cerrar la ventana tiene el mismo efecto.
  - `Ctrl+B c` abre una ventana nueva, y `Ctrl+B %` / `Ctrl+B "` dividen el panel.
- **Al salir**, URB dice cómo terminó la conexión: «Detached», «Session ended…» (exit, Ctrl+D o cierre) o «tmux server ended unexpectedly» (código `1`).
- **Aislamiento:** servidor tmux propio (socket `urb-god`), que nunca lee tu `~/.tmux.conf`. Si ya estás dentro de otro tmux, se niega a anidarse (código `1`).
- **Ficheros:**
  - Lee `godmode/` y la caché de CPU del HUD (`$XDG_RUNTIME_DIR/urb-god-$UID/`).
  - No escribe en tu configuración.
  - El historial de comandos va a tu `HISTFILE` habitual.
- **Configuración:** `GOD_HUD_POSITION`, `GOD_MOUSE` y `ANIMATIONS`.
- **Ratón** (`GOD_MOUSE=1`, por defecto): la rueda desplaza la salida del panel (vuelves al prompt al bajar del todo o con `q`); en programas a pantalla completa (`less`, `vim`) les llega como flechas. Para seleccionar texto con QTerminal: **Shift + arrastrar**.
- **Relacionados:** `urb red` y `urb sessions`.

---

## 4. URB Red

### `urb red`

Dentro de la shell del perfil RED se pueden usar estos comandos contextuales,
con los mismos argumentos, opciones, salida y códigos que la CLI completa:

| Comando corto | Equivalente |
|---|---|
| `scan ...` | `urb red recon ...` |
| `recon ...` | `urb red recon ...` |
| `services ...` | `urb red services ...` |
| `scans ...` | `urb red scans ...` |
| `findings ...` | `urb red findings ...` |
| `notes ...` | `urb red notes ...` |
| `target ...` | `urb red target ...` |
| `lab ...` | `urb red lab ...` |
| `status ...` | `urb red status ...` |
| `report ...` | `urb red report ...` |

Por ejemplo, `scan quick versions --dry-run`, `findings show F-001` y
`lab use demo`. Los atajos admiten el mismo autocompletado que `urb red`.
Si un nombre ya es un comando, alias, función o reservado de Zsh, RED lo
conserva y avisa: utiliza la sintaxis completa indicada en el aviso. Fuera de
RED no se instalan estos atajos. `urblab` sigue cambiando el directorio de la shell.

### Flujo de investigación RED v0.2

`urb red findings link F-001 --service 8080` vincula el hallazgo con una
observación del inventario. Si el puerto es ambiguo, especifica
`host:puerto/protocolo`. `urb red findings show F-001` muestra las claves y
`urb red findings unlink F-001 --service host:puerto/protocolo` elimina el
vínculo incluso si la observación ya no está disponible. La relación conserva
solo la clave, no copia datos del servicio ni implica una vulnerabilidad.

`urb red scans diff S-001 S-003` compara los XML existentes sin escanear: muestra
hosts, cambios explícitos de estado, servicio y versión, y puertos no observados.
Una ausencia no equivale a cerrado; perfiles distintos o resultados parciales
limitan la comparación.

`urb red report preview` muestra Markdown basado en los datos del laboratorio.
`urb red report generate [--output <ruta>]` crea un informe nuevo: por defecto
en `reports/` con nombre temporal único. Nunca sobrescribe un destino existente
ni el `report.md` editable. Los informes y la comparación requieren Python 3
con su biblioteca estándar y no hacen conexiones de red.
Perfil para laboratorios sobre la misma infraestructura de God Mode:

- Tema rojo y etiqueta `URB RED`.
- HUD con laboratorio, objetivo, VPN e IP (y CPU, RAM y sesiones activas en ventanas anchas).
- Prompt `╭─[RED]─[lab ▸ objetivo]─[ruta]`.
- Sesión tmux **propia** (socket `urb-red`): no interfiere con God Mode.

| Comando | Efecto |
|---|---|
| `urb red` | Abre URB Red o reconecta |
| `urb red --no-anim` | Sin animaciones |
| `urb red --kill [--yes]` | Termina la sesión de URB Red (God Mode no se ve afectado) |
| `urb red --session` | Estado de la sesión |
| `urb red --check` | Dependencias |
| `urb red status` | Laboratorio (y de dónde sale), ruta, objetivo, escaneos (último completo), resumen de hallazgos, VPN y sesión |

- **`urblab [nombre]`:** función de la Zsh de RED que cambia el directorio **de esa misma shell** al laboratorio (el del directorio actual, el seleccionado o el indicado). Fuera de RED no existe.
- **Contexto:** el laboratorio sale del **directorio actual** (un `.urb-lab` en él o en un padre) y, si no hay, del **seleccionado** con `urb red lab use`.
- **Requisitos:** los de God Mode para la shell; `nmap` para `recon` y `python3` para `services`.
- **Relacionados:** las secciones 5 a 9.

---

## 5. Laboratorios y objetivos

Un laboratorio es una carpeta con `scans/`, `exploits/`, `evidence/`, `notes/notes.md`, `report.md` y el marcador `.urb-lab` (`name=`, `created=`, `target=`). `urb ctf` y `urb red` comparten laboratorios.

### `urb red lab new <nombre> [--target <ip|host>] [--dir <base>]`
- **Efectos:** crea el laboratorio en `LABS_DIR` (`~/urb-labs` por defecto) o en `--dir`, y **lo selecciona** (`~/.local/share/urb-tools/state/active-lab`).
- **Si ya existe**, completa lo que falte sin sobrescribir nada. Si ya tenía un objetivo distinto, lo **conserva** y avisa.
- **Nombre:** letras, números, `.`, `_` y `-`, con un máximo de 64 caracteres (sin `..`). Un nombre o un objetivo no válidos devuelven el código `2`.
- **Ejemplo:** `urb red lab new htb-lame --target 10.10.10.3`

### `urb red lab use <nombre>` · `urb red lab list` · `urb red lab path [<nombre>]`
- `use`: selecciona un laboratorio existente. Si no existe, devuelve `1`.
- `list`: lista los laboratorios con su objetivo y número de escaneos, e indica cuál está seleccionado. Avisa si la selección ya no es válida.
- `path`: imprime la ruta del laboratorio actual o del indicado (es lo que usa `urblab`).

### `urb red target set <ip|host>` · `urb red target show`
- **Efecto de `set`:** guarda el objetivo principal en el `.urb-lab` del laboratorio actual, con escritura atómica y conservando las demás claves.
- **Valores admitidos:** IPv4, IPv6, CIDR, rango (`10.0.0.1-20`) o nombre de host. Nada que empiece por `-`.
- **`show`:** sin objetivo, devuelve `1`.
- **Ejemplo:** `urb red target set 10.10.10.3`

---

## 6. Reconocimiento

### `urb scan <objetivo> [opciones]`
Escaneo nmap con perfiles, progreso **real** (el que informa nmap) y resultados guardados.

| Opción | Valor por defecto | Efecto |
|---|---|---|
| `-P`, `--profile <nombre>` | `default` (`SCAN_DEFAULT_PROFILE`) | Perfil `SCAN_PROFILE_<nombre>` |
| `-p`, `--ports <spec>` | — | `22` · `22,80` · `1-1024` |
| `-o`, `--output <dir>` | la carpeta `scans/` del laboratorio actual o `SCAN_DIR` | Carpeta de resultados |
| `--no-save` | — | No conserva ficheros |
| `--sudo` | — | Ejecuta nmap con sudo sin preguntar |

- **Subcomandos:** `urb scan profiles` (perfiles configurados) y `urb scan results` (resultados guardados).
- **Perfiles por defecto:**
  - `quick` (`-T4 -F --open`)
  - `default` (`-sV -T4 --open`)
  - `full` (`-sV -sC -p- -T4 --open`)
  - `stealth` (`-sS -T3 --open`)
  - `udp` (`-sU --top-ports 50 -T4 --open`)
  - `os` (`-O -sV -T4 --open`)

  `stealth` es un escaneo SYN (`-sS`): **no** hace el escaneo indetectable.
- **Root:** los perfiles con `-sS`, `-sU` u `-O` lo necesitan. URB pregunta si usar sudo (o usa `--sudo`), y solo nmap se ejecuta como root.
- **Ficheros:** `<objetivo>_<perfil>_<AAAAMMDD-HHMMSS>.{nmap,xml,gnmap}`. Dos escaneos en el mismo segundo no se sobrescriben (sufijo `-2`). El `.log` solo se conserva si nmap falla.
- **Errores:** sin objetivo, con un objetivo, perfil o puertos inválidos → `2`; falta nmap → `127`; Ctrl+C → `130` (los resultados parciales quedan guardados).
- **Ejemplos:** `urb scan 10.10.10.5 --profile quick` · `urb scan 192.168.56.0/24 -p 22,80,443`

### `urb red recon initial [--target <ip|host>]`
- **Efecto:** ejecuta el perfil `default` (`-sV`) contra el objetivo del laboratorio y guarda los resultados en su carpeta `scans/`.
- **Antes de escanear** muestra el laboratorio, el objetivo y su procedencia. **Después**, el diagnóstico y el ID `S-NNN` del escaneo.
- **`--target`** se usa solo en esa ejecución: no cambia el objetivo guardado.
- **Errores:** sin laboratorio o sin objetivo → `1`; objetivo inválido → `2`.

### `urb red recon <modificador>... [--target <ip|host>] [--sudo] [--dry-run]`
Reconocimiento con el **Command Engine**: los modificadores se combinan en cualquier orden. Detalle completo en la [§13](#13-command-engine).

### Diagnóstico de escaneos
Cuando nmap falla o no encuentra el host, `recon` añade un bloque **DIAGNOSIS** basado solo en lo que nmap ya ha escrito (sin pings ni reintentos):

- `confirmed`: nmap lo ha informado explícitamente. Casos reconocidos: nombre no resoluble (falta la entrada en `/etc/hosts`), se necesita root, red inalcanzable.
- `possible`: es una hipótesis. Por ejemplo, «Host seems down» **no** demuestra que el host esté apagado: puede bloquear el ping o la VPN puede estar caída (prueba `nmap -Pn <objetivo>`).
- `unknown`: causa no reconocida; indica la ruta del `.log`.

---

## 7. Scan Manager

### `urb red scans [list]`
- **Muestra:** los escaneos del laboratorio con su ID estable (`S-001`…), fecha, objetivo, perfil (o combinación de modificadores), estado y ficheros.
- **Estados:**
  - `complete`: terminó correctamente.
  - `incomplete`: se interrumpió (el XML no tiene `<finished>`).
  - `failed`: nmap dio un error.
  - `partial`: faltan ficheros.
  - `missing`: ya no existen sus ficheros, pero el ID se conserva.
- **Ficheros:** el índice es `<lab>/scans/.index` (`S-NNN|base|epoch`) y solo crece. Los escaneos que ya existían se indexan la primera vez por orden temporal.
- **Hora:** la del nombre del fichero; si no la hay, la de `start=` del XML; como último recurso, la fecha de modificación.
- **Recuperación:** las líneas dañadas del índice se ignoran con un aviso. Si se borra el índice, se reconstruye desde los ficheros, **pero los IDs pueden no coincidir con los anteriores**. Las evidencias guardan rutas, no IDs, así que no se rompen.
- **Nunca ejecuta nmap.**

### `urb red scans show [latest|S-NNN]`
Muestra la fecha, el objetivo, el perfil, el estado, los ficheros con su tamaño y la tabla de puertos del escaneo.

- `latest` es el escaneo **completo** más reciente: los interrumpidos o fallidos no cuentan.
- Errores: referencia inválida → `2`; ID inexistente o ningún escaneo completo → `1`.

---

## 8. Inventario de servicios

### `urb red services [list] [--all]` · `urb red services show <ref>` · `urb red services refresh`
- **Qué es:** el inventario de lo que nmap observó, construido a partir de los **XML** de nmap (la única fuente de verdad).
- **Analizador:** Python 3 con solo la biblioteca estándar. Solo lee ficheros: **no genera tráfico de red**.
- **Qué muestra:**
  - Por defecto, solo los puertos `open`; `--all` incluye todos los estados.
  - Una fila por `host + puerto + protocolo` (TCP y UDP por separado), con la **observación más reciente**.
  - Si un escaneo posterior vio el puerto cerrado, deja de aparecer como abierto. Si un escaneo posterior no lo incluyó, **no** se da por cerrado.
  - Los datos que nmap no informó aparecen como `unknown`. Una `*` indica que vienen de un escaneo parcial o incompleto.
- **`show <ref>`:** `8080`, `8080/udp`, `10.10.10.3:8080` o `10.10.10.3:8080/tcp`. Muestra el estado actual (y de qué escaneo sale), la versión, cuándo se vio por primera vez y el historial (`S-001=open S-003=closed`).
- **Caché `<lab>/scans/.services`:**
  - Se reconstruye **solo** al ejecutar `urb red services` y solo si cambió algún XML o el índice. `refresh` la fuerza.
  - Si el analizador falla, se conserva el inventario anterior.
- **XML defectuosos:** un XML truncado aporta los hosts completos que se llegaron a leer; uno inválido se ignora con un aviso. Ninguno afecta a los demás.
- **No es un hallazgo:** un puerto abierto es inventario, nunca crea un finding automáticamente.
- **Errores:** falta `python3` → `127`; referencia inválida → `2`; servicio inexistente → `1`.

---

## 9. Findings, notas y evidencias

Ficheros: `<lab>/findings/F-NNN.finding`, uno por hallazgo, en formato `clave=valor` que se lee como datos; `findings/.seq` (contador) y `notes/notes.md` (notas generales).

### `urb red findings [list]`
Lista compacta con el ID, el estado y el título, más un resumen (`3 findings · 1 pending · …`). Los ficheros dañados aparecen como `damaged`.

### `urb red findings add "<título>" [--desc "<texto>"] [--status <estado>]`
- **Efecto:** crea `F-NNN` con un ID estable y monótono: los números borrados no se reutilizan mientras `.seq` esté íntegro.
- **Concurrencia:** está protegido; un hallazgo nuevo nunca sobrescribe otro.
- **Textos:** el título admite hasta 120 caracteres y la descripción hasta 1000. No se admiten saltos de línea, tabuladores ni otros caracteres de control (código `2`).

### `urb red findings show F-NNN`
Muestra el estado, las fechas, el laboratorio, la descripción, las notas con hora, las evidencias (marcando las ausentes) y el historial de cambios de estado.

### `urb red findings status F-NNN <estado>`

| Estado | Significado |
|---|---|
| `pending` | Pendiente de revisar |
| `investigating` | En curso |
| `suspected` | Hipótesis: hay indicios, sin verificar (alias `potential`) |
| `confirmed` | Verificado con evidencia. **No implica necesariamente una vulnerabilidad** |
| `discarded` | Hipótesis comprobada y refutada |
| `checked` | Comprobación realizada sin hallazgo (alias `completed`) |

Cada cambio queda en el historial. Un estado inválido devuelve `2`, y repetir el estado actual no cambia nada.

### `urb red findings note F-NNN "<texto>"`
Añade una nota con marca temporal al hallazgo (hasta 1000 caracteres, de una línea).

### `urb red findings evidence F-NNN <fichero>` · `… --scan <latest|S-NNN>`
- **Qué guarda:** una **referencia** al fichero, nunca una copia. URB no lo lee, ejecuta, mueve ni modifica.
- **Reglas de ruta:**
  - El fichero debe existir, ser un fichero normal y estar **dentro del laboratorio**.
  - Una ruta relativa se busca primero desde el directorio actual y después desde la raíz del laboratorio.
  - Se resuelven los enlaces simbólicos: los que salen del laboratorio y las rutas externas se rechazan (código `2`). Si necesitas un fichero de fuera, cópialo antes a `evidence/`.
- **`--scan`:** asocia el `.nmap` del escaneo indicado; `latest` es el último escaneo completo.
- **Duplicados:** se detectan aunque se escriban de otra forma; se informa y no se añaden.
- **Ejemplos:** `urb red findings evidence F-001 --scan latest` · `urb red findings evidence F-001 evidence/http.txt`

### `urb red notes` · `urb red notes add "<texto>"` · `urb red notes edit`
- Notas generales del laboratorio en `notes/notes.md`, el mismo fichero que crea `urb ctf`.
- `add` añade `- AAAA-MM-DD HH:MM:SS  texto` sin perder lo que ya había (escritura atómica).
- `edit` abre el fichero en tu editor.

### Integridad y concurrencia
- **Escrituras:** todas son atómicas y protegidas por un bloqueo del laboratorio (`<lab>/.urb-lock`). Los bloqueos abandonados se detectan y se liberan, y si el bloqueo está ocupado, URB espera unos 10 s antes de fallar con un mensaje claro.
- **Ficheros dañados:** se muestran, pero no se modifican.
- **Claves desconocidas:** se conservan (por ejemplo `port=` o `service=`, reservadas para futuras integraciones).

---

## 10. Sesiones tmux

### `urb sessions [list]`
- **Muestra:** una tabla de los perfiles (`god`, `red`) con su estado, ventanas, paneles, clientes y socket.
- **Estados:**
  - `attached`: con una terminal conectada.
  - `detached`: en segundo plano; los programas siguen.
  - `none`: no hay sesión.
  - `error`: tmux no ha respondido (se muestra el mensaje).
- **Consultar nunca crea sesiones.**

### `urb sessions info <god|red>` · `urb sessions attach <god|red> [--no-anim]` · `urb sessions kill <god|red> [--yes]`
- `info`: muestra la hora de creación, los paneles (comando y directorio) y los clientes conectados.
- `attach`: **solo reconecta**. Si no hay sesión, devuelve `1` y no crea ninguna.
- `kill`: pide confirmación **siempre** (salvo `--yes`) y solo cierra la sesión de ese perfil.

---

## 11. Network, Monitor y Logs

### `urb network [acción]`

| Acción | Efecto |
|---|---|
| `summary` (por defecto) | Nombre de host, IP, gateway, VPN, DNS e interfaces |
| `interfaces` | Estado, MAC, IPv4 e IPv6 |
| `routes` · `gateway` | Tabla de rutas · gateway y si responde |
| `connections [--listen\|--established]` | Sockets TCP/UDP (`ss`) |
| `discover [<CIDR>] [--sudo] [--force]` | `nmap -sn`. Solo redes privadas y prefijos de `/16` o más, salvo `--force`. Sin CIDR, usa tu red local. `--sudo` permite el descubrimiento ARP |
| `ping <host> [-c N]` | Conectividad (de 1 a 100 paquetes) |
| `check` | Gateway, Internet, DNS y HTTPS (destinos configurables) |

### `urb monitor`
- `urb monitor`: monitor a pantalla completa (`q` para salir, `s` para ordenar por CPU o memoria). Admite `--interval N` y `--procs N`.
- `urb monitor --once`: una instantánea en texto.
- `urb monitor procs [-n N]`: procesos que más CPU consumen.

El `%CPU` de los procesos es la media durante toda su vida (`ps`), no el consumo instantáneo.

### `urb logs [acción] [filtros]`
- **Acciones:** `summary` (por defecto), `auth`, `ssh`, `errors` y `search`.
- **Filtros:**
  - `--since` y `--until`: `AAAA-MM-DD`, `"AAAA-MM-DD HH:MM"`, `today` o `yesterday`.
  - `--user`, `--ip` y `--grep` (texto literal, sin distinguir mayúsculas).
  - `-n N`: las últimas N coincidencias.
  - `--file RUTA`: analiza un log concreto.
  - `--sudo`: lee los logs con sudo, solo para leerlos.
- **Fuentes:** `/var/log/auth.log` y `syslog`, o journald.
- **Permisos:** para leer los logs del sistema sin sudo hay que estar en el grupo `adm` o `systemd-journal`.

---

## 12. CTF

### `urb ctf new <nombre> [--dir BASE] [--target IP]` · `urb ctf list [--dir BASE]` · `urb ctf path <nombre>`
- Crea la estructura de laboratorio (la misma de la §5), pero **no** la selecciona: para eso está `urb red lab use`.
- `path` permite entrar en el laboratorio: `cd "$(urb ctf path box)"`.
- Si dentro de un laboratorio ejecutas `urb scan`, los resultados van a su carpeta `scans/`.

---

## 13. Command Engine

Capa de productividad. Los comandos se describen como **datos** en `commands/*.spec`, de los que salen el análisis de argumentos, la validación, la ayuda (`urb help red recon`, `urb help serve`) y el autocompletado.

**Reglas comunes:**
- Los **modificadores** (palabras sin `--`) van en cualquier orden y se normalizan al orden de la especificación: `quick versions` = `versions quick`, que generan **exactamente** el mismo comando.
- Un modificador desconocido, repetido o incompatible con otro devuelve el código `2` con un mensaje claro.
- Las **opciones con valor** se escriben siempre como `--opción valor`: `--opción=valor` se rechaza con una pista.
- **Precedencia:** valor explícito > tu configuración > valor por defecto.

### `urb red recon <modificador>... [--target <ip|host>] [--sudo] [--dry-run]`

| Modificador | Grupo | Opciones de nmap (configurables) | Notas |
|---|---|---|---|
| `quick` | ports | `RECON_MOD_quick="--top-ports 100"` | Primer vistazo rápido |
| `full` | ports | `RECON_MOD_full="-p-"` | Los 65535 puertos TCP (lento) |
| `udp` | ports | `RECON_MOD_udp="-sU --top-ports 50"` | Escanea UDP **en lugar de** TCP; necesita root |
| `versions` | — | `RECON_MOD_versions="-sV"` | Servicios y versiones |
| `scripts` | — | `RECON_MOD_scripts="-sC"` | Scripts NSE por defecto |
| `os` | — | `RECON_MOD_os="-O"` | Detección de sistema operativo; necesita root |
| `slow` | — | `RECON_MOD_slow="-T2"` | Menos carga sobre el objetivo. **No** es más sigiloso ni indetectable |

- **Base:** `RECON_BASE="-T4 --open"`. Cada modificador añade sus opciones.
- **`slow`** (o cualquier modificador con `-T`) **sustituye** el `-T` de la base: nunca hay dos `-T`.
- **Grupo `ports`:** `quick`, `full` y `udp` eligen qué puertos se escanean, así que solo se puede usar uno (`quick full` → error `2`).
- **Comprobación final:** aunque edites la configuración, si el resultado tuviera dos `-T` o dos selecciones de puertos, se rechaza.
- **Seguridad de la configuración:** las opciones se validan con las mismas reglas que los perfiles (nada de `-o*` ni `-i*`). URB construye el comando como un array, sin `eval`, y no hay ninguna opción pública para pasar texto libre a nmap.
- **Opciones:**
  - `--target <ip|host>`: solo para esa ejecución; por defecto se usa el objetivo del laboratorio.
  - `--sudo`: no pregunta al usar `os` o `udp`.
  - `--dry-run`: muestra el comando **exacto** (construido por la misma función que la ejecución real), el objetivo y la ruta de salida. **No** ejecuta nada, no crea ficheros y no genera tráfico.
- **Resultados:** en `<lab>/scans/<objetivo>_<modificadores>_<fecha>.*` (por ejemplo `10.10.10.3_quick-versions_…`). Reciben un ID `S-NNN` y aparecen en `scans` y `services`.
- **Sin modificadores**, muestra la ayuda. `recon initial` sigue funcionando igual.
- **Ejemplos:**
  ```bash
  urb red recon quick versions
  urb red recon versions quick --dry-run      # mismo comando que el anterior
  urb red recon full versions scripts
  urb red recon slow versions --target 10.10.10.30
  urb red recon udp --sudo
  ```

### `urb serve [--port <puerto>] [--bind <ip>] [--dir <directorio>] [--yes]`
Servidor HTTP con el `http.server` de la biblioteca estándar de Python.

| Opción | Por defecto | Configuración | Notas |
|---|---|---|---|
| `--port` | `8000` | `SERVE_PORT` | 1–65535. Los puertos por debajo de 1024 necesitan root: URB lo rechaza y sugiere otro (código `2`) |
| `--bind` | `127.0.0.1` | `SERVE_BIND` | IPv4, IPv6 o `localhost`. Una dirección **no local** expone los ficheros a la red y pide confirmación |
| `--dir` | `.` | — | Directorio que se comparte |
| `--yes` | — | — | Autoriza de forma explícita una dirección no local, sin preguntar |

- **Efectos:** muestra el directorio, la URL y el comando, y registra en pantalla cada petición. Ctrl+C lo detiene con «Server stopped» (código `0`).
- **Lo que no hace:** tocar el firewall, usar root o instalar nada.
- **Errores:**
  - Puerto ocupado: lo comprueba antes de arrancar y sugiere otro puerto (código `1`).
  - Dirección que no existe en la máquina (`1`) o directorio inexistente (`1`).
  - Falta `python3` (`127`) o algún valor no es válido (`2`).
  - Respondes «no» a la confirmación (`1`).
- **Ejemplos:** `urb serve` · `urb serve --port 8080` · `urb serve --dir ~/urb-labs/demo/exploits --port 9000`

### Autocompletado (Zsh, dentro de God Mode y URB Red)
- **Qué completa:** `urb <Tab>`, `urb red <Tab>`, los modificadores de `recon` (leídos del `.spec`), los IDs `F-NNN`, `--scan latest|S-NNN`, los puertos de `services show`, las opciones de `serve`, los temas de `help` y las secciones de `help red`.
- **Coste:** solo lee ficheros de índice con Zsh nativo. Nunca ejecuta nmap, no analiza XML y no lanza procesos.

---

## 14. Diagnóstico y errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `urb: command not found` | `~/.local/bin` no está en el `PATH` | Añádelo a `~/.zshrc` (o a `~/.bashrc`) como indica el instalador, o usa `~/.local/bin/urb` |
| `No lab: you are not inside a lab and none is selected` | Falta el contexto de laboratorio | `urb red lab new <nombre> --target <ip>` o `urb red lab use <nombre>` |
| `selected lab is no longer valid` | Se borró o movió el laboratorio seleccionado | `urb red lab list` y luego `urb red lab use <otro>` |
| `Lab … has no target` | El laboratorio no tiene objetivo | `urb red target set <ip>` o `--target <ip>` |
| `Invalid target` / `Invalid value for --port` | Valor con un formato no admitido | Revisa la sintaxis con `urb help …` |
| `'quick' and 'full' cannot be combined` | Dos modificadores del grupo `ports` | Elige solo uno de `quick`, `full` y `udp` |
| `These options need root` | `os` o `udp`, o perfiles con `-sS`/`-O` | Responde «sí» a sudo o añade `--sudo` |
| `nmap is not installed` / `python3 is required` | Falta la herramienta | `sudo apt install nmap` / `python3` |
| DIAGNOSIS `possible: Host seems down` | El host no respondió al descubrimiento | No está confirmado: revisa la VPN y prueba `nmap -Pn <objetivo>` |
| `no complete scan in this lab` | Solo hay escaneos interrumpidos o fallidos | Repite el escaneo |
| `… is outside the lab` (evidencia) | La ruta o el enlace sale del laboratorio | Copia el fichero a `<lab>/evidence/` |
| `the lab is locked by another URB command` | Otro comando URB está escribiendo | Espera y vuelve a intentarlo (los bloqueos abandonados se liberan solos) |
| `F-NNN is damaged` | Fichero editado a mano con un formato inválido | Corrígelo a mano: URB no lo modifica |
| `Port … is already in use` (`urb serve`) | Otro programa usa el puerto | `urb serve --port <otro>` |
| God Mode: `You are inside another tmux session` | God Mode y URB Red no se anidan | Desconéctate (`Ctrl+B d`) y vuelve a ejecutarlo |
| `[exited]` al salir de God Mode o URB Red | Terminó la última shell (exit/Ctrl+D) o se cerró la sesión | Para conservar los programas, desconéctate con `Ctrl+B d` |
| `tmux server ended unexpectedly` | El servidor tmux murió estando conectado | Es un error real: `urb sessions` y vuelve a abrir el perfil |
| Dashboard: `… cannot start inside another tmux session` | Abriste `urb` dentro de otro tmux | Desconéctate de ese tmux (`Ctrl+B d`) y abre `urb` de nuevo; la Zsh normal y las herramientas funcionan igualmente |
| `Invalid START_MODE …` al abrir `urb` | Valor no admitido en tu configuración | `urb config set START_MODE dashboard` (se abre el dashboard mientras tanto) |
| La rueda del ratón recorre el historial en lugar de desplazar la salida | Dentro de GOD/RED: el ratón de tmux está desactivado (`GOD_MOUSE=0`). tmux ocupa la pantalla alternativa, donde QTerminal convierte la rueda en ↑/↓ (confirmado en QTerminal). Fuera de tmux: la terminal se quedó en la pantalla alternativa | `urb config set GOD_MOUSE 1` y vuelve a abrir o reconectar la sesión. Fuera de tmux: `tput rmcup` (o `printf '\e[?1049l'`), o `reset` |
| No puedo seleccionar texto con el ratón dentro de GOD/RED | Con `GOD_MOUSE=1` el ratón lo gestiona tmux | Mantén **Shift** mientras arrastras (selección de QTerminal) |
| No puedo leer los logs | Tu usuario no está en `adm`/`systemd-journal` | `--sudo` o `sudo usermod -aG adm $USER` (y vuelve a iniciar sesión) |

Diagnóstico general: `urb doctor`, `urb god --check`, `urb sessions` y `urb red status`.
