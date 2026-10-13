import Foundation

/// Images disque montees : ne jamais jeter un `.dmg` en service.
public enum MountedImages {
    /// Chemins `image-path` de `hdiutil info -plist`.
    public static func parse(_ data: Data) -> Set<String> {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return [] }
        return Set(images.compactMap { $0["image-path"] as? String })
    }

    /// Inodes des images montees (compares par inode : le chemin d'hdiutil peut differer en forme).
    public static func inodes(of paths: Set<String>) -> Set<UInt64> {
        Set(paths.compactMap { path in
            var st = stat()
            return path.withCString { stat($0, &st) } == 0 ? UInt64(st.st_ino) : nil
        })
    }

    /// Lance `hdiutil info -plist` (quelques dizaines de ms). Echec : ensemble vide, et l'appelant
    /// reste prudent (voir `RangeEngine`).
    public static func current() -> Set<String>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }
}
