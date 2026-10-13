import Darwin
import Foundation

/// Ce que le plan demande au disque : presence d'un nom, contenu identique octet a octet, dossier
/// vide, contenu d'une archive retrouve dans un dossier.
public protocol FileProbe: Sendable {
    func exists(_ path: String) -> Bool
    func identical(_ a: String, _ b: String) -> Bool
    /// Vide, ou seulement un `.DS_Store` du Finder.
    func isEmptyDirectory(_ path: String) -> Bool
    /// Les entrees de l'archive sont-elles dans le dossier ? nil : impossible a dire (format non lu,
    /// archive illisible).
    func archiveMatches(_ archive: String, folder: String) -> Bool?
}

public struct DiskProbe: FileProbe {
    public init() {}

    public func exists(_ path: String) -> Bool { FileOps.exists(path) }

    /// Deux fichiers ordinaires de meme taille et de meme contenu. Jamais vrai pour un dossier, ni si
    /// une lecture echoue.
    public func identical(_ a: String, _ b: String) -> Bool {
        var sa = stat(), sb = stat()
        guard a.withCString({ lstat($0, &sa) }) == 0, b.withCString({ lstat($0, &sb) }) == 0,
              (sa.st_mode & S_IFMT) == S_IFREG, (sb.st_mode & S_IFMT) == S_IFREG,
              sa.st_size == sb.st_size else { return false }
        if sa.st_dev == sb.st_dev, sa.st_ino == sb.st_ino { return true }
        guard let ha = FileHandle(forReadingAtPath: a), let hb = FileHandle(forReadingAtPath: b) else { return false }
        defer { try? ha.close(); try? hb.close() }
        let chunk = 1 << 20
        var total: Int64 = 0
        do {
            while true {
                let da = try ha.read(upToCount: chunk) ?? Data()
                let db = try hb.read(upToCount: chunk) ?? Data()
                if da != db { return false }
                if da.isEmpty { return total == Int64(sa.st_size) }
                total += Int64(da.count)
            }
        } catch {
            return false
        }
    }

    public func isEmptyDirectory(_ path: String) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return true }
        return items.allSatisfy { $0 == ".DS_Store" }
    }

    /// Zip seulement (`unzip -Z1`) : au moins la moitie d'un echantillon de fichiers de l'archive (et au
    /// moins un) existe dans le dossier, chemin pris tel quel ou sans le dossier racine de l'archive.
    public func archiveMatches(_ archive: String, folder: String) -> Bool? {
        guard archive.lowercased().hasSuffix(".zip"), let entries = Self.zipEntries(archive) else { return nil }
        let base = NameNormalizer.split(FilePath.name(archive)).base
        // Ni dossiers, ni metadonnees du Finder (`__MACOSX/`, `._nom` AppleDouble, `.DS_Store`).
        let files = entries.filter { entry in
            let name = FilePath.name(entry)
            return !entry.hasSuffix("/") && !entry.hasPrefix("__MACOSX/") && name != ".DS_Store" && !name.hasPrefix("._")
        }
        let sample = Array(files.prefix(40))
        guard !sample.isEmpty else { return nil }
        let found = sample.filter { entry in
            if FileOps.exists(FilePath.join(folder, entry)) { return true }
            let prefix = base + "/"
            return entry.hasPrefix(prefix) && FileOps.exists(FilePath.join(folder, String(entry.dropFirst(prefix.count))))
        }.count
        return found >= max(1, (sample.count + 1) / 2)
    }

    /// Noms des entrees d'un zip ; nil si `unzip` echoue ou depasse 5 s (l'archive est alors tenue pour
    /// non ouverte). Sortie bornee a 4 Mo.
    static func zipEntries(_ path: String) -> [String]? {
        listEntries(path, executable: "/usr/bin/unzip", timeout: 5)
    }

    #if DEBUG
    /// Tests : executable et delai injectables.
    public static func zipEntries(_ path: String, executable: String, timeout: TimeInterval) -> [String]? {
        listEntries(path, executable: executable, timeout: timeout)
    }
    #endif

    /// `<executable> -Z1 <path>`, entree standard fermee, sortie lue sur un autre fil ; a l'echeance,
    /// SIGTERM puis SIGKILL, et nil.
    static func listEntries(_ path: String, executable: String, timeout: TimeInterval) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-Z1", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let output = OutputBox()
        let finished = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            output.data = handle.readData(ofLength: 4 << 20)
            finished.signal()
        }
        let deadline = DispatchTime.now() + timeout
        var timedOut = finished.wait(timeout: deadline) == .timedOut
        // Sortie fermee : le processus finit ; il a jusqu'a l'echeance pour le faire.
        while !timedOut, process.isRunning {
            if DispatchTime.now() >= deadline { timedOut = true } else { usleep(5_000) }
        }
        if timedOut {
            process.terminate()
            let pid = process.processIdentifier
            if finished.wait(timeout: .now() + 1) == .timedOut || process.isRunning {
                kill(pid, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        process.waitUntilExit()
        guard !timedOut, process.terminationReason == .exit, process.terminationStatus == 0,
              let data = output.data, let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

/// Sortie lue sur un autre fil (ecrite avant le signal, lue apres l'attente).
private final class OutputBox: @unchecked Sendable {
    var data: Data?
}

/// Sonde qui garde ses reponses tant que les fichiers ne changent pas (inode, taille, date) :
/// une passe toutes les quelques secondes ne relit pas les doublons ni les archives.
public final class CachingProbe: FileProbe, @unchecked Sendable {
    private let base: any FileProbe
    private let lock = NSLock()
    private var identicalCache: [String: Bool] = [:]
    private var archiveCache: [String: Bool?] = [:]

    public init(base: any FileProbe = DiskProbe()) {
        self.base = base
    }

    public func exists(_ path: String) -> Bool { base.exists(path) }
    public func isEmptyDirectory(_ path: String) -> Bool { base.isEmptyDirectory(path) }

    public func identical(_ a: String, _ b: String) -> Bool {
        guard let ka = Self.signature(a), let kb = Self.signature(b) else { return base.identical(a, b) }
        let key = a < b ? ka + "|" + kb : kb + "|" + ka
        if let hit = lock.withLock({ identicalCache[key] }) { return hit }
        let value = base.identical(a, b)
        lock.withLock {
            if identicalCache.count > 5000 { identicalCache.removeAll() }
            identicalCache[key] = value
        }
        return value
    }

    public func archiveMatches(_ archive: String, folder: String) -> Bool? {
        guard let ka = Self.signature(archive), let kf = Self.signature(folder) else { return base.archiveMatches(archive, folder: folder) }
        let key = ka + "|" + kf
        if let hit = lock.withLock({ archiveCache[key] }) { return hit }
        let value = base.archiveMatches(archive, folder: folder)
        lock.withLock {
            if archiveCache.count > 5000 { archiveCache.removeAll() }
            archiveCache[key] = value
        }
        return value
    }

    /// Chemin, inode, taille et date de modification (nanosecondes).
    static func signature(_ path: String) -> String? {
        var st = stat()
        guard path.withCString({ lstat($0, &st) }) == 0 else { return nil }
        return "\(path)#\(st.st_ino)#\(st.st_size)#\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec)"
    }
}
