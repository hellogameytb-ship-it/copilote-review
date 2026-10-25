import AppKit

MainActor.assumeIsolated {
    let app = CopiloteApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
