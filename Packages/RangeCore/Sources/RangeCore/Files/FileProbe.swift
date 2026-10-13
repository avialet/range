import Foundation

/// Ce que le plan demande au disque : presence d'un nom, contenu identique octet a octet.
public protocol FileProbe: Sendable {
    func exists(_ url: URL) -> Bool
    func identical(_ a: URL, _ b: URL) -> Bool
}

public struct DiskProbe: FileProbe {
    public init() {}

    public func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }

    /// Deux fichiers ordinaires de meme taille et de meme contenu. Jamais vrai pour un dossier.
    public func identical(_ a: URL, _ b: URL) -> Bool {
        var sa = stat(), sb = stat()
        guard lstat(a.path, &sa) == 0, lstat(b.path, &sb) == 0,
              (sa.st_mode & S_IFMT) == S_IFREG, (sb.st_mode & S_IFMT) == S_IFREG,
              sa.st_size == sb.st_size else { return false }
        if sa.st_dev == sb.st_dev, sa.st_ino == sb.st_ino { return true }
        guard let ha = try? FileHandle(forReadingFrom: a), let hb = try? FileHandle(forReadingFrom: b) else { return false }
        defer { try? ha.close(); try? hb.close() }
        let chunk = 1 << 20
        while true {
            let da = (try? ha.read(upToCount: chunk)) ?? nil
            let db = (try? hb.read(upToCount: chunk)) ?? nil
            if da != db { return false }
            if da == nil || da?.isEmpty == true { return true }
        }
    }
}
