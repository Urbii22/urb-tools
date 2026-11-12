# URB-Tools — Ejemplos de uso

Flujos completos, de principio a fin. Todos los comandos existen tal cual en la CLI. La referencia de cada comando está en [COMMANDS.md](COMMANDS.md) (`urb manual`).

> Usa estos flujos solo contra sistemas propios o con autorización explícita. Los ejemplos con `127.0.0.1` funcionan en tu propia máquina, sin otra máquina virtual.

---

## 1. Crear un laboratorio y recuperarlo otro día

```bash
urb red lab new demo --target 127.0.0.1     # crea ~/urb-labs/demo y lo selecciona
urb red status                              # laboratorio, objetivo, escaneos, hallazgos, VPN y sesión
urb red notes add "Empiezo la enumeración"
```

Otro día, aunque hayas reiniciado Kali:

```bash
urb red lab list                            # tus laboratorios (indica el seleccionado)
urb red lab use demo
urb red status                              # todo sigue ahí: objetivo, escaneos, hallazgos y notas
cd "$(urb red lab path)"                    # entrar en la carpeta (dentro de URB Red: urblab)
```

Prioridad del contexto: si estás dentro de la carpeta de otro laboratorio, se usa ese y no el seleccionado.

```bash
cd ~/urb-labs/otro-lab/notes && urb red target show    # objetivo de 'otro-lab'
```

---

## 2. Ejecutar nmap y consultar los servicios

Un servicio local de prueba y un escaneo real contra tu propia máquina:

```bash
python3 -m http.server 8080 --bind 127.0.0.1 &       # servicio de prueba
urb red recon initial                                # perfil 'default' contra el objetivo del laboratorio
urb red scans                                        # S-001 … con fecha, perfil y estado
urb red scans show latest                            # detalle y puertos del último escaneo completo
urb red services                                     # 127.0.0.1  8080/tcp  open  http  SimpleHTTPServer …
urb red services show 8080                           # versión, procedencia e historial
kill %1                                              # parar el servicio de prueba
```

Tras un escaneo posterior en el que el puerto aparezca cerrado:

```bash
urb red services                 # el 8080 ya no aparece como abierto
urb red services --all           # aparece como 'closed'; el historial lo muestra: S-001=open S-002=closed
```

---

## 3. Registrar un hallazgo y asociarle evidencias

```bash
urb red findings add "HTTP 8080 con listado de directorios" --desc "python http.server en 8080"
urb red findings status F-001 investigating
urb red findings note F-001 "El índice muestra todos los ficheros de la carpeta"
urb red findings evidence F-001 --scan latest        # el .nmap del último escaneo, sin escribir rutas
curl -s http://127.0.0.1:8080/ > ~/urb-labs/demo/evidence/listing.html
urb red findings evidence F-001 evidence/listing.html
urb red findings status F-001 confirmed              # verificado con evidencia (no implica gravedad)
urb red findings show F-001                          # notas, evidencias e historial
urb red findings                                     # lista + resumen
```

Una comprobación que no da nada también se registra:

```bash
urb red findings add "SSH: autenticación por contraseña" --status investigating
urb red findings status F-002 checked                # comprobado, sin hallazgo
```

Evidencias que se rechazan, a propósito:

```bash
urb red findings evidence F-001 /etc/passwd          # fuera del laboratorio → error
cp /ruta/de/fuera/captura.png ~/urb-labs/demo/evidence/
urb red findings evidence F-001 evidence/captura.png # ahora sí
```

---

## 4. Gestionar sesiones GOD y RED

```bash
urb god                       # se abre God Mode → trabaja… → Ctrl+B d (desconectar)
urb red                       # se abre URB Red → Ctrl+B c (ventana nueva, también [RED]) → Ctrl+B d
urb sessions                  # god detached · red detached
urb sessions info red         # ventanas, paneles (comando y directorio)
urb sessions attach red       # volver a RED (si no existiera, error: no crea ninguna)
urb sessions kill red         # pide confirmación → y
urb sessions                  # red none · god detached (God Mode intacto)
urb god                       # reconectar a God Mode → exit → "God Mode off. Session ended…"
```

Lo mismo sin salir del dashboard:

```text
urb                           # dashboard
  G                           # GOD MODE (crea o reconecta)  → trabaja… → Ctrl+B d
                              # de vuelta en el menú: "God Mode detached: your programs keep running"
                              # y GOD MODE marcado "● detached"
  R                           # RED MODE → Ctrl+B d → de vuelta en el menú (RED también "● detached")
  S                           # SESSIONS: God Mode / URB Red con su estado → Enter reconecta
  G                           # vuelve a la MISMA sesión de GOD (sus programas siguen ahí)
                              # → exit → "God Mode session ended (exit)"
  q                           # salir del dashboard: RED sigue viva en segundo plano
urb sessions                  # red detached · god none
```

Dentro de URB Red:

```bash
urblab                        # ir a la carpeta del laboratorio en esta misma shell
urb red findings evidence F-001 --scan <Tab>   # autocompleta latest, S-001…
```

---

## 5. Servidor HTTP local

```bash
cd ~/urb-labs/demo/exploits
urb serve                                     # http://127.0.0.1:8000/  (Ctrl+C para parar)
urb serve --port 8080
urb serve --dir ~/urb-labs/demo/evidence --port 9000
urb serve --bind 0.0.0.0 --port 8080          # expone los ficheros a tu red: pide confirmación
urb serve --bind 0.0.0.0 --port 8080 --yes    # confirmación explícita, sin preguntar
```

Si el puerto está ocupado:

```bash
urb serve --port 8080          # "Port 8080 is already in use … urb serve --port 8081"
```

URB no abre puertos en el firewall: que otra máquina pueda conectarse depende de tu red.

---

## 6. Modificadores del Command Engine

```bash
urb red recon quick versions --dry-run       # previsualiza: comando nmap exacto, objetivo y salida
urb red recon versions quick --dry-run       # el mismo comando (el orden no importa)
urb red recon quick versions                 # ejecutar
urb red recon full versions scripts          # todos los puertos TCP + versiones + scripts
urb red recon slow versions                  # -T2 en lugar de -T4: menos carga (no es más sigiloso)
urb red recon udp --sudo                     # top 50 UDP (necesita root; solo nmap se ejecuta con sudo)
urb red recon quick --target 10.10.10.30     # otro objetivo solo para esta ejecución
urb red recon quick full                     # error: quick y full eligen puertos, solo uno
urb help red recon                           # modificadores, opciones y notas
```

Ajustar lo que hace cada modificador en tu configuración:

```bash
urb config set RECON_MOD_quick "--top-ports 200"
urb red recon quick --dry-run                # ahora con --top-ports 200
```

---

## 7. Consultar y modificar la configuración

```bash
urb config path                       # dónde está cada cosa
urb config show                      # configuración efectiva
urb config init                       # crea ~/.config/urb-tools/urb.conf (no sobrescribe)
urb config set ANIMATIONS 0           # sin animaciones
urb config set GOD_HUD_POSITION bottom
urb config set SERVE_PORT 9000        # 'urb serve' usará 9000 si no indicas --port
urb config set START_MODE red        # 'urb' entra directamente en URB Red
urb config set START_MODE dashboard  # volver al menú como inicio (valor por defecto)
urb config edit                       # abrir el fichero en tu editor
urb doctor                            # dependencias y entorno
```

---

## 8. Dashboard: terminal normal, GOD y RED desde el menú

```text
cd ~/urb-labs/htb-box           # el directorio desde el que abres urb es el de trabajo
urb                             # dashboard
  Z                             # NORMAL SHELL: tu Zsh con tu ~/.zshrc, sin HUD ni prompt URB
    git status; ls              # … todo funciona como en tu terminal
    exit                        # → de vuelta en el dashboard ("Normal shell closed")
  R                             # URB Red con el laboratorio de esta carpeta y su objetivo
    urb red recon quick         # …
    Ctrl+B d                    # → dashboard; el escaneo sigue corriendo dentro de RED
  B                             # "BLUE MODE: coming soon, not available yet" (no abre nada)
  H                             # ayuda (less: q para volver)
  q                             # salir a QTerminal
```

`exit` termina lo que hayas abierto (en GOD/RED, la sesión entera si era su última shell); `Ctrl+B d` solo se desconecta y lo deja todo en marcha. En ambos casos vuelves al dashboard.

Si `urb` se abre dentro de otra sesión tmux, `G`/`R` muestran *cannot start inside another tmux session*: desconéctate de ese tmux y vuelve a abrir `urb`.

---

## 9. Ayuda y manual

```bash
urb help                    # resumen de todos los comandos
urb help red                # todas las secciones de URB Red
urb help red scans          # solo una sección
urb-help red findings       # lo mismo con el acceso directo
urb-help serve
urb manual                  # este manual completo (less)
urb manual examples         # estos ejemplos
urb manual path             # rutas de los ficheros
```
