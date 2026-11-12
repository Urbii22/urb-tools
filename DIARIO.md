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
