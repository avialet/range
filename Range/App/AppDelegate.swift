import AppKit
import RangeCore
import VialetKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Mode capture : dossiers jetables, ni surveillance, ni raccourci, ni reseau.
        if runSnapshotIfRequested() { return }
        #endif
        if let lock = RangeController.shared.lock, lock.openError != nil {
            lock.reportOpenFailureAndQuit()
            return
        }
        if RangeController.shared.isDuplicate {
            InstanceLock.yieldToRunningInstance()
            return
        }
        RangeController.shared.start()
        registerActions()
        _ = DockPresence.shared
        HubPresence.start(menuBar: MenuBarPresence.shared, actions: AppActions.shared, updater: Updater.shared)
        // Laisse l'app s'afficher avant le moindre appel reseau.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated { Updater.shared.checkAutomatically() }
        }
    }

    /// Actions rapides (`range://ranger`, `range://annuler`, `range://pause`), aussi dans le menu de Vialet.
    private func registerActions() {
        let actions = AppActions.shared
        actions.register(AppAction("ranger", title: "Ranger maintenant", symbol: "tray.and.arrow.down")) {
            RangeController.shared.showPreview()
        }
        actions.register(AppAction("annuler", title: "Annuler le dernier rangement", symbol: "arrow.uturn.backward")) {
            RangeController.shared.undoLast()
        }
        actions.register(AppAction("pause", title: "Suspendre ou reprendre", symbol: "pause.circle")) {
            RangeController.shared.paused.toggle()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppActions.shared.handle(urls)
    }

    /// L'app reste active (surveillance, barre des menus) fenetre fermee.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowSummoner.show() }
        return true
    }
}

extension AppActions {
    static let shared = AppActions(Brand.identity, open: { WindowSummoner.show() },
                                   checkForUpdates: { WindowSummoner.show(); Updater.shared.check() })
}
