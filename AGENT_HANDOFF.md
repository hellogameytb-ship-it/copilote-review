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
