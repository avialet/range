import AppKit
import Foundation
import os

/// Verrou `flock` a cote de la base : une seule instance de Range range un dossier a la fois (en plus
/// de `LSMultipleInstancesProhibited`, qui ne couvre pas un lancement direct du binaire).
final class InstanceLock {
    let acquired: Bool
    let path: String
    /// Le fichier de verrou ne s'ouvre pas : `errno` de `open`, sinon nil.
    let openError: Int32?
    private let fd: Int32

    static let logger = Logger(subsystem: "fr.vialet.range", category: "verrou")

    init(next database: URL) {
        path = database.deletingLastPathComponent().appendingPathComponent("range.lock").path
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        fd = path.withCString { open($0, O_CREAT | O_RDWR, 0o644) }
        openError = fd < 0 ? errno : nil
        acquired = fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0
    }

    deinit {
        if fd >= 0 { close(fd) }
    }

    /// Verrou introuvable : on le consigne, on le dit, puis on quitte (sans verrou, deux instances
    /// pourraient ranger en meme temps).
    @MainActor func reportOpenFailureAndQuit() {
        let code = openError ?? 0
        let reason = String(cString: strerror(code))
        Self.logger.error("Verrou d'instance impossible a ouvrir : \(self.path, privacy: .public) (errno \(code) : \(reason, privacy: .public))")
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Range ne peut pas d\u{00E9}marrer"
        alert.informativeText = "Le fichier de verrou \(path) ne s\u{2019}ouvre pas (\(reason)). Sans lui, deux copies de Range pourraient ranger en m\u{00EA}me temps : Range s\u{2019}arr\u{00EA}te."
        alert.addButton(withTitle: "Quitter")
        alert.runModal()
        NSApp.terminate(nil)
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
