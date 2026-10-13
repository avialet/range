import Foundation

public enum TrashReason: String, Codable, Sendable {
    /// La regle dit corbeille.
    case rule
    /// Le meme fichier, octet pour octet, est deja a destination.
    case alreadyAtDestination
}

public enum PlannedOperation: Equatable, Sendable {
    /// Chemin exact de destination (voir `FilePath`).
    case move(to: String)
    case trash(TrashReason)
}

/// Pourquoi une action attend.
public enum PlanWait: Equatable, Sendable {
    /// Delai de grace depuis l'arrivee (le lien " Ouvrir " du navigateur marche encore).
    case grace(until: Date)
    /// Age minimal de la regle (installeurs : 7 jours).
    case age(until: Date)
    /// Taille ou date encore en mouvement, ou fichier vu une seule fois.
    case stability
    /// Image disque montee.
    case mounted
    /// Rangement annule a la main : le fichier reste ou il est.
    case held
}

public enum PlanStatus: Equatable, Sendable {
    case ready
    case waiting(PlanWait)
}

public struct PlannedAction: Equatable, Sendable, Identifiable {
    public var facts: FileFacts
    public var ruleId: String
    public var operation: PlannedOperation
    public var status: PlanStatus

    public var id: String { facts.path }
    public var isReady: Bool { status == .ready }
}

public struct Plan: Sendable, Equatable {
    /// Pretes d'abord (ordre des regles, puis nom), puis en attente.
    public var actions: [PlannedAction]
    /// Partiels, caches, verrous.
    public var skipped: Int
    /// Aucune regle ne s'applique.
    public var untouched: Int
    /// Prochain moment ou une attente prend fin.
    public var nextWake: Date?

    public static let empty = Plan(actions: [], skipped: 0, untouched: 0, nextWake: nil)

    public var ready: [PlannedAction] { actions.filter(\.isReady) }
}

public struct PlanContext: Sendable {
    public var now: Date
    /// Delai de grace depuis l'arrivee, en secondes.
    public var grace: TimeInterval
    /// Dossier surveille.
    public var folder: String
    /// Dossier personnel pour les destinations `~/...`.
    public var home: String
    /// Chemins declares stables par le `StabilityTracker`.
    public var stablePaths: Set<String>
    /// Inodes des images montees ; nil si inconnu (toute image disque attend alors).
    public var mountedImages: Set<UInt64>?
    /// Inodes gardes en place apres une annulation.
    public var held: Set<UInt64>
    public var calendar: Calendar

    public init(now: Date, grace: TimeInterval, folder: String, home: String, stablePaths: Set<String>,
                mountedImages: Set<UInt64>?, held: Set<UInt64>, calendar: Calendar = .current) {
        self.now = now
        self.grace = grace
        self.folder = folder
        self.home = home
        self.stablePaths = stablePaths
        self.mountedImages = mountedImages
        self.held = held
        self.calendar = calendar
    }
}

/// `(faits, regles, maintenant) -> actions` : aucune ecriture, le disque n'est lu qu'a travers la sonde
/// (noms deja pris a destination, doublons identiques).
public enum Planner {
    public static func plan(_ facts: [FileFacts], rules: [Rule], context: PlanContext, probe: any FileProbe) -> Plan {
        let names = Set(facts.map(\.name))
        let hood = RuleNeighbourhood(names: names,
                                     directories: Dictionary(facts.filter(\.isDirectory).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a }),
                                     folder: context.folder, probe: probe)
        let watched = context.folder
        let order = Dictionary(rules.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        var actions: [PlannedAction] = []
        var skipped = 0, untouched = 0
        var reserved: Set<String> = []
        var wake: Date?

        for f in facts.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            if PartialDetector.skipReason(name: f.name, isDirectory: f.isDirectory, size: f.size, added: f.added,
                                          siblings: names, now: context.now) != nil {
                skipped += 1
                continue
            }
            guard let rule = rules.first(where: { $0.enabled && $0.matches(f, in: hood) }) else {
                untouched += 1
                continue
            }
            let operation: PlannedOperation
            switch rule.action {
            case .trash:
                operation = .trash(.rule)
            case .move(let destination, let subfolder):
                let folder = Destination.folder(destination, subfolder: subfolder, date: f.added, home: context.home,
                                                calendar: context.calendar)
                if folder == watched || watched.hasPrefix(folder + "/") {
                    // Ranger dans le dossier surveille lui-meme (ou plus haut) : rien a faire.
                    untouched += 1
                    continue
                }
                operation = resolve(f, in: folder, probe: probe, reserved: &reserved)
            }
            let status = status(of: f, rule: rule, context: context)
            if case .waiting(let w) = status, let until = wakeDate(w, now: context.now) {
                wake = min(wake ?? until, until)
            }
            actions.append(PlannedAction(facts: f, ruleId: rule.id, operation: operation, status: status))
        }
        actions.sort { a, b in
            if a.isReady != b.isReady { return a.isReady }
            let ra = order[a.ruleId] ?? 0, rb = order[b.ruleId] ?? 0
            if ra != rb { return ra < rb }
            return a.facts.name.localizedStandardCompare(b.facts.name) == .orderedAscending
        }
        return Plan(actions: actions, skipped: skipped, untouched: untouched, nextWake: wake)
    }

    static func status(of f: FileFacts, rule: Rule, context: PlanContext) -> PlanStatus {
        if context.held.contains(f.inode) { return .waiting(.held) }
        if f.kind == .diskImage {
            guard let mounted = context.mountedImages, !mounted.contains(f.inode) else { return .waiting(.mounted) }
        }
        if !context.stablePaths.contains(f.path) { return .waiting(.stability) }
        let graceEnd = f.added.addingTimeInterval(context.grace)
        let ageEnd = f.added.addingTimeInterval(rule.olderThanDays * 86400)
        if ageEnd > graceEnd, context.now < ageEnd { return .waiting(.age(until: ageEnd)) }
        if context.now < graceEnd { return .waiting(.grace(until: graceEnd)) }
        return .ready
    }

    static func wakeDate(_ wait: PlanWait, now: Date) -> Date? {
        switch wait {
        case .grace(let until), .age(let until): until
        case .stability: now.addingTimeInterval(StabilityTracker.window + 1)
        case .mounted, .held: nil
        }
    }

    /// Nom libre a destination : le meme, sinon " nom 2.ext ", " nom 3.ext "... ; si le meme contenu
    /// y est deja, la copie arrivee va a la corbeille.
    static func resolve(_ f: FileFacts, in folder: String, probe: any FileProbe, reserved: inout Set<String>) -> PlannedOperation {
        let first = FilePath.join(folder, f.name)
        if !reserved.contains(first), !probe.exists(first) {
            reserved.insert(first)
            return .move(to: first)
        }
        if !reserved.contains(first), probe.identical(f.path, first) { return .trash(.alreadyAtDestination) }
        var n = 2
        while true {
            let candidate = FilePath.join(folder, NameNormalizer.variant(f.name, number: n))
            if !reserved.contains(candidate), !probe.exists(candidate) {
                reserved.insert(candidate)
                return .move(to: candidate)
            }
            n += 1
        }
    }
}
