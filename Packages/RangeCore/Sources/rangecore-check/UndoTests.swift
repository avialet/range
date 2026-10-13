import Darwin
import Foundation
import GRDB
import RangeCore

/// Arborescence lisible : chemin relatif -> contenu (dossiers suivis d'un /).
func snapshotTree(_ root: URL) -> [String: String] {
    var tree: [String: String] = [:]
    let base = root.resolvingSymlinksInPath().path
    guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return tree }
    for case let url as URL in e {
        let rel = String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1))
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            tree[rel + "/"] = ""
        } else {
            tree[rel] = (try? String(contentsOf: url, encoding: .utf8)) ?? "?"
        }
    }
    return tree
}

/// Cree un fichier avec exactement ces octets de nom (sans normalisation de Foundation).
func makeRawFile(_ dir: URL, _ name: String, _ text: String = "x") {
    let path = dir.path + "/" + name
    let fd = path.withCString { open($0, O_CREAT | O_EXCL | O_WRONLY, 0o644) }
    if fd >= 0 { _ = text.withCString { write(fd, $0, strlen($0)) }; close(fd) }
}

/// Noms du dossier en octets (hexadecimal), tries.
func rawNames(_ dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        .map { $0.utf8.map { String(format: "%02x", $0) }.joined() }.sorted()
}

let undoTests: (String, [Test]) = ("Undo", [
    Test("accentedNamesKeepTheirBytes") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            makeRawFile(bench.downloads, "\u{E9}t\u{E9} compos\u{E9}.jpg", "a")
            makeRawFile(bench.downloads, "e\u{301}te\u{301} de\u{301}compose\u{301}.jpg", "b")
            makeRawFile(bench.downloads, "\u{C9}meute (1).png", "c")
            let before = rawNames(bench.downloads)
            expectEqual(before.count, 3)
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            expectEqual(result.moves.count, 3)
            let moved = result.moves.map { URL(fileURLWithPath: $0.destination).deletingLastPathComponent() }
            expectEqual(Set(moved.flatMap(rawNames)), Set(before), "noms gardes a destination")
            guard let id = result.batchId else { return expect(false, "pas de lot") }
            _ = bench.undoer.undoBatch(id, now: Date())
            expectEqual(rawNames(bench.downloads), before, "memes octets au retour")
        }
    },
    Test("undoBatchRestoresEverything") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            for (name, text) in [("Facture 3.pdf", "f"), ("photo.jpg", "p"), ("App.dmg", "d"), ("film.mov", "m"),
                                 ("rapport.pdf", "r"), ("rapport (1).pdf", "r"),
                                 ("Capture d\u{2019}\u{00E9}cran 2026-10-01 \u{00E0} 10.00.00.png", "c")] {
                try makeFile(bench.downloads, name, text)
            }
            // Une vraie archive, puis son dossier decompresse a cote (plus recent).
            let src = dir.appendingPathComponent("src")
            try makeFile(src, "Photos/a.txt", "a")
            try zipFolder(src.appendingPathComponent("Photos"), to: bench.downloads.appendingPathComponent("Photos.zip"))
            try FileManager.default.copyItem(at: src.appendingPathComponent("Photos"), to: bench.downloads.appendingPathComponent("Photos"))
            try makeFile(bench.home.appendingPathComponent("Pictures"), "deja.jpg", "existant")
            let before = snapshotTree(bench.root)
            let result = bench.executor.apply(try bench.plan(rules: ageless).ready, trigger: .initial, now: Date())
            expectEqual(result.moves.count, 7, "tout sauf le dossier Photos")
            expect(snapshotTree(bench.root) != before)
            guard let id = result.batchId else { return expect(false, "pas de lot") }
            let undo = bench.undoer.undoBatch(id, now: Date())
            expectEqual(undo.restored.count, 7)
            expectEqual(undo.failures.count, 0)
            var after = snapshotTree(bench.root)
            after["Trash/"] = nil
            expectEqual(after, before, "retour a l'identique")
            let batch = try bench.journal.batches().first
            expect(batch?.batch.undoneAt != nil)
            expect(batch?.moves.allSatisfy { $0.undoneAt != nil } == true)
            expectEqual(try bench.journal.lastUndoableBatch()?.batch.id, nil)
        }
    },
    Test("partialUndoKeepsBatchOpenWithReasons") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "a.jpg", "a")
            try makeFile(bench.downloads, "b.jpg", "b")
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            guard let id = result.batchId, let gone = result.moves.first(where: { $0.name == "b.jpg" }) else {
                return expect(false, "rien")
            }
            try FileManager.default.removeItem(atPath: gone.destination)
            let undo = bench.undoer.undoBatch(id, now: Date())
            expectEqual(undo.restored.count, 1)
            expectEqual(undo.failures.first?.error, .gone)
            let batch = try bench.journal.batch(id)
            expect(batch?.batch.undoneAt == nil, "lot pas entierement annule")
            expectEqual(batch?.progress, .partial)
            expectEqual(batch?.moves.first { $0.name == "b.jpg" }?.undoError, UndoError.gone.code)
        }
    },
    Test("journalErrorAfterRestoreDoesNotThrow") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg")
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            guard let move = result.moves.first else { return expect(false, "rien") }
            try bench.journal.database.write { db in try db.execute(sql: "DROP TABLE move") }
            let restored = try bench.undoer.undo(move, now: Date())
            expectEqual(restored, photo.path)
            expect(FileManager.default.fileExists(atPath: photo.path), "remis malgre le journal")
        }
    },
    Test("undoneFilesAreHeld") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg")
            let result = bench.executor.apply(try bench.plan().ready, trigger: .automatic, now: Date())
            guard let move = result.moves.first else { return expect(false, "rien") }
            _ = try bench.undoer.undo(move, now: Date())
            var st = stat(); stat(photo.path, &st)
            expect(try bench.journal.heldInodes().contains(UInt64(st.st_ino)))
            let facts = try FactsReader().read(folder: bench.downloads)
            let plan = Planner.plan(facts, rules: DefaultRules.all,
                                    context: PlanContext(now: Date(), grace: 0, folder: bench.downloads.path, home: bench.home.path,
                                                         stablePaths: Set(facts.map(\.path)), mountedImages: [],
                                                         held: try bench.journal.heldInodes()),
                                    probe: DiskProbe())
            expect(plan.ready.isEmpty, "pas de re-rangement automatique")
            try bench.journal.pruneHeld(present: [])
            expect(try bench.journal.heldInodes().isEmpty, "oublie quand le fichier est parti")
        }
    },
    Test("originalNameTakenGetsVariant") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "photo.jpg", "premiere")
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            try makeFile(bench.downloads, "photo.jpg", "seconde")
            guard let move = result.moves.first else { return expect(false, "rien") }
            let restored = try bench.undoer.undo(move, now: Date())
            expectEqual(FilePath.name(restored), "photo 2.jpg")
            expectEqual(try String(contentsOfFile: restored, encoding: .utf8), "premiere")
            expectEqual(try String(contentsOf: bench.downloads.appendingPathComponent("photo.jpg"), encoding: .utf8), "seconde")
        }
    },
    Test("emptiedTrashCannotBeUndone") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "App.dmg")
            let result = bench.executor.apply(try bench.plan(rules: ageless).ready, trigger: .manual, now: Date())
            guard let move = result.moves.first else { return expect(false, "rien") }
            expectEqual(bench.undoer.state(of: move), .undoable)
            try FileManager.default.removeItem(atPath: move.destination)
            expectEqual(bench.undoer.state(of: move), .gone)
            expectThrows { _ = try bench.undoer.undo(move, now: Date()) }
        }
    },
    Test("replacedFileIsNotTakenBack") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "photo.jpg", "a")
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            guard let move = result.moves.first else { return expect(false, "rien") }
            try FileManager.default.removeItem(atPath: move.destination)
            try makeFile(URL(fileURLWithPath: move.destination).deletingLastPathComponent(), "photo.jpg", "autre")
            expectEqual(bench.undoer.state(of: move), .changed)
            expectThrows { _ = try bench.undoer.undo(move, now: Date()) }
        }
    },
    Test("createdFolderKeptWhenNotEmpty") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "photo.jpg")
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            guard let move = result.moves.first else { return expect(false, "rien") }
            let folder = URL(fileURLWithPath: move.destination).deletingLastPathComponent()
            try makeFile(folder, "autre.jpg")
            _ = try bench.undoer.undo(move, now: Date())
            expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("autre.jpg").path))
        }
    },
    Test("weeklyCountAndRules") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "a.jpg", "a")
            try makeFile(bench.downloads, "b.jpg", "b")
            _ = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            expectEqual(try bench.journal.movedCount(since: Date().addingTimeInterval(-3600)), 2)
            expect(try bench.journal.loadRules() == nil)
            var rules = DefaultRules.all
            rules[0].olderThanDays = 21
            try bench.journal.saveRules(rules)
            expectEqual(try bench.journal.loadRules(), rules)
        }
    },
])
