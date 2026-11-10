#!/usr/bin/env python3
"""Exercise native Ask and Answer with synthetic recruiter evidence and isolated settings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--sha", required=True)
parser.add_argument("--restatement", action="store_true")
args = parser.parse_args()
build = Path(__file__).resolve().parents[1] / "build"
app, folder = args.app.resolve(), args.output.resolve()
assert app.is_relative_to(build) and folder.is_relative_to(build)
binary = app / "Contents/MacOS/Copilote"
assert hashlib.sha256(binary.read_bytes()).hexdigest() == args.sha
folder.mkdir(exist_ok=False)
cv = folder / "Brain/CV/Recruiter.pdf"
cv.parent.mkdir(parents=True)
# The reader verifies original bytes, not PDF rendering or extraction.
cv.write_bytes(b"%PDF-1.4\n% Synthetic recruiter source revision one\n%%EOF\n")
note = cv.with_name("Interview.md")
note.write_text("I failed the course, retook it and passed.")
rows = [
    ("a", "Harbor", "challenge technical teamwork", "The team tested a simulated queue.", cv),
    ("b", "Harbor", "challenge technical teamwork", "The simulated delay was reduced by 12%.", cv),
    ("c", "Other role", "education", "UNRELATED_DIPLOMA", cv),
    ("d", "Academic recovery", "challenge setback resilience failure academic", note.read_text(), note),
]
with sqlite3.connect(folder / "evidence.sqlite") as db:
    db.execute("CREATE TABLE evidence(id TEXT PRIMARY KEY, topic TEXT, tags TEXT, passage TEXT, source TEXT, source_sha256 TEXT)")
    for key, topic, tags, passage, file in rows:
        label = file.name + (" · p. 1" if file == cv else " · preparation")
        db.execute("INSERT INTO evidence VALUES(?,?,?,?,?,?)", (key, topic, tags, passage, label, hashlib.sha256(file.read_bytes()).hexdigest()))
with (folder / "run.log").open("w") as log:
    subprocess.run([str(binary), "-CopiloteRecette", str(folder), "-RecetteAnchorOnly", "-RecetteEvidenceOnly", *(["-RecetteRestatement"] if args.restatement else [])],
                   env={**os.environ, "COPILOTE_HEADLESS_GEOMETRY": "1"}, stdout=log, stderr=log, timeout=70, check=True)
checks = json.loads((folder / "recette.json").read_text())["checks"]
print(json.dumps({"checks": len(checks), "failures": [r["name"] for r in checks if not r["passed"]]}))
assert len(checks) >= (7 if args.restatement else 8) and all(r["passed"] for r in checks)
