import AppKit
import Foundation

/// Surveille le premier niveau d'un dossier (DispatchSource sur un descripteur `O_EVTONLY`) et
/// appelle `onChange` apres 2 s de calme. Les deplacements de Range relancent une passe qui ne
/// trouve rien : le planificateur est idempotent.
@MainActor
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    /// false si le dossier ne s'ouvre pas (acces refuse, absent).
    @discardableResult
    func watch(_ path: String) -> Bool {
        stop()
        let fd = path.withCString { open($0, O_EVTONLY) }
        guard fd >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        return true
    }

    func stop() {
        debounce?.cancel()
        source?.cancel()
        source = nil
    }

    private func schedule() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }
}
