import Foundation

public enum NameNormalizer {
    /// Extensions doubles gardees ensemble.
    static let doubleExtensions: Set<String> = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst"]

    /// Minuscules, sans accents, forme composee.
    public static func fold(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// `archive.tar.gz` -> (`archive`, `tar.gz`) ; un nom cache ou sans point n'a pas d'extension.
    public static func split(_ name: String) -> (base: String, ext: String) {
        let lower = name.lowercased()
        for double in doubleExtensions where lower.hasSuffix("." + double) && lower.count > double.count + 1 {
            return (String(name.dropLast(double.count + 1)), String(name.suffix(double.count)))
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    /// `rapport (1).pdf` -> `rapport.pdf` : copie numerotee par le navigateur. nil sinon.
    public static func duplicateOriginal(of name: String) -> String? {
        let (base, ext) = split(name)
        guard base.hasSuffix(")"), let open = base.range(of: " (", options: .backwards) else { return nil }
        let digits = base[open.upperBound..<base.index(before: base.endIndex)]
        guard !digits.isEmpty, digits.count <= 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let original = String(base[..<open.lowerBound])
        guard !original.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ext.isEmpty ? original : "\(original).\(ext)"
    }

    /// Variante a la Finder : `rapport 2.pdf`.
    public static func variant(_ name: String, number: Int) -> String {
        let (base, ext) = split(name)
        return ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
    }
}
