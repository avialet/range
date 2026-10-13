import Foundation
import RangeCore

/// Attend la fin d'une tache asynchrone depuis un test synchrone.
func blocking<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.value = .success(try await body()) } catch { box.value = .failure(error) }
        done.signal()
    }
    done.wait()
    return try box.value!.get()
}

final class ResultBox<T: Sendable>: @unchecked Sendable {
    var value: Result<T, Error>?
}

private func engine(_ bench: Bench, grace: TimeInterval = 0, mounted: Set<String>? = []) -> RangeEngine {
    RangeEngine(journal: bench.journal, trasher: FolderTrasher(folder: bench.trash.path),
                settings: EngineSettings(folder: bench.downloads.path, home: bench.home.path, grace: grace),
                mounted: { mounted })
}

let engineTests: (String, [Test]) = ("Engine", [
    Test("firstScanWaitsForStability") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "photo.jpg")
            let e = engine(bench)
            let t0 = Date()
            let first = try blocking { try await e.scan(now: t0) }
            expectEqual(first.actions.first?.status, .waiting(.stability))
            let second = try blocking { try await e.scan(now: t0.addingTimeInterval(16)) }
            expectEqual(second.actions.first?.status, .ready)
        }
    },
    Test("applyThenUndoLast") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let photo = try makeFile(bench.downloads, "photo.jpg")
            try makeFile(bench.downloads, "vacances.png")
            let e = engine(bench)
            let t0 = Date()
            _ = try blocking { try await e.scan(now: t0) }
            let plan = try blocking { try await e.scan(now: t0.addingTimeInterval(16)) }
            let result = try blocking { try await e.apply(only: [photo.path], trigger: .manual, now: t0.addingTimeInterval(17)) }
            expectEqual(result.moves.count, 1, "la ligne decochee reste")
            expectEqual(plan.ready.count, 2)
            expect(!FileManager.default.fileExists(atPath: photo.path))
            let undo = try blocking { try await e.undoLast(now: Date()) }
            expectEqual(undo?.restored.count, 1)
            expect(FileManager.default.fileExists(atPath: photo.path))
            let after = try blocking { try await e.scan(now: t0.addingTimeInterval(40)) }
            expectEqual(after.actions.first { $0.facts.name == "photo.jpg" }?.status, .waiting(.held))
        }
    },
    Test("applyRechecksBeforeActing") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let original = try makeFile(bench.downloads, "rapport.pdf", "meme")
            try makeFile(bench.downloads, "rapport (1).pdf", "meme")
            let photo = try makeFile(bench.downloads, "photo.jpg")
            let e = engine(bench)
            let t0 = Date()
            _ = try blocking { try await e.scan(now: t0) }
            let plan = try blocking { try await e.scan(now: t0.addingTimeInterval(16)) }
            expectEqual(plan.ready.count, 2)
            // Entre l'apercu et le clic : l'original du doublon change, un .part apparait a cote de la photo.
            try Data("autre contenu".utf8).write(to: original)
            try makeFile(bench.downloads, "photo.jpg.part")
            let ids = Set(plan.ready.map(\.id))
            let result = try blocking { try await e.apply(only: ids, trigger: .manual, now: t0.addingTimeInterval(17)) }
            expectEqual(result.moves.count, 0, "plus rien de sur")
            expect(FileManager.default.fileExists(atPath: photo.path))
            expect(FileManager.default.fileExists(atPath: bench.downloads.path + "/rapport (1).pdf"))
        }
    },
    Test("planEmptiedOnFailureAndSettings") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            try makeFile(bench.downloads, "photo.jpg")
            let e = engine(bench)
            let t0 = Date()
            _ = try blocking { try await e.scan(now: t0) }
            _ = try blocking { try await e.scan(now: t0.addingTimeInterval(16)) }
            expect(!(try blocking { await e.plan.actions.isEmpty }))
            chmod(bench.downloads.path, 0o000)
            _ = try? blocking { try await e.scan(now: t0.addingTimeInterval(20)) }
            chmod(bench.downloads.path, 0o755)
            expect(try blocking { await e.plan.actions.isEmpty }, "passe en echec")
            _ = try blocking { try await e.scan(now: t0.addingTimeInterval(40)) }
            let settings = EngineSettings(folder: bench.downloads.path, home: bench.home.path, grace: 60)
            try blocking { await e.update(settings: settings) }
            expect(try blocking { await e.plan.actions.isEmpty }, "reglages changes")
        }
    },
    Test("rulesAreSavedAndMerged") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            let e = engine(bench)
            var rules = try blocking { await e.rules }
            rules[5].enabled = false
            try blocking { [rules] in try await e.setRules(rules) }
            let again = engine(bench)
            let loaded = try blocking { await again.rules }
            expect(!loaded[5].enabled)
        }
    },
    Test("deniedFolderThrows") {
        try withTemporaryDirectory { dir in
            let bench = try Bench(dir)
            chmod(bench.downloads.path, 0o000)
            defer { chmod(bench.downloads.path, 0o755) }
            let e = engine(bench)
            do {
                _ = try blocking { try await e.scan(now: Date()) }
                expect(false, "aurait du echouer")
            } catch let error as FolderAccessError {
                expectEqual(error, .denied)
            }
        }
    },
])
