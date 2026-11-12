#!/usr/bin/env python3
"""Offline storage primitives for BLUE. Data imported here is never executable."""
import datetime as dt
import hashlib
import ipaddress
import os
import re
import sqlite3
from pathlib import Path

SCHEMA = """
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS sources (
 id INTEGER PRIMARY KEY AUTOINCREMENT, sha256 TEXT NOT NULL UNIQUE,
 filename TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('windows','linux')),
 imported_at TEXT NOT NULL, timezone TEXT, year INTEGER,
 records INTEGER NOT NULL DEFAULT 0, rejected INTEGER NOT NULL DEFAULT 0,
 snapshot TEXT NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS events (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 source_id INTEGER NOT NULL REFERENCES sources(id), record INTEGER NOT NULL,
 timestamp_original TEXT NOT NULL, timestamp_utc TEXT,
 host TEXT NOT NULL, event_type TEXT NOT NULL, username TEXT NOT NULL,
 ip TEXT NOT NULL, result TEXT NOT NULL, message TEXT NOT NULL,
 UNIQUE(source_id, record)
);
CREATE INDEX IF NOT EXISTS events_time ON events(timestamp_utc, id);
CREATE INDEX IF NOT EXISTS events_rule ON events(event_type, ip, timestamp_utc);
CREATE INDEX IF NOT EXISTS events_user ON events(username);
CREATE TABLE IF NOT EXISTS alerts (
 id INTEGER PRIMARY KEY AUTOINCREMENT, rule TEXT NOT NULL,
 threshold INTEGER NOT NULL, window_seconds INTEGER NOT NULL, ip TEXT NOT NULL,
 first_time TEXT NOT NULL, last_time TEXT NOT NULL, created TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','investigating','false_positive','confirmed')),
 merged_into INTEGER REFERENCES alerts(id)
);
CREATE INDEX IF NOT EXISTS alerts_group ON alerts(rule,threshold,window_seconds,ip,first_time,last_time);
CREATE TABLE IF NOT EXISTS alert_events (
 alert_id INTEGER NOT NULL REFERENCES alerts(id), event_id INTEGER NOT NULL REFERENCES events(id),
 PRIMARY KEY(alert_id,event_id)
);
CREATE TABLE IF NOT EXISTS cases (
 id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
 created TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending'
 CHECK(status IN ('pending','investigating','false_positive','confirmed','closed'))
);
CREATE TABLE IF NOT EXISTS case_alerts (
 case_id INTEGER NOT NULL REFERENCES cases(id), alert_id INTEGER NOT NULL REFERENCES alerts(id),
 PRIMARY KEY(case_id,alert_id)
);
CREATE TABLE IF NOT EXISTS case_notes (
 id INTEGER PRIMARY KEY AUTOINCREMENT, case_id INTEGER NOT NULL REFERENCES cases(id),
 created TEXT NOT NULL, text TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS evidence (
 id INTEGER PRIMARY KEY AUTOINCREMENT, case_id INTEGER NOT NULL REFERENCES cases(id),
 filename TEXT NOT NULL, sha256 TEXT NOT NULL, path TEXT NOT NULL, created TEXT NOT NULL,
 UNIQUE(case_id, sha256)
);
CREATE TABLE IF NOT EXISTS history (
 id INTEGER PRIMARY KEY AUTOINCREMENT, object_type TEXT NOT NULL CHECK(object_type IN ('alert','case')),
 object_id INTEGER NOT NULL, created TEXT NOT NULL, action TEXT NOT NULL
);
"""


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')


def connect(path):
    old = os.umask(0o077)
    try:
        db = sqlite3.connect(str(path), timeout=15)
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA busy_timeout=15000')
        return db
    finally:
        os.umask(old)


def create_database(path):
    db = connect(path)
    try:
        db.executescript(SCHEMA)
        db.commit()
    finally:
        db.close()


def valid_name(name):
    return bool(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}', name)) and name not in ('.', '..')


def clean(text):
    return ''.join(ch if ch.isprintable() else ' ' for ch in str(text or '')).strip()


def normalize_ip(text):
    try:
        return str(ipaddress.ip_address(text))
    except ValueError:
        return ''


def parse_timezone(value):
    if not value:
        return None
    if value in ('Z', 'UTC'):
        return dt.timezone.utc
    match = re.fullmatch(r'([+-])(\d\d):(\d\d)', value)
    if not match or int(match[2]) > 23 or int(match[3]) > 59:
        raise ValueError('timezone must be UTC or an explicit offset such as +01:00')
    offset = dt.timedelta(hours=int(match[2]), minutes=int(match[3]))
    return dt.timezone(offset if match[1] == '+' else -offset)


def parse_time(value, timezone=None, require_seconds=False):
    value = value.strip()
    if not value:
        return None
    if not re.match(r'^\d{4}-\d\d-\d\d[T ]\d\d:\d\d', value):
        return None
    if require_seconds and not re.match(r'^\d{4}-\d\d-\d\d[T ]\d\d:\d\d:\d\d', value):
        return None
    fraction = re.search(r':\d\d[.,](\d+)', value)
    if require_seconds and fraction and len(fraction.group(1)) > 6:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        if timezone is None:
            return None
        parsed = parsed.replace(tzinfo=timezone)
    return parsed.astimezone(dt.timezone.utc).isoformat(timespec='microseconds')


def fingerprint(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            block = f.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def visible(prefix, number):
    return f'{prefix}-{number:03d}'


def parse_id(value, prefix):
    m = re.fullmatch(prefix + r'-(\d+)', value, re.IGNORECASE)
    if not m or int(m[1]) < 1:
        raise ValueError(f'invalid {prefix} ID: {value}')
    return int(m[1])
