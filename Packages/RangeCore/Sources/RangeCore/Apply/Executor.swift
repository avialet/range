import Darwin
import Foundation

public enum ApplyFailure: Error, Equatable, Sendable {
    /// Le fichier a change depuis l'apercu (taille, date, inode) : il attendra la passe suivante.
    case changed
    /// Il n'est plus la.
    case vanished
    /// Autorisation refusee (Documents, dossier de destination).
    case denied
    /// Destination sur un autre volume : refuse en 0.1 (copie puis effacement).
    case otherVolume
    /// Le journal ne s'ecrit pas : rien n'est touche sans trace.
    case journal
    case failed(String)
}

public struct ApplyFailureItem: Sendable, Equatable {
    public var path: String
    public var reason: ApplyFailure
}

public struct ApplyResult: Sendable, Equatable {
    /// nil si rien n'a ete range (le lot vide est retire du journal).
    public var batchId: Int64?
    public var moves: [MoveRecord]
    public var failures: [ApplyFailureItem]
    /// Operations faites mais restees `pending` au journal (reglees par `Recovery` au prochain lancement).
    public var journalErrors = 0
}

/// Applique les actions pretes d'un plan, fichier par fichier, et les inscrit au journal AVANT d'agir :
/// ligne `pending` (source, destination prevue, inode, taille, dossiers a creer), puis l'operation, puis
/// `done` avec le chemin reel. Sans ligne ecrite, rien n'est touche. Chaque fichier est reverifie juste
/// avant (meme inode, meme taille, meme date) ; rien n'est jamais ecrase (renommage `RENAME_EXCL`) ;
/// la corbeille seulement ; jamais vers un autre volume.
public struct Executor: Sendable {
    let journal: Journal
    let trasher: any Trasher
    let probe: any FileProbe
    let reader: FactsReader

    public init(journal: Journal, trasher: any Trasher, probe: any FileProbe = DiskProbe(), reader: FactsReader = FactsReader()) {
        self.journal = journal
        self.trasher = trasher
        self.probe = probe
        self.reader = reader
    }

    public func apply(_ actions: [PlannedAction], trigger: BatchTrigger, now: Date,
                      shouldContinue: @Sendable () -> Bool = { true }) -> ApplyResult {
        var result = ApplyResult(batchId: nil, moves: [], failures: [])
        let ready = actions.filter(\.isReady)
        guard !ready.isEmpty else { return result }
        let batchId: Int64
        do {
            batchId = try journal.begin(trigger: trigger, date: now)
        } catch {
            result.failures = ready.map { ApplyFailureItem(path: $0.facts.path, reason: .journal) }
            return result
        }
        for action in ready {
            guard shouldContinue() else { break }
            switch perform(action, batchId: batchId, now: now, journalErrors: &result.journalErrors) {
            case .success(let move): result.moves.append(move)
            case .failure(let reason): result.failures.append(ApplyFailureItem(path: action.facts.path, reason: reason))
            }
        }
        if result.moves.isEmpty {
            do { try journal.deleteBatchIfEmpty(batchId) } catch { result.journalErrors += 1 }
        } else {
            result.batchId = batchId
        }
        return result
    }

    private func perform(_ action: PlannedAction, batchId: Int64, now: Date, journalErrors: inout Int) -> Result<MoveRecord, ApplyFailure> {
        let planned = action.facts
        guard let current = reader.facts(atPath: planned.path) else { return .failure(.vanished) }
        guard current.signature == planned.signature else { return .failure(.changed) }

        // 1. Ce qui va etre fait.
        var kind = MoveKind.trash
        var reason: TrashReason?
        var target = ""
        var missing: [String] = []
        switch action.operation {
        case .trash(let r):
            reason = r
        case .move(let planTarget):
            let folder = FilePath.parent(planTarget)
            guard Self.sameVolume(planned.path, folder) else { return .failure(.otherVolume) }
            missing = Self.missingFolders(folder)
            // Un nom pris entre l'apercu et maintenant : variante, ou corbeille si c'est le meme contenu.
            var reserved: Set<String> = []
            switch Planner.resolve(current, in: folder, probe: probe, reserved: &reserved) {
            case .move(let path):
                kind = .move
                target = path
            case .trash(let r):
                reason = r
                missing = []
            }
        }

        // 2. Le journal d'abord.
        let pending: MoveRecord
        do {
            pending = try journal.beginMove(MoveRecord(batchId: batchId, date: now, source: planned.path, destination: target,
                                                       kind: kind, ruleId: action.ruleId, reason: reason?.rawValue,
                                                       inode: Int64(bitPattern: current.inode), size: current.size,
                                                       isDirectory: current.isDirectory, createdDirs: missing))
        } catch {
            return .failure(.journal)
        }
        guard let id = pending.id else { return .failure(.journal) }

        // 3. L'operation.
        var final = target
        do {
            if kind == .move {
                try Self.createFolders(missing)
                try FileOps.renameExclusive(planned.path, target)
            } else {
                final = try trasher.trash(planned.path)
            }
        } catch {
            Self.removeEmpty(missing)
            do { try journal.discard(moveId: id) } catch { journalErrors += 1 }
            return .failure(Self.failure(error))
        }

        // 4. Fait : chemin reel.
        var done = pending
        done.state = .done
        done.destination = final
        do { try journal.complete(moveId: id, destination: final) } catch { journalErrors += 1 }
        return .success(done)
    }

    /// Dossiers a creer pour atteindre `folder`, du plus haut au plus profond.
    static func missingFolders(_ folder: String) -> [String] {
        var missing: [String] = []
        var cursor = folder
        while !FileOps.exists(cursor), cursor != "/" {
            missing.insert(cursor, at: 0)
            cursor = FilePath.parent(cursor)
        }
        return missing
    }

    /// Cree les dossiers donnes, dans l'ordre ; en cas d'echec, retire ceux deja crees.
    static func createFolders(_ folders: [String]) throws {
        var created: [String] = []
        do {
            for path in folders {
                try FileOps.makeDirectory(path)
                created.append(path)
            }
        } catch {
            removeEmpty(created)
            throw error
        }
    }

    /// Retire les dossiers crees par Range s'ils sont vides (un `.DS_Store` du Finder ne compte pas),
    /// du plus profond au plus haut.
    static func removeEmpty(_ folders: [String]) {
        for path in folders.reversed() {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { continue }
            guard items.allSatisfy({ $0 == ".DS_Store" }) else { break }
            for item in items { _ = FilePath.join(path, item).withCString { unlink($0) } }
            _ = path.withCString { rmdir($0) }
        }
    }

    /// Meme volume que le plus proche dossier existant de la destination.
    static func sameVolume(_ source: String, _ folder: String) -> Bool {
        var cursor = folder
        while !FileOps.exists(cursor), cursor != "/" { cursor = FilePath.parent(cursor) }
        var a = stat()
        guard source.withCString({ lstat($0, &a) }) == 0, let b = FileOps.device(cursor) else { return false }
        return a.st_dev == b
    }

    static func failure(_ error: Error) -> ApplyFailure {
        if let posix = error as? POSIXError, posix.code == .EXDEV { return .otherVolume }
        switch FolderAccessError.from(error) {
        case .denied: return .denied
        case .missing: return .vanished
        case .other(let message): return .failed(message)
        }
    }
}
