# Diario del proyecto — URB-Tools

## 2026-11-11 · Fase 1 (MVP)

**Entorno de prueba:** WSL Ubuntu 26.04 (bash 5.3, nmap 7.98, fzf, figlet, shellcheck instalados con apt en WSL).
Todavía no se ha probado en Kali.

### Estado por feature

| Feature | Código | Tests | Instalado | Probado en vivo |
|---|---|---|---|---|
| CLI `urb` (help, version, errores) | ✅ | ✅ | ✅ (HOME temporal en WSL) | ✅ WSL |
| Dashboard TUI | ✅ | — (manual) | ✅ | ✅ WSL vía pty (`script`): 110x34, 100x30, 80x24, 66x26 |
| RECON (nmap, progreso, tabla, guardado, Ctrl+C) | ✅ | ✅ | ✅ | ✅ WSL: localhost con un servicio real; cancelación en CLI y TUI |
| NETWORK (summary, ifaces, routes, conns, discover, check) | ✅ | ✅ | ✅ | ✅ WSL |
| MONITOR (en vivo y `--once`) | ✅ | ✅ | ✅ | ✅ WSL vía pty |
| LOGS (summary, auth, ssh, errors, search, --file) | ✅ | ✅ (fixture) | ✅ | ✅ WSL con journald (sin auth.log) |
| CTF (new/list/path, scans dentro del lab) | ✅ | ✅ | ✅ | ✅ WSL (también desde la TUI) |
| SETTINGS / config / doctor | ✅ | ✅ | ✅ | ✅ WSL |
| install.sh / uninstall.sh | ✅ | ✅ (HOME temporal) | — | ⏳ Kali real |

Resultado: `bash tests/run.sh` → 49/49 · `shellcheck -S warning` → 0 avisos.

### Pendiente de probar en Kali (VM)

```bash
git clone https://github.com/Urbii22/urb-tools.git && cd urb-tools && ./install.sh
urb doctor
urb                                   # en qterminal: revisar colores, tamaño, logo
urb scan <IP-de-lab> --profile quick
urb scan <IP-de-lab> --profile stealth --sudo
urb network discover 192.168.56.0/24 --sudo   # red host-only de la VM
urb logs                              # Kali: auth.log o journald; ¿usuario en grupo adm?
openvpn <htb.ovpn>  →  urb            # el panel debe mostrar "VPN ● ACTIVE tun0 10.10.x.x"
./uninstall.sh
```

Pendiente: zsh como shell por defecto (PATH a `~/.local/bin`), qterminal y fuentes Unicode.

## 2026-11-11 · Instalador: lanzador seguro y actualización con rollback

- `install.sh` solo sustituye `~/.local/bin/urb` si apunta a una instalación de URB-Tools (marcador `.urb-install`) o a un árbol de código de URB-Tools (`--link`). Un destino que solo acabe en `/bin/urb` ya no basta. La comprobación se hace antes de modificar nada.
- Actualización transaccional: copia y verifica en `urb-tools.new.<pid>` (ficheros, `bash -n`, `urb version`), mueve la anterior a `urb-tools.old.<pid>`, activa la nueva y verifica a través del lanzador. Si algo falla, restaura la app y el lanzador anteriores; la copia temporal solo se borra al terminar con éxito.
- Tests: 55/55 (10 del instalador, entre ellos el fallo simulado durante una actualización) · ShellCheck sin avisos.
- `uninstall.sh` usa la misma validación: ya no borra enlaces ajenos acabados en `/bin/urb` (58/58 tests).

## 2026-11-12 · Fase 2: URB God Mode (`urb god`)

**Arquitectura:** `godmode/god.sh` (proceso independiente; `bin/urb` solo le pasa la orden) → servidor tmux propio (`-L urb-god`, `godmode/tmux.conf`) → Zsh real con `ZDOTDIR=godmode/zsh`, que carga `~/.zshenv` y `~/.zshrc` del usuario sin modificarlos y añade el prompt URB. HUD = barra de estado de tmux (`hud/status.sh`, que reutiliza `lib/system.sh`). Paleta compartida en `themes/urb.theme`. Animaciones en `animations/fx.sh`.

**Semántica:** `exit` cierra la sesión · `Ctrl+B d` (o cerrar la ventana) desconecta y conserva los procesos · `urb god` reconecta · `urb god --kill` termina solo la sesión de God Mode.

| Feature | Código | Tests | Instalado | Probado en vivo |
|---|---|---|---|---|
| `urb god` (arranque, reconexión, salida) | ✅ | ✅ | ✅ (HOME temporal) | ✅ WSL en pty (`script`), no en QTerminal |
| Zsh real (directorio de partida, alias y `.zshrc` del usuario, historial, Ctrl+C) | ✅ | ✅ | ✅ | ✅ WSL |
| Aislamiento (otro servidor tmux intacto, `.zshrc` sin cambios, sin `~/.tmux.conf`) | ✅ | ✅ | — | ✅ WSL |
| HUD (CPU, RAM, IP, VPN, Git, hora) | ✅ | ✅ | ✅ | ✅ WSL (VPN activa sin probar) |
| Animaciones de entrada y salida | ✅ | ✅ | ✅ | ✅ WSL en pty |
| Instalador y desinstalador (copia, verificación, rollback, aviso de sesión abierta) | ✅ | ✅ | ✅ | ⏳ Kali |

**Pendiente de probar en Kali / QTerminal:**

```bash
cd ~/urb-tools && git pull && ./install.sh     # ofrecerá instalar tmux si falta
urb god --check
urb god                                        # animación, HUD arriba, prompt [GOD]
#   dentro: ls, Tab (autocompletado), flecha arriba (historial), htop/vim, sudo -v
#   redimensionar la ventana de QTerminal → el HUD se adapta
#   Ctrl+B d → "Detached…" → urb god → vuelve a la misma sesión
#   exit → "God Mode off" y la terminal queda como antes (título, cursor, scroll)
openvpn <htb.ovpn> → urb god                   # el HUD debe mostrar "● VPN tun0 10.10.x.x"
urb god --kill
```

A comprobar en QTerminal: que los glifos (◆ ▌ ╭ ╰ ❯ ✘ ⚙) se vean bien con la fuente de Kali, los colores de 256, y si QTerminal restaura el título de la ventana (`\e[22;0t` / `\e[23;0t`).

**2026-11-12 · Verificado en vivo en Kali (God Mode):** Diego confirma que `urb god` funciona en su Kali (QTerminal). Sin datos todavía sobre los puntos de detalle (VPN activa en el HUD, título de la ventana): si aparece algún problema, se anota aquí.
- Pendiente en Kali: `./install.sh` dos veces seguidas, `git pull && ./install.sh` como actualización, y `./install.sh --link`.

## 2026-11-12 · URB Red v0.1 (`urb red`)

**Arquitectura**
- **Motor visual de perfiles:** `godmode/god.sh --profile <nombre>` lee `godmode/profiles/*.profile` (datos validados: nombre, etiqueta, sesión, socket, tema y HUD). `god` reproduce exactamente el comportamiento anterior; `red` usa el socket `urb-red`, la sesión `red`, `themes/red.theme` y el HUD `red`.
- **Contexto de laboratorio:** `lib/lab.sh`. Metadatos en `<lab>/.urb-lab` (`name`, `created`, `target`); `state/active-lab` es solo la referencia al laboratorio seleccionado y se valida al usarla. Prioridad: el directorio actual (`.urb-lab` en él o en un padre) va antes que la selección global. Escrituras atómicas que conservan las demás claves. `ctf_find_lab_root` delega en `lab_find_root`.
- **Objetivos:** `lab_target_read`/`lab_target_set` (un objetivo principal, `target=`). Es el único punto de acceso, para poder admitir varios objetivos más adelante.
- **Ejecución:** `recon initial` envuelve `scan_main` (perfil `default`, `-o <lab>/scans`). `scan_main` expone `SCAN_LAST_BASE`/`SCAN_LAST_RC`, conserva el `.log` si nmap falla y no sobrescribe resultados del mismo segundo.
- **Diagnóstico:** `lib/diagnose.sh`, con reglas como datos (`confirmed`/`possible`/`unknown`). Solo lee el código de salida, el `.log` y el `.nmap`; no hace tráfico de red ni reintentos.
- **Zsh RED:** segmento laboratorio ▸ objetivo resuelto en Zsh nativo (sin procesos) y la función `urblab` (hace `cd` en la shell actual).

| Feature | Código | Tests | Instalado | Probado en vivo |
|---|---|---|---|---|
| `urb red` (shell, HUD rojo, prompt, animación) | ✅ | ✅ | ✅ (HOME temporal) | ✅ WSL en pty; no en QTerminal |
| `lab new/use/list/path`, `status` | ✅ | ✅ | ✅ | ✅ WSL |
| `target set/show` (persistente, atómico, validado) | ✅ | ✅ | ✅ | ✅ WSL |
| `recon initial` (+ `--target` sin guardar) | ✅ | ✅ (nmap simulado) | ✅ | ⏳ nmap real contra un laboratorio |
| Diagnóstico de errores | ✅ | ✅ | ✅ | ✅ WSL (simulado) |
| Aislamiento GOD/RED | ✅ | ✅ (pty real) | — | ✅ WSL |
| `urblab` | ✅ | ✅ | ✅ | ✅ WSL en pty |

**Pendiente de probar en Kali / QTerminal**

```bash
cd ~/urb-tools && git pull && ./install.sh
urb red lab new htb-lame --target 10.10.10.3
urb red status
openvpn <htb.ovpn>        # en otra terminal
urb red                    # tema rojo, HUD: LAB htb-lame │ TGT 10.10.10.3 │ ● VPN tun0 …
#   dentro: cd /tmp → urblab → vuelves al laboratorio
#   urb red recon initial  → resultados en ~/urb-labs/htb-lame/scans/
#   urb god (en otra ventana) → sesión GOD independiente
urb red --kill
```

**Limitaciones v0.1:** un solo objetivo por laboratorio; `recon initial` usa solo el perfil `default`; el diagnóstico cubre solo nmap; al reconectar con `urb red` se entra en la sesión existente (con su directorio), y el HUD muestra el laboratorio del directorio del panel activo.

## 2026-11-12 · Sesiones: fallo de tmux, `urb sessions` e indicador SES

**Investigación del informe** («`no such session: =red`» y `[exited]` tras `Ctrl+B d` en RED)
- **Causa confirmada y corregida — mensaje `no such session: =red`:** `god.sh` configuraba cada sesión nueva con `set-environment`/`set-option -t "=red"`. En tmux 3.6 esos dos comandos **no** aceptan el prefijo `=` (buscan una sesión llamada «=red»), así que fallaban **siempre**, en GOD y en RED. Consecuencia: las ventanas y paneles nuevos (`Ctrl+B c`, divisiones) no heredaban la Zsh ni el entorno del perfil. Corrección: nombre sin `=` (en el socket privado solo hay sesiones nuestras) y comprobación del resultado, sin reintentos.
- **No reproducido — sesión perdida con `Ctrl+B d`:** en WSL, 5 de 5 desconexiones conservaron la sesión. `Ctrl+B Ctrl+D` también la conserva (tmux ignora esa combinación). `[exited]` solo lo imprime tmux cuando termina la última shell (`exit`, `Ctrl+D`, la shell muere) o cuando la sesión se cierra desde fuera. **La causa exacta del caso observado sigue sin encontrarse.**
- **Para encontrarla la próxima vez:** `god.sh` informa ahora de cómo terminó cada conexión: desconexión, «Session ended: its last shell exited… or it was closed» o «tmux server ended unexpectedly» (código 1). Si la sesión muere justo al crearse, también lo dice («its shell exited»).

**`urb sessions`** (`modules/sessions.sh`, apoyado en `godmode/session.sh`)
- `list`, `info`, `attach` (solo reconecta; usa `god.sh --attach-only`) y `kill` (pide confirmación siempre salvo `--yes`; `kill-session` solo en el socket de ese perfil).
- Estados `attached` / `detached` / `none` / `error`. Un socket huérfano (servidor terminado) cuenta como `none`. Consultar nunca crea sesiones ni servidores.
- El análisis de perfiles salió de `god.sh` a `godmode/session.sh` para compartirlo, sin cambiar el comportamiento de `urb god`/`urb red`.

**HUD:** `SES n` solo con anchura suficiente (GOD ≥ 140, RED ≥ 150). Caché de 10 s en `$XDG_RUNTIME_DIR/urb-god-$UID/sessions` y ninguna llamada a tmux si no existe el socket.

| Comprobado automáticamente (WSL, pty real) | Pendiente de probar a mano en Kali / QTerminal |
|---|---|
| Sin «no such session» al crear; las ventanas nuevas heredan el perfil | Que el aviso no vuelva a aparecer al abrir RED/GOD |
| Detach conserva la sesión; `exit`, `Ctrl+D` y el cierre externo la terminan con mensaje; la pérdida del servidor da error (código 1) | Repetir varias veces `Ctrl+B d` en RED y anotar si alguna vez aparece `[exited]` |
| `urb sessions` (estados, info, attach sin crear, kill con confirmación, aislamiento GOD/RED, estado error) | Ver `SES n` en el HUD con la ventana maximizada |
| Caché del indicador (sin llamadas a tmux dentro de los 10 s) | |

**Guía rápida en Kali**

```bash
cd ~/urb-tools && git pull && ./install.sh
urb sessions                      # god none · red none
urb god                           # crear GOD → Ctrl+B d (desconectar)
urb red                           # crear RED → Ctrl+B c (ventana nueva: prompt [RED]) → Ctrl+B d
urb sessions                      # god detached · red detached
urb sessions info red             # 2 ventanas, paneles con su directorio
urb sessions attach red           # reconectar → Ctrl+B d
urb sessions kill red             # pide confirmación → y
urb sessions                      # red none · god detached (GOD intacta)
urb sessions attach red           # error: no existe (no se crea)
urb god                           # reconectar GOD → exit → "God Mode off. Session ended…"
```

Si alguna vez una desconexión acaba en `[exited]`, anota el mensaje que imprime `urb` justo después y la salida de `urb sessions`.

**2026-11-12 · Verificado en vivo en Kali (sesiones):** Diego confirma que todo funciona: `urb sessions` (list/info/attach/kill), las ventanas nuevas con el perfil, desconexión y reconexión de GOD y RED, y el aislamiento entre ambos. La desaparición puntual de RED tras `Ctrl+B d` no se ha vuelto a observar; su causa sigue sin confirmarse.

## 2026-11-12 · Fase 3: Findings & Investigation Manager

**Decisiones**
- **Un fichero por hallazgo** (`<lab>/findings/F-NNN.finding`, líneas `clave=valor`). Si uno se daña, los demás se siguen leyendo; cada cambio reescribe un solo fichero; el ID coincide con el nombre del fichero. Sin SQLite ni dependencias nuevas.
- **Integridad del formato:** ningún valor admite caracteres de control, así que un texto no puede crear líneas ni claves. La clave termina en el primer `=` y la fecha de `note`/`log` tiene longitud fija, por eso `=` y `|` son seguros en los textos. Un fichero con líneas inválidas, un ID que no coincide, sin título o con un estado desconocido se muestra como `damaged` y **no se modifica**. Las claves desconocidas (reservadas para futuras importaciones: `host`, `port`, `service`, `url`, `source`…) se conservan al reescribir.
- **IDs:** `max(.seq, mayor ID existente) + 1`, calculado con el bloqueo tomado. El fichero nuevo se publica con `ln` (falla si el destino existe), así que nunca se sobrescribe un hallazgo. `.seq` es monótono mientras esté íntegro: borrar un hallazgo no libera su ID. **Límite de la recuperación:** si se pierde o se corrompe `.seq` (se avisa) se recalcula desde el mayor ID existente; si además se había borrado a mano el hallazgo con el ID más alto, ese número podría volver a usarse (nunca sobre un fichero existente).
- **Bloqueo:** el enlace simbólico `<lab>/.urb-lock`, cuyo destino es «pid host epoch», se crea de forma atómica junto con su contenido. Un bloqueo es abandonado si su proceso no existe en este host o tiene más de 120 s; antes de borrarlo se vuelve a comprobar que sigue siendo el mismo. Se libera también ante Ctrl+C o un error. Si está ocupado, se espera ~10 s y se falla con un mensaje claro. *Fallo encontrado en las pruebas:* la primera versión (`mkdir` + fichero `owner`) tenía un instante en el que el bloqueo existía sin dueño y otro proceso podía tomarlo por abandonado: con 12 altas simultáneas, 2 fallaban (el `ln` impidió que se pisara nada). La versión con enlace simbólico pasa 12/12.
- **Notas:** las generales van en el `notes/notes.md` de siempre (una sola fuente; se crea si un laboratorio antiguo no lo tiene; nunca se pierde el contenido existente). Las de cada hallazgo, en su fichero (`note=`), con el historial de estados aparte (`log=`).
- **Evidencias:** solo referencias internas. Se resuelven con `readlink -f`, la ruta real debe quedar dentro del laboratorio y se guarda relativa a él. Se rechazan los enlaces que salen del laboratorio, las rutas externas, los directorios y los metadatos de URB. `--external` no se implementa.
- **Estados:** `pending`, `investigating`, `suspected`, `confirmed`, `discarded` y `checked` (alias `potential`, `completed`). `confirmed` significa «verificado con evidencia», no «vulnerabilidad».

| Comprobado automáticamente (WSL) | Pendiente de probar a mano en Kali |
|---|---|
| Crear/listar/mostrar, IDs estables y monótonos, estados y alias, notas, evidencias (internas, duplicados, enlaces y rutas externas rechazados) | Uso real durante una investigación |
| Inyección de campos imposible; textos con `= \| $( )` intactos | Colores de estados en QTerminal |
| 12 altas y 10 notas simultáneas sin pérdidas; bloqueo abandonado y bloqueo ocupado | `urb red notes edit` con tu `$EDITOR` |
| Escrituras fallidas sin pérdida de datos; ficheros dañados sin modificar | Uso dentro de `urb red` tras desconectar y reconectar |
| Aislamiento entre laboratorios, prioridad del directorio, laboratorios antiguos de `urb ctf`, `--no-color` | |

**Prueba en Kali (sin otra máquina virtual: un laboratorio ficticio con un servicio local)**

```bash
cd ~/urb-tools && git pull && ./install.sh
urb red lab new demo --target 127.0.0.1
python3 -m http.server 8080 --bind 127.0.0.1 &      # servicio de prueba local
urb red recon initial                                # escaneo real a tu propia máquina
urb red findings add "HTTP 8080 (python http.server)" --desc "Listado de directorios"
urb red findings add "SSH config" --status suspected
urb red findings status F-001 investigating
urb red findings note F-001 "Directory listing visible en /"
urb red findings evidence F-001 scans/$(ls ~/urb-labs/demo/scans | grep '\.nmap$' | head -n1)
urb red findings evidence F-001 /etc/passwd          # debe rechazarse (fuera del laboratorio)
urb red findings status F-002 discarded
urb red notes add "Enumeración inicial terminada"
urb red findings                                     # lista + resumen
urb red findings show F-001
urb red status                                       # incluye el resumen de hallazgos
kill %1                                              # parar el servidor de prueba
# Cerrar la terminal (o reiniciar Kali), abrir otra y repetir: urb red findings → todo sigue ahí
```

**Limitaciones:** sin edición de título ni descripción (`findings add` los fija; se puede editar el fichero a mano), sin borrado desde la CLI, descripción de una sola línea, sin importación automática desde nmap ni informes (planificado), y las evidencias solo pueden estar dentro del laboratorio.

## 2026-11-12 · Scan Manager + inventario de servicios + mejoras de uso

**Problema de partida:** asociar el último escaneo a un hallazgo obligaba a escribir `"scans/$(ls … | grep '\.nmap$' | head -n1)"`. Ahora basta con `urb red findings evidence F-001 --scan latest`.

**Decisiones**
- **Índice `scans/.index`** (`S-NNN|base|epoch`), que solo crece y se escribe de forma atómica bajo el bloqueo del laboratorio (reutiliza el de findings). Los escaneos que ya existían se indexan la primera vez por orden temporal; los nuevos, al consultarlos o al terminar `recon initial`. Un ID no cambia mientras se conserve el índice, aunque se borren los ficheros (se ve como `missing`). **Límite de la recuperación:** con el índice corrupto se ignoran las líneas dañadas; con el índice borrado se reconstruye y los IDs pueden no coincidir con los antiguos. Las evidencias guardan la ruta, no el ID.
- **Hora fiable:** el nombre del fichero (`AAAAMMDD-HHMMSS`, que pone URB), después `start=` del XML y por último la fecha de modificación. `latest` es el escaneo **completo** más reciente.
- **Estados** calculados al consultar: `complete` (XML con `exit="success"` y `.nmap`), `incomplete` (sin `<finished>`), `failed` (`.log` conservado o `exit` de error), `partial` (faltan ficheros), `missing`.
- **Servicios:** `lib/nmap_services.py` (Python 3, solo biblioteca estándar, `xml.etree.iterparse`). La fuente de verdad son los XML; `scans/.services` es una caché derivada que se reconstruye solo cuando cambia su sello (índice + tamaño y fecha de cada XML), o con `services refresh`. Hay una fila por host + protocolo + puerto con la observación más reciente; que un puerto no aparezca en un escaneo posterior no lo marca como cerrado. El historial guarda la procedencia. Un XML truncado conserva los hosts completos (marcados con `*`) y un XML roto se ignora sin afectar a los demás.
- **Relación futura:** escaneo = `S-NNN`, servicio = `host:puerto/proto` (clave natural, sin tabla extra) y hallazgo = `F-NNN`. Los hallazgos ya conservan las claves `service=` y `scan=` si se añaden, sin duplicar la fuente de verdad.
- **Autocompletado Zsh** (solo GOD/RED, `compdef _urb_complete urb`): listas fijas más lectura de `findings/F-*.finding`, `scans/.index` y `scans/.services` con funciones nativas de Zsh. Sin procesos, sin XML y sin nmap.

**Fallos encontrados en las pruebas:**
1. Si el índice todavía no existía, la primera indexación fallaba.
2. `BASH_REMATCH` se sobrescribía al validar el nombre base (el mismo patrón de fallo que en findings).
3. `read` con `IFS=$'\t'` fundía los campos vacíos de la caché y desplazaba columnas: ahora se separa por `\x1f`.

| Comprobado automáticamente (WSL) | Pendiente de probar a mano en Kali |
|---|---|
| Indexación de escaneos antiguos, IDs estables, escaneos nuevos, `latest` y estados | Con los escaneos reales del laboratorio `demo` |
| Concurrencia del índice, índice corrupto o borrado | Autocompletado con Tab en QTerminal |
| `--scan latest/S-NNN`, duplicados, sin `.nmap`, sin escaneos | Tablas a la anchura habitual de QTerminal |
| Varios hosts, TCP/UDP, versiones desconocidas, última observación, ausencia ≠ cerrado | |
| XML truncado e inválido, caché (no se reconstruye sin cambios), `refresh` | |
| Sin tráfico de red (nmap, ping, curl y nc como trampas) y sin python3 (código 127) | |

**Prueba en Kali con el laboratorio `demo` existente**

```bash
cd ~/urb-tools && git pull && ./install.sh
urb red lab use demo
urb red scans                                   # tus escaneos de antes, ahora con S-001…
urb red scans show latest
urb red services                                # 127.0.0.1  8080/tcp  open  http …
urb red services show 8080
urb red findings evidence F-001 --scan latest   # sin rutas
urb red findings show F-001
urb red                                         # dentro: urb red findings evidence F-001 --scan <Tab>
```

**Limitaciones:** sin enlace operativo hallazgo ↔ servicio todavía (solo el diseño), sin comparar escaneos, `recon initial` sigue usando solo el perfil `default`, y el autocompletado de nombres de laboratorio asume `~/urb-labs`.

## 2026-11-12 · Command Engine v0.1 + manual completo

**Arquitectura**
- **`lib/engine.sh`** lee las especificaciones `commands/*.spec` (datos `clave=valor` validados, nunca ejecutados): `modifier=nombre|grupo|flags|desc`, `option=nombre|tipo|defecto|clave_config|desc`, `group=`, `note=` y `example=`.
- **Análisis:** los modificadores no dependen del orden, se normalizan al orden del `.spec` y se rechazan los desconocidos, los repetidos y dos del mismo grupo. Las opciones van siempre como `--opción valor` (se rechaza `--opción=valor`) y se validan por tipo (`target`, `port`, `ip`, `dir`, `flag`).
- **Precedencia de valores:** explícito > configuración del usuario > defecto del `.spec`.
- **Una sola definición:** de cada `.spec` salen la validación, la ayuda (`urb help red recon`, `urb help serve`) y el autocompletado (Zsh lee el `.spec` de forma nativa). Un comando nuevo = un `.spec` + un manejador.
- **`urb red recon <modificadores>`:**
  - Usa `RECON_BASE` + `RECON_MOD_<mod>` de la configuración, que el usuario puede ajustar.
  - `slow` sustituye el `-T` de la base; la comprobación final rechaza dos `-T` o dos selecciones de puertos aunque la configuración se edite a mano. `quick`, `full` y `udp` forman el grupo `ports`.
  - Llama a `scan_main` por una **interfaz interna**: arrays `SCAN_ENGINE_ARGS` y `SCAN_ENGINE_OPTS` que solo existen en el mismo proceso, porque las variables de entorno no pueden ser arrays. No hay ninguna opción pública de argumentos libres.
  - `scan_build_cmd` es la **única** función que construye el comando, tanto para la ejecución real como para `--dry-run`.
  - `urb scan` y `recon initial` no cambian.
- **`urb serve`:** `python3 -m http.server` con `127.0.0.1:8000` por defecto (configurable con `SERVE_PORT`/`SERVE_BIND`).
  - Detecta el puerto ocupado antes de arrancar, intentando reservarlo con Python, y rechaza los puertos privilegiados sin root.
  - Una dirección no local exige confirmación o `--yes`. Ctrl+C lo detiene con el código 0. No toca el firewall.
- **Ayuda:**
  - `red_help` se divide en secciones (`urb help red <sección>`) y el `--help` de cada subcomando muestra su sección.
  - `urb help` admite temas y subtemas; un tema desconocido devuelve el código 2.
  - `bin/urb-help` es un lanzador de una línea que ejecuta `urb help` (sin duplicar la ayuda). El instalador lo crea con las mismas reglas de propiedad y rollback, respeta un `urb-help` ajeno, y el desinstalador solo borra el suyo.
  - `urb manual` abre `docs/COMMANDS.md` con `less`, o muestra la ruta.
- **Documentación:** `docs/COMMANDS.md` (14 secciones, en español) y `docs/EXAMPLES.md` (8 flujos). Los tests comprueban que cada comando, subcomando, modificador, opción, clave de configuración y estado está documentado, y que los ejemplos solo usan comandos reales.

**Fallos encontrados en las pruebas:** la columna de perfil de `scans` cortaba las combinaciones (`quick-versions`). Además, dos pruebas de Ctrl+C estaban mal planteadas: un proceso lanzado con `&` tiene SIGINT ignorado, así que ahora se prueban en una pseudo-terminal real.

| Comprobado automáticamente (WSL) | Pendiente de probar a mano en Kali |
|---|---|
| `quick versions` = `versions quick` (comando idéntico) y otras permutaciones | `urb red recon quick versions` real contra el laboratorio `demo` |
| Modificadores repetidos, desconocidos e incompatibles; `--opción=valor`; valores inválidos | Autocompletado con Tab de los modificadores y de `serve`/`help` en QTerminal |
| Precedencia explícito > config > defecto; `slow` sin doble `-T`; configuración manipulada | `urb manual` con `less` |
| `--dry-run` sin nmap, sin sudo, sin ficheros, sin carpetas y sin bloqueo | `urb serve` y un navegador real; Ctrl+C |
| Interfaz interna no accesible desde el entorno ni la CLI | |
| `serve`: puerto por defecto y personalizado, ocupado, privilegiado, inválido, sin python3, no local con y sin `--yes`, Ctrl+C (pty) | |
| `urb help`, secciones, `urb-help` idéntico, `urb manual`; instalación y desinstalación de `urb-help` | |
| Cobertura de la documentación y ejemplos válidos | |

**Prueba en Kali**

```bash
cd ~/urb-tools && git pull && ./install.sh
urb-help                                   # ayuda general (también: urb help)
urb-help red recon                         # modificadores generados desde el .spec
urb red lab use demo
urb red recon quick versions --dry-run     # comando nmap exacto, sin ejecutar
urb red recon versions quick --dry-run     # mismo comando
urb red recon quick versions               # escaneo real → S-00N
urb red scans && urb red services
urb red recon quick full                   # error: incompatibles
cd ~/urb-labs/demo && urb serve            # http://127.0.0.1:8000/ → abrir en el navegador → Ctrl+C
urb serve --bind 0.0.0.0                   # pide confirmación
urb manual                                 # manual completo (q para salir)
urb manual examples
urb red                                    # dentro: urb red recon <Tab><Tab> · urb serve --<Tab> · urb help red <Tab>
```

**Limitaciones:** el motor gestiona `red recon` y `serve`; el resto de comandos conserva su propio análisis de argumentos (migrarlos es trabajo futuro). Los ejemplos de `.spec` están en inglés, como el resto de la ayuda de la CLI; el manual está en español. `urb manual` usa `less` (sin renderizar Markdown).

## 2026-11-12 · Dashboard 2.0: centro de control (GOD, RED, BLUE, Zsh normal)

**Entorno de prueba:** WSL Ubuntu 26.04 (bash 5.3, tmux 3.6, zsh), pseudo-terminal real con `script` y capturas de pantalla con `tmux capture-pane`. **No se ha probado en QTerminal ni en Kali**: nada de lo de abajo es una prueba visual en QTerminal.

**Qué cambia**
- **Menú en tres secciones**, todo a una tecla y sin submenús:
  - TERMINAL ENVIRONMENTS: `G` GOD · `R` RED · `B` BLUE (*COMING SOON*, atenuado y no seleccionable) · `Z` NORMAL SHELL.
  - CYBERSECURITY TOOLS: `1`–`5`, con los mismos números de siempre.
  - SYSTEM: `6` SETTINGS · `S` SESSIONS · `H` HELP · `Q`/`Esc` EXIT. El refresco manual pasa de `r` a `Ctrl+L`.
- **Elementos como datos** (`DASH_ITEMS`: sección, tecla, tipo, destino, estado `ready`/`soon`). Un perfil futuro (DEV, BLUE) es una línea más su `.profile`.
- **GOD y RED:** se lanzan como procesos hijos con los lanzadores de siempre (`urb_god`, `red_main`, `sessions_attach`, que hacen `exec god.sh` dentro de una subshell). No hay ninguna implementación paralela.
  - Al volver se distingue entre detach, salida y fallo, usando el código de `god.sh` y el estado real de la sesión **después**.
  - El menú muestra `● detached` / `● attached` en vivo.
- **NORMAL SHELL:** `zsh -i` real en el directorio actual, con la configuración del usuario.
  - Si `urb` se abrió dentro de GOD/RED, se restaura el `ZDOTDIR` del usuario y se quitan `URB_GOD`, `URB_PROFILE*` y las opciones globales (`-y`).
  - `exit` vuelve al dashboard. Si falta zsh o termina al arrancar, aparece un aviso y se sigue en el menú.
- **Diseño adaptable:** mínimo 50×12, arriba a la izquierda.
  - Primero se ocultan los paneles de información y después el menú se desplaza (`↑ more` / `↓ more`).
  - Desde 100 columnas, el menú va a la izquierda y los paneles se apilan a la derecha.
- **`START_MODE=dashboard|god|red`** (por defecto `dashboard`). Se valida en `urb config set`; `blue` y otros valores se rechazan con el código 2.
  - Si el valor guardado no es válido o el entorno no abre, se informa y se abre el dashboard.
  - `urb dashboard` abre siempre el menú.

**Estado de la terminal (`lib/ui.sh`)**
- Un único punto de entrada y salida, idempotente: `ui_screen_enter` / `ui_screen_leave`.
- El `stty` se guarda una vez (el de la shell que lanzó `urb`) y es el que se restaura siempre.
- `ui_mouse_reset` apaga solo los modos de informe de ratón (1000/1002/1003/1005/1006/1015), y solo tras un hijo con tmux. No toca 1007 ni otras preferencias.
- **Traps:** se añaden `QUIT` (antes, `Ctrl+\` mataba la TUI sin pasar por `EXIT` y dejaba la pantalla alternativa y el eco apagado) y `TSTP` (antes, `Ctrl+Z` detenía la TUI y devolvía la shell en la pantalla alternativa).
- Mientras corre un hijo, el dashboard instala manejadores no-op (no «ignorar», que heredaría el hijo). La señal llega al hijo con su acción normal y Bash ejecuta el manejador cuando el hijo termina.

**Rueda del ratón (investigación).** Hipótesis: si la shell se queda en la **pantalla alternativa**, QTerminal (como otros terminales con *alternate scroll*) convierte la rueda en flechas ↑/↓, y Zsh recorre el historial. Sin reproducir en QTerminal, así que **no está confirmado**. Lo que sí se reprodujo en pty:
- **`godmode/god.sh`: Ctrl+C durante la animación de salida** (tras `Ctrl+B d` o `exit`) dejaba la terminal en la pantalla alternativa y con el cursor oculto, **3 de 3 veces**. `god_fx_disengage` entraba en ella sin trap.
  - Corregido con `_god_fx_out` (trap que restaura y sale con 130); con el arreglo, 3 de 3 restauradas.
  - Test de regresión: `test_god_ctrl_c_during_exit_animation_restores_screen`.
- `Ctrl+\` y `Ctrl+Z` en el dashboard tenían el mismo efecto (corregido, ver arriba).
- El dashboard 2.0 abre la Zsh normal y GOD/RED **fuera** de la pantalla alternativa (comprobado en el flujo de bytes).

| Feature | Código | Tests | Instalado | Probado en vivo |
|---|---|---|---|---|
| Menú en secciones, todas las opciones, BLUE deshabilitado | ✅ | ✅ | — | ✅ WSL (pty + capture-pane 120x40, 80x24, 60x16, 50x12); ❌ QTerminal |
| Navegación (↑↓ salta BLUE, teclas, desplazamiento) | ✅ | ✅ | — | ✅ WSL pty |
| GOD desde el menú: detach → menú, reconexión a la misma sesión, procesos vivos, exit | ✅ | ✅ | — | ✅ WSL pty; ❌ QTerminal |
| RED desde el menú, aislamiento GOD/RED | ✅ | ✅ | — | ✅ WSL pty; ❌ QTerminal/Kali |
| NORMAL SHELL (directorio, alias, sin variables URB, Ctrl+C, exit → menú) | ✅ | ✅ | — | ✅ WSL pty; ❌ QTerminal |
| SESSIONS (reconectar) y sesión compartida con otra terminal (2 clientes, sin robarla) | ✅ | ✅ | — | ✅ WSL pty |
| tmux anidado, errores de arranque (falta tmux/zsh, zsh que sale) | ✅ | ✅ | — | ✅ WSL pty |
| Señales (Ctrl+C/\/Z en el menú; hijo muerto por SIGINT) y stty/cursor/pantalla restaurados | ✅ | ✅ | — | ✅ WSL pty |
| `START_MODE` (validación, god, red, inválido, recuperación) | ✅ | ✅ | — | ✅ WSL pty |
| Ctrl+C en la animación de salida de GOD/RED | ✅ | ✅ | — | ✅ WSL pty (reproducido y corregido) |
| Rueda del ratón en QTerminal tras GOD/RED | — | — | — | ❌ pendiente: solo hipótesis |

Resultado: `bash tests/run.sh` → 158/158 · `shellcheck -S warning` → 0 avisos. No se ha instalado con `./install.sh` en esta sesión.

**Prueba en Kali / QTerminal** (instalar primero: `cd ~/urb-tools && git pull && ./install.sh`). En cada paso, comprueba también la rueda del ratón **sobre la salida de la shell** (debe desplazar el texto, no recorrer el historial):

```bash
seq 1 300                      # 0) referencia: la rueda desplaza la salida ANTES de usar urb
urb                            # 1) dashboard: secciones, BLUE atenuado "COMING SOON"; ↑↓ salta BLUE
#    B → "coming soon"; redimensiona la ventana pequeña → el menú se desplaza (↓ more)
#    Z → "Normal zsh (opened from URB)"; prompt de siempre, sin HUD
seq 1 300                      # 2) rueda en la Zsh normal → desplaza la salida
exit                           #    → vuelve al dashboard
#    G → GOD; ejecuta: sleep 600 ; luego Ctrl+B d → menú con "God Mode detached" y GOD "● detached"
#    G → reconecta: sigue el sleep (Ctrl+C lo corta); exit → "God Mode session ended (exit)"
#    R → RED con el laboratorio/objetivo de la carpeta; Ctrl+B d → menú; S → Enter en URB Red → reconecta → Ctrl+B d
#    q → QTerminal
seq 1 300                      # 3) rueda tras salir de urb → debe desplazar la salida
urb red                        # 4) sin dashboard: Ctrl+B d e INMEDIATAMENTE Ctrl+C durante la animación de salida
seq 1 300                      #    rueda → debe desplazar (antes del arreglo la terminal quedaba en pantalla alternativa)
urb config set START_MODE god && urb   # 5) entra directo en GOD; Ctrl+B d → vuelve a QTerminal
urb config set START_MODE dashboard
urb sessions                   # 6) estado final; urb sessions kill red / god si quieres cerrarlas
```

Si la rueda falla en algún paso, anota **en cuál**, y prueba `printf '\e[?1049l'`: si eso lo arregla, la terminal se había quedado en la pantalla alternativa.

**Limitaciones:**
- Los entornos tmux necesitan que `urb` no corra dentro de otro tmux (por diseño).
- Con `START_MODE=god|red`, `urb` espera a que termine GOD/RED como proceso hijo (para poder recuperar el dashboard si falla).
- BLUE no tiene perfil ni módulos (a propósito).
- Sin `~/.zshrc`, una Zsh real abre su asistente de primer uso (`zsh-newuser-install`) también desde NORMAL SHELL. Es lo esperado; en Kali el `.zshrc` ya existe.

Instalación comprobada: `./install.sh --yes` en un HOME temporal de WSL; el `urb` instalado abre GOD, hace detach y vuelve al menú, abre la Zsh normal y vuelve, y sale con código 0. La sesión GOD sigue viva.

## 2026-11-12 · Rueda del ratón dentro de GOD/RED (causa confirmada y corregida)

**Causa (confirmada por Diego en QTerminal):**
- El problema no estaba en el dashboard, sino en el diseño de GOD/RED.
- tmux siempre dibuja en la pantalla alternativa, y con `GOD_MOUSE=0` (antes, el valor por defecto) no pide el ratón.
- En ese caso QTerminal convierte la rueda en ↑/↓, que Zsh usa para recorrer el historial.
- En la Zsh normal (sin tmux) la rueda funcionaba bien.
- Prueba hecha: con `urb config set GOD_MOUSE 1` + sesión nueva, la rueda desplaza la salida.

**Cambio:**
- **Ratón activado por defecto:** `GOD_MOUSE=1` por defecto.
- **Se aplica también al reconectar:** `god.sh` lo aplica al crear **y al reconectar** la sesión, así que cambiar la configuración no obliga a cerrarla.
- **Rueda en `godmode/tmux.conf`** (`WheelUpPane` / `WheelDownPane`):
  - si el programa del panel usa el ratón, o el panel ya está desplazándose, se le pasa el evento;
  - en programas a pantalla completa sin ratón (`less`, `vim`) se envían 3 flechas;
  - en la shell, entra en el modo de desplazamiento de tmux (`copy-mode -e`, que sale solo al volver abajo).
- **Selección de texto con QTerminal:** Shift + arrastrar.

**Tests (WSL, pty real):** se envían eventos de rueda SGR (`\e[<64;…M`) al pty.
- En la shell → modo de desplazamiento con posición > 0.
- En un programa en pantalla alternativa → recibe `ESC [ A` ×3 y tmux no se desplaza.
- `GOD_MOUSE=0` + reconexión → `mouse off`.
- Comprobado que el test falla con el ratón desactivado.

| Feature | Código | Tests | Instalado | Probado en vivo |
|---|---|---|---|---|
| Rueda en GOD/RED (shell) | ✅ | ✅ | ✅ Kali | ✅ QTerminal (Diego, 2026-11-12, tras instalar 8f1ff6f) |
| Rueda en less/vim dentro de GOD/RED | ✅ | ✅ | — | ❌ QTerminal |
| Shift + arrastrar para seleccionar | — | — | — | ❌ QTerminal |
| GOD_MOUSE aplicado al reconectar | ✅ | ✅ | — | ✅ WSL pty |

**Prueba en QTerminal:**

```bash
cd ~/urb-tools && git pull && ./install.sh
grep GOD_MOUSE ~/.config/urb-tools/urb.conf   # si pone "0" (copiado por 'urb config init'): urb config set GOD_MOUSE 1
urb                      # → G (o R)
seq 1 300                # rueda arriba: sube por la salida; rueda abajo hasta el final (o q): vuelve al prompt
man ls                   # rueda: avanza/retrocede en man (q para salir)
# Shift + arrastrar sobre un texto → Ctrl+Shift+C → pegar con Ctrl+Shift+V
# Ctrl+B d → dashboard → q → seq 1 300 → la rueda desplaza en QTerminal normal
```

**Nota:** quien ya tenga `GOD_MOUSE="0"` en su `urb.conf` (lo copia `urb config init`) seguirá sin ratón hasta cambiarlo.

**Confirmación (2026-11-12):** con `8f1ff6f` instalado en Kali, Diego indica que la rueda «parece funcionar correctamente» en QTerminal. No ha detallado qué pasos probó: la rueda en `less`/`man` y la selección con Shift + arrastrar siguen sin confirmarse por separado.

# URB Red v0.2 — flujo de investigación

Los vínculos guardan claves de servicio sin copiar el inventario; la comparación
lee XML existentes y diferencia estados explícitos de ausencias. Los informes
Markdown se crean con nombres nuevos y mantienen el `report.md` manual.

# URB Blue v0.1

Workspace SOC offline con importaciones transaccionales SQLite, procedencia de
fuentes y una regla 4625. El perfil utiliza su propio socket y preserva RED/GOD.
