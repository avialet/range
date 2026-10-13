import Foundation

public enum Destination {
    /// Dossier final : destination (`~` = `home`) puis sous-dossier date.
    public static func folder(_ destination: String, subfolder: Subfolder, date: Date, home: URL,
                              calendar: Calendar) -> URL {
        var url = resolve(destination, home: home)
        let c = calendar.dateComponents([.year, .month], from: date)
        switch subfolder {
        case .none:
            break
        case .year:
            url.appendPathComponent(String(format: "%04d", c.year ?? 0), isDirectory: true)
        case .month:
            url.appendPathComponent(String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0), isDirectory: true)
        }
        return url
    }

    public static func resolve(_ destination: String, home: URL) -> URL {
        if destination == "~" { return home }
        if destination.hasPrefix("~/") {
            return home.appendingPathComponent(String(destination.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: destination, isDirectory: true)
    }

    /// Chemin relatif au dossier personnel (`~/...`) quand c'est possible.
    public static func abbreviate(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        if path == base { return "~" }
        if path.hasPrefix(base + "/") { return "~/" + path.dropFirst(base.count + 1) }
        return path
    }

    /// Dossiers standard sous leur nom francais du Finder.
    static let finderNames: [String: String] = [
        "Documents": "Documents", "Pictures": "Images", "Movies": "Vid\u{00E9}os", "Music": "Musique",
        "Desktop": "Bureau", "Downloads": "T\u{00E9}l\u{00E9}chargements",
    ]

    /// `~/Pictures/Captures` -> « Images › Captures » (› AAAA ou AAAA-MM avec le sous-dossier).
    public static func display(_ destination: String, subfolder: Subfolder = .none) -> String {
        var parts: [String]
        if destination.hasPrefix("~/") {
            parts = destination.dropFirst(2).split(separator: "/").map(String.init)
            if let first = parts.first, let name = finderNames[first] { parts[0] = name }
        } else if destination == "~" {
            parts = ["Dossier personnel"]
        } else {
            return destination + (subfolder == .none ? "" : " \u{203A} " + subfolderPattern(subfolder))
        }
        if subfolder != .none { parts.append(subfolderPattern(subfolder)) }
        return parts.joined(separator: " \u{203A} ")
    }

    static func subfolderPattern(_ s: Subfolder) -> String {
        switch s {
        case .none: ""
        case .year: "AAAA"
        case .month: "AAAA-MM"
        }
    }
}
