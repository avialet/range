import Foundation
import RangeCore

/// Ou Range lit et range. En DEBUG seulement, des variables d'environnement pointent des dossiers
/// jetables pour les essais, sans jamais toucher aux vrais dossiers : `RANGE_DOWNLOADS_PATH` (dossier
/// surveille), `RANGE_HOME_PATH` (racine des destinations `~/...`), `RANGE_TRASH_PATH` (corbeille de
/// substitution). En release : Telechargements (ou le dossier choisi), le dossier personnel et la
/// vraie corbeille, toujours.
struct RangePaths: Equatable {
    var folder: String
    var home: String
    /// nil : la vraie corbeille du Finder.
    var trash: String?

    static let defaultsFolderKey = Brand.key("WatchedFolder")

    static var realDownloads: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
    }

    static func current() -> RangePaths {
        let chosen = UserDefaults.standard.string(forKey: defaultsFolderKey)
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        func env(_ key: String) -> String? {
            environment[key].flatMap { $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath }
        }
        return RangePaths(folder: env("RANGE_DOWNLOADS_PATH") ?? chosen ?? realDownloads,
                          home: env("RANGE_HOME_PATH") ?? NSHomeDirectory(),
                          trash: env("RANGE_TRASH_PATH"))
        #else
        return RangePaths(folder: chosen ?? realDownloads, home: NSHomeDirectory(), trash: nil)
        #endif
    }

    /// Essai sur des dossiers jetables (DEBUG ; affiche dans la barre laterale).
    static var isTrial: Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        return ["RANGE_DOWNLOADS_PATH", "RANGE_HOME_PATH", "RANGE_TRASH_PATH"].contains { env[$0]?.isEmpty == false }
        #else
        return false
        #endif
    }

    var trasher: any Trasher {
        #if DEBUG
        if let trash { return FolderTrasher(folder: trash) }
        #endif
        return SystemTrasher()
    }

    var isDefaultFolder: Bool { folder == Self.realDownloads }

    /// Nom du dossier surveille tel que le montre le Finder ("Telechargements").
    var folderDisplayName: String {
        FileManager.default.displayName(atPath: folder)
    }
}
