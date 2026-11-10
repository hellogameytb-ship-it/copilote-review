#!/usr/bin/env python3
"""Check an externally curated SQLite revision. --install publishes it atomically to the private local directory."""
import argparse
import hashlib
import os
from pathlib import Path
import sqlite3
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("candidate", type=Path, help="staged private SQLite file with passages curated from the new CV")
parser.add_argument("--base", type=Path, required=True, help="currently selected personal base")
parser.add_argument("--install", action="store_true")
args = parser.parse_args()
base = args.base.resolve(strict=True)
with sqlite3.connect(args.candidate.resolve(strict=True).as_uri() + "?mode=ro", uri=True) as db:
    rows = db.execute("SELECT id,topic,tags,passage,source,source_sha256 FROM evidence ORDER BY id LIMIT 1001").fetchall()
if not 0 < len(rows) <= 1000:
    parser.error("expected one to 1000 curated records")
verified = {}
for key, topic, tags, passage, source, sha in rows:
    if not all(isinstance(x, str) for x in (key, topic, tags, passage, source, sha)) or not key or not topic or not passage or len(passage) > 1200 or len(topic) > 512 or len(source) > 240:
        parser.error("invalid evidence record")
    name = source.split(" · ")[0]
    if Path(name).name != name or Path(name).suffix.lower() not in (".pdf", ".md"):
        parser.error("source must cite an original PDF or Markdown filename")
    if name not in verified:
        paths = [p for p in (base/name, base/"CV"/name) if p.is_file() and p.resolve() == p and p.stat().st_size <= 32*1024*1024]
        if len(paths) != 1:
            parser.error("missing or ambiguous original in the selected base")
        verified[name] = hashlib.sha256(paths[0].read_bytes()).hexdigest()
    if verified[name] != sha.lower():
        parser.error("source digest mismatch: curate the changed document before replacing its evidence")
if args.install:
    directory = Path.home()/"Library/Application Support/Copilote/InterviewEvidence"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    final = directory/"evidence.sqlite"
    if any(final.with_name(final.name + suffix).exists() for suffix in ("-wal","-shm","-journal")):
        parser.error("finish the existing database writer before replacing this revision")
    fd, name = tempfile.mkstemp(dir=directory, prefix=".revision-")
    os.close(fd)
    stage = Path(name)
    try:
        with sqlite3.connect(stage) as out:
            out.execute("CREATE TABLE evidence(id TEXT PRIMARY KEY, topic TEXT, tags TEXT, passage TEXT, source TEXT, source_sha256 TEXT)")
            out.executemany("INSERT INTO evidence VALUES(?,?,?,?,?,?)", rows)
        out.close()
        os.replace(stage, final)
    finally:
        stage.unlink(missing_ok=True)
print(f"{len(rows)} records across {len(verified)} verified sources" + (" installed" if args.install else " checked"))
