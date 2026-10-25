#!/bin/bash
# Protected panels include settings/history. Explicit macOS file dialogs are isolated exceptions.
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import re,sys
bad=[]
import plistlib
if plistlib.loads(Path('Copilote/Info.plist').read_bytes()).get('LSUIElement') is not True:
    bad.append('LSUIElement must remain true')
pattern=re.compile(r'\.help\(|toolTip\s*=|\.contextMenu|\bMenu\s*\{|\.popover\(|\.alert\(|\.sheet\(|confirmationDialog|NSMenu\(|NSAlert\(|NSPopover|NSOpenPanel|NSSavePanel|fileImporter|pickerStyle\(\.menu\)|KeyboardShortcuts\.Recorder\(')
for path in Path('Copilote').rglob('*.swift'):
    if path.name.startswith('Diagnostic') or path.name=='SystemDialogs.swift': continue
    text=path.read_text()
    for i,line in enumerate(text.splitlines(),1):
        if line.lstrip().startswith('//'): continue
        if pattern.search(line): bad.append(f'{path}:{i}: unprotected transient UI: {line.strip()}')
        if 'setActivationPolicy(' in line and 'setActivationPolicy(.accessory)' not in line and path.name != 'WindowPrivacy.swift': bad.append(f'{path}:{i}: activation policy can leave accessory mode')
        if re.search(r'sharingType\s*=',line) and not re.search(r'sharingType\s*=\s*(?:\.none\b|WindowPrivacy.sharing)',line) and path.name != 'WindowPrivacy.swift': bad.append(f'{path}:{i}: sharing policy is not none')
        if re.search(r'NSWindow\(|NSStatusBar\.',line): bad.append(f'{path}:{i}: ordinary window or status menu creation')
        if re.search(r'canBecomeVisibleWithoutLogin\s*=\s*true',line): bad.append(f'{path}:{i}: login-window visibility must remain disabled')
        if (re.search(r'class\s+\w+\s*:\s*NSPanel\b',line) or re.search(r'\bNSPanel\(',line)) and path.name != 'ProtectedPanel.swift':
            bad.append(f'{path}:{i}: app panels must inherit the central ProtectedPanel presentation gate')
        if re.search(r'setValue\([^\n]*forKey:',line): bad.append(f'{path}:{i}: undocumented KVC setter')
for path in Path('Copilote/Main').glob('*.swift'):
    text=path.read_text()
    if len(re.findall(r'\bPicker\(',text)) != len(re.findall(r'pickerStyle\(\.(?:radioGroup|segmented)\)',text)):
        bad.append(f'{path}: every picker must use an inline style')
if bad:
    print('\n'.join(bad)); sys.exit(1)
print('✓ centralized stealth policy; app controls stay in panels; explicit OS dialogs isolated')
PY
