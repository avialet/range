import Foundation

public struct EngineSettings: Sendable, Equatable {
    /// Dossier surveille (Telechargements).
    public var folder: String
    /// Dossier personnel pour les destinations `~/...`.
    public var home: String
    /// Delai de grace depuis l'arrivee, en secondes.
    public var grace: TimeInterval

    public init(folder: String, home: String, grace: TimeInterval) {
        self.folder = folder
        self.home = home
        self.grace = grace
    }
}

/// Le moteur : lit le dossier, suit la stabilite, planifie, applique et defait. Un acteur : toutes les
/// lectures et ecritures de fichiers passent par lui, une a la fois, hors du fil principal.
public actor RangeEngine {
    public private(set) var plan: Plan = .empty
    public private(set) var rules: [Rule]
    public private(set) var settings: EngineSettings

    let journal: Journal
    let trasher: any Trasher
    let mounted: @Sendable () -> Set<String>?
    let reader = FactsReader()
    private var tracker = StabilityTracker()
    private let cancelFlag = Flag()
    /// Dates d'arrivee imposees par nom (essais sur un clone, captures) : un clone arrive « maintenant ».
    private var addedOverrides: [String: Date] = [:]

    public init(journal: Journal, trasher: any Trasher, settings: EngineSettings,
                mounted: @escaping @Sendable () -> Set<String>? = { MountedImages.current() }) {
        self.journal = journal
        self.trasher = trasher
        self.settings = settings
        self.mounted = mounted
        self.rules = DefaultRules.merge(saved: (try? journal.loadRules()) ?? [])
    }

    public func update(settings: EngineSettings) {
        if settings.folder != self.settings.folder { tracker = StabilityTracker() }
        self.settings = settings
    }

    public func setAddedOverrides(_ overrides: [String: Date]) {
        addedOverrides = overrides
    }

    public func setRules(_ rules: [Rule]) throws {
        self.rules = rules
        try journal.saveRules(rules)
    }

    /// Une passe : lecture du premier niveau, stabilite, plan. Rien n'est deplace.
    @discardableResult
    public func scan(now: Date) throws -> Plan {
        var facts = try reader.read(path: settings.folder)
        if !addedOverrides.isEmpty {
            for i in facts.indices { if let date = addedOverrides[facts[i].name] { facts[i].added = date } }
        }
        tracker.observe(facts, now: now)
        try? journal.pruneHeld(present: Set(facts.map(\.inode)))
        let stable = Set(facts.filter { tracker.isStable($0, now: now) }.map(\.path))
        let images: Set<UInt64>? = facts.contains { $0.kind == .diskImage } ? mounted().map(MountedImages.inodes) : []
        let context = PlanContext(now: now, grace: settings.grace, folder: settings.folder, home: settings.home,
                                  stablePaths: stable, mountedImages: images,
                                  held: (try? journal.heldInodes()) ?? [])
        plan = Planner.plan(facts, rules: rules, context: context, probe: DiskProbe())
        return plan
    }

    /// Applique les actions pretes du dernier plan, sauf les chemins decoches.
    public func apply(excluding: Set<String> = [], trigger: BatchTrigger, now: Date) -> ApplyResult {
        cancelFlag.set(false)
        let flag = cancelFlag
        let actions = plan.ready.filter { !excluding.contains($0.id) }
        let result = Executor(journal: journal, trasher: trasher, reader: reader)
            .apply(actions, trigger: trigger, now: now, shouldContinue: { !flag.value })
        let done = Set(result.moves.map(\.source))
        plan.actions.removeAll { done.contains($0.id) }
        return result
    }

    /// Arrete une application en cours apres le fichier courant.
    public nonisolated func cancel() {
        cancelFlag.set(true)
    }

    public func undoBatch(_ id: Int64, now: Date) -> UndoResult {
        Undoer(journal: journal).undoBatch(id, now: now)
    }

    /// Defait le dernier lot encore defaisable ; nil s'il n'y en a pas.
    public func undoLast(now: Date) -> UndoResult? {
        guard let last = try? journal.lastUndoableBatch(), let id = last.batch.id else { return nil }
        return undoBatch(id, now: now)
    }

    public func undo(moveId: Int64, now: Date) throws -> String {
        guard let move = try journal.database.read({ db in try MoveRecord.fetchOne(db, key: moveId) }) else {
            throw UndoError.gone
        }
        return try Undoer(journal: journal).undo(move, now: now)
    }

    /// Le fichier garde en place apres une annulation peut de nouveau etre range.
    public func release(inode: UInt64) throws {
        try journal.release(inode: inode)
    }
}

/// Drapeau partage entre fils.
final class Flag: @unchecked Sendable {
    private var stored = false
    private let lock = NSLock()
    var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ v: Bool) { lock.lock(); stored = v; lock.unlock() }
}
