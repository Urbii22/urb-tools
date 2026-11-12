# URB-Tools — URB Terminal

```
██╗   ██╗██████╗ ██████╗
██║   ██║██╔══██╗██╔══██╗
██║   ██║██████╔╝██████╔╝
██║   ██║██╔══██╗██╔══██╗
╚██████╔╝██║  ██║██████╔╝
 ╚═════╝ ╚═╝  ╚═╝╚═════╝   CYBERSECURITY TOOLKIT
```

Suite modular de ciberseguridad para **Kali Linux** escrita en **Bash**, con un
dashboard TUI propio (**URB Terminal**). No sustituye a Zsh, Bash ni a tu emulador
de terminal: es una aplicación independiente que se abre con `urb`.

> Úsala solo contra sistemas propios o con autorización explícita por escrito.

---

## Características (v0.1.0 — Fase 1)

| Módulo | Estado | Qué hace |
|---|---|---|
| **Dashboard** (`urb`) | ✅ operativo | Logo, host/usuario, SO, kernel, uptime, IP local, gateway, VPN (tun/wg/…), interfaces, CPU/RAM/disco con barras, menú con teclado. Se adapta al tamaño de la terminal y se refresca solo. |
| **RECON** (`urb scan`) | ✅ operativo | Nmap con perfiles configurables, puertos abiertos en vivo, progreso **real** de nmap (`--stats-every`), tabla de puertos/servicios/versiones y resultados en `.nmap`, `.xml` y `.gnmap`. Ctrl+C cancela limpio. |
| **NETWORK** (`urb network`) | ✅ operativo | Resumen, interfaces (MAC/IPv4/IPv6), rutas, gateway, conexiones (`ss`), descubrimiento de hosts (`nmap -sn`, solo redes privadas salvo `--force`), ping y chequeo de conectividad. |
| **MONITOR** (`urb monitor`) | ✅ operativo | Monitor a pantalla completa: CPU total y por núcleo, RAM, swap, discos y procesos (ordenar por CPU/MEM). `--once` para una instantánea. |
| **LOGS** (`urb logs`) | ✅ v1 | Fallos de autenticación, eventos SSH, errores del sistema y búsqueda por fechas, usuario, IP o texto. Lee `auth.log`/`syslog` o journald. Resumen con top de IPs y usuarios. |
| **CTF** (`urb ctf`) | ✅ operativo | Crea laboratorios `scans/ exploits/ evidence/ notes/ report.md`. Si ejecutas `urb scan` dentro de un laboratorio, los resultados van a su `scans/`. |
| **URB Red** (`urb red`) | ✅ v0.1 | Perfil para laboratorios sobre God Mode: tema rojo; HUD y prompt con laboratorio, objetivo y VPN; objetivo persistente; `recon initial` con diagnóstico de errores; registro de hallazgos y notas. Ver [URB Red](#urb-red-urb-red--v01) y [Hallazgos](#hallazgos-y-notas-urb-red-findings--urb-red-notes). |
| **God Mode** (`urb god`) | ✅ v1 | Zsh real dentro de un tmux aislado en la misma ventana, con HUD (CPU, RAM, IP, VPN, Git), prompt URB y animaciones de entrada y salida. Ver [God Mode](#god-mode-urb-god). |
| **SETTINGS** (`urb config`) | ✅ operativo | Ver/editar configuración, activar/desactivar animaciones, motor de menús (propio o `fzf`), `urb doctor`. |

Nada de lo que aparece en pantalla es simulado: todos los datos salen de `/proc`, `ip`, `ss`, `df`, `ps`, nmap o los logs reales.

---

## Requisitos

- Kali Linux (o cualquier Debian/Ubuntu) con **Bash ≥ 4.4**.
- Obligatorios (vienen en Kali): `iproute2` (`ip`, `ss`), `procps`, `coreutils`, `awk`, `ncurses-bin` (`tput`).
- Opcionales: `nmap` (RECON y descubrimiento), `fzf`, `figlet`, `curl`, `iputils-ping`, `less`. Para God Mode: `tmux` (≥ 3.0) y `zsh`.

`urb doctor` te dice qué tienes y qué falta.

## Instalación

```bash
git clone https://github.com/Urbii22/urb-tools.git
cd urb-tools
./install.sh
```

El instalador:

1. Comprueba el sistema operativo, la versión de Bash y las dependencias.
2. Te enseña lo que falta y **solo** instala paquetes (`sudo apt-get install …`) si lo confirmas.
3. Copia la aplicación a `~/.local/lib/urb-tools` y crea el enlace `~/.local/bin/urb`.
4. Crea `~/.config/urb-tools/urb.conf` si no existe (nunca lo sobrescribe).
5. **No modifica** `.bashrc`, `.zshrc` ni ningún otro archivo personal.

Puedes ejecutarlo tantas veces como quieras: actualiza la copia instalada y conserva tu configuración.
Opciones: `--yes` (sin preguntas), `--no-deps` (no ofrece instalar paquetes) y `--link` (modo desarrollo: `urb` apunta al repositorio y los cambios se aplican al momento).

### Añadir `~/.local/bin` al PATH

Si el instalador avisa de que `~/.local/bin` no está en el `PATH`, añádelo tú. En Kali, la shell por defecto es zsh:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Con bash:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

### Desinstalar

```bash
./uninstall.sh
```

Borra solo el lanzador y `~/.local/lib/urb-tools`. Tu configuración (`~/.config/urb-tools`), los escaneos (`~/.local/share/urb-tools`) y los laboratorios (`~/urb-labs`) se quedan.

---

## Uso

```bash
urb                       # Dashboard interactivo (URB Terminal)
urb help [comando]        # Ayuda general o de un comando
urb version
urb doctor                # Dependencias y entorno
```

### Dashboard

| Tecla | Acción |
|---|---|
| `↑ ↓` / `j k` | Moverse |
| `Enter` / `→` | Abrir módulo |
| `1`–`6` | Ir directo a un módulo |
| `r` | Refrescar datos |
| `q` / `Esc` | Salir o volver |

Necesita una terminal de al menos 60×20. Con 34 filas o más aparece el logo grande; desde 90 columnas, paneles lado a lado.

### RECON

```bash
urb scan 10.10.10.5                       # perfil por defecto (-sV)
urb scan 10.10.10.5 --profile quick
urb scan 192.168.56.0/24 -p 22,80,443
urb scan 10.10.10.5 --profile stealth --sudo   # -sS necesita root: solo nmap se ejecuta con sudo
urb scan profiles                         # perfiles configurados
urb scan results                          # últimos resultados guardados
```

Los perfiles se definen en la configuración (`SCAN_PROFILE_<nombre>="opciones"`). Las opciones de ficheros (`-o*`, `-i*`) no están permitidas en los perfiles, porque URB gestiona la salida.

### NETWORK

```bash
urb network                    # resumen
urb network interfaces | routes | gateway
urb network connections [--listen|--established]
urb network discover 192.168.56.0/24 [--sudo]
urb network ping 10.10.10.5 -c 3
urb network check
```

### MONITOR

```bash
urb monitor                    # pantalla completa: q salir, s ordenar CPU/MEM
urb monitor --once             # instantánea en texto
urb monitor procs -n 15
```

### LOGS

```bash
urb logs                                   # resumen de autenticación
urb logs auth --since 2026-11-01 --ip 10.0.0.5
urb logs ssh --user root -n 50
urb logs errors --since today
urb logs search --grep "session opened"
urb logs summary --file ./evidence/auth.log   # analizar un log concreto
urb logs auth --sudo                       # si tu usuario no puede leer los logs
```

Para leer los logs del sistema sin `sudo`, tu usuario tiene que estar en el grupo `adm` (o en `systemd-journal`).

### CTF

```bash
urb ctf new htb-lame --target 10.10.10.3
cd "$(urb ctf path htb-lame)"
urb scan 10.10.10.3            # se guarda en htb-lame/scans/
urb ctf list
```

### Configuración

```bash
urb config show
urb config edit                # $EDITOR (nano/vi por defecto)
urb config set ANIMATIONS 0
```

El archivo de usuario es `~/.config/urb-tools/urb.conf` y sobrescribe `config/default.conf`. Solo se leen pares `CLAVE="valor"`: nunca se ejecuta su contenido.

Cada módulo también puede ejecutarse por separado: `bash modules/network.sh routes`.

---

## God Mode (`urb god`)

God Mode convierte la ventana de terminal en la que estás (QTerminal u otra) en un espacio de trabajo avanzado. Sigue siendo **tu Zsh real**: comandos, autocompletado, historial, tuberías, programas interactivos y herramientas de Kali funcionan igual que siempre. Por debajo usa tmux, con un HUD compacto en la barra de estado y el prompt URB.

```bash
urb god                # activar (o reconectar con una sesión que siga viva)
urb god --no-anim      # sin animaciones
urb god --status       # ¿hay una sesión de God Mode abierta?
urb god --kill         # terminar la sesión (pregunta si hay programas en marcha)
urb god --check        # comprobar dependencias
urb god --help
```

Requisitos: `tmux` (≥ 3.0) y `zsh`. Si faltan, `urb god` te dice cómo instalarlos (`sudo apt install tmux zsh`) y el resto de URB-Tools funciona igual. Kali ya trae Zsh y tmux suele estar disponible; el instalador te ofrece instalar lo que falte.

**Qué verás:** una animación breve con el logo URB y comprobaciones reales (versiones, sesión, directorio), y después tu terminal con:
- un HUD de una línea con CPU, RAM, IP, VPN (`tun0`/`wg`…), rama de Git del directorio actual y hora. Se refresca cada 2 s y se compacta en ventanas estrechas;
- el prompt URB (`╭─[GOD]─[usuario@host]─[ruta]─[git:rama*]` / `╰─❯`), con el código de error y los trabajos en segundo plano a la derecha;
- todo lo demás es terminal, alineada arriba a la izquierda, empezando en el directorio desde el que ejecutaste `urb god`.

**Salir, desconectarse y terminar.** No es lo mismo:

| Acción | Qué pasa con tus programas | Cómo volver |
|---|---|---|
| `exit` en la shell | Se cierra la shell. Si era la última, la sesión termina y vuelves a tu terminal normal. | `urb god` abre una sesión nueva |
| `Ctrl+B d` (desconectar) | **Siguen ejecutándose** en segundo plano | `urb god` reconecta con ellos |
| Cerrar la ventana de QTerminal | Igual que desconectar: siguen vivos | `urb god` |
| `urb god --kill` | Se terminan la sesión y todo lo que corre en ella (pide confirmación si hay programas activos) | — |

Dentro funcionan los atajos estándar de tmux: `Ctrl+B c` abre una ventana nueva y `Ctrl+B %` / `Ctrl+B "` dividen el panel, siempre en el directorio actual.

**Aislamiento y seguridad:**
- Usa un **servidor tmux propio** (socket `urb-god`) con su propia configuración (`godmode/tmux.conf`). Nunca lee ni modifica tu `~/.tmux.conf`, y tus sesiones tmux no se ven afectadas: `urb god --kill` solo cierra la suya.
- Zsh arranca con un `ZDOTDIR` temporal (`godmode/zsh/`) que **carga tu `~/.zshenv` y tu `~/.zshrc` sin modificarlos** y después aplica el prompt URB. No se toca ni `.zshrc` ni `.bashrc`.
- Si ya estás dentro de tmux, `urb god` no se anida: te pide que te desconectes primero.
- Se ejecuta con tu usuario. No da privilegios de root ni ninguna capacidad extra: lo que hagas con `sudo` dentro de God Mode funciona igual que fuera.

**Configuración** (`urb config set CLAVE VALOR`): `ANIMATIONS=0|1`, `GOD_HUD_POSITION=top|bottom` y `GOD_MOUSE=0|1`. Con `GOD_MOUSE=0`, la selección de texto de QTerminal funciona como siempre.

---

## URB Red (`urb red`) — v0.1

URB Red es el primer **perfil especializado** sobre la infraestructura de God Mode, pensado para laboratorios (HTB, THM, VulnHub, laboratorios propios). Es la misma Zsh real dentro de tmux, con estas diferencias:

- **Tema rojo** y etiqueta `URB RED`.
- **HUD:** laboratorio activo, objetivo, VPN e IP; en ventanas anchas, también CPU y RAM.
- **Prompt:** `╭─[RED]─[htb-lame ▸ 10.10.10.3]─[ruta]─[git]`.
- **Sesión tmux propia** (socket `urb-red`, sesión `red`): abrir, desconectar o terminar RED no afecta a `urb god`, y al revés.

Dentro de RED, Ctrl+C, `exit`, `Ctrl+B d`, `--kill` y la reconexión funcionan igual que en God Mode.

```bash
# Laboratorios (son los mismos que crea 'urb ctf')
urb red lab new htb-lame --target 10.10.10.3   # crea el laboratorio y lo selecciona
urb red lab use htb-lame                       # selecciona uno que ya existe
urb red lab list                               # lista (indica el seleccionado)
urb red status                                 # laboratorio, objetivo, escaneos, VPN y sesión

# Objetivo (se guarda en <lab>/.urb-lab y sobrevive al cierre de la terminal)
urb red target set 10.10.10.3
urb red target show

# Reconocimiento inicial: perfil nmap 'default' (-sV) contra el objetivo del laboratorio
urb red recon initial
urb red recon initial --target 10.10.10.30     # solo para esta ejecución; no cambia el guardado

# Shell
urb red                    # abrir URB Red (--no-anim, --kill [--yes], --session)
```

**Qué laboratorio se usa.** Primero el del **directorio actual**: si estás dentro de un laboratorio (hay un `.urb-lab` en el directorio o en uno de sus padres), se usa ese. Si no, el **seleccionado** con `urb red lab use`. Antes de cualquier operación de red, `recon initial` muestra qué laboratorio y qué objetivo va a usar y de dónde salen.

**`urblab [nombre]`** es una función de la Zsh de RED que cambia el directorio de *esa misma* shell al laboratorio, sin abrir otra.

**`recon initial`** reutiliza el motor de `urb scan`: progreso real de nmap, tabla de puertos y servicios, y resultados en `<lab>/scans/` (`.nmap`, `.xml`, `.gnmap`). Si dos escaneos coinciden en el mismo segundo, no se sobrescriben. Si nmap falla, se conserva el `.log` y se muestra un **diagnóstico**:
- `confirmed`: nmap o el sistema lo han dicho explícitamente. Por ejemplo, que no se puede resolver el nombre (falta la entrada en `/etc/hosts`), que hacen falta permisos de root o que la red no es alcanzable.
- `possible`: una hipótesis, **no comprobada**. Por ejemplo, «Host seems down»: no demuestra que el host esté apagado; puede estar bloqueando las sondas de ping o la VPN puede estar caída.
- `unknown`: no se reconoce la causa, y se indica dónde está el log.

El diagnóstico no lanza pings, consultas ni reintentos: solo lee lo que ya produjo la ejecución.

**Seguridad:** los ficheros `.urb-lab`, `state/active-lab`, `*.profile` y `*.theme` son **datos**: se leen línea a línea, se validan y nunca se ejecutan. Las escrituras son atómicas (fichero temporal + `mv`) y conservan las demás claves. No se usa root por defecto, no queda ningún proceso residente y no se escanea nada en segundo plano al entrar en RED.

---

## Hallazgos y notas (`urb red findings` / `urb red notes`)

Un registro de investigación por laboratorio: qué has comprobado, qué sospechas, qué has confirmado y qué has descartado, con notas fechadas y referencias a evidencias. Todo queda dentro del laboratorio, así que al cerrar Kali y volver otro día (o al desconectarte y reconectarte con tmux) sigue ahí. Funciona dentro y fuera de `urb red`: no necesita tmux ni el HUD.

```bash
urb red findings                                   # lista compacta + resumen
urb red findings add "HTTP puerto 80" --desc "Apache 2.4; login en /admin"
urb red findings add "FTP anonymous" --status suspected
urb red findings show F-001                        # detalle: notas, evidencias, historial
urb red findings status F-001 investigating
urb red findings note F-001 "He revisado el formulario de login"
urb red findings evidence F-001 scans/10.10.10.3_default_20261112-101500.nmap

urb red notes                                      # notas generales (notes/notes.md)
urb red notes add "He terminado la enumeración inicial"
urb red notes edit                                 # abre notes.md en $EDITOR
```

```
━━ URB RED / FINDINGS · htb-lame ━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ID       STATUS         TITLE
  F-001    investigating  HTTP puerto 80
  F-002    discarded      FTP anonymous
  F-003    pending        SSH configuration

  3 findings · 1 pending · 1 investigating · 1 discarded
```

**Estados.** Cada cambio queda en el historial del hallazgo.

| Estado | Significado |
|---|---|
| `pending` | Pendiente de revisar |
| `investigating` | En curso |
| `suspected` | **Hipótesis**: hay indicios, pero no está verificada (alias: `potential`) |
| `confirmed` | **Verificado con evidencia**. Confirmado ≠ vulnerabilidad: puede ser una observación cierta sin impacto. El impacto se describe en la descripción o en las notas |
| `discarded` | Hipótesis comprobada y **refutada** |
| `checked` | **Comprobación realizada sin hallazgo** (alias: `completed`) |

**Evidencias.** Son referencias, no copias. URB nunca lee, ejecuta, mueve ni modifica el fichero.
- Debe existir, ser un fichero normal y estar **dentro del laboratorio**.
- La ruta puede ser relativa al directorio actual o a la raíz del laboratorio.
- Se resuelven los enlaces simbólicos y se guarda la ruta real, relativa al laboratorio. Un enlace que apunte fuera se rechaza.
- Las rutas externas no se aceptan: copia antes el fichero a `evidence/`.
- Los duplicados se detectan aunque se escriban de otra forma.
- Si una evidencia se borra después, `show` la marca como `(missing)`.

**Almacenamiento** (sin bases de datos ni procesos residentes):

```
<lab>/findings/F-001.finding   # un fichero por hallazgo, líneas clave=valor (datos, nunca código)
<lab>/findings/.seq            # contador monótono de IDs
<lab>/notes/notes.md           # notas generales (el mismo fichero que crea 'urb ctf')
```

- Los textos no admiten caracteres de control (saltos de línea, tabuladores…), así que no pueden crear líneas ni claves falsas. `=` y `|` sí se permiten.
- Cada cambio se escribe de forma atómica, protegido por un bloqueo del laboratorio que detecta y libera los bloqueos abandonados.
- Un hallazgo nuevo nunca sobrescribe a otro.
- Un fichero dañado se muestra como `damaged` y no se modifica.
- Los campos que URB no conoce (por ejemplo `port=` o `service=`, para futuras importaciones) se conservan al reescribir.

---

## Escaneos y servicios (`urb red scans` / `urb red services`)

URB conoce los escaneos que ya has hecho en el laboratorio y te deja referirte a ellos con IDs cortos, sin escribir rutas:

```bash
urb red scans                                  # escaneos con ID estable, fecha, objetivo, perfil y estado
urb red scans show latest                      # detalle + puertos (también: show S-002)
urb red findings evidence F-001 --scan latest  # asocia el .nmap de ese escaneo (o --scan S-002)

urb red services                               # inventario de puertos abiertos (desde los XML de nmap)
urb red services --all                         # también cerrados / filtrados
urb red services show 8080                     # detalle, procedencia e historial (8080/udp, 10.10.10.3:8080…)
urb red services refresh                       # reconstruir el inventario
```

```
━━ URB RED / SERVICES · demo ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HOST             PORT       STATE          SERVICE      VERSION                            SEEN
  127.0.0.1        8080/tcp   open           http         SimpleHTTPServer 0.6 (Python 3.13) S-001
```

**Escaneos**
- Una ejecución es el conjunto de ficheros con el mismo nombre base (`.nmap`, `.xml`, `.gnmap` y `.log` si falló). Nada se copia ni se mueve.
- Los IDs `S-NNN` viven en `scans/.index`, que solo crece. Los escaneos que ya tenías se indexan la primera vez por orden temporal; los nuevos reciben el siguiente número, y `recon initial` muestra el ID al terminar.
- Si borras los ficheros de un escaneo, su ID se conserva y aparece como `missing`.
- Estados:
  - `complete`: terminó bien.
  - `incomplete`: se interrumpió (el XML no tiene `<finished>`).
  - `failed`: nmap dio un error.
  - `partial`: faltan ficheros.
  - `missing`: ya no existen sus ficheros.
- **`latest`** es el escaneo **completo** más reciente. La hora sale del nombre del fichero, si no del `start=` del XML y, como último recurso, de la fecha del fichero; nunca del orden de `ls`.
- Si `.index` se corrompe, las líneas dañadas se ignoran con un aviso. Si se borra, se reconstruye desde los ficheros, pero los IDs **pueden no coincidir** con los originales. Las evidencias de los hallazgos guardan la ruta del fichero, no el ID, así que no se rompen.

**Servicios**
- La **única fuente de verdad son los XML de nmap**. Se analizan con Python 3 y su biblioteca estándar (`xml.etree`), sin expresiones regulares ni paquetes pip, y sin tráfico de red.
- La caché `scans/.services` se reconstruye **solo** al ejecutar `urb red services`, y solo si cambió algún XML o el índice. Nunca se recalcula desde el prompt, el HUD ni el autocompletado.
- Hay una fila por `host + puerto + protocolo` (TCP y UDP por separado), con la **observación más reciente**. Si un escaneo posterior lo vio cerrado, deja de listarse como abierto. Si un escaneo posterior simplemente no lo incluye, **no** se interpreta como cerrado.
- Se guardan el primer y el último escaneo que lo vieron y el historial (`S-001=open S-003=closed`).
- Un XML truncado aporta los hosts completos que se llegaron a leer, marcados con `*`. Un XML roto se ignora con un aviso, sin afectar a los demás. Lo que nmap no informa aparece como `unknown`.
- El inventario no es un registro de hallazgos: un puerto abierto nunca crea un hallazgo automáticamente. Para relacionarlos en el futuro, cada servicio se identifica por la clave `host:puerto/proto` (por ejemplo `127.0.0.1:8080/tcp`), que un hallazgo podrá guardar como `service=`.

**Autocompletado (dentro de GOD y RED):** `urb <Tab>`, `urb red <Tab>`, IDs `F-NNN`, `--scan latest|S-NNN` y los puertos de `services show`. Solo lee los índices ya existentes: no ejecuta nmap, no analiza XML y no lanza procesos.

---

## Sesiones (`urb sessions`)

Un gestor global de las sesiones de God Mode y URB Red. Funciona desde cualquier terminal, sin activar ninguna de ellas.

```bash
urb sessions                    # tabla: perfil, estado, ventanas, paneles, clientes, socket
urb sessions info red           # detalle: paneles (comando y directorio), clientes, hora de creación
urb sessions attach red         # reconectar (solo si existe: nunca crea una sesión)
urb sessions kill red           # terminar (pide confirmación SIEMPRE; --yes para no preguntar)
```

| Estado | Significado |
|---|---|
| `attached` | La sesión existe y hay una terminal conectada |
| `detached` | La sesión existe en segundo plano: sus programas siguen ejecutándose |
| `none` | No hay sesión (incluye el caso de un socket huérfano de un servidor ya terminado) |
| `error` | No se ha podido consultar a tmux (no está instalado, permisos…); se muestra el mensaje |

- Consultar (`urb sessions`, `info`) **nunca crea sesiones ni arranca servidores**.
- Cada perfil usa su propio socket (`urb-god`, `urb-red`): `kill red` solo cierra RED, y nada afecta a tus propias sesiones tmux.

**Cómo termina una conexión.** Al volver a tu terminal, `urb god` y `urb red` te dicen qué ha pasado:
- `Detached from …`: te has desconectado (`Ctrl+B d` o has cerrado la ventana). La sesión sigue viva.
- `… off. Session ended: its last shell exited …`: terminó la última shell de la sesión (`exit`, `Ctrl+D`) o alguien la cerró (`urb sessions kill`, `kill-session`). tmux no permite distinguir entre estos casos.
- `… tmux server ended unexpectedly`: el servidor tmux murió estando conectado. Es un error (código 1), no una salida normal.

**HUD:** con suficiente anchura (GOD desde 140 columnas, RED desde 150) aparece `SES n`, el número de sesiones URB activas. Se calcula como mucho una vez cada 10 s (caché compartida en `$XDG_RUNTIME_DIR`) y no consulta tmux si no existe el socket. Con menos anchura, se oculta.

---

## Arquitectura

```
urb-tools/
├── bin/urb               # CLI: opciones globales y despacho de comandos
├── lib/
│   ├── utils.sh          # colores, mensajes, validación de entradas, config segura
│   ├── ui.sh             # motor TUI: tema, cajas, barras, búfer de dibujo, teclado, menús
│   ├── system.sh         # lectura de datos reales (/proc, ip, df…)
│   ├── lab.sh            # contexto de laboratorio y objetivo (.urb-lab, active-lab)
│   ├── diagnose.sh       # diagnóstico de errores (confirmed / possible / unknown)
│   ├── findings.sh       # hallazgos: formato, bloqueo, IDs, evidencias, notas
│   ├── scans.sh          # índice de escaneos (S-NNN), estados, latest, caché de servicios
│   ├── nmap_services.py  # XML de nmap → inventario (Python 3, solo biblioteca estándar)
│   └── dashboard.sh      # URB Terminal (dashboard principal)
├── modules/              # scan, network, monitor, logs, ctf, settings, red, findings, inventory, sessions
├── godmode/              # URB God Mode (independiente de los módulos)
│   ├── god.sh            # activación, sesión tmux aislada, salida, --status/--kill/--attach-only
│   ├── session.sh        # perfiles y consultas de sesión de solo lectura (compartido)
│   ├── tmux.conf         # configuración tmux propia (nunca usa ~/.tmux.conf)
│   ├── profiles/         # perfiles visuales: god.profile, red.profile (datos)
│   ├── zsh/              # ZDOTDIR temporal: carga tu ~/.zshrc + prompt URB/RED + urblab
│   ├── hud/status.sh     # HUD de la barra de estado (datos reales)
│   ├── animations/fx.sh  # animaciones de entrada y salida
│   └── themes/           # urb.theme (base) y red.theme (datos: Bash, Zsh y tmux)
├── config/default.conf
├── tests/                # runner en Bash puro + fixtures
├── install.sh / uninstall.sh
```

Decisiones técnicas:

- **Bash puro, sin dependencias obligatorias.** El menú y el dashboard usan un motor propio (`tput` y secuencias ANSI). `fzf` y `figlet` son mejoras opcionales.
- **Sin parpadeo:** cada frame se compone en un búfer y se escribe con un solo `printf` en la pantalla alternativa.
- **Terminal siempre restaurada:** traps de `EXIT`, `INT`, `TERM` y `HUP` (cursor, eco y pantalla principal).
- **Aislamiento:** cada módulo lanzado desde el dashboard corre en una subshell, así que un error o un Ctrl+C dentro de un módulo te devuelve al dashboard.
- **Sin `set -e`:** los errores esperables (herramienta ausente, permisos, entradas inválidas) se comprueban y se informan con códigos de salida (`2` = uso incorrecto, `127` = falta una herramienta, `130` = cancelado).
- **Seguridad:** sin `eval`, entradas validadas (IP/CIDR/hostname/puertos/nombres), nada que empiece por `-` llega a nmap como objetivo, `sudo` solo para el comando que lo necesita y tras avisar.

Para añadir un módulo, crea `modules/<nombre>.sh` con `<nombre>_main` (CLI) y `<nombre>_menu` (interactivo). Después cárgalo en `bin/urb` y añádelo a `DASH_ITEMS` en `lib/dashboard.sh`.

## Tests

```bash
bash tests/run.sh            # todos
bash tests/run.sh logs       # solo los ficheros que contienen "logs"
shellcheck -x bin/urb lib/*.sh modules/*.sh godmode/*.sh godmode/hud/*.sh godmode/animations/*.sh install.sh uninstall.sh tests/*.sh
```

## Hoja de ruta

- **Fase 2 — Reconocimiento y análisis:** importar resultados XML de nmap al informe del laboratorio, enumeración por servicio (HTTP, SMB, FTP), comparar escaneos, más patrones de logs (fail2ban, servidores web) y exportar a CSV/Markdown.
- **Fase 3 — Experiencia visual:** temas de color, informes HTML/PDF, más animaciones (desactivables), gráficas históricas de CPU/RAM y soporte de ratón.

## Licencia

MIT. Consulta [LICENSE](LICENSE).
