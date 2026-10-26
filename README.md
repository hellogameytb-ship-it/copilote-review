# Copilote — source review snapshot

Native macOS conversation assistance in Swift, SwiftUI and AppKit. This sanitized snapshot corresponds to the build 19 source plus isolated capture experiments, replacing the older review snapshot. See [AGENT_HANDOFF.md](AGENT_HANDOFF.md) for changes, architecture, validation and remaining limits.

This repository has its own history and pseudonymous commit identity. It excludes personal documents, knowledge vaults, interview context, notes, credentials, recordings, screenshots, signing identity, private reports and original Git history. Profiles contain generic instructions; provide your own synthetic context for review.

## Development

Requires macOS, Xcode and XcodeGen. Configure your own signing identity in `project.yml`. `make gen` generates the project, `make build` builds the app, and `make kit-test` runs framework tests. Demo fixtures are omitted; commands requiring them need synthetic replacements. This sanitized export has not been independently built or runtime-tested. Upstream test results in the handoff do not establish validation of a separately signed build.

Use assistance only where permitted. Window capture-exclusion flags do not guarantee invisibility to screen-sharing or recording tools, including ScreenCaptureKit-based capture. Cursor visibility is not guaranteed.

Vendored license notices remain under `Copilote/Resources/web/vendor/licenses/`. This README makes no additional license grant for project code.
