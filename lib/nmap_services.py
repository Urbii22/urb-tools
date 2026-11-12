#!/usr/bin/env python3
# =============================================================================
#  lib/nmap_services.py — Inventario de servicios a partir del XML de nmap
#  Solo biblioteca estándar (xml.etree). Solo lee ficheros: sin red.
#
#  Entrada (stdin), una línea por escaneo:  S-001<TAB>epoch<TAB>/ruta/al.xml
#  Salida (stdout), formato de la caché <lab>/scans/.services:
#    #scan<TAB>S-001<TAB>ok|partial|incomplete|invalid|missing<TAB>hosts<TAB>detalle
#    svc<TAB>host<TAB>proto<TAB>port<TAB>state<TAB>service<TAB>product<TAB>version
#       <TAB>extrainfo<TAB>hostname<TAB>last_scan<TAB>last_epoch<TAB>last_quality
#       <TAB>first_scan<TAB>first_epoch<TAB>history
#
#  Reglas:
#   - Clave única: host + protocolo + puerto (sin duplicados entre escaneos).
#   - Vale la observación MÁS RECIENTE de esa clave (por hora del escaneo y,
#     a igualdad, por ID). Si un escaneo posterior no incluye el puerto, NO se
#     interpreta como cerrado: simplemente no hay observación nueva.
#   - El historial guarda todas las observaciones (escaneo:estado).
#   - XML truncado: se conservan los hosts completos leídos antes del error
#     (calidad "partial"); un XML sin <finished> es "incomplete". Un fichero
#     roto nunca afecta a los demás.
#   - Lo que nmap no informa queda vacío (se muestra como desconocido).
# =============================================================================
import sys
import xml.etree.ElementTree as ET


def clean(value):
    """Texto de una línea, sin tabuladores ni caracteres de control."""
    if value is None:
        return ""
    return "".join(ch if ch.isprintable() and ch != "\t" else " " for ch in str(value)).strip()


def host_info(host):
    addr, hostname = "", ""
    for a in host.findall("address"):
        t = a.get("addrtype", "")
        if t in ("ipv4", "ipv6"):
            addr = a.get("addr", "")
            if t == "ipv4":
                break
    if not addr:
        a = host.find("address")
        if a is not None:
            addr = a.get("addr", "")
    hn = host.find("hostnames/hostname")
    if hn is not None:
        hostname = hn.get("name", "")
    return clean(addr), clean(hostname)


def parse_scan(path):
    """Devuelve (calidad, observaciones, detalle). Nunca lanza excepciones."""
    obs = []
    finished = False
    root_ok = False
    hosts = 0
    try:
        for event, elem in ET.iterparse(path, events=("start", "end")):
            if event == "start" and elem.tag == "nmaprun":
                root_ok = True
            if event != "end":
                continue
            if elem.tag == "finished":
                finished = True
            elif elem.tag == "host":
                hosts += 1
                addr, hostname = host_info(elem)
                for p in elem.findall("ports/port"):
                    st = p.find("state")
                    sv = p.find("service")
                    obs.append({
                        "host": addr,
                        "hostname": hostname,
                        "proto": clean(p.get("protocol", "")),
                        "port": clean(p.get("portid", "")),
                        "state": clean(st.get("state", "") if st is not None else ""),
                        "service": clean(sv.get("name", "") if sv is not None else ""),
                        "product": clean(sv.get("product", "") if sv is not None else ""),
                        "version": clean(sv.get("version", "") if sv is not None else ""),
                        "extrainfo": clean(sv.get("extrainfo", "") if sv is not None else ""),
                    })
                elem.clear()
    except FileNotFoundError:
        return "missing", [], "XML file not found"
    except ET.ParseError as exc:
        if not root_ok:
            return "invalid", [], "not a valid nmap XML (%s)" % clean(exc)
        return "partial", obs, "XML truncated or damaged (%s); %d host(s) recovered" % (clean(exc), hosts)
    except OSError as exc:
        return "invalid", [], "cannot read XML (%s)" % clean(exc)
    if not root_ok:
        return "invalid", [], "not an nmap XML"
    if not finished:
        return "incomplete", obs, "scan did not finish (no <finished>); %d host(s) read" % hosts
    return "ok", obs, "%d host(s)" % hosts


def main():
    scans = []
    for line in sys.stdin:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 3:
            continue
        sid, epoch, path = parts
        try:
            epoch = int(epoch)
        except ValueError:
            epoch = 0
        try:
            num = int(sid.split("-", 1)[1])
        except (IndexError, ValueError):
            continue
        scans.append((epoch, num, sid, path))
    scans.sort()

    inventory = {}
    out = sys.stdout
    for epoch, _num, sid, path in scans:
        quality, observations, detail = parse_scan(path)
        hosts = len({o["host"] for o in observations})
        out.write("#scan\t%s\t%s\t%d\t%s\n" % (sid, quality, hosts, clean(detail)))
        for o in observations:
            if not o["host"] or not o["port"] or not o["proto"]:
                continue
            key = (o["host"], o["proto"], o["port"])
            entry = inventory.get(key)
            if entry is None:
                entry = {"first_scan": sid, "first_epoch": epoch, "history": []}
                inventory[key] = entry
            # Orden cronológico: la última observación procesada es la más reciente
            entry.update(o)
            entry["last_scan"] = sid
            entry["last_epoch"] = epoch
            entry["last_quality"] = quality
            entry["history"].append("%s:%s" % (sid, o["state"] or "unknown"))

    def sort_key(item):
        (host, proto, port), _e = item
        try:
            p = int(port)
        except ValueError:
            p = 0
        return (host, proto, p)

    for (host, proto, port), e in sorted(inventory.items(), key=sort_key):
        out.write("\t".join([
            "svc", host, proto, port, e["state"], e["service"], e["product"], e["version"],
            e["extrainfo"], e["hostname"], e["last_scan"], str(e["last_epoch"]), e["last_quality"],
            e["first_scan"], str(e["first_epoch"]), " ".join(e["history"]),
        ]) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
