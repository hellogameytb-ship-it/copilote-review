#!/usr/bin/env python3
"""Build, but never launch, a headless latency-audit variant of a committed candidate in build/."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, help='Frozen candidate source commit')
parser.add_argument('output', type=Path, help='New directory underneath the repository build/')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
output = args.output.resolve()
assert output.is_relative_to(repo / 'build') and not output.exists()
source = subprocess.check_output(['git', 'rev-parse', args.source + '^{commit}'], cwd=repo, text=True).strip()
archive_data = subprocess.check_output(['git', 'archive', source], cwd=repo)
output.mkdir(parents=True)
with tarfile.open(fileobj=io.BytesIO(archive_data)) as archive:
    archive.extractall(output, filter='data')
files = list((output / 'Copilote').rglob('*.swift')) + list((output / 'CopiloteKit').rglob('*.swift'))
original = {str(p.relative_to(output)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
fixture = Path(__file__).with_name('DiagnosticLatencyAudit.swift')
shutil.copy2(fixture, output / 'Copilote/App/DiagnosticLatencyAudit.swift')
recipe = output / 'Copilote/App/DiagnosticRecette.swift'
text = recipe.read_text()
needle = '            if DiagnosticAnchorFixture.isRequested {\n'
assert text.count(needle) == 1
text = text.replace(needle, '''            if DiagnosticAnchorFixture.isRequested && args.contains("-RecetteLatencyAudit") {
                await DiagnosticLatencyAudit.run(folder:folder,overlay:overlay,settings:settings,listening:listening,assist:assist,session:session,provider:fake,record:record)
                defaults.removePersistentDomain(forName:suite); NSApp.terminate(nil); return
            }
''' + needle, 1)
recipe.write_text(text)
assert all(hashlib.sha256((output / name).read_bytes()).hexdigest() == digest
           for name, digest in original.items() if name != 'Copilote/App/DiagnosticRecette.swift')
(output / 'audit-provenance.json').write_text(json.dumps({
    'candidateSource': source, 'originalSwiftFiles': original,
    'changes': ['DiagnosticRecette: opt-in test branch', 'DiagnosticLatencyAudit: test-only addition'],
    'productionLogicUnchanged': True, 'notTheInstallableCandidate': True,
    'fixtureSHA256': hashlib.sha256(fixture.read_bytes()).hexdigest(),
}, indent=2, sort_keys=True))
subprocess.run(['make', 'build'], cwd=output, check=True)
print('Built only. Headless audit requires COPILOTE_HEADLESS_GEOMETRY=1 and -RecetteAnchorOnly.')
