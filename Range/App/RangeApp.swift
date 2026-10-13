import SwiftUI
import VialetKit

@main
struct RangeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = RangeController.shared
    @State private var presence = MenuBarPresence.shared

    /// Teintes de l'app avant le premier rendu (et police Bricolage Grotesque des titres).
    init() { Theme.configure(Brand.palette) }

    var body: some Scene {
        Window(Brand.displayName, id: "main") {
            MainWindow()
                .environment(controller)
                .fontDesign(.rounded)
                .frame(minWidth: 780, minHeight: 520)
                .onAppear { AppearanceChoice.current(defaultsKey: Brand.key("Appearance")).apply(defaultsKey: Brand.key("Appearance")) }
                .captureOpenWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 920, height: 640)
        .commands {
            AboutCommands(identity: Brand.identity)
            UpdateCommands(updater: .shared)
        }

        Settings {
            SettingsView().environment(controller)
        }

        MenuBarExtra(isInserted: presence.binding) {
            MenuBarContent().environment(controller)
        } label: {
            MenuBarIcon(glyph: Brand.glyph)
        }
    }
}
