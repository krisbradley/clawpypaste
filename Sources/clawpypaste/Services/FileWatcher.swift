import Foundation

// Watches a file for size/content changes using a DispatchSource on its fd.
// When the file is rotated (renamed/replaced), the watcher reopens on the
// next manual rescan trigger.
final class FileWatcher {
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private(set) var url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit { stop() }

    func updatePath(_ newURL: URL) {
        guard newURL != url else { return }
        stop()
        url = newURL
        start()
    }

    private func start() {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .global(qos: .utility)
        )
        let handler = onChange
        s.setEventHandler { handler() }
        s.setCancelHandler { [fd] in
            if fd >= 0 { close(fd) }
        }
        s.resume()
        source = s
    }

    private func stop() {
        source?.cancel()
        source = nil
        fd = -1
    }
}
