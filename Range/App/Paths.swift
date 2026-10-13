import Foundation
import RangeCore

/// Ou Range lit et range. Les variables d'environnement pointent des dossiers jetables pour les
/// essais et les captures, sans jamais toucher aux vrais dossiers :
/// `RANGE_DOWNLOADS_PATH` (dossier surveille), `RANGE_HOME_PATH` (racine des destinations `~/...`),
/// `RANGE_TRASH_PATH` (corbeille de substitution).
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

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> RangePaths {
        func env(_ key: String) -> String? {
            environment[key].flatMap { $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath }
        }
        let chosen = UserDefaults.standard.string(forKey: defaultsFolderKey)
        return RangePaths(folder: env("RANGE_DOWNLOADS_PATH") ?? chosen ?? realDownloads,
                          home: env("RANGE_HOME_PATH") ?? NSHomeDirectory(),
                          trash: env("RANGE_TRASH_PATH"))
    }

    /// Essai sur des dossiers jetables (affiche dans la barre laterale).
    static var isTrial: Bool {
        let env = ProcessInfo.processInfo.environment
        return ["RANGE_DOWNLOADS_PATH", "RANGE_HOME_PATH", "RANGE_TRASH_PATH"].contains { env[$0]?.isEmpty == false }
    }

    var trasher: any Trasher { trash.map { FolderTrasher(folder: $0) } ?? SystemTrasher() }

    var isDefaultFolder: Bool { folder == Self.realDownloads }

    /// Nom du dossier surveille tel que le montre le Finder (« Téléchargements »).
    var folderDisplayName: String {
        FileManager.default.displayName(atPath: folder)
    }
}
