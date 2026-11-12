#!/usr/bin/env python3
"""URB BLUE offline investigation CLI."""
import argparse
import csv
import os
import re
import sqlite3
import sys
from pathlib import Path

from blue_store import connect, create_database, now, parse_id, valid_name, visible, clean
from blue_ingest import ingest, snapshot
from blue_detect import run as detect

ROOT = Path(os.environ.get('URB_BLUE_ROOT', '~/urb-blue')).expanduser()
STATE = Path(os.environ.get('XDG_DATA_HOME', '~/.local/share')).expanduser() / 'urb-tools' / 'state' / 'active-blue'


def ensure_private(path):
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.is_symlink() or not path.is_dir() or path.stat().st_uid != os.getuid():
        raise ValueError(f'unsafe directory: {path}')
    os.chmod(path, 0o700)


def workspace_by_name(name):
    if not valid_name(name):
        raise ValueError('invalid workspace name')
    if ROOT.is_symlink():
        raise ValueError('configured workspace directory cannot be a symlink')
    root = ROOT.resolve()
    path = root / name
    if path.is_symlink() or not path.is_dir() or (path / '.urb-blue').is_symlink() or not (path / '.urb-blue').is_file():
        raise ValueError(f'workspace not found: {name}')
    if path.resolve().parent != root:
        raise ValueError('workspace escapes configured directory')
    for part in ('sources', 'evidence'):
        sub = path / part
        if sub.is_symlink() or not sub.is_dir() or sub.resolve().parent != path.resolve():
            raise ValueError(f'unsafe workspace directory: {part}')
    dbpath = path / 'blue.sqlite3'
    if dbpath.is_symlink() or not dbpath.is_file():
        raise ValueError('workspace database missing or unsafe')
    return path


def active():
    try:
        name = STATE.read_text(encoding='utf-8').strip()
    except FileNotFoundError:
        raise ValueError('no workspace selected; run: urb blue workspace use <name>')
    return workspace_by_name(name)


def select(name):
    workspace_by_name(name)
    ensure_private(STATE.parent)
    import tempfile
    fd, tmp = tempfile.mkstemp(prefix='.active-blue-', dir=STATE.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(name + '\n')
        os.replace(tmp, STATE)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def workspace(args):
    if args.action == 'new':
        if not valid_name(args.name):
            raise ValueError('invalid workspace name')
        ensure_private(ROOT)
        path = ROOT.resolve() / args.name
        path.mkdir(mode=0o700)
        (path / 'sources').mkdir(mode=0o700)
        (path / 'evidence').mkdir(mode=0o700)
        create_database(path / 'blue.sqlite3')
        (path / '.hud').write_text('0 0\n', encoding='ascii')
        # Publish the marker last; incomplete directories never look usable.
        (path / '.urb-blue').write_text('version=1\n', encoding='utf-8')
        select(args.name)
        print(f'Workspace created and selected: {args.name}')
    elif args.action == 'use':
        select(args.name)
        print(f'Workspace selected: {args.name}')
    elif args.action == 'list':
        if ROOT.is_dir():
            for p in sorted(ROOT.iterdir()):
                if valid_name(p.name):
                    try:
                        workspace_by_name(p.name)
                        print(p.name)
                    except ValueError:
                        continue
    elif args.action == 'status':
        print(f'Workspace: {active()}')


def ref(db, table, value, prefix):
    ident = parse_id(value, prefix)
    if db.execute(f'SELECT 1 FROM {table} WHERE id=?', (ident,)).fetchone() is None:
        raise ValueError(f'{value} not found')
    return ident


def summary(db, path):
    counts = [db.execute('SELECT count(*) FROM ' + table).fetchone()[0] for table in ('sources', 'events', 'alerts', 'cases')]
    print(f'Workspace: {path.name}\nSources: {counts[0]}  Events: {counts[1]}  Alerts: {counts[2]}  Cases: {counts[3]}')


def update_hud(db, path):
    import tempfile
    db.execute('BEGIN IMMEDIATE')
    tmp = None
    try:
        alerts = db.execute('SELECT COUNT(*) FROM alerts WHERE merged_into IS NULL').fetchone()[0]
        cases = db.execute("SELECT COUNT(*) FROM cases WHERE status <> 'closed'").fetchone()[0]
        fd, tmp = tempfile.mkstemp(prefix='.hud-', dir=path)
        with os.fdopen(fd, 'w', encoding='ascii') as out:
            out.write(f'{alerts} {cases}\n')
        os.replace(tmp, path / '.hud')
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        if tmp and os.path.exists(tmp): os.unlink(tmp)


def history(db, kind, ident, text):
    db.execute('INSERT INTO history(object_type,object_id,created,action) VALUES(?,?,?,?)', (kind, ident, now(), text))


def cases(db, path, args):
    if args.action == 'list':
        for r in db.execute('SELECT * FROM cases ORDER BY id'):
            print(f'{visible("C",r["id"])} | {r["status"]} | {r["title"]}')
        return
    if args.action == 'new':
        title = clean(args.value)
        if not title or len(title) > 200 or args.extra or args.alert:
            raise ValueError('usage: cases new "title"')
        with db:
            cur = db.execute('INSERT INTO cases(title,created) VALUES(?,?)',(title,now()))
            history(db,'case',cur.lastrowid,'created')
        print(f'Created {visible("C",cur.lastrowid)}')
        return
    cid = ref(db, 'cases', args.value or '', 'C')
    if args.action == 'show':
        row = db.execute('SELECT * FROM cases WHERE id=?',(cid,)).fetchone()
        print(f'{visible("C",cid)} | {row["status"]} | {row["title"]}')
        print('Alerts: ' + ', '.join(visible('A',r[0]) for r in db.execute('SELECT alert_id FROM case_alerts WHERE case_id=? ORDER BY alert_id',(cid,))))
        for r in db.execute('SELECT created,text FROM case_notes WHERE case_id=? ORDER BY id',(cid,)): print(f'Note {r[0]}: {r[1]}')
        for r in db.execute('SELECT filename,sha256,path FROM evidence WHERE case_id=? ORDER BY id',(cid,)): print(f'Evidence: {r[0]} sha256={r[1]} ({r[2]})')
        for r in db.execute("SELECT created,action FROM history WHERE object_type='case' AND object_id=? ORDER BY id",(cid,)): print(f'{r[0]} {r[1]}')
    elif args.action == 'link':
        aid = ref(db,'alerts',args.alert or '', 'A')
        with db:
            cur = db.execute('INSERT OR IGNORE INTO case_alerts VALUES(?,?)',(cid,aid))
            if cur.rowcount: history(db,'case',cid,f'linked {visible("A",aid)}')
        print('Alert linked' if cur.rowcount else 'Alert already linked')
    elif args.action == 'note':
        text = clean(args.extra)
        if not text or len(text) > 2000: raise ValueError('note must be 1..2000 characters')
        with db:
            db.execute('INSERT INTO case_notes(case_id,created,text) VALUES(?,?,?)',(cid,now(),text))
            history(db,'case',cid,'note added')
        print('Note added')
    elif args.action in ('status','close'):
        status = 'closed' if args.action == 'close' else args.extra
        if status not in ('pending','investigating','false_positive','confirmed','closed'): raise ValueError('invalid case status')
        with db:
            db.execute('UPDATE cases SET status=? WHERE id=?',(status,cid)); history(db,'case',cid,'status -> '+status)
        print('Case updated')
    elif args.action == 'evidence':
        if not args.extra: raise ValueError('usage: cases evidence C-001 <file>')
        temp, sha = snapshot(args.extra, path / 'evidence')
        final = path / 'evidence' / (sha + '.evidence')
        try:
            with db:
                if final.exists():
                    from blue_store import fingerprint
                    if final.is_symlink() or final.stat().st_nlink != 1 or fingerprint(final) != sha: raise ValueError('invalid existing evidence snapshot')
                else:
                    os.link(temp, final)
                    os.chmod(final, 0o400)
                db.execute('INSERT INTO evidence(case_id,filename,sha256,path,created) VALUES(?,?,?,?,?)', (cid,clean(Path(args.extra).name),sha,final.name,now()))
                history(db,'case',cid,'evidence added: '+sha)
            print(f'Evidence copied: sha256={sha}')
        finally:
            temp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(prog='urb blue')
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('workspace'); a = p.add_subparsers(dest='action', required=True)
    for action in ('new', 'use'):
        a.add_parser(action).add_argument('name')
    a.add_parser('list'); a.add_parser('status')
    sub.add_parser('status'); sub.add_parser('sources')
    p = sub.add_parser('ingest'); p.add_argument('kind', choices=('windows', 'linux')); p.add_argument('path'); p.add_argument('--tz', default=''); p.add_argument('--year', type=int)
    p = sub.add_parser('events'); p.add_argument('action', nargs='?', choices=('show',)); p.add_argument('event', nargs='?'); p.add_argument('--id'); p.add_argument('--user'); p.add_argument('--ip'); p.add_argument('--since'); p.add_argument('--limit', type=int, default=50)
    p = sub.add_parser('detect'); p.add_argument('action', choices=('rules', 'run')); p.add_argument('--threshold', type=int, default=5); p.add_argument('--window', type=int, default=600, help='window in seconds')
    p = sub.add_parser('alerts'); p.add_argument('action', nargs='?', default='list', choices=('list','show','status')); p.add_argument('alert', nargs='?'); p.add_argument('value', nargs='?')
    p = sub.add_parser('cases'); p.add_argument('action', nargs='?', default='list', choices=('new','list','show','link','note','evidence','status','close')); p.add_argument('value', nargs='?'); p.add_argument('extra', nargs='?'); p.add_argument('--alert')
    args = parser.parse_args()
    os.umask(0o077)
    if args.command == 'workspace':
        workspace(args); return
    path = active()
    db = connect(path / 'blue.sqlite3')
    db.row_factory = sqlite3.Row
    try:
        if args.command == 'status':
            summary(db, path)
        elif args.command == 'ingest':
            if args.year is not None and not 1970 <= args.year <= 9999:
                raise ValueError('year must be between 1970 and 9999')
            sid, accepted, rejected, duplicate = ingest(db, path, args.kind, args.path, args.tz, args.year)
            print(f'Source {visible("SRC", sid)}: {"already imported" if duplicate else "imported"}; accepted={accepted}, rejected={rejected}')
        elif args.command == 'sources':
            print('ID | KIND | SHA-256 | FILE | EVENTS | REJECTED | TIMEZONE | NO UTC | SNAPSHOT')
            for r in db.execute('SELECT s.*, (SELECT count(*) FROM events e WHERE e.source_id=s.id AND e.timestamp_utc IS NULL) AS no_utc FROM sources s ORDER BY s.id'):
                snapshot_path = path / 'sources' / r['snapshot']
                snapshot_state = 'present' if re.fullmatch(r'[0-9a-f]{64}\.source', r['snapshot']) and snapshot_path.is_file() and not snapshot_path.is_symlink() else 'missing/unsafe'
                print(f'{visible("SRC",r["id"])} | {r["kind"]} | {r["sha256"]} | {r["filename"]} | {r["records"]} | {r["rejected"]} | {r["timezone"] or "unknown"} | {r["no_utc"]} | {snapshot_state}')
        elif args.command == 'events':
            if args.action == 'show':
                eid = ref(db, 'events', args.event or '', 'E')
                r = db.execute('SELECT events.*,sources.sha256,sources.snapshot FROM events JOIN sources ON sources.id=events.source_id WHERE events.id=?', (eid,)).fetchone()
                print(f'Event: {visible("E",eid)}  Source: {visible("SRC",r["source_id"])}')
                for k in r.keys(): print(f'{k}: {clean(r[k]) if r[k] is not None else "unknown"}')
            else:
                if not 1 <= args.limit <= 1000: raise ValueError('limit must be 1..1000')
                conditions, values = [], []
                for key, column in (('id','event_type'), ('user','username'), ('ip','ip')):
                    val = getattr(args, key)
                    if val is not None: conditions.append(column + '=?'); values.append(val)
                if args.since:
                    from blue_store import parse_time
                    since = parse_time(args.since)
                    if since is None: raise ValueError('--since requires an ISO timestamp with timezone, e.g. 2026-11-12T10:00+01:00')
                    conditions.append('timestamp_utc>=?'); values.append(since)
                query = 'SELECT * FROM events' + (' WHERE ' + ' AND '.join(conditions) if conditions else '') + ' ORDER BY timestamp_utc IS NULL,timestamp_utc DESC,id DESC LIMIT ?'
                print('ID | UTC (unknown last) | HOST | TYPE | USER | IP | RESULT')
                for r in db.execute(query, (*values,args.limit)):
                    print(f'{visible("E",r["id"])} | {r["timestamp_utc"] or "unknown"} | {r["host"]} | {r["event_type"]} | {r["username"]} | {r["ip"]} | {r["result"]}')
        elif args.command == 'detect':
            if args.action == 'rules': print('windows_4625: >=5 failures per IP in 600s (use --threshold and --window); a match is not a confirmed incident')
            else:
                a,b,c = detect(db,args.threshold,args.window)
                skipped = db.execute("SELECT count(*) FROM events WHERE event_type='4625' AND (ip='' OR timestamp_utc IS NULL)").fetchone()[0]
                print(f'Alerts: {a} created, {b} updated, {c} merged; {skipped} event(s) lack IP or usable time')
        elif args.command == 'alerts':
            if args.action == 'list':
                for r in db.execute('SELECT a.*,count(ae.event_id) AS n FROM alerts a LEFT JOIN alert_events ae ON ae.alert_id=a.id GROUP BY a.id ORDER BY a.id'):
                    print(f'{visible("A",r["id"])} | {r["status"]} | {r["ip"]} | {r["n"]} events | {r["first_time"]} - {r["last_time"]}' + (f' | merged into {visible("A",r["merged_into"])}' if r['merged_into'] else ''))
            else:
                aid = ref(db,'alerts',args.alert or '', 'A')
                if args.action == 'show':
                    r = db.execute('SELECT * FROM alerts WHERE id=?',(aid,)).fetchone()
                    for k in r.keys(): print(f'{k}: {r[k]}')
                    print('Events: ' + ', '.join(visible('E',r[0]) for r in db.execute('SELECT event_id FROM alert_events WHERE alert_id=? ORDER BY event_id',(aid,))))
                    for r in db.execute("SELECT created,action FROM history WHERE object_type='alert' AND object_id=? ORDER BY id",(aid,)): print(f'{r[0]} {r[1]}')
                else:
                    if args.value not in ('pending','investigating','false_positive','confirmed'): raise ValueError('invalid alert status')
                    with db:
                        db.execute('UPDATE alerts SET status=? WHERE id=?',(args.value,aid)); history(db,'alert',aid,'status -> '+args.value)
                    print('Alert updated')
        elif args.command == 'cases':
            cases(db, path, args)
        if (args.command == 'ingest' or (args.command == 'detect' and args.action == 'run') or
                (args.command == 'alerts' and args.action == 'status') or
                (args.command == 'cases' and args.action not in ('list', 'show'))):
            try:
                update_hud(db, path)
            except (OSError, sqlite3.Error) as exc:
                print(f'Warning: HUD summary not updated: {clean(exc)}', file=sys.stderr)
    finally:
        db.close()


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, sqlite3.Error, UnicodeError, csv.Error, OverflowError) as exc:
        print(f'urb blue: {clean(exc)}', file=sys.stderr)
        sys.exit(1)
