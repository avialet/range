import Darwin
import Foundation

/// Chemins en chaines, octets gardes tels quels. `URL(fileURLWithPath:)` et `appendingPathComponent`
/// decomposent les accents (" e " devient " e " + accent) : un fichier remis en place doit retrouver
/// exactement son nom, donc tout ce qui cree un nom sur le disque passe par ici.
public enum FilePath {
    public static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    public static func name(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    public static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }
}

public enum FileOps {
    public static func exists(_ path: String) -> Bool {
        var st = stat()
        return path.withCString { lstat($0, &st) } == 0
    }

    public static func isDirectory(_ path: String) -> Bool {
        var st = stat()
        return path.withCString { stat($0, &st) } == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// Renommage atomique qui refuse d'ecraser (`RENAME_EXCL`) ; `EXDEV` si autre volume.
    public static func renameExclusive(_ from: String, _ to: String) throws {
        let status = from.withCString { a in to.withCString { b in renamex_np(a, b, UInt32(RENAME_EXCL)) } }
        if status != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    public static func makeDirectory(_ path: String) throws {
        if path.withCString({ mkdir($0, 0o755) }) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    public static func device(_ path: String) -> dev_t? {
        var st = stat()
        return path.withCString { stat($0, &st) } == 0 ? st.st_dev : nil
    }
}
