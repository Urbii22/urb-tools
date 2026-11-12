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

## Arquitectura

```
urb-tools/
├── bin/urb               # CLI: opciones globales y despacho de comandos
├── lib/
│   ├── utils.sh          # colores, mensajes, validación de entradas, config segura
│   ├── ui.sh             # motor TUI: tema, cajas, barras, búfer de dibujo, teclado, menús
│   ├── system.sh         # lectura de datos reales (/proc, ip, df…)
│   └── dashboard.sh      # URB Terminal (dashboard principal)
├── modules/              # scan, network, monitor, logs, ctf, settings
├── godmode/              # URB God Mode (independiente de los módulos)
│   ├── god.sh            # activación, sesión tmux aislada, salida, --status/--kill
│   ├── tmux.conf         # configuración tmux propia (nunca usa ~/.tmux.conf)
│   ├── zsh/              # ZDOTDIR temporal: carga tu ~/.zshrc + prompt URB
│   ├── hud/status.sh     # HUD de la barra de estado (datos reales)
│   ├── animations/fx.sh  # animaciones de entrada y salida
│   └── themes/urb.theme  # paleta compartida (Bash, Zsh y tmux)
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
