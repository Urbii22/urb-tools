#!/usr/bin/env python3
"""Offline RED investigation output; Nmap XML and URB files remain authoritative."""
import datetime
import os
import re
import sys
import tempfile
from pathlib import Path

from nmap_services import clean, parse_scan


def cell(value):
    return clean(value).replace("|", "\\|") or "unknown"


def index(lab):
    rows = []
    path = lab / "scans" / ".index"
    if path.exists():
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.fullmatch(r"(S-\d{1,6})\|([A-Za-z0-9][A-Za-z0-9._:,+-]{0,200})\|(\d{1,12})", line)
            if m:
                rows.append(m.groups())
    return rows


def diff(a, b, ida, idb, profile_a, profile_b):
    ha, hb = set(), set()
    qa, oa, da = parse_scan(a, ha)
    qb, ob, db = parse_scan(b, hb)
    if qa in ("invalid", "missing") or qb in ("invalid", "missing"):
        raise ValueError(f"Cannot compare XML: {ida}: {qa} ({da}); {idb}: {qb} ({db})")
    print(f"Comparing {ida} ({profile_a}, {qa}) → {idb} ({profile_b}, {qb})")
    print("Coverage may differ; absence is never interpreted as closed.")
    if qa != "ok" or qb != "ok" or profile_a != profile_b or "unknown" in (profile_a, profile_b):
        print("UNCERTAIN: partial/incomplete XML or different/unknown profiles; coverage may be insufficient.")
    print(f"Hosts {ida}: {', '.join(sorted(ha)) or 'none observed'}")
    print(f"Hosts {idb}: {', '.join(sorted(hb)) or 'none observed'}")
    def keyed(obs):
        return {(o['host'], o['proto'], o['port']): o for o in obs if o['host'] and o['proto'] and o['port']}
    left, right = keyed(oa), keyed(ob)
    print("HOST | PORT | OBSERVATION | BEFORE | AFTER")
    count = 0
    for key in sorted(left.keys() | right.keys()):
        x, y = left.get(key), right.get(key)
        host, proto, port = key
        changes = []
        if x is None:
            changes.append(("newly observed open" if y['state'] == 'open' else "not observed before", "not observed", y['state'] or 'unknown'))
        elif y is None:
            changes.append(("not observed after", x['state'] or 'unknown', "not observed"))
        else:
            for label, fields in (("explicit state change", ('state',)), ("service identification", ('service',)), ("version", ('product', 'version', 'extrainfo'))):
                old = ' '.join(x[f] for f in fields if x[f]) or 'unknown'
                new = ' '.join(y[f] for f in fields if y[f]) or 'unknown'
                if old != new:
                    changes.append((label, old, new))
        for label, old, new in changes:
            print(f"{cell(host)} | {cell(port)}/{cell(proto)} | {label} | {cell(old)} | {cell(new)}")
            count += 1
    if not count:
        print("No differences in recorded port observations.")


def report(lab):
    metadata = {}
    for line in (lab / '.urb-lab').read_text(encoding='utf-8', errors='replace').splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            metadata[k] = v
    scans = index(lab)
    findings = sorted((lab / 'findings').glob('F-*.finding')) if (lab / 'findings').is_dir() else []
    out = [f"# Investigation report — {cell(metadata.get('name', lab.name))}", '',
           f"- Target: {cell(metadata.get('target', ''))}", f"- Generated: {datetime.datetime.now().astimezone().isoformat(timespec='seconds')}",
           '', '## Executive summary', '', f"{len(scans)} indexed scan(s) and {len(findings)} finding file(s) are recorded. An observed service is not evidence of a vulnerability.",
           '', '## Scans and provenance', '', '| ID | Profile / source | XML |', '|---|---|---|']
    for sid, base, _ in scans:
        m = re.match(r'^(.+)_([A-Za-z0-9]+(?:-[A-Za-z0-9]+)*)_\d{8}-\d{6}(?:-\d+)?$', base)
        out.append(f"| {cell(sid)} | {cell(m.group(2) if m else 'unknown')} | {cell('scans/' + base + '.xml')} ({'present' if (lab / 'scans' / (base + '.xml')).is_file() else 'missing'}) |")
    if not scans:
        out.append('| — | No scans recorded | — |')
    out += ['', '## Hosts and services', '', '| Host | Port | State | Service | Version | Last observation |', '|---|---|---|---|---|---|']
    cache = lab / 'scans' / '.services'
    entries = 0
    warnings = []
    observed_hosts = set()
    if cache.exists():
        for line in cache.read_text(encoding='utf-8', errors='replace').splitlines():
            f = line.split('\t')
            if len(f) >= 3 and f[0] == '#scan' and f[2] != 'ok':
                warnings.append(f"{f[1]}: {f[2]} — {f[4] if len(f) > 4 else 'unknown'}")
            if len(f) >= 3 and f[0] == '#host':
                observed_hosts.add((f[2], f[1]))
            if len(f) >= 13 and f[0] == 'svc':
                out.append('| ' + ' | '.join(map(cell, [f[1], f'{f[3]}/{f[2]}', f[4], f[5], ' '.join(f[6:9]), f'{f[10]} ({f[12]})'])) + ' |')
                entries += 1
    if not entries:
        out.append('| — | — | No service observations | — | — | — |')
    out += ['', '### Observed hosts and source scans', '']
    out.extend(f"- {cell(host)} — {cell(sid)}" for host, sid in sorted(observed_hosts))
    if not observed_hosts:
        out.append('No host observations recorded in the inventory cache.')
    out += ['', '## Findings', '']
    if not findings:
        out.append('No findings recorded.')
    for path in findings:
        fields = {}
        malformed = False
        for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                fields.setdefault(k, []).append(v)
            elif line:
                malformed = True
        get = lambda k: fields.get(k, [''])[0]
        out += [f"### {cell(path.stem)} — {cell(get('title'))}", '', f"- Status (recorded): {cell(get('status'))}", f"- Description: {cell(get('desc'))}"]
        if malformed or get('id') != path.stem or not get('title') or get('status') not in ('pending', 'investigating', 'suspected', 'confirmed', 'discarded', 'checked', 'potential', 'completed', 'done'):
            out.append('- WARNING: finding data appears damaged; review the source file.')
        for key in fields.get('service_link', []):
            out.append(f"- Linked service key: {cell(key)}")
        evidence = fields.get('evidence', [])
        if not evidence:
            out.append('- Evidence: none linked.')
        for e in evidence:
            resolved = (lab / e).resolve()
            try:
                resolved.relative_to(lab.resolve())
                present = resolved.is_file()
            except ValueError:
                present = False
            out.append(f"- Evidence: {cell(e)} ({'present' if present else 'missing or outside lab'})")
        for note in fields.get('note', []):
            out.append(f"- Investigation note: {cell(note)}")
        out.append('')
    out += ['## Research notes', '']
    notes = lab / 'notes' / 'notes.md'
    out.append(notes.read_text(encoding='utf-8', errors='replace') if notes.is_file() else 'No notes recorded.')
    out += ['', '## Limitations and pending checks', '', '- Observations depend on scan coverage and time; a missing port is not necessarily closed.', '- Check partial, failed or missing XML and verify evidence independently. Pending and suspected findings are not confirmed.', '- This report reproduces recorded statuses; it does not validate vulnerability claims or evidence.']
    out.extend('- Scan quality: ' + cell(w) for w in warnings)
    out.append('')
    return '\n'.join(out)


def main():
    mode, lab_arg, *args = sys.argv[1:]
    lab = Path(lab_arg)
    if mode == 'diff':
        diff(*args)
    elif mode == 'preview':
        print(report(lab), end='')
    elif mode == 'generate':
        content = report(lab)
        destination = Path(args[0]) if args else lab / 'reports' / ('report-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.md')
        if not args:
            destination.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix='.urb-report-', dir=destination.parent)
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as output:
                output.write(content)
            os.link(temporary, destination)  # atomic, fails if destination exists
        finally:
            os.unlink(temporary)
        print(f'Report created: {destination}')
    else:
        raise ValueError('unknown operation')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        sys.exit(1)
