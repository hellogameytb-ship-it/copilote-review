#!/usr/bin/env python3
"""Keep all transitions visible; settling never erases a recorded leak."""
import argparse
import csv
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser()
parser.add_argument('root', type=Path)
parser.add_argument('runs', nargs='+')
args = parser.parse_args()
rows, phases, controls = [], [], []

def stats(frames):
    valid = [f for f in frames if 'meanRGBA' in f]
    complete = [f for f in valid if f['frameStatus'] == 0]
    image_gaps = [(b['callbackHostSeconds']-a['callbackHostSeconds'])*1000
                  for a, b in zip(complete, complete[1:])]
    return {
        'callbacks': len(frames), 'imageFrames': len(valid),
        'completeFrames': sum(f['frameStatus'] == 0 for f in frames),
        'patternFrames': sum(f['partialOrFullPatternDetected'] for f in valid),
        'fullPatternFrames': sum(f['patternDetected'] for f in valid),
        'minAlpha': min((f['meanRGBA'][3] for f in valid), default=None),
        'maxAlpha': max((f['meanRGBA'][3] for f in valid), default=None),
        'meanRGBA': [statistics.mean(f['meanRGBA'][k] for f in valid) for k in range(4)] if valid else None,
        'maxCompositeBackgroundMAE': max((f['syntheticBackgroundMAE'] for f in valid), default=None),
        'maxMarkerFraction': max((f['markerSampleFraction'] for f in valid), default=None),
        'maxCallbackGapMs': max((f['gapSincePreviousCallbackMs'] for f in frames), default=0),
        'gapsOver100ms': sum(f['gapSincePreviousCallbackMs'] > 100 for f in frames),
        'maxCompleteImageGapWithinGroupMs': max(image_gaps, default=0),
        'p95CompleteImageGapWithinGroupMs': sorted(image_gaps)[int(.95*(len(image_gaps)-1))] if image_gaps else 0,
        'completeImageGapsOver100msWithinGroup': sum(g > 100 for g in image_gaps),
    }

for run in args.runs:
    report = json.loads((args.root / run / 'report.json').read_text())
    assert report['existingPermission'] and not report['permissionRequested']
    assert not report['desktopCapture'] and not report['config']['capturesAudio']
    assert report['createdRegions'] == report['releasedRegions']
    assert report['cleanup']['cgError'] == 0
    assert len(report['results']) == 19
    for phase in report['results']:
        assert phase['status'] == 'completed' and not phase.get('framesTruncated')
        assert phase['visible'] and phase['onActiveSpace']
        frames = phase['frames']
        steady = [f for f in frames if f['segment'] == 'steady-before' and f['elapsedMs'] >= 800 and f['frameStatus'] == 0]
        assert len(steady) >= 6, (run, phase['name'], 'insufficient steady frames')
        if phase['mode'] == 0:
            if phase['kind'] == 'background':
                assert all(f['backgroundSimilarity'] >= .9 and not f['partialOrFullPatternDetected'] for f in steady)
            else:
                assert all(f['patternDetected'] for f in steady), (run, phase['name'], 'positive control')
        for segment in ['setup', 'steady-before', 'motion', 'after-series', 'after-delayed-reapply']:
            selected = [f for f in frames if f['segment'] == segment]
            if selected:
                rows.append({'run': run, 'phase': phase['name'], 'mode': phase['mode'], 'segment': segment, **stats(selected)})
        # Additional steady subsets are reported separately, never replacing raw segment rows.
        rows.append({'run': run, 'phase': phase['name'], 'mode': phase['mode'], 'segment': 'steady-complete-800ms', **stats(steady)})
        late = [f for f in frames if f['segment'] == 'after-delayed-reapply' and f['elapsedMs'] >= phase.get('lateApplyElapsedMs', float('inf')) + 200 and f['frameStatus'] == 0]
        if phase['kind'] in ('resize', 'move'):
            assert len(late) >= 6, (run, phase['name'], 'insufficient delayed frames')
            rows.append({'run': run, 'phase': phase['name'], 'mode': phase['mode'], 'segment': 'late-complete-plus200ms', **stats(late)})
        events = phase['events']
        apis = [e['api']['cgError'] for e in events if 'api' in e]
        assert all(e == 0 for e in apis)
        leaks = [f for f in frames if f.get('partialOrFullPatternDetected')]
        post_policy = [f for f in leaks if f.get('ptsMinusPolicyAppliedMs', -1) >= 0]
        phases.append({'run': run, 'phase': phase['name'], 'mode': phase['mode'], **stats(frames),
            'allAPICGErrors': apis, 'statusCounts': phase['statusCounts'],
            'postPolicyPTSPatternFrames': len(post_policy),
            'patternElapsedMs': [round(f['elapsedMs'], 3) for f in leaks],
            'postPolicyPatternElapsedMs': [round(f['elapsedMs'], 3) for f in post_policy],
            'nativeDidResize': sum(e['kind'] == 'native-windowDidResize' and e['segment'] == 'motion' for e in events),
            'nativeLiveResizeStarts': sum(e['kind'] == 'native-windowWillStartLiveResize' for e in events),
            'nativeLiveResizeEnds': sum(e['kind'] == 'native-windowDidEndLiveResize' for e in events),
            'anyInLiveResize': any(f['inLiveResize'] for f in frames) or any(e['inLiveResize'] for e in events),
            'minPTSAfterPolicyMs': min(f.get('ptsMinusPolicyAppliedMs', 0) for f in frames),
            'maxCallbackMinusPTSMs': max((f['callbackHostSeconds']-f['presentationSeconds'])*1000 for f in frames),
        })
    complete = [f for p in report['results'] for f in p['frames']
                if f['frameStatus'] == 0 and 'meanRGBA' in f]
    gaps = [(b['callbackHostSeconds']-a['callbackHostSeconds'])*1000
            for a, b in zip(complete, complete[1:])]
    controls.append({'run': run, 'controlsPassed': True, 'phases': 19,
                     'createdRegions': report['createdRegions'], 'releasedRegions': report['releasedRegions'],
                     'maxCompleteImageGapIncludingPhaseBoundariesMs': max(gaps),
                     'p95CompleteImageGapIncludingPhaseBoundariesMs': sorted(gaps)[int(.95*(len(gaps)-1))],
                     'completeImageGapsOver100msIncludingPhaseBoundaries': sum(g > 100 for g in gaps)})

result = {'controls': controls, 'phases': phases, 'segments': rows,
          'physicalLiveResize': 'NOT TESTED', 'fullDisplay': 'NOT TESTED',
          'settledSubsetDoesNotDiscardRawTransitions': True}
(args.root / 'addendum-summary.json').write_text(json.dumps(result, indent=2))
with (args.root / 'addendum-segments.csv').open('w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print(json.dumps({'controls': controls, 'callbacks': sum(p['callbacks'] for p in phases),
                  'protectedPhasesWithPostPolicyPattern': [p for p in phases if p['mode'] and p['postPolicyPTSPatternFrames']]}, indent=2))
