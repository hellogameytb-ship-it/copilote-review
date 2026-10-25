#!/usr/bin/env python3
"""Negative probes in a temporary fixture tree; never edits production Swift files."""
from pathlib import Path
import json, plistlib, shutil, subprocess, tempfile
checker = Path(__file__).with_name('check-overlay-windows.sh')
results = []
with tempfile.TemporaryDirectory(prefix='copilote-window-policy-') as tmp:
    root = Path(tmp)
    (root/'Tools').mkdir(); (root/'Copilote/App').mkdir(parents=True)
    (root/'Copilote/Info.plist').write_bytes(plistlib.dumps({'LSUIElement': True}))
    shutil.copy2(checker, root/'Tools/check-overlay-windows.sh')
    def probe(name, source, allowed):
        file = root/'Copilote/App'/name
        file.write_text(source)
        result = subprocess.run(['/bin/bash',str(root/'Tools/check-overlay-windows.sh')],capture_output=True,text=True)
        file.unlink()
        passed = (result.returncode == 0) == allowed
        results.append({'file':name,'source':source,'expectedAllowed':allowed,'passed':passed})
    for name in ['SystemDialogs.swift','DiagnosticNewSurface.swift']:
        for source in ['let x = NSOpenPanel()', 'let x = NSSavePanel()', 'let x = NSPanel()', 'let x = NSWindow()', 'let x = NSMenu()', 'let x = NSAlert()', 'panel.canBecomeVisibleWithoutLogin = true']:
            probe(name,source,False)
    probe('DiagnosticPresentation.swift','panel.sharingType = .readOnly',True)
    probe('DiagnosticPresentation.swift','NSApp.setActivationPolicy(.regular)',True)
    probe('DiagnosticPresentation.swift','otherPanel.sharingType = .readOnly',False)
print(json.dumps(results,indent=2))
assert all(row['passed'] for row in results)
