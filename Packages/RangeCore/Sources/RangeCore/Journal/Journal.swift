import Foundation
import GRDB

public enum BatchTrigger: String, Codable, Sendable {
    /// Le premier grand menage, apres l'apercu.
    case initial
    /// « Ranger N fichiers » depuis l'apercu.
    case manual
    /// Passe automatique en arriere-plan.
    case automatic

    public var label: String {
        switch self {
        case .initial: "Premier m\u{00E9}nage"
        case .manual: "Rangement"
        case .automatic: "Rangement automatique"
        }
    }
}

public enum MoveKind: String, Codable, Sendable {
    case move, trash
}

/// Une ligne est ecrite `pending` avant le deplacement, puis passe `done` avec le chemin reel.
/// Au lancement, `Recovery` regle le sort des `pending` laissees par un arret brutal.
public enum MoveState: String, Codable, Sendable {
    case pending, done
}

public struct BatchRecord: Codable, Sendable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "batch"
    public var id: Int64?
    public var date: Date
    public var trigger: BatchTrigger
    public var undoneAt: Date?

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct MoveRecord: Codable, Sendable, Equatable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "move"
    public var id: Int64?
    public var batchId: Int64
    public var date: Date
    public var source: String
    /// Emplacement apres rangement : dossier de destination ou corbeille.
    public var destination: String
    public var kind: MoveKind
    public var ruleId: String
    /// `TrashReason` pour une mise a la corbeille.
    public var reason: String?
    public var inode: Int64
    public var size: Int64
    public var isDirectory: Bool
    /// Dossiers crees pour ce rangement, du plus haut au plus profond.
    public var createdDirs: [String]
    public var undoneAt: Date?
    /// Emplacement de retour (le nom d'origine ou une variante).
    public var restoredTo: String?
    public var state: MoveState = .done
    /// Pourquoi la derniere tentative d'annulation a echoue.
    public var undoError: String?

    public init(batchId: Int64, date: Date, source: String, destination: String, kind: MoveKind, ruleId: String,
                reason: String? = nil, inode: Int64, size: Int64, isDirectory: Bool, createdDirs: [String] = []) {
        self.batchId = batchId
        self.date = date
        self.source = source
        self.destination = destination
        self.kind = kind
        self.ruleId = ruleId
        self.reason = reason
        self.inode = inode
        self.size = size
        self.isDirectory = isDirectory
        self.createdDirs = createdDirs
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public var name: String { (source as NSString).lastPathComponent }
}

public enum UndoProgress: Sendable, Equatable {
    case none, partial, full
}

public struct BatchSummary: Sendable, Equatable, Identifiable {
    public var batch: BatchRecord
    public var moves: [MoveRecord]
    public var id: Int64 { batch.id ?? 0 }

    /// Annule entierement (tous les fichiers remis), en partie, ou pas du tout.
    public var progress: UndoProgress {
        if batch.undoneAt != nil { return .full }
        return moves.contains { $0.undoneAt != nil || $0.undoError != nil } ? .partial : .none
    }
}

/// Journal d'annulation et reglages du coeur, dans la base de l'app.
public struct Journal: Sendable {
    public let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func begin(trigger: BatchTrigger, date: Date) throws -> Int64 {
        try database.write { db in
            var batch = BatchRecord(date: date, trigger: trigger)
            try batch.insert(db)
            return batch.id ?? 0
        }
    }

    /// Ligne `pending`, ecrite AVANT de toucher au fichier.
    public func beginMove(_ move: MoveRecord) throws -> MoveRecord {
        try database.write { db in
            var m = move
            m.state = .pending
            try m.insert(db)
            return m
        }
    }

    /// L'operation a eu lieu : chemin reel, ligne `done`.
    public func complete(moveId: Int64, destination: String) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE move SET state = 'done', destination = ? WHERE id = ?", arguments: [destination, moveId])
        }
    }

    /// L'operation n'a pas eu lieu : la ligne disparait.
    public func discard(moveId: Int64) throws {
        try database.write { db in
            _ = try MoveRecord.deleteOne(db, key: moveId)
        }
    }

    public func pendingMoves() throws -> [MoveRecord] {
        try database.read { db in
            try MoveRecord.filter(Column("state") == MoveState.pending.rawValue).order(Column("id")).fetchAll(db)
        }
    }

    public func deleteBatchIfEmpty(_ id: Int64) throws {
        try database.write { db in
            let count = try MoveRecord.filter(Column("batchId") == id).fetchCount(db)
            if count == 0 { _ = try BatchRecord.deleteOne(db, key: id) }
        }
    }

    /// Retire les lots sans aucune ligne.
    public func deleteEmptyBatches() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM batch WHERE id NOT IN (SELECT DISTINCT batchId FROM move)")
        }
    }

    /// Lots du plus recent au plus ancien, avec leurs fichiers dans l'ordre d'application.
    public func batches(limit: Int = 300) throws -> [BatchSummary] {
        try database.read { db in
            let batches = try BatchRecord.order(Column("date").desc, Column("id").desc).limit(limit).fetchAll(db)
            let ids = batches.compactMap(\.id)
            let moves = try MoveRecord.filter(ids.contains(Column("batchId")) && Column("state") == MoveState.done.rawValue)
                .order(Column("id")).fetchAll(db)
            let grouped = Dictionary(grouping: moves, by: \.batchId)
            return batches.map { BatchSummary(batch: $0, moves: grouped[$0.id ?? 0] ?? []) }
        }
    }

    public func batch(_ id: Int64) throws -> BatchSummary? {
        try database.read { db in
            guard let batch = try BatchRecord.fetchOne(db, key: id) else { return nil }
            let moves = try MoveRecord.filter(Column("batchId") == id && Column("state") == MoveState.done.rawValue)
                .order(Column("id")).fetchAll(db)
            return BatchSummary(batch: batch, moves: moves)
        }
    }

    /// Le plus recent lot pas encore annule ayant au moins un fichier a remettre.
    public func lastUndoableBatch() throws -> BatchSummary? {
        try batches(limit: 50).first { $0.batch.undoneAt == nil && $0.moves.contains { $0.undoneAt == nil } }
    }

    public func markUndone(moveId: Int64, at date: Date, restoredTo: String) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE move SET undoneAt = ?, restoredTo = ? WHERE id = ?",
                           arguments: [date, restoredTo, moveId])
        }
    }

    public func setUndoError(moveId: Int64, _ message: String?) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE move SET undoError = ? WHERE id = ?", arguments: [message, moveId])
        }
    }

    public func markBatchUndone(_ id: Int64, at date: Date) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE batch SET undoneAt = ? WHERE id = ?", arguments: [date, id])
        }
    }

    /// Fichiers ranges (et pas remis) depuis une date.
    public func movedCount(since date: Date) throws -> Int {
        try database.read { db in
            try MoveRecord.filter(Column("date") >= date && Column("undoneAt") == nil
                                  && Column("state") == MoveState.done.rawValue).fetchCount(db)
        }
    }

    // MARK: Regles

    public func loadRules() throws -> [Rule]? {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT json FROM rule ORDER BY position")
            guard !rows.isEmpty else { return nil }
            return try rows.map { row in try JSONDecoder().decode(Rule.self, from: Data((row["json"] as String).utf8)) }
        }
    }

    public func saveRules(_ rules: [Rule]) throws {
        let encoded = try rules.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try database.write { db in
            try db.execute(sql: "DELETE FROM rule")
            for (i, rule) in rules.enumerated() {
                try db.execute(sql: "INSERT INTO rule (id, position, json) VALUES (?, ?, ?)",
                               arguments: [rule.id, i, encoded[i]])
            }
        }
    }

    // MARK: Fichiers gardes en place

    public func hold(inode: UInt64, path: String, date: Date) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO held (inode, path, date) VALUES (?, ?, ?)",
                           arguments: [Int64(bitPattern: inode), path, date])
        }
    }

    public func release(inode: UInt64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM held WHERE inode = ?", arguments: [Int64(bitPattern: inode)])
        }
    }

    public func heldInodes() throws -> Set<UInt64> {
        try database.read { db in
            Set(try Int64.fetchAll(db, sql: "SELECT inode FROM held").map { UInt64(bitPattern: $0) })
        }
    }

    /// Oublie les fichiers gardes qui ont quitte le dossier.
    public func pruneHeld(present: Set<UInt64>) throws {
        let held = try heldInodes()
        let gone = held.subtracting(present)
        guard !gone.isEmpty else { return }
        try database.write { db in
            for inode in gone {
                try db.execute(sql: "DELETE FROM held WHERE inode = ?", arguments: [Int64(bitPattern: inode)])
            }
        }
    }
}
