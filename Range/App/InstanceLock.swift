import AppKit
import Foundation

/// Verrou `flock` a cote de la base : une seule instance de Range range un dossier a la fois (en plus
/// de `LSMultipleInstancesProhibited`, qui ne couvre pas un lancement direct du binaire).
final class InstanceLock {
    let acquired: Bool
    private let fd: Int32

    init(next database: URL) {
        let path = database.deletingLastPathComponent().appendingPathComponent("range.lock").path
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        fd = path.withCString { open($0, O_CREAT | O_RDWR, 0o644) }
        acquired = fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0
    }

    deinit {
        if fd >= 0 { close(fd) }
    }

    /// Montre l'instance deja ouverte (meme bundle), puis quitte celle-ci.
    @MainActor static func yieldToRunningInstance() {
        let me = NSRunningApplication.current
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0 != me }) {
            other.activate()
        }
        NSApp.terminate(nil)
    }
}
