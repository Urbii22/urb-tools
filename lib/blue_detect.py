#!/usr/bin/env python3
"""Deterministic sliding-window 4625 rule, preserving existing alert IDs."""
import datetime as dt
import itertools

from blue_store import now


def run(db, threshold, seconds):
    if threshold < 2 or seconds < 1:
        raise ValueError('threshold must be >= 2 and window must be positive')
    db.execute('BEGIN IMMEDIATE')
    try:
        db.execute('CREATE TEMP TABLE IF NOT EXISTS blue_match_ids (id INTEGER PRIMARY KEY)')
        rows = db.execute("SELECT id,ip,timestamp_utc FROM events WHERE event_type='4625' AND ip<>'' AND timestamp_utc IS NOT NULL ORDER BY ip,timestamp_utc,id")
        # Connected components of overlapping triggering windows. A bridge merges
        # old alerts into the lowest ID; old IDs and case references remain valid.
        made = updated = merged = 0
        for ip, group in itertools.groupby(rows, key=lambda row: row[1]):
            events = [(event_id, stamp, dt.datetime.fromisoformat(stamp).timestamp()) for event_id, _, stamp in group]
            intervals = []
            left = 0
            for right, event in enumerate(events):
                while event[2] - events[left][2] > seconds:
                    left += 1
                if right - left + 1 >= threshold:
                    if intervals and left <= intervals[-1][1]:
                        intervals[-1] = (intervals[-1][0], right)
                    else:
                        intervals.append((left, right))
            for left, right in intervals:
                part = events[left:right + 1]
                ids = [x[0] for x in part]
                db.execute('DELETE FROM blue_match_ids')
                db.executemany('INSERT INTO blue_match_ids VALUES(?)', ((eid,) for eid in ids))
                existing = db.execute(
                    "SELECT DISTINCT a.id FROM alerts a JOIN alert_events ae ON ae.alert_id=a.id JOIN blue_match_ids m ON m.id=ae.event_id WHERE a.rule='windows_4625' AND a.threshold=? AND a.window_seconds=? AND a.ip=? AND a.merged_into IS NULL ORDER BY a.id",
                    (threshold, seconds, ip)).fetchall()
                if existing:
                    aid = existing[0][0]
                    for (old,) in existing[1:]:
                        db.execute('INSERT OR IGNORE INTO alert_events SELECT ?,event_id FROM alert_events WHERE alert_id=?', (aid, old))
                        db.execute('UPDATE alerts SET merged_into=? WHERE id=?', (aid, old))
                        db.execute("INSERT INTO history(object_type,object_id,created,action) VALUES('alert',?,?,?)", (old, now(), f'merged into A-{aid:03d}'))
                        merged += 1
                    old_count = db.execute('SELECT COUNT(*) FROM alert_events WHERE alert_id=?', (aid,)).fetchone()[0]
                    for eid in ids:
                        db.execute('INSERT OR IGNORE INTO alert_events VALUES(?,?)', (aid, eid))
                    new_count = db.execute('SELECT COUNT(*) FROM alert_events WHERE alert_id=?', (aid,)).fetchone()[0]
                    db.execute('UPDATE alerts SET first_time=MIN(first_time,?),last_time=MAX(last_time,?) WHERE id=?', (part[0][1], part[-1][1], aid))
                    if new_count != old_count:
                        db.execute("INSERT INTO history(object_type,object_id,created,action) VALUES('alert',?,?,?)", (aid, now(), f'events updated: {old_count} -> {new_count}'))
                        updated += 1
                else:
                    cur = db.execute("INSERT INTO alerts(rule,threshold,window_seconds,ip,first_time,last_time,created) VALUES('windows_4625',?,?,?,?,?,?)", (threshold, seconds, ip, part[0][1], part[-1][1], now()))
                    aid = cur.lastrowid
                    db.executemany('INSERT INTO alert_events VALUES(?,?)', ((aid, eid) for eid in ids))
                    db.execute("INSERT INTO history(object_type,object_id,created,action) VALUES('alert',?,?,?)", (aid, now(), 'rule matched; not a confirmed incident'))
                    made += 1
        db.commit()
        return made, updated, merged
    except BaseException:
        db.rollback()
        raise
