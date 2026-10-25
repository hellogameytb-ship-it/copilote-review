#!/usr/bin/env python3
"""Summarize bounded, synthetic-only SCStream measurements. Never interprets CGError as pixel proof."""
import argparse, csv, hashlib, json
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('root',type=Path);parser.add_argument('runs',nargs='+');args=parser.parse_args()
rows=[];controls=[]
for run in args.runs:
    report=json.loads((args.root/run/'report.json').read_text())
    assert report['existingPermission'] and not report['permissionRequested']
    assert not report['fullDisplayCapture'] and not report['audioCapture']
    assert report['createdRegions']==report['releasedRegions']
    for phase in report['results']:
        frames=[f for f in phase.get('frames',[]) if f.get('settled') and f['frameStatus']==0]
        assert len(frames)==6, (run,phase.get('name'),'six complete settled frames required')
        name=phase['name'];positive=(name.startswith('baseline') or name.startswith('sharing-off') or name.startswith('spi-off'))
        if positive: assert all(f['patternDetected'] for f in frames),(run,name,'positive control failed')
        if name=='background-control': assert all(f['backgroundSimilarity']>=.9 and not f['partialOrFullPatternDetected'] for f in frames)
        assert phase['localWindowVisible'] and phase['onActiveSpace']
        rows.append({'run':run,'os':report['os'],'method':report['method'],'phase':name,'mechanism':phase['mechanism'],
                     'transition':phase['transition'],'completeSettledFrames':len(frames),'apiCGError':phase['api']['cgError'],
                     'fullPatternFrames':sum(f['patternDetected'] for f in frames),'partialOrFullPatternFrames':sum(f['partialOrFullPatternDetected'] for f in frames),
                     'maxSimilarity':max(f['templateSimilarity'] for f in frames),'maxMarkerFraction':max(f['markerSampleFraction'] for f in frames),
                     'minOpaqueFraction':min(f['opaqueSampleFraction'] for f in frames),'maxOpaqueFraction':max(f['opaqueSampleFraction'] for f in frames),
                     'elapsedFirstSettledMs':round(frames[0]['elapsedMs'],2),'elapsedLastSettledMs':round(frames[-1]['elapsedMs'],2),
                     'collectionStartedAfterMutationMs':round(phase['collectionStartedAfterMutationMs'],2),
                     'framePoints':phase['windowFramePoints'],'backingScale':phase['backingScaleFactor']})
    controls.append({'run':run,'positiveAndBackgroundControlsPassed':True,'allPhasesHaveSixCompleteSettledFrames':True,'createdRegions':report['createdRegions'],'releasedRegions':report['releasedRegions']})
(args.root/'pixel-summary.json').write_text(json.dumps({'controls':controls,'rows':rows},indent=2))
with (args.root/'pixel-summary.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
matrix=[]
for os in ['macOS 15.x','macOS 26.x','macOS 27.0.1 (26A434), arm64']:
    for method in ['SCK full-display stream','SCK single-window stream before protection change','SCK single-window stream started after protection change']:
        for mechanism in ['none','sharingType.none','CGSSetWindowCaptureExcludeShape']:
            status='NON TESTÉ';detail='No authorized isolated system for this OS/method.'
            if os.startswith('macOS 27') and method!='SCK full-display stream':
                status='MEASURED — two runs, six complete settled frames per phase'
                detail={'none':'Known pattern detected; OFF restores it.','sharingType.none':'No pattern samples; transparent samples in this single-window stream only.','CGSSetWindowCaptureExcludeShape':'No pattern at stable size; opaque gray. Immediate resize leaks pattern; delayed reapply masks it again.'}[mechanism]
            if status.startswith('MEASURED') and mechanism=='CGSSetWindowCaptureExcludeShape' and method=='SCK single-window stream started after protection change':detail='No pattern samples at the tested stable size; opaque gray. Resize was tested separately in the active stream.'
            if method=='SCK full-display stream':detail='Not started: cannot guarantee no private desktop pixels on this user desktop. Needs isolated display/session.'
            matrix.append({'os':os,'method':method,'mechanism':mechanism,'status':status,'detail':detail})
(args.root/'mechanism-method-os-matrix.json').write_text(json.dumps(matrix,ensure_ascii=False,indent=2))
print(json.dumps({'runs':args.runs,'controlsPassed':True,'phases':len(rows),'completeSettledFrames':sum(x['completeSettledFrames'] for x in rows),'resizeLeakRuns':[x['run'] for x in rows if x['phase']=='spi-only-resized-active' and x['partialOrFullPatternFrames']>0]},indent=2))
