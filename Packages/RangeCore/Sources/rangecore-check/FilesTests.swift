#if DEBUG
import Foundation
import RangeCore

let filesTests: (String, [Test]) = ("Files", [
    Test("kindFromExtension") {
        expectEqual(FileKind.classify(extension: "dmg", isDirectory: false, isPackage: false), .diskImage)
        expectEqual(FileKind.classify(extension: "pkg", isDirectory: false, isPackage: false), .installer)
        expectEqual(FileKind.classify(extension: "mpkg", isDirectory: false, isPackage: false), .installer)
        expectEqual(FileKind.classify(extension: "zip", isDirectory: false, isPackage: false), .archive)
        expectEqual(FileKind.classify(extension: "gz", isDirectory: false, isPackage: false), .archive)
        expectEqual(FileKind.classify(extension: "PNG", isDirectory: false, isPackage: false), .image)
        expectEqual(FileKind.classify(extension: "heic", isDirectory: false, isPackage: false), .image)
        expectEqual(FileKind.classify(extension: "mov", isDirectory: false, isPackage: false), .movie)
        expectEqual(FileKind.classify(extension: "mp4", isDirectory: false, isPackage: false), .movie)
        expectEqual(FileKind.classify(extension: "mp3", isDirectory: false, isPackage: false), .audio)
        expectEqual(FileKind.classify(extension: "pdf", isDirectory: false, isPackage: false), .pdf)
        expectEqual(FileKind.classify(extension: "xlsx", isDirectory: false, isPackage: false), .spreadsheet)
        expectEqual(FileKind.classify(extension: "csv", isDirectory: false, isPackage: false), .spreadsheet)
        expectEqual(FileKind.classify(extension: "pptx", isDirectory: false, isPackage: false), .presentation)
        expectEqual(FileKind.classify(extension: "docx", isDirectory: false, isPackage: false), .document)
        expectEqual(FileKind.classify(extension: "txt", isDirectory: false, isPackage: false), .document)
        expectEqual(FileKind.classify(extension: "ttf", isDirectory: false, isPackage: false), .font)
        expectEqual(FileKind.classify(extension: "", isDirectory: true, isPackage: false), .folder)
        expectEqual(FileKind.classify(extension: "app", isDirectory: true, isPackage: true), .application)
        expectEqual(FileKind.classify(extension: "xyz123", isDirectory: false, isPackage: false), .other)
    },
    Test("partialDownloadsAreSkipped") {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(-3600)
        func reason(_ name: String, dir: Bool = false, size: Int64 = 10, added: Date = old, siblings: Set<String> = []) -> SkipReason? {
            PartialDetector.skipReason(name: name, isDirectory: dir, size: size, added: added, siblings: siblings, now: now)
        }
        expectEqual(reason("film.mp4.download", dir: true), .partialDownload)
        expectEqual(reason("film.mp4.crdownload"), .partialDownload)
        expectEqual(reason("Unconfirmed 12345.crdownload"), .partialDownload)
        expectEqual(reason("film.mp4.part"), .partialDownload)
        expectEqual(reason("film.mp4.PART"), .partialDownload)
        expectEqual(reason("a.partial"), .partialDownload)
        expectEqual(reason("a.opdownload"), .partialDownload)
        expectEqual(reason("a.tmp"), .partialDownload)
        expectEqual(reason("film.mp4", siblings: ["film.mp4.part"]), .partialTwin)
        expectEqual(reason("film.mp4", siblings: ["film.mp4.crdownload"]), .partialTwin)
        expectEqual(reason("vide.pdf", size: 0, added: now.addingTimeInterval(-60)), .emptyRecent)
        expect(reason("vide.pdf", size: 0, added: now.addingTimeInterval(-700)) == nil, "vide ancien")
        expect(reason("dossier", dir: true, size: 0, added: now) == nil, "dossier vide")
        expectEqual(reason("~$Budget.xlsx"), .officeLock)
        expectEqual(reason(".DS_Store"), .hidden)
        expectEqual(reason(".localized"), .hidden)
        expectEqual(reason("Icon\r"), .hidden)
        expect(reason("rapport.pdf") == nil, "fichier ordinaire")
        expect(reason("partie.pdf") == nil, "nom qui contient part")
    },
    Test("stabilityNeedsTwoIdenticalObservations") {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var tracker = StabilityTracker()
        var f = FileFacts.sample("a.pdf", size: 100, modified: t0.addingTimeInterval(-7200), added: t0.addingTimeInterval(-7200))
        expect(!tracker.isStable(f, now: t0), "jamais vu")
        tracker.observe([f], now: t0)
        expect(!tracker.isStable(f, now: t0.addingTimeInterval(5)), "trop tot")
        expectEqual(tracker.nextCheck(for: f), t0.addingTimeInterval(StabilityTracker.window))
        tracker.observe([f], now: t0.addingTimeInterval(16))
        expect(tracker.isStable(f, now: t0.addingTimeInterval(16)), "stable apres 15 s")
        f.size = 200
        tracker.observe([f], now: t0.addingTimeInterval(20))
        expect(!tracker.isStable(f, now: t0.addingTimeInterval(20)), "a grossi")
        expect(!tracker.isStable(f, now: t0.addingTimeInterval(30)), "pas revu depuis")
        tracker.observe([f], now: t0.addingTimeInterval(36))
        expect(tracker.isStable(f, now: t0.addingTimeInterval(36)), "stable de nouveau")
        tracker.observe([], now: t0.addingTimeInterval(40))
        expect(!tracker.isStable(f, now: t0.addingTimeInterval(40)), "oublie quand absent")
    },
    Test("stabilityWatchesInodeAndDate") {
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        var tracker = StabilityTracker()
        var f = FileFacts.sample("a.pdf", size: 100, modified: t0, added: t0)
        tracker.observe([f], now: t0)
        f.modified = t0.addingTimeInterval(10)
        tracker.observe([f], now: t0.addingTimeInterval(20))
        expect(!tracker.isStable(f, now: t0.addingTimeInterval(20)), "date changee")
        f.inode = 999
        tracker.observe([f], now: t0.addingTimeInterval(40))
        expect(!tracker.isStable(f, now: t0.addingTimeInterval(40)), "autre fichier au meme nom")
    },
    Test("namesFoldAccentsAndCase") {
        expectEqual(NameNormalizer.fold("Reçu Électricité"), "recu electricite")
        expectEqual(NameNormalizer.split("archive.tar.gz").base, "archive")
        expectEqual(NameNormalizer.split("archive.tar.gz").ext, "tar.gz")
        expectEqual(NameNormalizer.split("photo.JPG").ext, "JPG")
        expectEqual(NameNormalizer.split("Makefile").base, "Makefile")
        expectEqual(NameNormalizer.split("Makefile").ext, "")
        expectEqual(NameNormalizer.split(".bashrc").base, ".bashrc")
        expectEqual(NameNormalizer.split("v1.2 notes").ext, "2 notes", "extension avec espace : on garde la regle simple")
    },
    Test("browserDuplicateNames") {
        expectEqual(NameNormalizer.duplicateOriginal(of: "rapport (1).pdf"), "rapport.pdf")
        expectEqual(NameNormalizer.duplicateOriginal(of: "rapport (12).pdf"), "rapport.pdf")
        expectEqual(NameNormalizer.duplicateOriginal(of: "rapport (2)"), "rapport")
        expectEqual(NameNormalizer.duplicateOriginal(of: "archive (1).tar.gz"), "archive.tar.gz")
        expect(NameNormalizer.duplicateOriginal(of: "rapport.pdf") == nil)
        expect(NameNormalizer.duplicateOriginal(of: "rapport(1).pdf") == nil, "sans espace")
        expect(NameNormalizer.duplicateOriginal(of: "chapitre (a).pdf") == nil)
        expect(NameNormalizer.duplicateOriginal(of: " (1).pdf") == nil, "pas de nom")
    },
    Test("finderVariants") {
        expectEqual(NameNormalizer.variant("rapport.pdf", number: 2), "rapport 2.pdf")
        expectEqual(NameNormalizer.variant("archive.tar.gz", number: 3), "archive 3.tar.gz")
        expectEqual(NameNormalizer.variant("Dossier", number: 2), "Dossier 2")
    },
    Test("screenshotNames") {
        expect(ScreenshotName.matches("Capture d\u{2019}\u{00E9}cran 2026-10-14 \u{00E0} 09.41.12.png"))
        expect(ScreenshotName.matches("Capture d'e\u{0301}cran 2026-10-14 a\u{0300} 09.41.12.png"), "forme decomposee")
        expect(ScreenshotName.matches("Screenshot 2026-10-14 at 09.41.12.png"))
        expect(ScreenshotName.matches("Screen Shot 2022-01-03 at 10.00.00 AM.png"))
        expect(!ScreenshotName.matches("Capture du projet.png"))
        expect(!ScreenshotName.matches("Screenshot.png"))
    },
    Test("invoiceHeuristic") {
        expect(InvoiceHeuristic.matches(name: "Facture-2026-031.pdf", sources: []))
        expect(InvoiceHeuristic.matches(name: "facture2026.pdf", sources: []))
        expect(InvoiceHeuristic.matches(name: "Factures octobre.pdf", sources: []))
        expect(InvoiceHeuristic.matches(name: "Invoice_INV-0042.pdf", sources: []))
        expect(InvoiceHeuristic.matches(name: "Re\u{00E7}u de paiement.pdf", sources: []))
        expect(InvoiceHeuristic.matches(name: "Receipt-2291.pdf", sources: []))
        expect(InvoiceHeuristic.matches(name: "Avoir 12.pdf", sources: []))
        expect(InvoiceHeuristic.matches(name: "quittance-loyer.pdf", sources: []))
        expect(InvoiceHeuristic.matches(name: "document.pdf", sources: ["https://pay.stripe.com/receipts/acct_1/rcpt_2/pdf"]))
        expect(InvoiceHeuristic.matches(name: "123.pdf", sources: ["https://www.paddle.com/x"]))
        expect(!InvoiceHeuristic.matches(name: "Recueil de textes.pdf", sources: []), "recueil")
        expect(!InvoiceHeuristic.matches(name: "A avoir lu.pdf", sources: []), "avoir sans numero")
        expect(!InvoiceHeuristic.matches(name: "Rapport annuel.pdf", sources: ["https://exemple.fr/rapport.pdf"]))
        expect(!InvoiceHeuristic.matches(name: "Bill of materials.pdf", sources: []))
    },
    Test("mountedImagesFromHdiutil") {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>images</key><array>
        <dict><key>image-path</key><string>/Users/x/Downloads/App.dmg</string></dict>
        <dict><key>image-path</key><string>/Users/x/Downloads/Autre.dmg</string></dict>
        <dict><key>autre</key><string>rien</string></dict>
        </array></dict></plist>
        """
        expectEqual(MountedImages.parse(Data(plist.utf8)), ["/Users/x/Downloads/App.dmg", "/Users/x/Downloads/Autre.dmg"])
        expectEqual(MountedImages.parse(Data("pas un plist".utf8)), [])
    },
])
#endif
