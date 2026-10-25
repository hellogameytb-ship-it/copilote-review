# Delivery — build 15 installed and checked

Build 15 was installed after visible fixture validation. Exact binary SHA-256: bb91e216a1f3d6b423cb5573e15e583bd6069da1a3aaceed5be31f2a1061b71b. Signature and installed manifest were verified; build 13 was backed up outside the volatile build directory. No active session was interrupted.

Visible checks exercised confirmation, focus and positioning. An Auto test initially clicked its label rather than its switch; corrected targeted clicks toggled both ways without keyboard acquisition or movement. Interrupted focus-stress cycles were not counted as passes. Visible fixture code uses the same production sources; distinguish this from physically hand-operated testing of every workflow.

The installed binary started hidden, then explicitly reopened with listening stopped and Stealth ON. All 13 notes and the semantic content of 80 preferences, including shortcuts, were preserved; JSON serialization order changed for some values. No private SPI is integrated. Receiver-side screen-sharing and cursor guarantees remain unverified.

The candidate-only statements below are historical and superseded by this delivery notice.

---

# Current update — candidate 15 (not installed)

Stealth OFF now requires inline confirmation in the pill and settings. The same owner-specific transient token controls both paths; cancel, Escape, hiding, focus loss, suspension and session changes invalidate it. ON remains immediate; a previously confirmed OFF persists. There is no OFF shortcut.

Ask/window stability: native position is tracked after asynchronous drag completion; existing anchor geometry is retained during input and answers. AppKit could shift a reattached child despite correct saved coordinates. The chosen child frame is now applied after addChildWindow.

Three silent isolated runs: 721 checks each (2,163 total), 1,398 geometry measurements with zero unwanted offset. 317 framework tests pass. Parent reviewed confirmation state/lifecycle and reattachment changes, reran the window linter and verified candidate signature. These are real AppKit objects with display/focus blocked and rendered-control closures invoked, NOT physical mouse or live-focus tests. Physical clicks, drag, focus transfer and global shortcuts still need an idle authorized test window. Installed build 13 remains unchanged. Cursor exclusion is not implemented or promised.

Earlier build artifacts/backups stored only in the ignored build directory became unavailable after that directory disappeared for an undetermined reason. Current candidate 15 tests and manifests were rebuilt; prior reports are historical results, not a claim that all older raw artifacts remain available.

Sanitized export is source-review material and has not been independently rebuilt. Do not publish personal notes, profiles or vault contents. Private SPI remains an isolated experiment, not production code.

---

# Current update — build 13 and isolated experiments

Build 13 adds an app-owned ProtectedFileBrowser behind the asynchronous SystemDialogs seam. Native NSOpenPanel/NSSavePanel creation is removed. Folder selection, bookmarks, cancellation, Markdown export and inline overwrite confirmation are retained. Session/hidden guards apply throughout. This non-sandboxed browser does not grant Powerbox sandbox access. Export uses exclusive creation, rejects symlink targets and rechecks replacement metadata; replacement is not a transaction against malicious concurrent writers.

Character-palette events delivered to protected app windows are consumed, without global interception. Physical Globe handling before delivery to the app remains unverified. The linter no longer exempts SystemDialogs or all diagnostics; two exact deliberate drift injections remain allowed.

Upstream: 309 framework tests, browser 37/37 across three runs, guard 49/49, profile 20/20, presentation 28/28, UI 77/77 and launch 14/14 in each Stealth state. Independent review reran the linter and its 17 negative probes and verified candidate signature. Sanitized export itself has not been rebuilt.

## Capture research — NOT production code

Tools/Experiments/CaptureExcludeShape is outside app targets. Private SPI is not loaded by the app. Keep public sharingType policy in production. The harness tests a synthetic window only, using SCK desktopIndependentWindow with no PID/app filter. This does not establish full-display behavior.

On the recorded macOS 27.0.1 / 26A434 environment: sharingType alone produced transparent samples; SPI alone produced opaque gray and resize leaks. Two combination-addendum runs measured 2,355 images: no pattern detected in 708 combination frames, with no established steady-state advantage over sharingType alone. SPI with final-only resize reapplication leaked in 30 motion frames; per-didResize reapplication had no sampled motion leak but one setup leak. Capture gaps reached 550 ms. Queued pre-policy frames and sampled spatial coverage prevent a no-transient-leak claim.

| Method / OS | sharingType alone | SPI alone | Combined |
| --- | --- | --- | --- |
| SCK single-window / recorded 27.0.1 | Transparent in tested phases; queued pre-policy frames noted | Gray, transient leaks | Transparent, no detected pattern; no proven gain |
| SCK whole display / recorded 27.0.1 | Not tested | Not tested | Not tested |
| SCK / macOS 15.x or 26.x | Not tested | Not tested | Not tested |
| Meet / Zoom / Teams receiver, all modes | Not tested | Not tested | Not tested |

No receiver-side cursor exclusion, hardware lock/sleep, or physical monitor changes are established. Reproduce only in an authorized synthetic environment; no desktop capture fallback exists. Read the experiment README for protocol, sampling limitations and commands. Do not integrate SPI unless an actual public-mechanism failure is demonstrated and a separately reviewed experiment establishes a benefit.

The earlier handoff below records build 12 history; its statement about OS file dialogs is superseded by this update.

---

# Agent handoff — build 12 source snapshot

## Scope and changes since the previous public snapshot

This update replaces the old review source with the current build 12 source. Review this tree rather than assuming findings from the previous snapshot still apply. No personal application context or production preferences are included.

- Compact dark translucent appearance replaces the rejected bright treatment. The pill is 600 × 40, with compact controls and a distinct Stealth ON/OFF label. It is not claimed to reproduce Liquid Glass exactly. Text stays opaque; system accessibility preferences are not changed.
- Topics are independently selectable above a central answer reader. Background answers do not unexpectedly change the selected topic. Manual requests, contextual follow-ups and ordered multiple screenshots remain supported.
- Infosys technical-interview profile uses English and bounded user-supplied context. Missing application, role, team and stack facts remain unknown. Normal mode removes profile instructions and profile-generated context from subsequent requests. Archived Excel notes remain private and separate.
- Manual sticky notes retain persistence, pinning and explicit AI inclusion controls. Personal notes are absent from this export.
- ProtectedPanel and WindowPrivacy centralize local presentation protection. Cold launch and recovery stay hidden and idle; an explicit user action reveals the expanded interface. Background provider output cannot authorize display.
- Explicit Stealth OFF remains available and persistent. ON uses accessory activation and window-sharing exclusion; OFF changes the local window policy. Listening, automatic answers and Stealth are distinct states.
- SystemDialogs rejects file open/save requests inline before constructing a system dialog when presentation is unauthorized or a session is active, including paused sessions. Dialogs are cancelled when the session starts or presentation is suspended; authorization is rechecked before accepting results. Explicit file selection outside a session is retained.
- Sleep, lock and unavailable-screen handling hide/pause the app without automatic redisplay. Production windows are non-restorable and cannot become visible without login.

## Architecture and audit reconciliation

Start with `Copilote/App`, `Copilote/Overlay`, `Copilote/Main`, `Copilote/Session`, `Copilote/Listening` and `Copilote/Capture`. Framework logic and tests live in `CopiloteKit` and `CopiloteKitTests`.

Search for `WindowPrivacy`, `ProtectedPanel`, `SystemDialogs`, `SettingsStore`, `DiagnosticInterviewProfile` and `DiagnosticReader` for the relevant implementation and recipes.

The older audit's MainWindow and status-menu findings must be rechecked: MainWindow now uses the protected panel hierarchy, the old status NSMenu is removed, and production display paths are centrally guarded. DiagnosticGlass is a fixture, not a normal production presentation path. System file dialogs remain OS-owned and are gated rather than falsely represented as universally excluded from capture.

Do not introduce `canBecomeVisibleWithoutLogin = true`, arbitrary window-level escalation, automatic display after recovery, or a regular activation policy while Stealth is ON. Do not replace working file/bookmark handling with an incomplete custom filesystem browser merely to claim capture exclusion.

## Validation evidence and its limits

Upstream validation reported: 306 framework tests on build 11 (framework unchanged for build 12); build 12 targeted presentation/dialog guard checks 49/49 across three runs, profile checks 20/20, UI checks 77/77, movement checks 21/21 and launch checks 14/14. Movement included 120 synthetic moves with zero measured group offset; this is not a physical FPS benchmark. Dialog adapter tests did not open real native file dialogs.

The installed upstream build 12 passed signature verification, hidden idle startup and explicit expanded reopen checks. Existing notes and preferences were preserved. Visual inspection covered compact controls and reader sizing. These results belong to the upstream installation, not an independently rebuilt sanitized export.

Still unverified: recipient-side Meet/Zoom/Teams capture, cursor exclusion, physical lock/unlock, real multi-monitor unplugging, hardware smoothness and real native file-picker cancellation. Long synthetic conversation tests are not equivalent to a human meeting. Do not call this universally invisible or completely validated.

## Instructions for subsequent agents

1. Work from current main and preserve privacy gates, profile isolation and independent topic selection.
2. Use synthetic documents, notes and credentials. Never request or commit a complete personal vault.
3. Distinguish static code findings, fixture results, real application behavior and recipient-side capture observations.
4. Supply focused patches with reproduction steps and regression evidence. Check all display paths before changing lifecycle, menus, dialogs or focus handling.
5. Validate a locally configured build separately; omitted fixtures and sanitized bundle identifiers/signing settings can affect commands and app identity.
6. Do not infer a person's political opinions, employment status or technical experience from example prompts. Do not solve supervised assessments through covert assistance.
