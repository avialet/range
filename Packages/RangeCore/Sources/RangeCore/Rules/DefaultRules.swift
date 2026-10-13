import Foundation

/// Regles pretes a l'ouverture. Ordre = priorite : la premiere qui correspond gagne.
public enum DefaultRules {
    public static let all: [Rule] = [
        Rule(id: "installers", title: "Installeurs",
             summary: "Images disque et paquets (.dmg, .pkg), non mont\u{00E9}s",
             condition: RuleCondition(extensions: ["dmg", "pkg", "mpkg"]), olderThanDays: 7, action: .trash),
        Rule(id: "duplicates", title: "Doublons du navigateur",
             summary: "\u{00AB}\u{00A0}nom (1)\u{00A0}\u{00BB} identique octet \u{00E0} octet \u{00E0} l\u{2019}original",
             condition: RuleCondition(special: .browserDuplicate), action: .trash),
        Rule(id: "opened-archives", title: "Archives d\u{00E9}j\u{00E0} ouvertes",
             summary: "Archive (.zip, .7z, .rar, .tar.gz) dont le dossier d\u{00E9}compress\u{00E9} est \u{00E0} c\u{00F4}t\u{00E9}",
             condition: RuleCondition(special: .openedArchive), olderThanDays: 3, action: .trash),
        Rule(id: "invoices", title: "Factures",
             summary: "PDF dont le nom ou l\u{2019}origine parle de facture, re\u{00E7}u, invoice\u{2026}",
             condition: RuleCondition(kinds: [.pdf], special: .invoice),
             action: .move(destination: "~/Documents/Factures", subfolder: .year)),
        Rule(id: "screenshots", title: "Captures d\u{2019}\u{00E9}cran",
             summary: "Images nomm\u{00E9}es \u{00AB}\u{00A0}Capture d\u{2019}\u{00E9}cran\u{2026}\u{00A0}\u{00BB}",
             condition: RuleCondition(special: .screenshot),
             action: .move(destination: "~/Pictures/Captures", subfolder: .month)),
        Rule(id: "images", title: "Images", summary: "Photos, illustrations, ic\u{00F4}nes",
             condition: RuleCondition(kinds: [.image]),
             action: .move(destination: "~/Pictures/T\u{00E9}l\u{00E9}charg\u{00E9}es", subfolder: .month)),
        Rule(id: "movies", title: "Vid\u{00E9}os", summary: "Films et enregistrements",
             condition: RuleCondition(kinds: [.movie]),
             action: .move(destination: "~/Movies/T\u{00E9}l\u{00E9}charg\u{00E9}es", subfolder: .none)),
        Rule(id: "rest", title: "Le reste",
             summary: "Documents, archives, dossiers\u{2026} oubli\u{00E9}s",
             enabled: false, condition: RuleCondition(), olderThanDays: 30,
             action: .move(destination: "~/Documents/T\u{00E9}l\u{00E9}charg\u{00E9}s", subfolder: .month)),
    ]

    /// Regles enregistrees, completees par les regles par defaut apparues depuis (a leur place).
    /// Les reglages de l'utilisateur (interrupteur, age, destination) sont gardes ; les textes et
    /// conditions viennent toujours du code.
    public static func merge(saved: [Rule]) -> [Rule] {
        let byId = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return all.map { rule in
            guard let mine = byId[rule.id] else { return rule }
            var merged = rule
            merged.enabled = mine.enabled
            merged.olderThanDays = mine.olderThanDays
            merged.action = mine.action
            return merged
        }
    }
}
