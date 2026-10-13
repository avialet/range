import Foundation

/// Pourquoi un element n'est pas meme examine.
public enum SkipReason: String, Sendable, Equatable {
    /// Telechargement en cours (`.download` Safari, `.crdownload` Chrome, `.part` Firefox...).
    case partialDownload
    /// Nom final cree d'avance par le navigateur pendant que `X.part` se remplit.
    case partialTwin
    /// Fichier vide arrive il y a moins de 10 min (en train de naitre).
    case emptyRecent
    /// Verrou d'Office (`~$Budget.xlsx`).
    case officeLock
    /// Fichier cache, `.localized`, `Icon\r`.
    case hidden
}

public enum PartialDetector {
    public static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp"]
    /// Un fichier vide plus jeune que ce delai est peut-etre en train d'etre ecrit.
    public static let emptyDelay: TimeInterval = 600

    public static func skipReason(name: String, isDirectory: Bool, size: Int64, added: Date,
                                  siblings: Set<String>, now: Date) -> SkipReason? {
        if name.hasPrefix(".") || name == "Icon\r" { return .hidden }
        if name.hasPrefix("~$") { return .officeLock }
        let ext = (name as NSString).pathExtension.lowercased()
        if partialExtensions.contains(ext) { return .partialDownload }
        for partial in partialExtensions where siblings.contains("\(name).\(partial)") { return .partialTwin }
        if !isDirectory, size == 0, now.timeIntervalSince(added) < emptyDelay { return .emptyRecent }
        return nil
    }
}
