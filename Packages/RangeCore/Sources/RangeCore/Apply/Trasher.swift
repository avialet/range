import Foundation

/// Mise a la corbeille : jamais de suppression. Renvoie l'emplacement dans la corbeille.
public protocol Trasher: Sendable {
    func trash(_ path: String) throws -> String
    /// Ou chercher un fichier jete dont la ligne est restee `pending` (voir `Recovery`).
    var searchFolders: [String] { get }
}

/// La vraie corbeille du Finder (`FileManager.trashItem`), restaurable par "Remettre" aussi.
public struct SystemTrasher: Trasher {
    public init() {}

    public var searchFolders: [String] {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).map(\.path)
    }

    public func trash(_ path: String) throws -> String {
        var result: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &result)
        guard let trashed = result?.path else { throw CocoaError(.fileWriteUnknown) }
        return trashed
    }
}

#if DEBUG
/// Corbeille de substitution (tests, essais sur un dossier jetable : `RANGE_TRASH_PATH`).
public struct FolderTrasher: Trasher {
    public let folder: String

    public init(folder: String) {
        self.folder = folder
    }

    public var searchFolders: [String] { [folder] }

    public func trash(_ path: String) throws -> String {
        if !FileOps.exists(folder) { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
        let name = FilePath.name(path)
        var target = FilePath.join(folder, name)
        var n = 2
        while FileOps.exists(target) {
            target = FilePath.join(folder, NameNormalizer.variant(name, number: n))
            n += 1
        }
        try FileOps.renameExclusive(path, target)
        return target
    }
}
#endif
