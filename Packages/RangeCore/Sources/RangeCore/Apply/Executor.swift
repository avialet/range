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
}

/// Applique les actions pretes d'un plan, fichier par fichier, et les inscrit au journal.
/// Chaque fichier est reverifie juste avant (meme inode, meme taille, meme date) ; rien n'est jamais
/// ecrase (renommage `RENAME_EXCL`) ; la corbeille seulement ; jamais vers un autre volume.
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
        guard !ready.isEmpty, let batchId = try? journal.begin(trigger: trigger, date: now) else { return result }
        for action in ready {
            guard shouldContinue() else { break }
            switch perform(action, batchId: batchId, now: now) {
            case .success(let move):
                if let saved = try? journal.record(move) { result.moves.append(saved) } else { result.moves.append(move) }
            case .failure(let reason):
                result.failures.append(ApplyFailureItem(path: action.facts.path, reason: reason))
            }
        }
        if result.moves.isEmpty {
            try? journal.deleteBatchIfEmpty(batchId)
        } else {
            result.batchId = batchId
        }
        return result
    }

    private func perform(_ action: PlannedAction, batchId: Int64, now: Date) -> Result<MoveRecord, ApplyFailure> {
        let planned = action.facts
        guard let current = reader.facts(atPath: planned.path) else { return .failure(.vanished) }
        guard current.signature == planned.signature else { return .failure(.changed) }
        func record(_ destination: String, _ kind: MoveKind, reason: TrashReason? = nil, created: [String] = []) -> MoveRecord {
            MoveRecord(batchId: batchId, date: now, source: planned.path, destination: destination, kind: kind,
                       ruleId: action.ruleId, reason: reason?.rawValue, inode: Int64(bitPattern: current.inode),
                       size: current.size, isDirectory: current.isDirectory, createdDirs: created)
        }
        switch action.operation {
        case .trash(let reason):
            do {
                return .success(record(try trasher.trash(planned.path), .trash, reason: reason))
            } catch {
                return .failure(Self.failure(error))
            }
        case .move(let target):
            let folder = FilePath.parent(target)
            guard Self.sameVolume(planned.path, folder) else { return .failure(.otherVolume) }
            var created: [String] = []
            do {
                created = try Self.createFolders(folder)
                // Un nom pris entre l'apercu et maintenant : variante, ou corbeille si c'est le meme contenu.
                var reserved: Set<String> = []
                switch Planner.resolve(current, in: folder, probe: probe, reserved: &reserved) {
                case .move(let path):
                    try FileOps.renameExclusive(planned.path, path)
                    return .success(record(path, .move, created: created))
                case .trash(let reason):
                    Self.removeEmpty(created)
                    return .success(record(try trasher.trash(planned.path), .trash, reason: reason))
                }
            } catch {
                Self.removeEmpty(created)
                return .failure(Self.failure(error))
            }
        }
    }

    /// Cree les dossiers manquants, du plus haut au plus profond ; renvoie ceux qui ont ete crees.
    static func createFolders(_ folder: String) throws -> [String] {
        var missing: [String] = []
        var cursor = folder
        while !FileOps.exists(cursor), cursor != "/" {
            missing.insert(cursor, at: 0)
            cursor = FilePath.parent(cursor)
        }
        var created: [String] = []
        do {
            for path in missing {
                try FileOps.makeDirectory(path)
                created.append(path)
            }
        } catch {
            removeEmpty(created)
            throw error
        }
        return created
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
