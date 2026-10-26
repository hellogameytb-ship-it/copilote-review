#!/usr/bin/env python3
"""Run only a reviewed headless-capable build artifact, never an installed app."""
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
build = Path(__file__).resolve().parents[1] / 'build'
app, output = args.app.resolve(), args.output.resolve()
assert app.is_relative_to(build) and output.is_relative_to(build), 'Only local build artifacts are allowed'
binary = app / 'Contents/MacOS/Copilote'
data = binary.read_bytes()
digest = hashlib.sha256(data).hexdigest()
assert digest == args.sha, 'Binary differs from requested hash'
assert b'COPILOTE_HEADLESS_GEOMETRY' in data, 'Refusing an older app without the headless fixture gate'
output.mkdir(exist_ok=False)
(output / 'provenance.json').write_text(json.dumps({'binarySHA256': digest, 'app': str(app), 'headless': True}, indent=2))
with (output / 'run.log').open('w') as log:
    subprocess.run([str(binary), '-CopiloteRecette', str(output), '-RecetteAnchorOnly'],
                   env={**os.environ, 'COPILOTE_HEADLESS_GEOMETRY': '1'},
                   stdout=log, stderr=log, timeout=150, check=True)
recipe = json.loads((output / 'recette.json').read_text())
geometry = json.loads((output / 'anchors.json').read_text())
failures = [row['name'] for row in recipe['checks'] if not row['passed']]
summary = {
    'run': output.name, 'binarySHA256': digest, 'checks': len(recipe['checks']),
    'passed': sum(row['passed'] for row in recipe['checks']), 'failures': failures,
    'geometrySamples': len(geometry['samples']),
    'maxAnchorDelta': max(row['anchorDelta'] for row in geometry['samples']),
    'maxRequiredPanelOriginDelta': max(row['panelOriginDelta'] for row in geometry['samples'] if row['panelStabilityRequired']),
    'spaceChangesObserved': geometry['spaceChangesObserved'],
    'ownApplicationActivations': geometry['ownApplicationActivations'],
}
confirmation_file = output / 'stealth-confirmation.json'
if confirmation_file.exists():
    confirmation = json.loads(confirmation_file.read_text())
    summary['confirmationGeometrySamples'] = len(confirmation['geometry'])
    summary['maxConfirmationOriginDelta'] = max((row['maxRequiredOriginDelta'] for row in confirmation['geometry']), default=0)
    summary['nativeVisibleFocusTested'] = confirmation['nativeVisibleFocusTested']
    summary['physicalClicksTested'] = confirmation['physicalClicksTested']
    summary['ownApplicationActivations'] += confirmation.get('ownApplicationActivations', 0)
    summary['spaceChangesObserved'] += confirmation.get('spaceChangesObserved', 0)
panel_file = output / 'panel-shortcut.json'
if panel_file.exists():
    panel = json.loads(panel_file.read_text())
    summary['panelShortcutGeometrySamples'] = len(panel['geometry'])
    summary['maxPanelShortcutOriginDelta'] = max((row['maxOriginDelta'] for row in panel['geometry']), default=0)
    summary['panelShortcutAnswerRequests'] = panel['answerRequests']
capture_file = output / 'capture-button.json'
if capture_file.exists():
    capture = json.loads(capture_file.read_text())
    summary['captureButtonLayouts'] = len(capture['layouts'])
    summary['captureButtonGeometrySamples'] = len(capture['geometry'])
    summary['maxCaptureButtonOriginDelta'] = max((row['maxOriginDelta'] for row in capture['geometry']), default=0)
    summary['fixtureCaptureCalls'] = capture['captureCalls']
answer_file = output / 'answer-now.json'
if answer_file.exists():
    answer = json.loads(answer_file.read_text())
    summary['freshAnswerChecks'] = len(answer['checks'])
    summary['freshAnswerFailures'] = [row['name'] for row in answer['checks'] if not row['passed']]
chat_file = output / 'chat.json'
if chat_file.exists():
    chat = json.loads(chat_file.read_text())
    summary['chatChecks'] = len(chat['checks'])
    summary['chatFailures'] = [row['name'] for row in chat['checks'] if not row['passed']]
paste_file = output / 'paste.json'
if paste_file.exists():
    paste = json.loads(paste_file.read_text())
    summary['pasteChecks'] = len(paste['checks'])
    summary['pasteFailures'] = [row['name'] for row in paste['checks'] if not row['passed']]
(output / 'summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
assert not failures, 'Headless geometry regression failed'
