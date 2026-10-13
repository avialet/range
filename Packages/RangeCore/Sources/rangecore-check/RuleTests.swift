#if DEBUG
import Foundation
import RangeCore

let ruleTests: (String, [Test]) = ("Rules", [
    Test("defaultRulesInPlanOrder") {
        let rules = DefaultRules.all
        expectEqual(rules.map(\.id), ["installers", "duplicates", "opened-archives", "invoices", "screenshots",
                                      "images", "movies", "rest"])
        expectEqual(rules.filter(\.enabled).count, 7, "le reste est eteint")
        expectEqual(rules[0].olderThanDays, 7)
        expectEqual(rules[2].olderThanDays, 3)
        expectEqual(rules[7].olderThanDays, 30)
        expectEqual(rules[3].action, .move(destination: "~/Documents/Factures", subfolder: .year))
        expectEqual(rules[4].action, .move(destination: "~/Pictures/Captures", subfolder: .month))
        expectEqual(rules[0].action, .trash)
    },
    Test("rulesRoundTripAsJSON") {
        let data = try JSONEncoder().encode(DefaultRules.all)
        let back = try JSONDecoder().decode([Rule].self, from: data)
        expectEqual(back, DefaultRules.all)
    },
    Test("mergeKeepsUserSettingsAndAddsNewRules") {
        var saved = DefaultRules.all
        saved[0].olderThanDays = 14
        saved[5].enabled = false
        saved.removeLast()
        let merged = DefaultRules.merge(saved: saved)
        expectEqual(merged.count, DefaultRules.all.count)
        expectEqual(merged[0].olderThanDays, 14)
        expect(!merged[5].enabled)
        expectEqual(merged.last?.id, "rest")
    },
    Test("destinationResolvesHomeAndSubfolder") {
        let home = "/Users/test"
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = DateComponents(calendar: cal, year: 2026, month: 3, day: 14, hour: 12).date!
        expectEqual(Destination.folder("~/Documents/Factures", subfolder: .year, date: date, home: home, calendar: cal),
                    "/Users/test/Documents/Factures/2026")
        expectEqual(Destination.folder("~/Pictures/Captures", subfolder: .month, date: date, home: home, calendar: cal),
                    "/Users/test/Pictures/Captures/2026-03")
        expectEqual(Destination.folder("/Volumes/Data/Ranges", subfolder: .none, date: date, home: home, calendar: cal),
                    "/Volumes/Data/Ranges")
    },
    Test("abbreviateKeepsPrivatePrefix") {
        let home = "/private/tmp/essai/home"
        expectEqual(Destination.abbreviate("/private/tmp/essai/home/Documents/Factures/2026/a.pdf", home: home),
                    "~/Documents/Factures/2026/a.pdf")
        expectEqual(Destination.abbreviate(home, home: home), "~")
        expectEqual(Destination.abbreviate("/Volumes/X/a", home: home), "/Volumes/X/a")
        try withTemporaryDirectory { dir in
            // Dossier personnel existant sous /private, destination pas encore creee.
            let real = dir.path.hasPrefix("/private") ? dir.path : "/private" + dir.path
            expectEqual(Destination.abbreviate(real + "/Pictures/Neuf/a.png", home: real), "~/Pictures/Neuf/a.png")
        }
    },
    Test("destinationDisplayNames") {
        expectEqual(Destination.display("~/Documents/Factures"), "Documents \u{203A} Factures")
        expectEqual(Destination.display("~/Pictures/Captures"), "Images \u{203A} Captures")
        expectEqual(Destination.display("~/Movies/T\u{00E9}l\u{00E9}charg\u{00E9}es"), "Vid\u{00E9}os \u{203A} T\u{00E9}l\u{00E9}charg\u{00E9}es")
        expectEqual(Destination.display("~/Desktop"), "Bureau")
        expectEqual(Destination.display("/Volumes/Data/X"), "/Volumes/Data/X")
        expectEqual(Destination.display("~/Documents/Factures", subfolder: .year), "Documents \u{203A} Factures, par ann\u{00E9}e")
        expectEqual(Destination.display("~/Pictures/Captures", subfolder: .month), "Images \u{203A} Captures, par mois")
    },
])
#endif
