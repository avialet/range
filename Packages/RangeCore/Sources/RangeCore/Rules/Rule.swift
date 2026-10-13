import Foundation

/// Sous-dossier date sous la destination, d'apres la date d'arrivee du fichier.
public enum Subfolder: String, Codable, Sendable, CaseIterable {
    case none, year, month

    public var label: String {
        switch self {
        case .none: "Aucun"
        case .year: "Par ann\u{00E9}e"
        case .month: "Par mois"
        }
    }
}

public enum RuleAction: Codable, Equatable, Sendable {
    /// Destination absolue ou relative au dossier personnel (`~/Documents/Factures`).
    case move(destination: String, subfolder: Subfolder)
    case trash
}

/// Conditions qu'une simple extension ne dit pas.
public enum RuleSpecial: String, Codable, Sendable {
    /// `nom (1).ext` identique octet a octet a `nom.ext` a cote.
    case browserDuplicate
    /// `X.zip` avec le dossier `X` a cote.
    case openedArchive
    case invoice
    case screenshot
}

/// Conditions d'une regle : toutes celles donnees doivent etre vraies ; dans une liste, une seule suffit.
public struct RuleCondition: Codable, Equatable, Sendable {
    public var kinds: [FileKind]?
    public var extensions: [String]?
    public var nameContains: [String]?
    public var sourceContains: [String]?
    public var special: RuleSpecial?

    public init(kinds: [FileKind]? = nil, extensions: [String]? = nil, nameContains: [String]? = nil,
                sourceContains: [String]? = nil, special: RuleSpecial? = nil) {
        self.kinds = kinds
        self.extensions = extensions
        self.nameContains = nameContains
        self.sourceContains = sourceContains
        self.special = special
    }
}

public struct Rule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Phrase courte sous le titre (« Images disque et paquets de plus de 7 jours »).
    public var summary: String
    public var enabled: Bool
    public var condition: RuleCondition
    /// Age minimal depuis l'arrivee, en jours (0 : le delai de grace seul).
    public var olderThanDays: Double
    public var action: RuleAction

    public init(id: String, title: String, summary: String, enabled: Bool = true, condition: RuleCondition,
                olderThanDays: Double = 0, action: RuleAction) {
        self.id = id
        self.title = title
        self.summary = summary
        self.enabled = enabled
        self.condition = condition
        self.olderThanDays = olderThanDays
        self.action = action
    }

    public var isTrash: Bool { action == .trash }
}

/// Voisinage d'un fichier dans le dossier surveille, pour les conditions speciales.
public struct RuleNeighbourhood: Sendable {
    public var names: Set<String>
    public var directories: Set<String>
    public var folder: String
    public var probe: any FileProbe

    public init(names: Set<String>, directories: Set<String>, folder: String, probe: any FileProbe) {
        self.names = names
        self.directories = directories
        self.folder = folder
        self.probe = probe
    }
}

extension Rule {
    /// La regle s'applique-t-elle (age mis a part) ?
    public func matches(_ f: FileFacts, in hood: RuleNeighbourhood) -> Bool {
        let c = condition
        if let kinds = c.kinds, !kinds.contains(f.kind) { return false }
        if let exts = c.extensions {
            let ext = (f.name as NSString).pathExtension.lowercased()
            let full = NameNormalizer.split(f.name).ext.lowercased()
            guard exts.contains(where: { $0.lowercased() == ext || $0.lowercased() == full }) else { return false }
        }
        if let words = c.nameContains {
            let name = NameNormalizer.fold(f.name)
            guard words.contains(where: { name.contains(NameNormalizer.fold($0)) }) else { return false }
        }
        if let words = c.sourceContains {
            let sources = f.sources.map(NameNormalizer.fold)
            guard words.contains(where: { w in sources.contains { $0.contains(NameNormalizer.fold(w)) } }) else { return false }
        }
        switch c.special {
        case nil:
            return true
        case .browserDuplicate?:
            guard !f.isDirectory, let original = NameNormalizer.duplicateOriginal(of: f.name),
                  hood.names.contains(original) else { return false }
            return hood.probe.identical(f.path, FilePath.join(hood.folder, original))
        case .openedArchive?:
            guard f.kind == .archive, !f.isDirectory else { return false }
            return hood.directories.contains(NameNormalizer.split(f.name).base)
        case .invoice?:
            return InvoiceHeuristic.matches(name: f.name, sources: f.sources)
        case .screenshot?:
            return f.isScreenCapture || (f.kind == .image && ScreenshotName.matches(f.name))
        }
    }
}
