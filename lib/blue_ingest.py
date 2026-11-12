#!/usr/bin/env python3
"""Streaming source snapshots and event parsing for BLUE."""
import csv
import datetime as dt
import hashlib
import os
import re
import tempfile
from pathlib import Path

from blue_store import clean, normalize_ip, now, parse_time, parse_timezone

csv.field_size_limit(1024 * 1024)


def snapshot(source, directory):
    """Copy once, hashing the exact bytes preserved; reject changing input."""
    fd, temp = tempfile.mkstemp(prefix='.source-', dir=directory)
    digest = hashlib.sha256()
    try:
        with open(source, 'rb') as src, os.fdopen(fd, 'wb') as dst:
            before = os.fstat(src.fileno())
            if not __import__('stat').S_ISREG(before.st_mode):
                raise ValueError('source must be a regular file')
            remaining = before.st_size
            while remaining:
                block = src.read(min(1024 * 1024, remaining))
                if not block:
                    raise ValueError('source changed during import; retry')
                remaining -= len(block)
                digest.update(block)
                dst.write(block)
            after = os.fstat(src.fileno())
            if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                raise ValueError('source changed during import; retry')
            dst.flush()
            os.fsync(dst.fileno())
        return Path(temp), digest.hexdigest()
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        Path(temp).unlink(missing_ok=True)
        raise


def windows_rows(path, timezone):
    with open(path, encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f, strict=True)
        if not reader.fieldnames:
            raise ValueError('CSV has no header')
        names = {x.strip().lower(): x for x in reader.fieldnames if x is not None}
        if len(names) != len(reader.fieldnames):
            raise ValueError('CSV contains duplicate or invalid headers')
        if 'eventid' not in names or 'timestamp' not in names:
            raise ValueError('Windows CSV requires Timestamp and EventID headers')
        def value(row, *keys):
            for key in keys:
                if key in names:
                    return clean(row.get(names[key], ''))
            return ''
        for record, row in enumerate(reader, 2):
            if None in row or any(value is None for value in row.values()):
                yield record, None
                continue
            eventid = value(row, 'eventid')
            stamp = row.get(names['timestamp'], '') or ''
            if not eventid.isdigit():
                yield record, None
                continue
            result = {'4624': 'success', '4625': 'failure'}.get(eventid, '')
            yield record, (stamp, parse_time(stamp, timezone, require_seconds=True), value(row, 'host', 'computer'),
                           eventid, value(row, 'user', 'username'), normalize_ip(value(row, 'ip', 'ipaddress', 'sourceip')),
                           result, row.get(names.get('message', ''), '') or '')


_SYSLOG = re.compile(r'^(?P<month>Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(?P<day>\d{1,2})\s+(?P<time>\d\d:\d\d:\d\d)\s+(?P<host>\S+)\s+(?P<msg>.*)$')
_ISO = re.compile(r'^(?P<stamp>\d{4}-\d\d-\d\dT\S+)\s+(?P<host>\S+)\s+(?P<msg>.*)$')
_SSH = re.compile(r'\b(?P<result>Failed|Accepted) (?:password|publickey) for (?:invalid user )?(?P<user>\S+) from (?P<ip>\S+)')


def linux_rows(path, timezone, year):
    with open(path, encoding='utf-8-sig', errors='strict') as f:
        for record, raw in enumerate(f, 1):
            line = raw.rstrip('\r\n')
            m = _ISO.match(line)
            legacy = None if m else _SYSLOG.match(line)
            if not m and not legacy:
                yield record, None
                continue
            if legacy:
                stamp = line[:legacy.start('host')].rstrip()
                normalized = None
                if year and timezone:
                    try:
                        month = ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec').index(legacy['month']) + 1
                        hour, minute, second = map(int, legacy['time'].split(':'))
                        parsed = dt.datetime(year, month, int(legacy['day']), hour, minute, second)
                        normalized = parsed.replace(tzinfo=timezone).astimezone(dt.timezone.utc).isoformat(timespec='microseconds')
                    except ValueError:
                        pass
                host, message = legacy['host'], legacy['msg']
            else:
                stamp = m['stamp']
                normalized = parse_time(stamp, timezone, require_seconds=True)
                host, message = m['host'], m['msg']
            ssh = _SSH.search(message)
            result = ('failure' if ssh['result'] == 'Failed' else 'success') if ssh else ''
            yield record, (clean(stamp), normalized, clean(host), 'ssh_auth' if ssh else 'auth',
                           clean(ssh['user']) if ssh else '', normalize_ip(ssh['ip']) if ssh else '', result, message)


def ingest(db, workspace, kind, source, zone, year):
    if str(source).lower().endswith('.evtx'):
        raise ValueError('binary EVTX is not supported; export Windows events to CSV first')
    tz = parse_timezone(zone)
    directory = workspace / 'sources'
    temp, sha = snapshot(source, directory)
    final = directory / (sha + '.source')
    try:
        db.execute('BEGIN IMMEDIATE')
        existing = db.execute('SELECT id,kind,timezone,year FROM sources WHERE sha256=?', (sha,)).fetchone()
        if existing:
            db.rollback()
            if (existing[1], existing[2] or '', existing[3]) != (kind, zone or '', year):
                raise ValueError('source already imported with different kind or time settings; use a new workspace')
            return existing[0], 0, 0, True
        if final.exists():
            # An interrupted prior transaction may have left a snapshot.
            from blue_store import fingerprint
            if final.is_symlink() or final.stat().st_nlink != 1 or fingerprint(final) != sha:
                raise ValueError('existing snapshot does not match source hash')
        else:
            os.link(temp, final)
            os.chmod(final, 0o400)
        cursor = db.execute('INSERT INTO sources(sha256,filename,kind,imported_at,timezone,year,snapshot) VALUES(?,?,?,?,?,?,?)',
                            (sha, clean(Path(source).name), kind, now(), zone, year, final.name))
        source_id = cursor.lastrowid
        accepted = rejected = 0
        rows = windows_rows(temp, tz) if kind == 'windows' else linux_rows(temp, tz, year)
        for record, event in rows:
            if event is None:
                rejected += 1
                continue
            db.execute('INSERT INTO events(source_id,record,timestamp_original,timestamp_utc,host,event_type,username,ip,result,message) VALUES(?,?,?,?,?,?,?,?,?,?)',
                       (source_id, record, *event))
            accepted += 1
        db.execute('UPDATE sources SET records=?, rejected=? WHERE id=?', (accepted, rejected, source_id))
        db.commit()
        return source_id, accepted, rejected, False
    except BaseException:
        db.rollback()
        raise
    finally:
        temp.unlink(missing_ok=True)
