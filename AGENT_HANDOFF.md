# Current update — build 22: Answer context and request reliability

Answer now freezes the full two-minute conversation at the click, without a three-fragment limit. The preceding two-to-five-minute band completes long statements; older session material supplies relevant background without duplication. Recent substantive questions take priority over old topics; acknowledgements and short follow-ups retain their context. No extra model call is used to select context. Exclusions, Clear chat boundaries, private profile isolation and fresh-response behavior remain intact.

Codex work uses one shared bounded queue with manual priority, background coalescing, spacing and expiry. Observable 429 errors trigger shared cooldown respecting supplied delays, without automatic replay or account/provider switching. Cancellation waits for terminal confirmation; an unresponsive owned transport is quarantined. Previous answers and newer drafts survive failures. Redacted local diagnostics retain timing, action, recognized error metadata and correlation IDs, not prompts or personal content. These changes cannot prevent all service-side rate limits.

Validation of the exact private candidate: 360 framework tests and 1,255 native fixture checks, including 26 Answer, 18 reliability, 30 paste and 23 chat checks. 613 geometry samples and 17 window-policy probes passed. Synthetic provider/transport/audio text only; no live AI, real microphone, desktop capture or physical keyboard test. Prompt transport is verified; model interpretation is not guaranteed. Sanitized export is not independently rebuilt.

Candidate binary SHA-256: cb534fd08c425661b5438b2eef537ca60fd44d6704136576acea1ac831b26dc3. Installation verification is pending at this export. No private interview material, profile, notes, credentials or original Git history is included. Preserve existing privacy gates and avoid private capture APIs; universal capture invisibility is not promised.

---

Earlier updates below are historical and superseded where applicable.

# Current update — build 20 image paste

Command-V in the Ask composer now adds copied images to the existing preview stack without sending a request. The draft, selection and local focus are retained. Ordinary text uses native selection replacement and updates the SwiftUI binding. Text URLs remain text and are never downloaded.

Copied image files outrank Finder names/icons. Otherwise PNG outranks TIFF per item; image data outranks companion text. Paste snapshots are taken only on the explicit gesture, with no clipboard polling. Multiple items and rapid gestures preserve order. Limits: 20 images, 32 MiB per image and 64 MiB per gesture; background thumbnail decoding feeds the existing JPEG pipeline capped at 1600 pixels.

Sending waits for import completion. Cancel import invalidates pending batches/decodes while preserving completed previews. Full reset prevents late images from reappearing. Clear chat continues to preserve pending captures and exclusion choices. Unsupported or invalid images produce inline feedback, with no system dialogs. Preserve these distinctions in follow-up changes.

Validation: 329 framework tests; 1,228 native fixture checks including 29 paste, 23 chat and 18 fresh-Answer checks; 613 geometry samples without required movement; 17 window-policy probes and overlay linter pass. Tests invoke Paste on the production editor with an isolated pasteboard and synthetic images/provider. Initial color-fixture failures were corrected and final results rerun. No physical keyboard gesture, third-party clipboard integration, real audio, desktop capture or live AI was tested. The sanitized export is not independently rebuilt.

Build20 installed after idle verification and build19 backup. Installed binary SHA-256 independently verified: 7a41cf7e42273bc55b2a3560228146e26688810d019f1c1d04e0bf0d638d4b2f; signature passes. Startup remains hidden. No private profile, notes, source documents or original Git history are exported. Capture exclusion is not a universal invisibility guarantee.

---

Historical updates below are superseded by build20 where applicable.

# Current update — build 19 installed and verified

The reader is now a chronological chat: manual Ask/Answer requests retain their actual question and response; streaming updates only that entry. Explicit topic-card navigation can add/select its cached response. Scrolling up stays anchored while newer content arrives; Latest returns to the bottom. Copy belongs to each entry. Retry is available only for the selected failed request and validates its ID.

Clear chat uses inline confirmation (also through the existing clear shortcut). It cancels requests and lookups, clears rendered exchanges and their model context, and sets a boundary for subsequent audio context without stopping capture. Late pre-boundary transcripts, topic decisions and answer callbacks are rejected. Profiles, allowed notes, pending screenshots and screenshot exclusion choices are preserved. Previously saved sessions on disk are not deleted. The first interim speech after reset is suppressed until a new finalized phrase establishes post-reset context.

Previous exchanges sent to the model are bounded to six pairs and 12,000 characters; this is NOT a total context budget. Audio transcript, profile and other context are separate. Visible chat remains available until clearing. Fresh Answer behavior from build18 is preserved.

Validation: 329 framework tests; 1,199 native fixture checks including 23 chat and 18 fresh-Answer checks; 613 geometry samples with no required-origin movement. Narrow/wide/confirmation renders inspected. Initial native fixture failures involved hidden-render refresh scheduling and incorrect confirmation invocation; logs retained, final exact candidate passes. Parent found and requested the old-row Retry correction, then verified its tests and implementation.

Installation: build18 backed up; listening checked stopped before replacement. Build19 started hidden without taking focus. Existing notes, preferences and active private profile preserved. Installed hash and signature independently rechecked. Test/backup app bundles are archived to avoid Spotlight duplicates.

Exact binary SHA-256: eb967fb725a3b2a6aad1ac6c17a3061aef678bf20db7e1642a41304841ae7c1e. Signature independently verified. Synthetic provider/transcripts/images only: no live AI, real audio, desktop capture, physical clicks or global keyboard delivery tested. Sanitized export is not independently rebuilt. No private profile or vault data is included. Capture invisibility remains unguaranteed.

---

Historical updates below are superseded by build19 where applicable.

# Current update — build 18 installed and verified

Answer and its existing shortcut now create a fresh response from speech frozen at the click, independently of selected cards and their cached answers. The last finalized phrases and recent provisional transcription are emphasized, with five minutes of preceding speech and cumulative included session context. Provisional text is labeled, expires, and is removed when finalized. No usable speech produces an inline message instead of replaying a card.

Each request freezes profile, preferences, allowed notes, selected base, captures and transcript exclusions. A cancellable lookup retrieves relevant source excerpts and replaces the old extracts while preserving exclusions. A later click cancels the prior request; late callbacks cannot replace its response. Explicit card selection still permits cached navigation. This does not fix all automatic topic segmentation/latency issues.

Also included: configurable Option-Command-P to expand/collapse the panel, and a 220-by-40 Capture screen button displaying the effective shortcut (default Shift-Command-S). Capture adds an image to the preview stack without automatically sending it to the model. Existing order/removal/cancellation behavior is retained.

Validation of the private upstream binary: 327 framework tests; 1,176 native fixture checks, including 18 fresh-Answer checks. 613 geometry samples report no required-origin movement. Parent independently reviewed the code, native result files, binary hash and signature. SHA-256: c132898e14aed2291c70ca1b2cbd5d376b448fea140e989ab63b05c455b8226b.

Scope: synthetic provider, synthetic transcript/base excerpts/images, no live model request, microphone capture, desktop capture, physical clicks or global keyboard events. Actual personal-base retrieval and a live call have not been validated in this lot. The sanitized export has not been independently built. Screen-sharing and cursor invisibility remain unverified; private capture SPI is not integrated.

Agent guidance: preserve request snapshot/cancellation and exclusion invariants, do not restore implicit card/cache routing for Answer, and do not expose private notes or source data in commits. Build18 was installed after checking listening was stopped twice. The old build15 was backed up. Installed hash and signature were independently rechecked. Startup remained hidden without taking focus, with listening stopped; 13 notes and all existing preferences were preserved. No live audio or desktop capture was started.

---

Historical delivery notes follow; build18 source supersedes the older source descriptions.

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
