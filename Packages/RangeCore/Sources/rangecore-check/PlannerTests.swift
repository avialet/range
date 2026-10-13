import Foundation
import RangeCore

/// Sonde sans disque : fichiers presents et paires identiques declares.
struct FakeProbe: FileProbe {
    var existing: Set<String> = []
    var identicalPairs: Set<[String]> = []
    func exists(_ path: String) -> Bool { existing.contains(path) }
    func identical(_ a: String, _ b: String) -> Bool {
        identicalPairs.contains([a, b]) || identicalPairs.contains([b, a])
    }
}

private let now = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "Europe/Paris"),
                                 year: 2026, month: 10, day: 14, hour: 12).date!
private let day: TimeInterval = 86400

private func context(_ facts: [FileFacts], stable: Bool = true, mounted: Set<UInt64>? = [], held: Set<UInt64> = [],
                     grace: TimeInterval = 600) -> PlanContext {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    return PlanContext(now: now, grace: grace, folder: "/dl", home: "/h",
                       stablePaths: stable ? Set(facts.map(\.path)) : [], mountedImages: mounted, held: held, calendar: cal)
}

private func plan(_ facts: [FileFacts], rules: [Rule] = DefaultRules.all, probe: FakeProbe = FakeProbe(),
                  stable: Bool = true, mounted: Set<UInt64>? = [], held: Set<UInt64> = [], grace: TimeInterval = 600) -> Plan {
    Planner.plan(facts, rules: rules, context: context(facts, stable: stable, mounted: mounted, held: held, grace: grace), probe: probe)
}

private func old(_ name: String, days: Double = 40, size: Int64 = 1000, directory: Bool = false,
                 sources: [String] = [], capture: Bool = false) -> FileFacts {
    let date = now.addingTimeInterval(-days * day)
    return FileFacts.sample(name, size: size, modified: date, added: date, directory: directory, sources: sources, screenCapture: capture)
}

let plannerTests: (String, [Test]) = ("Planner", [
    Test("installersGoToTrashAfterSevenDays") {
        let p = plan([old("App.dmg", days: 8), old("Outil.pkg", days: 2)])
        let dmg = p.actions.first { $0.facts.name == "App.dmg" }
        expectEqual(dmg?.operation, .trash(.rule))
        expectEqual(dmg?.status, .ready)
        expectEqual(dmg?.ruleId, "installers")
        let pkg = p.actions.first { $0.facts.name == "Outil.pkg" }
        expectEqual(pkg?.status, .waiting(.age(until: now.addingTimeInterval(-2 * day + 7 * day))))
        expectEqual(p.ready.count, 1)
    },
    Test("mountedImageIsNeverTouched") {
        let p = plan([old("App.dmg", days: 8)], mounted: [old("App.dmg").inode])
        expectEqual(p.actions.first?.status, .waiting(.mounted))
        let unknown = plan([old("App.dmg", days: 8)], mounted: nil)
        expectEqual(unknown.actions.first?.status, .waiting(.mounted), "hdiutil muet : prudence")
    },
    Test("browserDuplicatesIdenticalOnly") {
        let a = old("rapport.pdf"), b = old("rapport (1).pdf"), c = old("devis (1).pdf"), d = old("devis.pdf")
        let probe = FakeProbe(identicalPairs: [["/dl/rapport (1).pdf", "/dl/rapport.pdf"]])
        let p = plan([a, b, c, d], probe: probe)
        expectEqual(p.actions.first { $0.facts.name == "rapport (1).pdf" }?.ruleId, "duplicates")
        expectEqual(p.actions.first { $0.facts.name == "rapport (1).pdf" }?.operation, .trash(.rule))
        expect(p.actions.first { $0.facts.name == "devis (1).pdf" }?.ruleId != "duplicates", "contenu different")
    },
    Test("openedArchivesNeedTheirFolder") {
        let p = plan([old("Photos.zip", days: 4), old("Photos", directory: true), old("Seule.zip", days: 4)])
        expectEqual(p.actions.first { $0.facts.name == "Photos.zip" }?.ruleId, "opened-archives")
        expect(p.actions.first { $0.facts.name == "Seule.zip" }?.ruleId != "opened-archives")
    },
    Test("invoicesMoveByYear") {
        let f = old("Facture 2026-031.pdf", days: 20)
        let p = plan([f])
        expectEqual(p.actions.first?.operation, .move(to: "/h/Documents/Factures/2026/Facture 2026-031.pdf"))
        expectEqual(p.actions.first?.status, .ready)
        let fromStripe = plan([old("doc.pdf", days: 1, sources: ["https://pay.stripe.com/receipts/1"])])
        expectEqual(fromStripe.actions.first?.ruleId, "invoices")
    },
    Test("screenshotsAndImagesByMonth") {
        let shot = old("Capture d\u{2019}\u{00E9}cran 2026-09-30 \u{00E0} 10.00.00.png", days: 14)
        let photo = old("vacances.jpg", days: 14)
        let flagged = old("sans-nom.png", days: 14, capture: true)
        let p = plan([shot, photo, flagged])
        expectEqual(p.actions.first { $0.facts.name == shot.name }?.operation,
                    .move(to: "/h/Pictures/Captures/2026-09/\(shot.name)"))
        expectEqual(p.actions.first { $0.facts.name == "sans-nom.png" }?.ruleId, "screenshots")
        expectEqual(p.actions.first { $0.facts.name == "vacances.jpg" }?.operation,
                    .move(to: "/h/Pictures/T\u{00E9}l\u{00E9}charg\u{00E9}es/2026-09/vacances.jpg"))
    },
    Test("restIsOffByDefault") {
        let p = plan([old("notes.txt", days: 60)])
        expect(p.actions.isEmpty)
        expectEqual(p.untouched, 1)
        var rules = DefaultRules.all
        rules[7].enabled = true
        let on = plan([old("notes.txt", days: 60), old("recent.txt", days: 2)], rules: rules)
        expectEqual(on.actions.first { $0.facts.name == "notes.txt" }?.status, .ready)
        expect(on.actions.first { $0.facts.name == "recent.txt" }?.status != .ready)
    },
    Test("disabledRuleLetsTheNextOneMatch") {
        var rules = DefaultRules.all
        rules[4].enabled = false
        let shot = old("Screenshot 2026-09-30 at 10.00.00.png", days: 14)
        expectEqual(plan([shot], rules: rules).actions.first?.ruleId, "images")
    },
    Test("partialsAndHiddenAreSkipped") {
        let p = plan([old("film.mp4.crdownload", days: 0.001), old("film.mp4", days: 0.001), old(".DS_Store"),
                      old("x.mov.part", days: 0.001), old("x.mov", days: 0.001, size: 0)])
        expect(p.actions.isEmpty)
        expectEqual(p.skipped, 5)
    },
    Test("graceAndStabilityWait") {
        let fresh = FileFacts.sample("photo.jpg", modified: now.addingTimeInterval(-60), added: now.addingTimeInterval(-60))
        let p = plan([fresh])
        expectEqual(p.actions.first?.status, .waiting(.grace(until: now.addingTimeInterval(540))))
        expectEqual(p.nextWake, now.addingTimeInterval(540))
        let unstable = plan([old("photo.jpg")], stable: false)
        expectEqual(unstable.actions.first?.status, .waiting(.stability))
        expectEqual(unstable.nextWake, now.addingTimeInterval(StabilityTracker.window + 1))
        let zero = plan([fresh], grace: 0)
        expectEqual(zero.actions.first?.status, .ready)
    },
    Test("heldFilesStay") {
        let f = old("photo.jpg")
        let p = plan([f], held: [f.inode])
        expectEqual(p.actions.first?.status, .waiting(.held))
        expect(p.ready.isEmpty)
    },
    Test("conflictsGetFinderSuffix") {
        let f = old("vacances.jpg", days: 14)
        let target = "/h/Pictures/T\u{00E9}l\u{00E9}charg\u{00E9}es/2026-09/vacances.jpg"
        let taken = FakeProbe(existing: [target, "/h/Pictures/T\u{00E9}l\u{00E9}charg\u{00E9}es/2026-09/vacances 2.jpg"])
        expectEqual(plan([f], probe: taken).actions.first?.operation,
                    .move(to: "/h/Pictures/T\u{00E9}l\u{00E9}charg\u{00E9}es/2026-09/vacances 3.jpg"))
        let same = FakeProbe(existing: [target], identicalPairs: [["/dl/vacances.jpg", target]])
        expectEqual(plan([f], probe: same).actions.first?.operation, .trash(.alreadyAtDestination))
    },
    Test("destinationInsideWatchedFolderIsIgnored") {
        var rules = DefaultRules.all
        rules[5].action = .move(destination: "/dl", subfolder: .none)
        let p = plan([old("photo.jpg")], rules: rules)
        expect(p.actions.isEmpty, "ranger dans le dossier lui-meme : rien")
    },
    Test("readyComeFirstThenByRule") {
        let p = plan([old("vacances.jpg", days: 14), old("App.dmg", days: 2), old("Old.dmg", days: 9)])
        expectEqual(p.actions.map(\.facts.name), ["Old.dmg", "vacances.jpg", "App.dmg"])
    },
])
