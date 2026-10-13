import Foundation

public enum Destination {
    /// Dossier final : destination (`~` = `home`) puis sous-dossier date. Chemin en chaine (voir `FilePath`).
    public static func folder(_ destination: String, subfolder: Subfolder, date: Date, home: String,
                              calendar: Calendar) -> String {
        let base = resolve(destination, home: home)
        let c = calendar.dateComponents([.year, .month], from: date)
        switch subfolder {
        case .none: return base
        case .year: return FilePath.join(base, String(format: "%04d", c.year ?? 0))
        case .month: return FilePath.join(base, String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0))
        }
    }

    public static func resolve(_ destination: String, home: String) -> String {
        let path: String
        if destination == "~" {
            path = home
        } else if destination.hasPrefix("~/") {
            path = FilePath.join(home, String(destination.dropFirst(2)))
        } else {
            path = destination
        }
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Chemin relatif au dossier personnel (`~/...`) quand c'est possible.
    public static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return path
    }

    /// Dossiers standard sous leur nom francais du Finder.
    static let finderNames: [String: String] = [
        "Documents": "Documents", "Pictures": "Images", "Movies": "Vid\u{00E9}os", "Music": "Musique",
        "Desktop": "Bureau", "Downloads": "T\u{00E9}l\u{00E9}chargements",
    ]

    /// `~/Pictures/Captures` -> « Images › Captures » (« , par mois » avec le sous-dossier).
    public static func display(_ destination: String, subfolder: Subfolder = .none) -> String {
        var parts: [String]
        if destination.hasPrefix("~/") {
            parts = destination.dropFirst(2).split(separator: "/").map(String.init)
            if let first = parts.first, let name = finderNames[first] { parts[0] = name }
        } else if destination == "~" {
            parts = ["Dossier personnel"]
        } else {
            parts = [destination]
        }
        return parts.joined(separator: " \u{203A} ") + subfolderSuffix(subfolder)
    }

    static func subfolderSuffix(_ s: Subfolder) -> String {
        switch s {
        case .none: ""
        case .year: ", par ann\u{00E9}e"
        case .month: ", par mois"
        }
    }
}
