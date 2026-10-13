import Darwin
import Foundation

public enum UndoState: Equatable, Sendable {
    case undoable
    case undone
    /// Plus a l'endroit note : corbeille videe, fichier deplace ou supprime depuis.
    case gone
    /// Un autre fichier occupe la place (inode ou taille differents).
    case changed
}

public enum UndoError: Error, Equatable, Sendable {
    case alreadyUndone, gone, changed, sourceFolderMissing, denied
    case failed(String)

    /// Raison gardee au journal (`undoError`).
    public var code: String {
        switch self {
        case .alreadyUndone: "alreadyUndone"
        case .gone: "gone"
        case .changed: "changed"
        case .sourceFolderMissing: "sourceFolderMissing"
        case .denied: "denied"
        case .failed(let message): "failed:" + message
        }
    }
}

public struct UndoFailure: Sendable, Equatable {
    public var moveId: Int64
    public var name: String
    public var error: UndoError
}

public struct UndoResult: Sendable, Equatable {
    public var restored: [String]
    public var failures: [UndoFailure]
    /// Fichiers remis en place mais dont le journal n'a pas pu etre mis a jour.
    public var journalErrors = 0
}

/// Remet un fichier range a sa place d'origine, apres verification que c'est bien lui.
public struct Undoer: Sendable {
    let journal: Journal

    public init(journal: Journal) {
        self.journal = journal
    }

    public func state(of move: MoveRecord) -> UndoState {
        if move.undoneAt != nil { return .undone }
        var st = stat()
        guard move.destination.withCString({ lstat($0, &st) }) == 0 else { return .gone }
        guard Int64(bitPattern: UInt64(st.st_ino)) == move.inode else { return .changed }
        if !move.isDirectory, Int64(st.st_size) != move.size { return .changed }
        return .undoable
    }

    /// Renvoie l'emplacement retrouve (le nom d'origine, ou "nom 2.ext" s'il est repris). Une fois le
    /// fichier remis, une erreur du journal ne fait pas echouer l'annulation (`journalError`).
    public func undo(_ move: MoveRecord, now: Date) throws -> String {
        var journalError = false
        return try undo(move, now: now, journalError: &journalError)
    }

    func undo(_ move: MoveRecord, now: Date, journalError: inout Bool) throws -> String {
        switch state(of: move) {
        case .undone: throw UndoError.alreadyUndone
        case .gone: throw UndoError.gone
        case .changed: throw UndoError.changed
        case .undoable: break
        }
        let folder = FilePath.parent(move.source)
        guard FileOps.isDirectory(folder) else { throw UndoError.sourceFolderMissing }
        // Le nom d'origine, octet pour octet ; s'il est repris, "nom 2.ext".
        var target = move.source
        var n = 2
        while FileOps.exists(target) {
            target = FilePath.join(folder, NameNormalizer.variant(FilePath.name(move.source), number: n))
            n += 1
        }
        do {
            try FileOps.renameExclusive(move.destination, target)
        } catch {
            if case .denied = FolderAccessError.from(error) { throw UndoError.denied }
            throw UndoError.failed((error as NSError).localizedDescription)
        }
        // Ce qui est arrive doit etre le fichier note : sinon il repart d'ou il vient.
        if Recovery.inode(target) != move.inode {
            try? FileOps.renameExclusive(target, move.destination)
            throw UndoError.changed
        }
        Executor.removeEmpty(move.createdDirs)
        do {
            if let id = move.id { try journal.markUndone(moveId: id, at: now, restoredTo: target) }
            try journal.hold(inode: UInt64(bitPattern: move.inode), path: target, date: now)
        } catch {
            journalError = true
        }
        return target
    }

    /// Defait tout un lot, du dernier fichier au premier. Le lot n'est marque annule que si tout est remis ;
    /// sinon chaque fichier garde la raison de son echec.
    public func undoBatch(_ id: Int64, now: Date) -> UndoResult {
        var result = UndoResult(restored: [], failures: [])
        let summary: BatchSummary
        do {
            guard let found = try journal.batch(id) else { return result }
            summary = found
        } catch {
            result.journalErrors += 1
            return result
        }
        for move in summary.moves.reversed() where move.undoneAt == nil {
            var journalError = false
            do {
                result.restored.append(try undo(move, now: now, journalError: &journalError))
                if journalError { result.journalErrors += 1 }
                if let moveId = move.id, move.undoError != nil {
                    do { try journal.setUndoError(moveId: moveId, nil) } catch { result.journalErrors += 1 }
                }
            } catch {
                let reason = error as? UndoError ?? .failed("\(error)")
                result.failures.append(UndoFailure(moveId: move.id ?? 0, name: move.name, error: reason))
                if let moveId = move.id {
                    do { try journal.setUndoError(moveId: moveId, reason.code) } catch { result.journalErrors += 1 }
                }
            }
        }
        if result.failures.isEmpty {
            do { try journal.markBatchUndone(id, at: now) } catch { result.journalErrors += 1 }
        }
        return result
    }
}
