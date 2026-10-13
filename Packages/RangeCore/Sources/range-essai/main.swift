import Foundation
import RangeCore

// Essai du moteur sur un dossier jetable, jamais sur les vrais dossiers :
//   swift run range-essai <apercu|ranger|annuler-tout> --dossier <clone> --maison <faux home>
//       --corbeille <fausse corbeille> --base <base.sqlite> [--dates-de <dossier d'origine, lu seulement>]
//       [--grace <secondes>]
// La premiere passe ne voit rien de stable : l'outil en fait deux, a 16 s d'ecart.

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let command = CommandLine.arguments.dropFirst().first ?? ""
guard ["apercu", "ranger", "annuler-tout"].contains(command),
      let folder = argument("--dossier"), let home = argument("--maison"),
      let trash = argument("--corbeille"), let base = argument("--base") else {
    fail("usage : range-essai <apercu|ranger|annuler-tout> --dossier D --maison H --corbeille T --base B [--dates-de O] [--grace s]")
}
let realHome = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
for path in [folder, home, trash, base] {
    let full = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    if full == realHome || ["Downloads", "Documents", "Pictures", "Movies", "Desktop", ".Trash"].contains(where: { full.hasPrefix(realHome + "/" + $0) }) {
        fail("refus : \(full) est un vrai dossier")
    }
}

let journal = Journal(database: try AppDatabase.open(at: URL(fileURLWithPath: base)))
let engine = RangeEngine(journal: journal, trasher: FolderTrasher(folder: trash),
                         settings: EngineSettings(folder: folder, home: home,
                                                  grace: TimeInterval(argument("--grace") ?? "600") ?? 600))

func run() async throws {
    if command == "annuler-tout" {
        var restored = 0, failed = 0
        while let result = await engine.undoLast(now: Date()) {
            restored += result.restored.count
            failed += result.failures.count
            for f in result.failures { print("  echec : \(f.name) \(f.error)") }
        }
        print("remis en place : \(restored), echecs : \(failed)")
        return
    }
    if let original = argument("--dates-de") {
        let facts = try FactsReader().read(folder: URL(fileURLWithPath: original))
        await engine.setAddedOverrides(Dictionary(facts.map { ($0.name, $0.added) }, uniquingKeysWith: { a, _ in a }))
    }
    let t0 = Date()
    _ = try await engine.scan(now: t0)
    print("premiere passe, attente de 16 s pour la stabilite...")
    try await Task.sleep(for: .seconds(16))
    let plan = try await engine.scan(now: Date())
    let rules = await engine.rules
    print("ignores (partiels, caches) : \(plan.skipped), sans regle : \(plan.untouched)")
    for rule in rules {
        let mine = plan.actions.filter { $0.ruleId == rule.id }
        guard !mine.isEmpty else { continue }
        let ready = mine.filter(\.isReady)
        print("\n[\(rule.title)] \(ready.count) prets, \(mine.count - ready.count) en attente")
        for a in mine.prefix(6) {
            let op: String
            switch a.operation {
            case .move(let to): op = "-> " + Destination.abbreviate(to, home: home)
            case .trash(let reason): op = "-> corbeille (\(reason.rawValue))"
            }
            print("  \(a.isReady ? "+" : ".") \(a.facts.name) \(op)\(a.isReady ? "" : " [\(a.status)]")")
        }
    }
    if command == "ranger" {
        let result = await engine.apply(trigger: .manual, now: Date())
        print("\nranges : \(result.moves.count), echecs : \(result.failures.count)")
        for f in result.failures { print("  echec : \(f.path) \(f.reason)") }
    }
}

let done = DispatchSemaphore(value: 0)
Task.detached {
    do { try await run() } catch { print("erreur : \(error)") }
    done.signal()
}
done.wait()
