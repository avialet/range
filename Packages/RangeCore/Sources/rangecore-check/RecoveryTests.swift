import Darwin
import Foundation
import GRDB
import RangeCore

/// Inode d'un chemin.
func inode(_ path: String) -> Int64 {
    var st = stat()
    _ = path.withCString { lstat($0, &st) }
    return Int64(bitPattern: UInt64(st.st_ino))
}

/// Ligne `pending` ecrite comme le fait l'application avant d'agir (simulation d'un arret brutal).
func pendingRow(_ bench: Bench, source: String, destination: String, kind: MoveKind, created: [String] = []) throws -> MoveRecord {
    let batch = try bench.journal.begin(trigger: .automatic, date: Date())
    return try bench.journal.beginMove(MoveRecord(batchId: batch, date: Date(), source: source, destination: destination,
                                                  kind: kind, ruleId: "images", inode: inode(source), size: 3,
                                                  isDirectory: false, createdDirs: created))
}

let recoveryTests: (String, [Test]) = ("Recovery", [
    Test("journalWrittenBeforeTheMove") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg")
            let plan = try bench.plan()
            // Journal inutilisable : rien ne doit bouger.
            try bench.journal.database.write { db in try db.execute(sql: "DROP TABLE move") }
            let result = bench.executor.apply(plan.ready, trigger: .manual, now: Date())
            expectEqual(result.moves.count, 0)
            expectEqual(result.failures.first?.reason, .journal)
            expect(FileManager.default.fileExists(atPath: photo.path), "reste en place")
            expect(!FileManager.default.fileExists(atPath: bench.home.path + "/Pictures/T\u{00E9}l\u{00E9}charg\u{00E9}es"),
                   "aucun dossier cree")
        }
    },
    Test("pendingRowsAreHiddenUntilDone") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg", "abc")
            _ = try pendingRow(bench, source: photo.path, destination: bench.home.path + "/Pictures/photo.jpg", kind: .move)
            expect(try bench.journal.batches().allSatisfy { $0.moves.isEmpty })
            expectEqual(try bench.journal.pendingMoves().count, 1)
        }
    },
    Test("pendingMoveFoundAtDestinationIsKept") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg", "abc")
            let dest = bench.home.path + "/Pictures/photo.jpg"
            _ = try pendingRow(bench, source: photo.path, destination: dest, kind: .move)
            try FileOps.renameExclusive(photo.path, dest)
            let report = try Recovery(journal: bench.journal, trashFolders: [bench.trash.path]).reconcile()
            expectEqual(report.kept, 1)
            let move = try bench.journal.batches().first?.moves.first
            expectEqual(move?.state, .done)
            guard let move else { return expect(false, "pas de ligne") }
            _ = try bench.undoer.undo(move, now: Date())
            expect(FileManager.default.fileExists(atPath: photo.path), "annulable")
        }
    },
    Test("pendingMoveNeverDoneIsDropped") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg", "abc")
            let created = bench.home.path + "/Pictures/Neuf"
            try FileOps.makeDirectory(created)
            _ = try pendingRow(bench, source: photo.path, destination: created + "/photo.jpg", kind: .move, created: [created])
            let report = try Recovery(journal: bench.journal, trashFolders: [bench.trash.path]).reconcile()
            expectEqual(report.dropped, 1)
            expect(try bench.journal.pendingMoves().isEmpty)
            expectEqual(try bench.journal.batches().count, 0, "lot vide retire")
            expect(!FileOps.exists(created), "dossier cree retire")
            expect(FileManager.default.fileExists(atPath: photo.path))
        }
    },
    Test("pendingTrashFoundByInode") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let dmg = try makeFile(bench.downloads, "App.dmg", "abc")
            _ = try pendingRow(bench, source: dmg.path, destination: "", kind: .trash)
            try FileManager.default.createDirectory(at: bench.trash, withIntermediateDirectories: true)
            try FileOps.renameExclusive(dmg.path, bench.trash.path + "/App 3.dmg")
            let report = try Recovery(journal: bench.journal, trashFolders: [bench.trash.path]).reconcile()
            expectEqual(report.kept, 1)
            expectEqual(try bench.journal.batches().first?.moves.first?.destination, bench.trash.path + "/App 3.dmg")
        }
    },
])
