#!/usr/bin/env python3
"""Run the headless audit variant, never the installed app or a live provider."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--sha', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
app, output = args.app.resolve(), args.output.resolve()
assert app.is_relative_to(repo / 'build') and output.is_relative_to(repo / 'build')
binary = app / 'Contents/MacOS/Copilote'
data = binary.read_bytes()
assert hashlib.sha256(data).hexdigest() == args.sha
assert b'COPILOTE_HEADLESS_GEOMETRY' in data and b'RecetteLatencyAudit' in data
source = app.parent.parent
provenance = json.loads((source / 'audit-provenance.json').read_text())
assert provenance['productionLogicUnchanged'] and provenance['notTheInstallableCandidate']
assert all(hashlib.sha256((source / name).read_bytes()).hexdigest() == sha
           for name, sha in provenance['originalSwiftFiles'].items()
           if name != 'Copilote/App/DiagnosticRecette.swift')
assert hashlib.sha256((source / 'Copilote/App/DiagnosticLatencyAudit.swift').read_bytes()).hexdigest() == provenance['fixtureSHA256']
output.mkdir(exist_ok=False)
(output / 'provenance.json').write_text(json.dumps({**provenance, 'auditBinarySHA256': args.sha}, indent=2))
with (output / 'run.log').open('w') as log:
    subprocess.run([str(binary), '-CopiloteRecette', str(output), '-RecetteAnchorOnly', '-RecetteLatencyAudit'],
                   env={**os.environ, 'COPILOTE_HEADLESS_GEOMETRY': '1'}, stdout=log, stderr=log, timeout=60, check=True)
recipe = json.loads((output / 'recette.json').read_text())
audit = json.loads((output / 'latency-audit.json').read_text())
failures = [row['name'] for row in recipe['checks'] if not row['passed']]
summary = {'auditBinarySHA256': args.sha, 'candidateSource': provenance['candidateSource'],
           'checks': len(recipe['checks']), 'passed': sum(row['passed'] for row in recipe['checks']),
           'failures': failures, 'scenarios': len(audit['findings']), 'liveAIRequests': audit['liveAIRequests'],
           'audioUsed': audit['audioUsed'], 'desktopCaptured': audit['desktopCaptured']}
(output / 'summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
assert not failures
