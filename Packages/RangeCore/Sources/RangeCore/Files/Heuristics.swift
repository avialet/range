import Foundation

/// Captures d'ecran de macOS : " Capture d'ecran 2026-10-14 a 09.41.12 ", " Screenshot 2026-... at ... ".
public enum ScreenshotName {
    public static func matches(_ name: String) -> Bool {
        let folded = NameNormalizer.fold(name).replacingOccurrences(of: "\u{2019}", with: "'")
        let prefixes = ["capture d'ecran ", "screenshot ", "screen shot "]
        guard let prefix = prefixes.first(where: { folded.hasPrefix($0) }) else { return false }
        let rest = folded.dropFirst(prefix.count)
        // Date AAAA-MM-JJ juste apres le prefixe.
        let date = rest.prefix(10)
        guard date.count == 10 else { return false }
        for (i, c) in date.enumerated() {
            if i == 4 || i == 7 { guard c == "-" else { return false } } else { guard c.isASCII, c.isNumber else { return false } }
        }
        return true
    }
}

/// Factures : un PDF dont le nom ou l'adresse d'origine en parle. Liste ecrite de zero, sans accents
/// (les noms sont replies avant comparaison).
public enum InvoiceHeuristic {
    /// Mots du nom, compares mot a mot (pluriel en s accepte).
    public static let nameWords: Set<String> = [
        "facture", "invoice", "receipt", "recu", "quittance", "billing", "stripe", "paddle", "factura", "rechnung",
    ]
    /// Mots faibles : seulement avec un numero dans le nom (" Avoir 12 ", pas " A avoir lu ").
    public static let numberedWords: Set<String> = ["avoir", "bill"]
    /// Fragments de l'adresse d'origine.
    public static let sourceFragments: [String] = [
        "stripe.com", "paddle.com", "paddle.net", "invoice", "facture", "factur", "billing", "receipt",
    ]

    public static func matches(name: String, sources: [String]) -> Bool {
        let tokens = Self.tokens(NameNormalizer.split(name).base)
        let hasNumber = tokens.contains { $0.allSatisfy(\.isNumber) }
        for token in tokens {
            let singular = token.hasSuffix("s") ? String(token.dropLast()) : token
            if nameWords.contains(token) || nameWords.contains(singular) { return true }
            if hasNumber, numberedWords.contains(token) || numberedWords.contains(singular) {
                // " Bill of materials " n'a pas de numero ; " bill 2026-03 " oui.
                return true
            }
        }
        for source in sources {
            let folded = NameNormalizer.fold(source)
            if sourceFragments.contains(where: { folded.contains($0) }) { return true }
        }
        return false
    }

    /// Mots replies, coupes aussi entre lettres et chiffres (" facture2026 " -> facture, 2026).
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsDigit = false
        for c in NameNormalizer.fold(text) {
            guard c.isLetter || c.isNumber else {
                if !current.isEmpty { tokens.append(current); current = "" }
                continue
            }
            let digit = c.isNumber
            if !current.isEmpty, digit != currentIsDigit { tokens.append(current); current = "" }
            current.append(c)
            currentIsDigit = digit
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
