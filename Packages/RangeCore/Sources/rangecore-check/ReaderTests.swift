import Darwin
import Foundation
import RangeCore

let readerTests: (String, [Test]) = ("Reader", [
    Test("readsTopLevelFacts") {
        try withTemporaryDirectory { dir in
            let pdf = try makeFile(dir, "Facture 12.pdf", "abc")
            try makeFile(dir, "Projet/dedans.txt")
            try makeFile(dir, ".DS_Store")
            let facts = try FactsReader().read(folder: dir)
            let names = facts.map(\.name).sorted()
            expectEqual(names, [".DS_Store", "Facture 12.pdf", "Projet"], "premier niveau seulement")
            guard let f = facts.first(where: { $0.name == "Facture 12.pdf" }),
                  let p = facts.first(where: { $0.name == "Projet" }) else { return expect(false, "absent") }
            expectEqual(f.kind, .pdf)
            expectEqual(f.size, 3)
            expect(!f.isDirectory)
            expectEqual(f.url.path, pdf.path)
            var st = stat()
            stat(pdf.path, &st)
            expectEqual(f.inode, UInt64(st.st_ino))
            expect(abs(f.added.timeIntervalSinceNow) < 60, "arrivee recente")
            expect(p.isDirectory)
            expectEqual(p.kind, .folder)
            expectEqual(p.size, 0)
        }
    },
    Test("readsSourceAndQuarantine") {
        try withTemporaryDirectory { dir in
            let url = try makeFile(dir, "App.dmg")
            let sources = ["https://exemple.fr/telecharger", "https://cdn.exemple.fr/App.dmg"]
            let plist = try PropertyListSerialization.data(fromPropertyList: sources, format: .binary, options: 0)
            _ = plist.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, plist.count, 0, 0) }
            let quarantine = "0083;6526a2f1;Safari;B3C1A5E2-0000-0000-0000-000000000000"
            _ = quarantine.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
            let capture = try makeFile(dir, "ecran.png")
            let yes = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
            _ = yes.withUnsafeBytes { setxattr(capture.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, yes.count, 0, 0) }
            let facts = try FactsReader().read(folder: dir)
            let dmg = facts.first { $0.name == "App.dmg" }
            expectEqual(dmg?.sources ?? [], sources)
            expectEqual(dmg?.agent, "Safari")
            expectEqual(dmg?.kind, .diskImage)
            expect(dmg?.isScreenCapture == false)
            expect(facts.first { $0.name == "ecran.png" }?.isScreenCapture == true)
        }
    },
    Test("missingFolderIsReported") {
        let url = URL(fileURLWithPath: "/tmp/range-introuvable-\(UUID().uuidString)")
        do {
            _ = try FactsReader().read(folder: url)
            expect(false, "aurait du echouer")
        } catch let error as FolderAccessError {
            expectEqual(error, .missing)
        }
    },
    Test("deniedFolderIsReported") {
        try withTemporaryDirectory { dir in
            let locked = dir.appendingPathComponent("ferme")
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            chmod(locked.path, 0o000)
            defer { chmod(locked.path, 0o755) }
            do {
                _ = try FactsReader().read(folder: locked)
                expect(false, "aurait du echouer")
            } catch let error as FolderAccessError {
                expectEqual(error, .denied)
            }
        }
    },
    Test("probeComparesBytes") {
        try withTemporaryDirectory { dir in
            let a = try makeFile(dir, "a.pdf", String(repeating: "x", count: 3_000_000))
            let b = try makeFile(dir, "b.pdf", String(repeating: "x", count: 3_000_000))
            let c = try makeFile(dir, "c.pdf", String(repeating: "x", count: 2_999_999) + "y")
            let d = try makeFile(dir, "d.pdf", "court")
            let probe = DiskProbe()
            expect(probe.identical(a, b))
            expect(!probe.identical(a, c), "dernier octet")
            expect(!probe.identical(a, d), "taille")
            expect(!probe.identical(a, dir.appendingPathComponent("absent")))
            expect(!probe.identical(dir, dir), "dossiers jamais identiques")
            expect(probe.exists(a))
            expect(!probe.exists(dir.appendingPathComponent("absent")))
        }
    },
])
