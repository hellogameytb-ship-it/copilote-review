# Copilote — source review snapshot

Native macOS conversation-assistance application, written in Swift, SwiftUI and AppKit.

This standalone snapshot is intended for source review and proposed patches. It does not include the original Git history, personal knowledge base, interview profiles, session data, recordings, screenshots, signing identity or demo fixtures. It predates ongoing UI and profile changes in the private working project. Do not assume feature parity with the installed application.

## Development

Requires macOS, Xcode and XcodeGen. Review `project.yml` and set your own signing configuration before building. `make gen` generates the Xcode project; `make build` builds the app; `make kit-test` runs framework tests. Commands requiring omitted fixtures need your own synthetic data. This sanitized export has not been independently built or runtime-tested.

## Review map

- `Copilote/`: native app, panels, settings, input and session integration.
- `CopiloteKit/`: reusable conversation, provider, audio and indexing logic.
- `CopiloteKitTests/`: framework tests.
- `Replay/`, `Tools/`, `scripts/`: diagnostics and development utilities.

Use synthetic examples only. Never add credentials or private documents. Capture-exclusion settings do not guarantee invisibility in screen-sharing applications. Use assistance only where permitted.

Vendored dependency license notices remain under `Copilote/Resources/web/vendor/licenses/`. No additional license grant is made for project code by this README.
