import Darwin
import Foundation
import RangeCore

/// Banc d'essai : un faux Telechargements, un faux dossier personnel et une fausse corbeille.
struct Bench {
    let root: URL
    var downloads: URL { root.appendingPathComponent("Downloads") }
    var home: URL { root.appendingPathComponent("home") }
    var trash: URL { root.appendingPathComponent("Trash") }
    let journal: Journal

    init(_ root: URL) throws {
        self.root = root
        for dir in [root.appendingPathComponent("Downloads"), root.appendingPathComponent("home/Documents"),
                    root.appendingPathComponent("home/Pictures")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        journal = Journal(database: try AppDatabase.inMemory())
    }

    var executor: Executor { Executor(journal: journal, trasher: FolderTrasher(folder: trash.path)) }
    var undoer: Undoer { Undoer(journal: journal) }

    /// Plan complet sur le disque, tout etant declare stable et sans delai de grace.
    func plan(rules: [Rule] = DefaultRules.all, now: Date = Date()) throws -> Plan {
        let facts = try FactsReader().read(folder: downloads)
        let context = PlanContext(now: now, grace: 0, folder: downloads.path, home: home.path,
                                  stablePaths: Set(facts.map(\.path)), mountedImages: [], held: [])
        return Planner.plan(facts, rules: rules, context: context, probe: DiskProbe())
    }
}

func backdate(_ url: URL, days: Double) {
    let date = Date().addingTimeInterval(-days * 86400)
    try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

/// Regles ou l'age ne compte pas (les fichiers de test viennent d'arriver).
var ageless: [Rule] {
    DefaultRules.all.map { var r = $0; r.olderThanDays = 0; return r }
}

let applyTests: (String, [Test]) = ("Apply", [
    Test("movesCreatesFoldersAndJournals") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let pdf = try makeFile(bench.downloads, "Facture 7.pdf", "facture")
            var st = stat(); stat(pdf.path, &st)
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            expectEqual(result.failures.count, 0)
            expectEqual(result.moves.count, 1)
            let year = Calendar.current.component(.year, from: Date())
            let dest = bench.home.appendingPathComponent("Documents/Factures/\(year)/Facture 7.pdf")
            expect(FileManager.default.fileExists(atPath: dest.path), "range")
            expect(!FileManager.default.fileExists(atPath: pdf.path), "parti")
            var st2 = stat(); stat(dest.path, &st2)
            expectEqual(st2.st_ino, st.st_ino, "renommage, pas copie")
            let batches = try bench.journal.batches()
            expectEqual(batches.count, 1)
            expectEqual(batches.first?.batch.trigger, .manual)
            let move = batches.first?.moves.first
            expectEqual(move?.source, pdf.path)
            expectEqual(move?.destination, dest.path)
            expectEqual(move?.kind, .move)
            expectEqual(move?.ruleId, "invoices")
            expectEqual(move?.createdDirs ?? [], [bench.home.appendingPathComponent("Documents/Factures").path,
                                                  bench.home.appendingPathComponent("Documents/Factures/\(year)").path])
        }
    },
    Test("trashGoesThroughTrasher") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "App.dmg")
            let result = bench.executor.apply(try bench.plan(rules: ageless).ready, trigger: .automatic, now: Date())
            expectEqual(result.moves.first?.kind, .trash)
            expectEqual(result.moves.first?.destination, bench.trash.appendingPathComponent("App.dmg").path)
            expect(FileManager.default.fileExists(atPath: bench.trash.appendingPathComponent("App.dmg").path))
        }
    },
    Test("changedSincePlanIsLeftAlone") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg", "un")
            let plan = try bench.plan()
            try Data("encore en cours".utf8).write(to: photo)
            let result = bench.executor.apply(plan.ready, trigger: .manual, now: Date())
            expectEqual(result.moves.count, 0)
            expectEqual(result.failures.first?.reason, .changed)
            expect(FileManager.default.fileExists(atPath: photo.path))
            expectEqual(try bench.journal.batches().count, 0, "lot vide retire")
        }
    },
    Test("conflictAfterPlanGetsVariant") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "Facture 9.pdf", "nouvelle")
            let plan = try bench.plan()
            guard case .move(let target)? = plan.ready.first?.operation else { return expect(false, "pas de deplacement") }
            try makeFile(URL(fileURLWithPath: FilePath.parent(target)), "Facture 9.pdf", "ancienne")
            let result = bench.executor.apply(plan.ready, trigger: .manual, now: Date())
            expectEqual(result.moves.first?.destination, FilePath.join(FilePath.parent(target), "Facture 9 2.pdf"))
            expectEqual(try String(contentsOfFile: target, encoding: .utf8), "ancienne", "jamais ecrase")
        }
    },
    Test("identicalAtDestinationGoesToTrash") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "Facture 9.pdf", "meme")
            let plan = try bench.plan()
            guard case .move(let target)? = plan.ready.first?.operation else { return expect(false, "pas de deplacement") }
            try makeFile(URL(fileURLWithPath: FilePath.parent(target)), "Facture 9.pdf", "meme")
            let result = bench.executor.apply(plan.ready, trigger: .manual, now: Date())
            expectEqual(result.moves.first?.kind, .trash)
            expectEqual(result.moves.first?.reason, TrashReason.alreadyAtDestination.rawValue)
        }
    },
    Test("stopsBetweenFiles") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            for name in ["a.jpg", "b.jpg", "c.jpg"] { try makeFile(bench.downloads, name, name) }
            let counter = Counter()
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date(),
                                              shouldContinue: { counter.next() < 1 })
            expectEqual(result.moves.count, 1)
            expectEqual(try FileManager.default.contentsOfDirectory(atPath: bench.downloads.path).count, 2)
        }
    },
    Test("deniedDestinationIsReported") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg")
            let pictures = bench.home.appendingPathComponent("Pictures")
            chmod(pictures.path, 0o555)
            defer { chmod(pictures.path, 0o755) }
            let result = bench.executor.apply(try bench.plan().ready, trigger: .manual, now: Date())
            expectEqual(result.failures.first?.reason, .denied)
            expect(FileManager.default.fileExists(atPath: photo.path))
        }
    },
])

/// Compteur partage pour `shouldContinue`.
final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func next() -> Int { lock.lock(); defer { lock.unlock() }; let v = value; value += 1; return v }
}
