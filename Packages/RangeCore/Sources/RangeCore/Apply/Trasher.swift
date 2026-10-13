import Foundation

/// Mise a la corbeille : jamais de suppression. Renvoie l'emplacement dans la corbeille.
public protocol Trasher: Sendable {
    func trash(_ url: URL) throws -> URL
}

/// La vraie corbeille du Finder (`FileManager.trashItem`), restaurable par « Remettre » aussi.
public struct SystemTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let path = result?.path else { throw CocoaError(.fileWriteUnknown) }
        return URL(fileURLWithPath: path)
    }
}

/// Corbeille de substitution (tests, essais sur un dossier jetable : `RANGE_TRASH_PATH`).
public struct FolderTrasher: Trasher {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func trash(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        var target = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(NameNormalizer.variant(name, number: n))
            n += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}
