import RangeCore
import SwiftUI
import VialetKit

/// Reglages : cartes standard du kit (raccourci facultatif, toujours la, mises a jour, apparence),
/// puis Rangement et Dossier surveille.
struct SettingsView: View {
    @Environment(RangeController.self) private var controller

    static let graces = [2, 5, 10, 30, 60]

    var body: some View {
        @Bindable var controller = controller
        SettingsScreen(app: Brand.identity, hotKey: .shared, updater: .shared, menuBar: MenuBarPresence.shared,
                       dock: DockPresence.shared, hotKeyEnabled: $controller.hotKeyEnabled,
                       hotKeyHint: "Depuis n\u{2019}importe quelle app : ouvre ou masque la fen\u{00EA}tre de Range.",
                       alwaysOnHint: "Fermer la fen\u{00EA}tre ne quitte pas Range : il continue de surveiller \(controller.paths.folderDisplayName). \u{2318}Q pour quitter.",
                       updateNote: HubPresence.updateNote,
                       width: 480) {
            // Cartes propres a Range.
            SettingsCard(icon: "tray.and.arrow.down", color: Theme.accent, title: "Rangement") {
                Toggle("Ranger automatiquement", isOn: $controller.automatic)
                    .disabled(!controller.initialDone)
                Text(controller.initialDone
                     ? "Sinon, Range montre ce qu\u{2019}il ferait dans \u{00AB}\u{00A0}\u{00C0} ranger\u{00A0}\u{00BB} et attend votre clic."
                     : "Disponible apr\u{00E8}s le premier m\u{00E9}nage, fait \u{00E0} la main depuis l\u{2019}aper\u{00E7}u.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("D\u{00E9}lai de gr\u{00E2}ce")
                    Spacer(minLength: 12)
                    Picker("D\u{00E9}lai de gr\u{00E2}ce", selection: $controller.graceMinutes) {
                        ForEach(Self.graces, id: \.self) { Text("\($0)\u{00A0}min").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                Text("Un fichier arriv\u{00E9} reste en place ce temps-l\u{00E0} : le lien \u{00AB}\u{00A0}Ouvrir\u{00A0}\u{00BB} du navigateur marche encore.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsCard(icon: "folder", color: Theme.sun, title: "Dossier surveill\u{00E9}") {
                HStack(spacing: 10) {
                    Image(nsImage: IconCache.icon(controller.paths.folder))
                        .resizable().frame(width: 20, height: 20)
                    Text(controller.isCapturing ? "~/Downloads" : Destination.abbreviate(controller.paths.folder, home: NSHomeDirectory()))
                        .font(Theme.ui(12.5, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Choisir\u{2026}") { controller.chooseFolder() }
                        .disabled(RangePaths.isTrial)
                }
                if !controller.paths.isDefaultFolder, !RangePaths.isTrial, !controller.isCapturing {
                    Button("Revenir \u{00E0} T\u{00E9}l\u{00E9}chargements") { controller.resetFolder() }
                        .buttonStyle(.link)
                        .font(Theme.ui(12, weight: .semibold))
                }
                Text("Range ne regarde que le premier niveau de ce dossier. Les fichiers rang\u{00E9}s vont dans Documents, Images et Vid\u{00E9}os, selon les r\u{00E8}gles.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
