import Foundation
import RangeCore

extension FileFacts {
    /// Faits fictifs pour les tests purs (dossier /dl, inode derive du nom).
    static func sample(_ name: String, size: Int64 = 1000, modified: Date, added: Date, directory: Bool = false,
                       sources: [String] = [], screenCapture: Bool = false, folder: String = "/dl") -> FileFacts {
        let ext = NameNormalizer.split(name).ext.lowercased()
        let lastExt = (name as NSString).pathExtension.lowercased()
        return FileFacts(path: FilePath.join(folder, name), name: name, isDirectory: directory,
                         kind: FileKind.classify(extension: ext.contains(".") ? lastExt : ext, isDirectory: directory,
                                                 isPackage: directory && lastExt == "app"),
                         size: size, modified: modified, added: added,
                         inode: UInt64(abs(name.hashValue) % 1_000_000 + 1), sources: sources,
                         isScreenCapture: screenCapture)
    }
}

/// Archive zip d'un dossier (ditto, comme le Finder).
func zipFolder(_ folder: URL, to zip: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
    try p.run()
    p.waitUntilExit()
}

/// Dossier temporaire reel, supprime a la fin du test.
func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rangecore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir.resolvingSymlinksInPath())
}

@discardableResult
func makeFile(_ dir: URL, _ name: String, _ text: String = "contenu") throws -> URL {
    let url = dir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
}
