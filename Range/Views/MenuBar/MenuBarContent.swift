import SwiftUI
import VialetKit

struct MenuBarContent: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        Text(controller.statusLine)
        Divider()
        Button("Ranger maintenant\u{2026}") { controller.showPreview() }
        Button("Annuler le dernier rangement") { controller.undoLast() }
            .disabled(!controller.canUndoLast)
        if controller.initialDone && controller.automatic {
            Button(controller.paused ? "Reprendre" : "Suspendre") { controller.paused.toggle() }
        }
        Divider()
        Button("Ouvrir \(Brand.displayName)") { WindowSummoner.show() }
        SettingsLink { Text("R\u{00E9}glages\u{2026}") }
        Button("\u{00C0} propos de \(Brand.displayName)") { AboutPanel.show(Brand.identity) }
        Divider()
        Button("Quitter") { NSApp.terminate(nil) }
    }
}
