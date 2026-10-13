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
}

public struct UndoFailure: Sendable, Equatable {
    public var moveId: Int64
    public var name: String
    public var error: UndoError
}

public struct UndoResult: Sendable, Equatable {
    public var restored: [URL]
    public var failures: [UndoFailure]
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
        guard lstat(move.destination, &st) == 0 else { return .gone }
        guard Int64(bitPattern: UInt64(st.st_ino)) == move.inode else { return .changed }
        if !move.isDirectory, Int64(st.st_size) != move.size { return .changed }
        return .undoable
    }

    /// Renvoie l'emplacement retrouve (le nom d'origine, ou « nom 2.ext » s'il est repris).
    public func undo(_ move: MoveRecord, now: Date) throws -> URL {
        switch state(of: move) {
        case .undone: throw UndoError.alreadyUndone
        case .gone: throw UndoError.gone
        case .changed: throw UndoError.changed
        case .undoable: break
        }
        let source = URL(fileURLWithPath: move.source)
        let folder = source.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw UndoError.sourceFolderMissing
        }
        var target = source
        var n = 2
        while DiskProbe().exists(target) {
            target = folder.appendingPathComponent(NameNormalizer.variant(source.lastPathComponent, number: n))
            n += 1
        }
        do {
            try FileManager.default.moveItem(at: URL(fileURLWithPath: move.destination), to: target)
        } catch {
            if case .denied = FolderAccessError.from(error) { throw UndoError.denied }
            throw UndoError.failed((error as NSError).localizedDescription)
        }
        Executor.removeEmpty(move.createdDirs)
        if let id = move.id { try journal.markUndone(moveId: id, at: now, restoredTo: target.path) }
        try journal.hold(inode: UInt64(bitPattern: move.inode), path: target.path, date: now)
        return target
    }

    /// Defait tout un lot, du dernier fichier au premier.
    public func undoBatch(_ id: Int64, now: Date) -> UndoResult {
        var result = UndoResult(restored: [], failures: [])
        guard let summary = try? journal.batch(id) else { return result }
        for move in summary.moves.reversed() where move.undoneAt == nil {
            do {
                result.restored.append(try undo(move, now: now))
            } catch {
                result.failures.append(UndoFailure(moveId: move.id ?? 0, name: move.name,
                                                   error: error as? UndoError ?? .failed("\(error)")))
            }
        }
        try? journal.markBatchUndone(id, at: now)
        return result
    }
}
