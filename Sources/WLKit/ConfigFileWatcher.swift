import Foundation

/// Watches the parent directory of a config file. Atomic save replaces the
/// inode, so the file itself is the wrong thing to watch.
public final class ConfigFileWatcher: @unchecked Sendable {
    private let path: String
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "cc.worklouder.config-watch")
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public init(path: String, debounce: TimeInterval = 0.25, onChange: @escaping () -> Void) {
        self.path = path
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() {
        queue.sync { startLocked() }
    }

    public func stop() {
        queue.sync { stopLocked() }
    }

    deinit {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    private func startLocked() {
        stopLocked()
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let fd = open(parent.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleLocked()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        self.source = source
        source.resume()
    }

    private func stopLocked() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    private func scheduleLocked() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
