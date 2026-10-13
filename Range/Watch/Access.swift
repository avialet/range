import AppKit
import Foundation
import RangeCore

/// Acces aux dossiers proteges (Telechargements, Documents). L'app n'est pas sandboxee : macOS
/// demande l'autorisation au premier acces (textes `NSDownloadsFolderUsageDescription` et
/// `NSDocumentsFolderUsageDescription`), et un refus donne `EPERM`. Signature ad hoc : chaque mise a
/// jour change l'empreinte du binaire et macOS redemande.
enum AccessState: Equatable {
    case unknown
    case granted
    case denied
    case missing
}

enum Access {
    /// Lit le dossier (et declenche l'invite de macOS si elle n'a jamais ete montree). Bloquant :
    /// a appeler hors du fil principal.
    nonisolated static func probe(_ path: String) -> AccessState {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
            return .granted
        } catch {
            switch FolderAccessError.from(error) {
            case .denied: return .denied
            case .missing: return .missing
            case .other: return .denied
            }
        }
    }

    /// Reglages Systeme > Confidentialite et securite > Fichiers et dossiers.
    @MainActor static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        NSWorkspace.shared.open(url)
    }
}
