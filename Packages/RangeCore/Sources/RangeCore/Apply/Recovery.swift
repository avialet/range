import Darwin
import Foundation

public struct RecoveryReport: Sendable, Equatable {
    /// Operations retrouvees (a destination ou dans la corbeille) : lignes passees `done`.
    public var kept = 0
    /// Operations jamais faites ou introuvables : lignes retirees.
    public var dropped = 0
}

/// Au lancement : les lignes `pending` sont celles d'un arret brutal entre le journal et l'operation.
/// Destination presente avec le meme inode : on garde. Mise a la corbeille : on cherche l'inode dans la
/// corbeille. Sinon la ligne est retiree (et les dossiers qu'elle prevoyait de creer, s'ils sont vides).
public struct Recovery: Sendable {
    let journal: Journal
    let trashFolders: [String]

    public init(journal: Journal, trashFolders: [String]) {
        self.journal = journal
        self.trashFolders = trashFolders
    }

    public func reconcile() throws -> RecoveryReport {
        var report = RecoveryReport()
        for move in try journal.pendingMoves() {
            guard let id = move.id else { continue }
            if let found = locate(move) {
                try journal.complete(moveId: id, destination: found)
                report.kept += 1
            } else {
                Executor.removeEmpty(move.createdDirs)
                try journal.discard(moveId: id)
                report.dropped += 1
            }
        }
        if report.dropped > 0 { try journal.deleteEmptyBatches() }
        return report
    }

    private func locate(_ move: MoveRecord) -> String? {
        if !move.destination.isEmpty, Self.inode(move.destination) == move.inode { return move.destination }
        guard move.kind == .trash else { return nil }
        // Le fichier est encore a sa place : rien n'a ete fait.
        if Self.inode(move.source) == move.inode { return nil }
        for folder in trashFolders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names {
                let path = FilePath.join(folder, name)
                if Self.inode(path) == move.inode { return path }
            }
        }
        return nil
    }

    static func inode(_ path: String) -> Int64? {
        var st = stat()
        guard path.withCString({ lstat($0, &st) }) == 0 else { return nil }
        return Int64(bitPattern: UInt64(st.st_ino))
    }
}
