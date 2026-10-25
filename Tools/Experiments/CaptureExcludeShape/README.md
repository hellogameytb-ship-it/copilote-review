# Isolated CGS capture-shape experiment

This directory is outside every Copilote/Xcode target. Nothing here is loaded by the installed app or candidate 13. The SPI is resolved dynamically from CoreGraphics; all calls use a window created and registered in this process. No `@silgen_name`, hard-linked private symbol, foreign PID/window operation, permission request or system setting change.

## Reproduce the final pixel protocol

From the repository root:

```sh
/bin/sh Tools/Experiments/CaptureExcludeShape/build.sh
python3 Tools/Experiments/CaptureExcludeShape/run.py build/retours-16 repro-a repro-b
python3 Tools/Experiments/CaptureExcludeShape/analyze.py build/retours-16 repro-a repro-b
```

Each run displays one non-key synthetic checkerboard panel for a bounded interval, then closes it. Existing screen-recording permission is required; without it the test stops without requesting permission. Only `SCContentFilter(desktopIndependentWindow:)` is used, selecting the app-created window ID. There is no PID/app inclusion or exclusion filter. No desktop, microphone or system audio is captured. Cursor capture is off only for this test's stream.

`stream.mm` runs 15 phases: positive baseline, background control, baseline restore, sharing-none during an active stream, OFF restore, SPI alone during the stream, OFF restore, SPI before resize, immediate reapply after resize, reapply again after settling, OFF restore, and separate stream-start cases for sharing-none, baseline, SPI and OFF. The two protections are never combined in this final protocol.

The pattern animates a small corner outside sampled cell centers to obtain complete frames. At 10 fps, each phase retains bounded per-frame scalar measurements (up to 40 image records), with a 600 ms settling threshold, target of six complete settled frames, three-second phase limit and 90-second overall watchdog. Forty-eight spatial color samples compare a predefined checkerboard with RGB tolerance 0.10. A full positive requires similarity ≥0.90 and marker fraction ≥0.65. A partial leak requires at least two colored samples and two spatial-template matches; partial visibility is never classified as safe merely because full-pattern detection failed. Raw status codes, frame dimensions, window geometry, scale, early frames and transition timings remain in JSON.

Only cropped synthetic ROI PNGs are persisted, plus measurements. The complete frame buffers stay in RAM. `analyze.py` rejects missing positive/background controls or fewer than six complete settled frames; it reports pixels separately from CGError.

There is deliberately **no full-display capture mode**. A foreground shield on the user's desktop cannot guarantee that notifications, menus or another window will never introduce private pixels. Full-display tests need an isolated session/display/VM containing only fixtures. They remain NOT TESTED here.

## Earlier lifecycle probe

`main.mm` also builds `capture-shape-experiment OUTPUT [--capture-own-window]`. It exercises missing-symbol resolution, null-region clearing, CF lifetime, resize, suspend/reopen, an injected nonzero error and window recreation. Its optional screenshots are exploratory only; the final comparison uses `stream.mm`. The exploratory first run had a failed baseline screenshot and must not be used as the controlled pixel result.

## Result and limits

On macOS 27.0.1 (26A434), arm64, two final runs reproduced partial capture after immediate resize despite CGError 0. Delayed reapplication removed the sampled pattern again. At stable size SPI output was opaque gray, while sharing-none output was transparent in this particular single-window stream. OFF restored the pattern. These are not full-display, receiver, cursor, other-OS, physical resize, lock/sleep or multi-display results.

Dynamic lookup avoids failure from an absent symbol, but cannot guarantee ABI stability or semantic behavior of a private API. Any integration needs separate review, geometry lifecycle handling, explicit failure behavior and additional authorized receiver/isolated-display tests. The prototype remains unshipped.

## Authorized combination addendum (retours 17)

The additional human authorization permits comparing the combination in this isolated harness only. `addendum.mm` reuses the fixture/metrics helpers; it does not change the prior protocol or either production binary.

```sh
/bin/sh Tools/Experiments/CaptureExcludeShape/build-addendum.sh
python3 Tools/Experiments/CaptureExcludeShape/run-addendum.py build/retours-17 repro-a repro-b
python3 Tools/Experiments/CaptureExcludeShape/analyze-addendum.py build/retours-17 repro-a repro-b
```

The 19 phases compare no protection, sharing-none, SPI, and both at 480×300 and 640×400 points; background/OFF controls; twelve incremental resize steps; and incremental moves. A single fixed 640×400 SCK stream requests 30 fps without configuration changes. For SPI and both, resize policies compare real `windowDidResize` callbacks with reapplication at the end of the **programmatic** trajectory. A further reapplication follows 600 ms later. This is not a physical live-resize gesture: `inLiveResize` and native start/end callbacks are recorded, not synthesized.

Every callback is retained up to a checked cap of 180 per phase. Setup, motion, immediately-after, and late phases remain separate. Analysis reports all leaks, including queued frames with timestamps preceding policy application, and callback/complete-image gaps. Settled subsets never erase transient evidence. The 48-point metric can miss thinner edge exposure; cropped PNGs do not cover the edges. Synthetic alpha compositing uses generated checker colors, never desktop pixels or a receiver capture.

The two runs found a transparent combination, without a measured improvement over sharing-none in steady single-window capture. SPI alone leaked in 14/18 and 16/20 motion frames when waiting until the trajectory ended. Reapplying on every resize callback had no sampled motion leak (40 frames), but one setup frame still leaked in the second run. There were also two queued pre-policy pattern frames delivered after sharing-none was applied. See `docs/diagnostic-retours-17-2026-10-25.md` for counts, timing gaps, and limitations. Full-display and physical live-resize remain NOT TESTED.
