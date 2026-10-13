#if DEBUG
import AppKit
import RangeCore
import VialetKit

/// Mode capture sans ecran : `Range -RangeSnapshot <dossier> [-RangeSnapshotAppearance dark]
/// [-RangeSnapshotOnly a,b] [-RangeSnapshotSize 1000x720]`. Tout se passe dans un dossier temporaire
/// (faux Telechargements d'une quarantaine de fichiers neutres, faux dossier personnel, fausse
/// corbeille, base jetable) : rien de reel n'est lu ni deplace. Scenarios : `mainWindow` (premier
/// menage), `regles`, `journal`, `proposition` (apres le premier menage), `accueil` (autorisation),
/// `acces-perdu` (apres une mise a jour), plus `settings`, `about` et `update` du kit.
extension AppDelegate {
    func runSnapshotIfRequested() -> Bool {
        guard SnapshotRequest.parse(prefix: Brand.name, arguments: CommandLine.arguments) != nil else { return false }
        let controller = RangeController.shared
        let seed = CaptureSeed()
        let main = SnapshotScenario("mainWindow") {
            await controller.prepareForCapture(paths: seed.paths, added: seed.added, initialDone: false, automatic: false)
            controller.section = .pending
            try await Task.sleep(for: .seconds(2))
            return WindowSummoner.mainWindow
        }
        let rules = SnapshotScenario("regles") {
            controller.section = .rules
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        let journal = SnapshotScenario("journal") {
            await seed.fillJournal(controller)
            controller.section = .journal
            try await Task.sleep(for: .seconds(1.5))
            return WindowSummoner.mainWindow
        }
        let offer = SnapshotScenario("proposition") {
            controller.section = .pending
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        let welcome = SnapshotScenario("accueil") {
            controller.setBlockerForCapture(nil, access: .unknown)
            controller.section = .pending
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        let lost = SnapshotScenario("acces-perdu") {
            controller.setBlockerForCapture(.folderDenied(afterUpdate: true), access: .denied)
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        let standard = SnapshotRunner.standardScenarios(mainWindow: { WindowSummoner.mainWindow }, identity: Brand.identity)
        return SnapshotRunner.runIfRequested(prefix: Brand.name,
                                             scenarios: standard + [main, rules, journal, offer, welcome, lost])
    }
}

/// Faux Telechargements : noms neutres, ages varies (dates d'arrivee imposees).
@MainActor
final class CaptureSeed {
    let root: URL
    let paths: RangePaths
    private(set) var added: [String: Date] = [:]

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("RangeCapture-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("T\u{00E9}l\u{00E9}chargements")
        let home = root.appendingPathComponent("home")
        for dir in [folder, home.appendingPathComponent("Documents"), home.appendingPathComponent("Pictures"),
                    home.appendingPathComponent("Movies")] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        paths = RangePaths(folder: folder.path, home: home.path, trash: root.appendingPathComponent("Trash").path)
        let day: Double = 86400
        let files: [(String, Double, Int)] = [
            ("Lecteur-Media-3.2.dmg", 12 * day, 48_000), ("Outil-Notes-1.4.pkg", 9 * day, 21_000),
            ("Studio-Photo-2.0.dmg", 2 * day, 96_000),
            ("Programme-colloque.pdf", 5 * day, 900), ("Programme-colloque (1).pdf", 5 * day, 900),
            ("Plan-du-site.pdf", 8 * day, 700), ("Plan-du-site (1).pdf", 8 * day, 700),
            ("Maquettes-v3.zip", 6 * day, 30_000), ("Polices-titrage.zip", 4 * day, 12_000),
            ("Facture-2026-0412.pdf", 3 * day, 300), ("Invoice-INV-20931.pdf", 8 * day, 280),
            ("Re\u{00E7}u \u{00E9}lectricit\u{00E9} septembre.pdf", 12 * day, 260), ("Avoir-2026-018.pdf", 15 * day, 240),
            ("Capture d\u{2019}\u{00E9}cran 2026-10-09 \u{00E0} 10.12.31.png", 5 * day, 4_000),
            ("Capture d\u{2019}\u{00E9}cran 2026-10-13 \u{00E0} 16.40.02.png", 1 * day, 3_800),
            ("affiche-concert.jpg", 20 * day, 5_200), ("photo-equipe.heic", 9 * day, 6_100),
            ("logo-association.png", 31 * day, 1_100), ("IMG_2041.jpeg", 2 * day, 7_300),
            ("texture-papier.webp", 14 * day, 2_600), ("illustration-couverture.png", 4 * day, 8_800),
            ("carte-voeux.jpg", 40 * day, 3_100), ("nouvelle-photo.jpg", 180, 4_400),
            ("Tutoriel-montage.mp4", 6 * day, 60_000), ("Interview-podcast.mov", 11 * day, 72_000),
            ("Compte-rendu-reunion.docx", 3 * day, 1_900), ("Budget-previsionnel.xlsx", 18 * day, 2_300),
            ("Rapport-annuel-2025.pdf", 25 * day, 3_400), ("notes.txt", 2 * day, 400),
            ("video-longue.mp4.crdownload", 60, 50_000),
            ("Bilan-trimestre.pdf", 7 * day, 1_500), ("Fiche-inscription.pdf", 10 * day, 800),
        ]
        let now = Date()
        for (name, age, size) in files {
            let path = FilePath.join(folder.path, name)
            // Contenu de remplissage ; les doublons ont le meme contenu que leur original.
            let key = NameNormalizer.duplicateOriginal(of: name) ?? name
            let data = Data(String(repeating: key, count: max(1, size / max(1, key.utf8.count))).utf8)
            FileManager.default.createFile(atPath: path, contents: data)
            added[name] = now.addingTimeInterval(-age)
            try? FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: path)
        }
        for dir in ["Maquettes-v3", "Polices-titrage", "Dossier-presse"] {
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent(dir), withIntermediateDirectories: true)
            added[dir] = now.addingTimeInterval(-6 * day)
        }
    }

    /// Trois lots dans le passe, dont un fichier remis en place et un fichier jete puis vide de la corbeille.
    func fillJournal(_ controller: RangeController) async {
        let now = Date()
        let yesterday = Calendar.current.date(bySettingHour: 18, minute: 5, second: 0,
                                              of: now.addingTimeInterval(-86400)) ?? now.addingTimeInterval(-86400)
        await controller.applyForCapture(only: ["Lecteur-Media-3.2.dmg", "Outil-Notes-1.4.pkg", "Plan-du-site (1).pdf",
                                                "Maquettes-v3.zip", "Avoir-2026-018.pdf", "carte-voeux.jpg",
                                                "logo-association.png", "Interview-podcast.mov"],
                                         trigger: .initial, date: yesterday)
        await controller.applyForCapture(only: ["Invoice-INV-20931.pdf", "texture-papier.webp"],
                                         trigger: .automatic, date: now.addingTimeInterval(-2 * 3600))
        await controller.applyForCapture(only: ["Capture d\u{2019}\u{00E9}cran 2026-10-09 \u{00E0} 10.12.31.png",
                                                "Programme-colloque (1).pdf", "affiche-concert.jpg"],
                                         trigger: .automatic, date: now.addingTimeInterval(-25 * 60))
        // Corbeille videe pour un fichier du premier lot (fausse corbeille du dossier temporaire).
        if let trash = paths.trash {
            try? FileManager.default.removeItem(atPath: FilePath.join(trash, "Outil-Notes-1.4.pkg"))
        }
        if let move = controller.batches.flatMap(\.moves).first(where: { $0.name == "texture-papier.webp" }) {
            controller.undoMove(move)
            try? await Task.sleep(for: .milliseconds(400))
        }
        controller.toast = nil
        controller.reloadJournal()
    }
}
#endif
