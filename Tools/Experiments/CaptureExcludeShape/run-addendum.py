#!/usr/bin/env python3
"""Bounded runner; captures only the harness-created synthetic window."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

root = Path(sys.argv[1]).resolve()
binary = root / 'capture-shape-addendum'
for name in sys.argv[2:]:
    out = root / name
    out.mkdir(exist_ok=False)
    (out / 'provenance.json').write_text(json.dumps({
        'binary': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'started': time.time()}, indent=2))
    with (out / 'run.log').open('w') as log:
        result = subprocess.run([str(binary), str(out)], stdout=log,
                                stderr=subprocess.STDOUT, timeout=110)
    result.check_returncode()
    assert (out / 'report.json').exists(), 'Missing final report'
    print(name, 'completed', flush=True)
