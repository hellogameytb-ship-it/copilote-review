#!/usr/bin/env python3
"""Run the bounded own-window pixel experiment; never enables a desktop capture mode."""
import argparse, hashlib, json, subprocess
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('root',type=Path);parser.add_argument('runs',nargs='+');a=parser.parse_args()
root=a.root.resolve();binary=root/'capture-shape-stream'
for name in a.runs:
    if Path(name).name != name: raise SystemExit('Use a simple output directory name.')
    folder=root/name
    folder.mkdir(exist_ok=False)
    (folder/'provenance.json').write_text(json.dumps({'binarySHA256':hashlib.sha256(binary.read_bytes()).hexdigest(),'captureMode':'own-window only','timeoutSeconds':100},indent=2))
    with (root/(name+'.log')).open('w') as log:
        subprocess.run([str(binary),str(folder)],stdout=log,stderr=log,timeout=100,check=True)
    d=json.loads((folder/'report.json').read_text())
    print(name,':',len(d['results']),'phases, existing permission:',d['existingPermission'],flush=True)
