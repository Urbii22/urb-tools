# =============================================================================
#  commands/red-recon.spec — 'urb red recon <modificadores>' (Command Engine)
#  DATOS: se leen y validan; nunca se ejecutan. Las opciones de nmap de cada
#  modificador están en la configuración (RECON_BASE, RECON_MOD_<nombre>) para
#  que puedas ajustarlas en ~/.config/urb-tools/urb.conf.
# =============================================================================
name=red recon
summary=Nmap reconnaissance of the lab target, built from short modifiers
usage=urb red recon <modifier>... [--target <ip|host>] [--sudo] [--dry-run]   |   urb red recon initial
requires=nmap
group=ports|each one chooses which ports are scanned (quick: top 100, full: all 65535, udp: top 50 UDP)
modifier=quick|ports||Top 100 TCP ports (fast first look)
modifier=full|ports||All 65535 TCP ports (slow, thorough)
modifier=udp|ports|root|Top 50 UDP ports instead of TCP (needs root)
modifier=versions|||Service and version detection (-sV)
modifier=scripts|||Default NSE scripts (-sC)
modifier=os||root|Operating system detection (needs root)
modifier=slow|||Lower timing (-T2) instead of the base timing: less load on the target. It is NOT stealthier or undetectable
option=target|target|||Target for this run only (default: the lab target; the saved target is not changed)
option=sudo|flag|||Run nmap through sudo without asking (only nmap runs as root)
option=dry-run|flag|||Show the exact nmap command, target and output path; run nothing, create nothing
note=Without modifiers, 'urb red recon' shows this help. 'urb red recon initial' keeps working as before (profile 'default').
note=Base options come from RECON_BASE (default "-T4 --open"); each modifier adds RECON_MOD_<name>. 'slow' replaces the base -T value.
note=Results are saved in <lab>/scans/ with the modifiers in the name (e.g. 10.10.10.3_quick-versions_...) and get an S-NNN ID.
example=urb red recon quick versions
example=urb red recon versions quick              (same command as above)
example=urb red recon full versions scripts
example=urb red recon quick --target 10.10.10.30 --dry-run
example=urb red recon udp --sudo
