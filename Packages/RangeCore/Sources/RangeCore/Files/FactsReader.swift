import Darwin
import Foundation

/// Lecture du dossier surveille impossible.
public enum FolderAccessError: Error, Equatable, Sendable {
    /// Autorisation refusee (TCC : Telechargements, Documents) ou droits Unix.
    case denied
    case missing
    case other(String)

    static func from(_ error: Error) -> FolderAccessError {
        let ns = error as NSError
        let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
            ?? (ns.domain == NSPOSIXErrorDomain ? ns.code : nil)
        if posix == Int(EPERM) || posix == Int(EACCES) { return .denied }
        if posix == Int(ENOENT) { return .missing }
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .denied
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .missing
            default: break
            }
        }
        return .other(ns.localizedDescription)
    }
}

/// Lit le premier niveau d'un dossier en `FileFacts` (attributs, attributs etendus).
public struct FactsReader: Sendable {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey,
        .creationDateKey, .nameKey,
    ]

    public init() {}

    public func read(folder: URL) throws -> [FileFacts] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Self.keys, options: [])
        } catch {
            throw FolderAccessError.from(error)
        }
        // Chemins batis sur `folder` tel que donne (contentsOfDirectory peut ajouter /private).
        return urls.compactMap { facts(of: folder.appendingPathComponent($0.lastPathComponent)) }
    }

    /// Faits d'un element, nil s'il a disparu entre-temps.
    public func facts(of url: URL) -> FileFacts? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        let values = try? url.resourceValues(forKeys: Set(Self.keys))
        let isDirectory = (st.st_mode & S_IFMT) == S_IFDIR
        let isPackage = values?.isPackage ?? false
        let name = values?.name ?? url.lastPathComponent
        let modified = values?.contentModificationDate
            ?? Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        let added = values?.addedToDirectoryDate ?? values?.creationDate ?? modified
        let ext = NameNormalizer.split(name).ext
        let lastExt = (name as NSString).pathExtension
        let kind = FileKind.classify(extension: ext.contains(".") ? lastExt : ext, isDirectory: isDirectory, isPackage: isPackage)
        let quarantine = Self.xattrString(url.path, "com.apple.quarantine")
        let agent = quarantine.flatMap { q -> String? in
            let parts = q.split(separator: ";", omittingEmptySubsequences: false)
            return parts.count > 2 && !parts[2].isEmpty ? String(parts[2]) : nil
        }
        return FileFacts(url: url, name: name, isDirectory: isDirectory, kind: kind,
                         size: isDirectory ? 0 : Int64(st.st_size), modified: modified, added: added,
                         inode: UInt64(st.st_ino),
                         sources: Self.xattrPlist(url.path, "com.apple.metadata:kMDItemWhereFroms") as? [String] ?? [],
                         agent: agent,
                         isScreenCapture: Self.xattrPlist(url.path, "com.apple.metadata:kMDItemIsScreenCapture") as? Bool ?? false)
    }

    static func xattrData(_ path: String, _ name: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0, size < 1_000_000 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return read == size ? data : nil
    }

    static func xattrString(_ path: String, _ name: String) -> String? {
        xattrData(path, name).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func xattrPlist(_ path: String, _ name: String) -> Any? {
        xattrData(path, name).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
    }
}
