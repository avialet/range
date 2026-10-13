import Darwin
import Foundation
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

let undoTests: (String, [Test]) = ("Undo", [
    Test("undoBatchRestoresEverything") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            for (name, text) in [("Facture 3.pdf", "f"), ("photo.jpg", "p"), ("App.dmg", "d"), ("film.mov", "m"),
                                 ("Photos.zip", "z"), ("rapport.pdf", "r"), ("rapport (1).pdf", "r"),
                                 ("Capture d\u{2019}\u{00E9}cran 2026-10-01 \u{00E0} 10.00.00.png", "c")] {
                try makeFile(bench.downloads, name, text)
            }
            try FileManager.default.createDirectory(at: bench.downloads.appendingPathComponent("Photos"), withIntermediateDirectories: true)
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
                                    context: PlanContext(now: Date(), grace: 0, folder: bench.downloads, home: bench.home,
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
            expectEqual(restored.lastPathComponent, "photo 2.jpg")
            expectEqual(try String(contentsOf: restored, encoding: .utf8), "premiere")
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
