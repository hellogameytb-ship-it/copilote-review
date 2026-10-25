import CoreServices
import Foundation

/// FSEvents on the base folder and the added photo folders: one callback per burst of changes
/// (an editor saving, a dozen photos copied), on the main queue.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private var pending: DispatchWorkItem?

    init?(folders: [URL], onChange: @escaping () -> Void) {
        self.onChange = onChange
        let paths = folders.map(\.path).filter { FileManager.default.fileExists(atPath: $0) } as CFArray
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().changed()
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
