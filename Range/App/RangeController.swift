import AppKit
import Observation
import RangeCore
import VialetKit

enum MainSection: String, CaseIterable, Hashable {
    case pending, rules, journal

    var label: String {
        switch self {
        case .pending: "\u{00C0} ranger"
        case .rules: "R\u{00E8}gles"
        case .journal: "Journal"
        }
    }

    var icon: String {
        switch self {
        case .pending: "tray.full"
        case .rules: "list.bullet.rectangle"
        case .journal: "clock.arrow.circlepath"
        }
    }
}

/// Pourquoi le rangement automatique est arrete sans que l'utilisateur l'ait demande.
enum Blocker: Equatable {
    /// Telechargements illisible (premier lancement, ou autorisation perdue apres une mise a jour).
    case folderDenied(afterUpdate: Bool)
    case folderMissing
    /// Un deplacement vers Documents a ete refuse.
    case documentsDenied
}

/// Message court en bas de la fenetre, avec « Annuler » quand on peut defaire.
struct Toast: Equatable {
    var text: String
    var undoBatch: Int64?
}

/// Orchestration : passes (surveillance, minuteur, reveil), rangement automatique ou apercu,
/// annulation, pause, autorisations. L'IO passe par `RangeEngine`, hors du fil principal.
@MainActor
@Observable
final class RangeController {
    static let shared = RangeController()

    enum Keys {
        static let automatic = Brand.key("Automatic")
        static let paused = Brand.key("Paused")
        static let initialDone = Brand.key("InitialDone")
        static let autoOffered = Brand.key("AutoOffered")
        static let grace = Brand.key("GraceMinutes")
        static let lastVersion = Brand.key("LastRunVersion")
        static let hotKeyEnabled = Brand.key("HotKeyEnabled")
    }

    let database: AppDatabase
    let journal: Journal
    private(set) var engine: RangeEngine
    private(set) var paths: RangePaths

    var section: MainSection = .pending
    private(set) var plan: Plan = .empty
    private(set) var rules: [Rule] = DefaultRules.all
    private(set) var batches: [BatchSummary] = []
    private(set) var undoStates: [Int64: UndoState] = [:]
    private(set) var weekCount = 0
    private(set) var lastScan: Date?
    private(set) var access: AccessState = .unknown
    private(set) var blocker: Blocker?
    private(set) var isScanning = false
    private(set) var isApplying = false
    /// Lignes decochees : restent en place (cette session).
    var excluded: Set<String> = []
    var toast: Toast?

    var automatic: Bool { didSet { store(automatic, Keys.automatic); if automatic { scan() } } }
    var paused: Bool { didSet { store(paused, Keys.paused); if !paused { scan() } } }
    private(set) var initialDone: Bool { didSet { store(initialDone, Keys.initialDone) } }
    var autoOffered: Bool { didSet { store(autoOffered, Keys.autoOffered) } }
    var graceMinutes: Int {
        didSet {
            store(graceMinutes, Keys.grace)
            applySettings()
        }
    }
    var hotKeyEnabled: Bool {
        didSet {
            store(hotKeyEnabled, Keys.hotKeyEnabled)
            applyHotKey()
        }
    }

    /// false en mode capture : rien n'est ecrit dans les reglages de l'utilisateur.
    nonisolated(unsafe) static var persists = true

    private func store(_ value: Any, _ key: String) {
        if Self.persists { UserDefaults.standard.set(value, forKey: key) }
    }

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var rescanRequested = false
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// Apres une mise a jour, pas de rangement automatique avant une lecture reussie du dossier.
    @ObservationIgnored private var updateCheckPending = false
    @ObservationIgnored private var started = false
    /// Une seule instance par base : sans verrou, cette copie s'efface devant l'autre.
    @ObservationIgnored private(set) var lock: InstanceLock?
    var isDuplicate: Bool { lock?.acquired == false }
    /// Captures : horloge avancee (stabilite acquise), reglages montres comme sur un vrai Mac.
    @ObservationIgnored private(set) var isCapturing = false
    @ObservationIgnored private var clockOffset: TimeInterval = 0

    private init() {
        #if DEBUG
        let capturing = SnapshotRequest.parse(prefix: Brand.name, arguments: CommandLine.arguments) != nil
            && ProcessInfo.processInfo.environment["RANGE_DB_PATH"] == nil
        lock = capturing ? nil : InstanceLock(next: AppDatabase.defaultURL)
        #else
        lock = InstanceLock(next: AppDatabase.defaultURL)
        #endif
        do {
            #if DEBUG
            // Captures : jamais la vraie base ni les vrais reglages.
            if SnapshotRequest.parse(prefix: Brand.name, arguments: CommandLine.arguments) != nil,
               ProcessInfo.processInfo.environment["RANGE_DB_PATH"] == nil {
                Self.persists = false
                database = try AppDatabase.open(at: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("RangeCapture-\(ProcessInfo.processInfo.processIdentifier).sqlite"))
            } else {
                database = try AppDatabase.open()
            }
            #else
            database = try AppDatabase.open()
            #endif
        } catch {
            fatalError("Impossible d'ouvrir la base \(AppDatabase.defaultURL.path) : \(error)")
        }
        journal = Journal(database: database)
        // Essai sur dossiers jetables : les reglages se lisent (arguments `-RangeAutomatic YES`...) mais
        // ne s'ecrivent pas dans ceux de l'utilisateur.
        if RangePaths.isTrial { Self.persists = false }
        let d = UserDefaults.standard
        automatic = d.bool(forKey: Keys.automatic)
        paused = d.bool(forKey: Keys.paused)
        initialDone = d.bool(forKey: Keys.initialDone)
        autoOffered = d.bool(forKey: Keys.autoOffered)
        let grace = d.object(forKey: Keys.grace) != nil ? max(0, d.integer(forKey: Keys.grace)) : 10
        graceMinutes = max(1, grace)
        hotKeyEnabled = d.bool(forKey: Keys.hotKeyEnabled)
        let current = RangePaths.current()
        paths = current
        engine = RangeEngine(journal: journal, trasher: current.trasher,
                             settings: EngineSettings(folder: current.folder, home: current.home,
                                                      grace: TimeInterval(max(1, grace) * 60)))
        reloadJournal()
    }

    // MARK: Demarrage

    func start() {
        guard !started else { return }
        started = true
        let version = AppInfo.version
        let last = UserDefaults.standard.string(forKey: Keys.lastVersion)
        if initialDone, let last, last != version { updateCheckPending = true }
        store(version, Keys.lastVersion)
        Task {
            // Journal d'abord : operations interrompues par un arret brutal, avant toute passe.
            do {
                _ = try await engine.recover()
            } catch {
                NSLog("Range : reprise du journal impossible : \(error)")
            }
            rules = await engine.rules
            reloadJournal()
            // Premier lancement : rien n'est lu avant le clic sur "Autoriser" de la carte d'accueil.
            if initialDone || UserDefaults.standard.bool(forKey: Brand.key("AccessAsked")) { scan() }
        }
        watcher = FolderWatcher { [weak self] in self?.scan() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { RangeController.shared.scan() }
        }
        applyHotKey()
    }

    /// Bouton « Autoriser » : lit Telechargements (invite de macOS), puis Documents si une regle y range.
    func requestAccess() {
        store(true, Brand.key("AccessAsked"))
        let folder = paths.folder
        let documents = rules.contains { rule in
            guard rule.enabled, case .move(let destination, _) = rule.action else { return false }
            return destination.hasPrefix("~/Documents")
        } ? paths.home + "/Documents" : nil
        Task {
            let state = await Task.detached { Access.probe(folder) }.value
            if state == .granted, let documents {
                _ = await Task.detached { Access.probe(documents) }.value
            }
            scan()
        }
    }

    // MARK: Passes

    /// Une passe : lecture, plan ; rangement automatique si tout le permet.
    func scan() {
        guard started else { return }
        if isScanning || isApplying { rescanRequested = true; return }
        isScanning = true
        Task {
            defer {
                isScanning = false
                if rescanRequested { rescanRequested = false; scan() }
            }
            do {
                let plan = try await engine.scan(now: Date().addingTimeInterval(clockOffset))
                lastScan = Date()
                if access != .granted {
                    access = .granted
                    watcher?.watch(paths.folder)
                }
                if case .folderDenied = blocker { blocker = nil }
                if blocker == .folderMissing { blocker = nil }
                updateCheckPending = false
                self.plan = plan
                excluded.formIntersection(Set(plan.actions.map(\.id)))
                scheduleNextPass(plan.nextWake)
                if canRunAutomatically, !plan.ready.filter({ !excluded.contains($0.id) }).isEmpty {
                    isScanning = false
                    await apply(Set(plan.ready.filter { !excluded.contains($0.id) }.map(\.id)), trigger: .automatic)
                }
            } catch let error as FolderAccessError {
                watcher?.stop()
                self.plan = .empty
                access = error == .missing ? .missing : .denied
                blocker = error == .missing ? .folderMissing : .folderDenied(afterUpdate: updateCheckPending)
                scheduleNextPass(nil)
            } catch {
                scheduleNextPass(nil)
            }
        }
    }

    var canRunAutomatically: Bool {
        automatic && !paused && initialDone && blocker == nil && !updateCheckPending && access == .granted
    }

    /// Prochaine passe : fin d'une attente (delai de grace, stabilite), au plus tard dans une heure.
    private func scheduleNextPass(_ wake: Date?) {
        timer?.cancel()
        let hour = Date().addingTimeInterval(3600)
        let next = min(wake ?? hour, hour)
        let delay = max(2, next.timeIntervalSinceNow + 1)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    // MARK: Ranger

    /// Lignes cochees pretes.
    var selectedReady: [PlannedAction] { plan.ready.filter { !excluded.contains($0.id) } }

    /// "Ranger N fichiers" de l'apercu : exactement les lignes affichees et cochees (par inclusion).
    func applySelection() {
        let ids = Set(selectedReady.map(\.id))
        Task { await apply(ids, trigger: initialDone ? .manual : .initial) }
    }

    private func apply(_ ids: Set<String>, trigger: BatchTrigger) async {
        guard !isApplying, !ids.isEmpty else { return }
        isApplying = true
        let result: ApplyResult
        do {
            result = try await engine.apply(only: ids, trigger: trigger, now: Date().addingTimeInterval(clockOffset))
        } catch {
            isApplying = false
            showToast(Toast(text: "Lecture du dossier impossible : rien n\u{2019}a \u{00E9}t\u{00E9} rang\u{00E9}.", undoBatch: nil))
            scan()
            return
        }
        isApplying = false
        if trigger != .automatic, !result.moves.isEmpty { initialDone = true }
        if result.failures.contains(where: { $0.reason == .denied }) {
            blocker = .documentsDenied
        } else if blocker == .documentsDenied, !result.moves.isEmpty {
            blocker = nil
        }
        reloadJournal()
        if !result.moves.isEmpty {
            let n = result.moves.count
            showToast(Toast(text: "\(n) fichier\(n > 1 ? "s" : "") rang\u{00E9}\(n > 1 ? "s" : "")", undoBatch: result.batchId))
        } else if let first = result.failures.first, trigger != .automatic {
            showToast(Toast(text: Self.describe(first.reason), undoBatch: nil))
        }
        scan()
    }

    static func describe(_ failure: ApplyFailure) -> String {
        switch failure {
        case .changed: "Un fichier bouge encore : il attendra la prochaine passe."
        case .vanished: "Un fichier a disparu entre-temps."
        case .denied: "Acc\u{00E8}s refus\u{00E9} \u{00E0} un dossier de destination."
        case .otherVolume: "Destination sur un autre disque : non prise en charge."
        case .journal: "Journal illisible : rien n\u{2019}a \u{00E9}t\u{00E9} d\u{00E9}plac\u{00E9}."
        case .failed(let message): message
        }
    }

    /// « Réessayer » apres un refus de Documents.
    func retryAfterBlocker() {
        blocker = nil
        scan()
    }

    func toggle(_ action: PlannedAction) {
        if excluded.contains(action.id) { excluded.remove(action.id) } else { excluded.insert(action.id) }
    }

    func setGroup(_ actions: [PlannedAction], checked: Bool) {
        for a in actions where a.isReady {
            if checked { excluded.remove(a.id) } else { excluded.insert(a.id) }
        }
    }

    func release(_ action: PlannedAction) {
        Task {
            try? await engine.release(inode: action.facts.inode)
            scan()
        }
    }

    // MARK: Annuler

    var canUndoLast: Bool {
        batches.contains { $0.batch.undoneAt == nil && $0.moves.contains { undoStates[$0.id ?? 0] == .undoable } }
    }

    func undoLast() {
        Task {
            guard let result = try? await engine.undoLast(now: Date()) else {
                showToast(Toast(text: "Rien \u{00E0} remettre en place", undoBatch: nil))
                return
            }
            finishUndo(result)
        }
    }

    func undoBatch(_ id: Int64) {
        Task { finishUndo(await engine.undoBatch(id, now: Date())) }
    }

    func undoMove(_ move: MoveRecord) {
        guard let id = move.id else { return }
        Task {
            do {
                _ = try await engine.undo(moveId: id, now: Date())
                reloadJournal()
                showToast(Toast(text: "\(move.name) est de retour", undoBatch: nil))
                scan()
            } catch {
                reloadJournal()
                showToast(Toast(text: "Impossible de remettre \(move.name) en place.", undoBatch: nil))
            }
        }
    }

    private func finishUndo(_ result: UndoResult) {
        reloadJournal()
        let n = result.restored.count
        var text = n == 0 ? "Rien \u{00E0} remettre en place" : "\(n) fichier\(n > 1 ? "s" : "") remis en place"
        if !result.failures.isEmpty {
            text += " \u{00B7} \(result.failures.count) non remis (voir le Journal)"
        }
        showToast(Toast(text: text, undoBatch: nil))
        scan()
    }

    func showToast(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Journal

    func reloadJournal() {
        batches = (try? journal.batches()) ?? []
        let undoer = Undoer(journal: journal)
        var states: [Int64: UndoState] = [:]
        for batch in batches.prefix(60) {
            for move in batch.moves { if let id = move.id { states[id] = undoer.state(of: move) } }
        }
        undoStates = states
        let week = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        weekCount = (try? journal.movedCount(since: week)) ?? 0
    }

    var lastBatchDate: Date? { batches.first { $0.batch.undoneAt == nil }?.batch.date }

    // MARK: Regles et reglages

    func update(_ rule: Rule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i] = rule
        let all = rules
        Task {
            try? await engine.setRules(all)
            scan()
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Surveiller"
        panel.directoryURL = URL(fileURLWithPath: paths.folder)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: RangePaths.defaultsFolderKey)
        applySettings()
    }

    func resetFolder() {
        UserDefaults.standard.removeObject(forKey: RangePaths.defaultsFolderKey)
        applySettings()
    }

    private func applySettings() {
        paths = RangePaths.current()
        let settings = EngineSettings(folder: paths.folder, home: paths.home, grace: TimeInterval(max(1, graceMinutes) * 60))
        access = .unknown
        Task {
            await engine.update(settings: settings)
            scan()
        }
    }

    func applyHotKey() {
        if hotKeyEnabled {
            HotKeyController.shared.start { WindowSummoner.toggle() }
        } else {
            HotKeyController.shared.suspend()
        }
    }

    // MARK: Etat pour la barre des menus

    /// « Rangé il y a 4 min · en pause ».
    var statusLine: String {
        var parts: [String] = []
        if let date = lastBatchDate {
            parts.append("Rang\u{00E9} " + Self.relative.localizedString(for: date, relativeTo: Date()))
        } else {
            parts.append("Rien rang\u{00E9} pour l\u{2019}instant")
        }
        if blocker != nil {
            parts.append("arr\u{00EA}t\u{00E9}")
        } else if paused {
            parts.append("en pause")
        } else if !automatic || !initialDone {
            parts.append("sur demande")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return f
    }()

    /// Ouvre la fenetre sur l'apercu et relance une passe.
    func showPreview() {
        section = .pending
        WindowSummoner.show()
        scan()
    }

    #if DEBUG
    /// Captures : dossiers jetables, dates d'arrivee imposees, stabilite acquise sans attendre.
    func prepareForCapture(paths: RangePaths, added: [String: Date], initialDone: Bool, automatic: Bool) async {
        isCapturing = true
        clockOffset = 40
        self.paths = paths
        self.initialDone = initialDone
        self.automatic = automatic
        engine = RangeEngine(journal: journal, trasher: paths.trasher,
                             settings: EngineSettings(folder: paths.folder, home: paths.home, grace: 600))
        await engine.setAddedOverrides(added)
        rules = await engine.rules
        started = true
        _ = try? await engine.scan(now: Date())
        plan = (try? await engine.scan(now: Date().addingTimeInterval(16))) ?? .empty
        access = .granted
        lastScan = Date().addingTimeInterval(-90)
    }

    /// Lot du journal date dans le passe (captures).
    func applyForCapture(only names: Set<String>, trigger: BatchTrigger, date: Date) async {
        let ids = Set(plan.ready.filter { names.contains($0.facts.name) }.map(\.id))
        _ = try? await engine.apply(only: ids, trigger: trigger, now: Date().addingTimeInterval(clockOffset), batchDate: date)
        plan = (try? await engine.scan(now: Date().addingTimeInterval(clockOffset))) ?? plan
        initialDone = true
        reloadJournal()
    }

    func setBlockerForCapture(_ blocker: Blocker?, access: AccessState) {
        self.blocker = blocker
        self.access = access
        plan = .empty
        if access == .unknown {
            lastScan = nil
            weekCount = 0
            initialDone = false
        }
    }
    #endif
}
