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
