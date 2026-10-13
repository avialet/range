import RangeCore
import SwiftUI
import VialetKit

/// Fenetre principale (grammaire de Pince) : barre laterale (marque, compte de la semaine, sections,
/// etat), et a droite le bandeau de mise a jour puis la section choisie.
struct MainWindow: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 210)
                .frame(maxHeight: .infinity)
                .background(Theme.sidebar)
            VStack(spacing: 0) {
                UpdateNotice(updater: .shared)
                Group {
                    switch controller.section {
                    case .pending: PendingView()
                    case .rules: RulesView()
                    case .journal: JournalView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AmbientBackground())
            .overlay(alignment: .bottom) { ToastHost() }
        }
        .onAppear { controller.reloadJournal() }
    }
}

/// Message en bas de la fenetre (isole : son animation ne touche pas le contenu).
private struct ToastHost: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        ZStack {
            if let toast = controller.toast {
                ToastView(toast: toast).padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: controller.toast)
    }
}

private struct Sidebar: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(Brand.displayName)
                .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(controller.weekCount)")
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text(controller.weekCount > 1 ? "rang\u{00E9}s cette semaine" : "rang\u{00E9} cette semaine")
                    .font(Theme.ui(12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            List(MainSection.allCases, id: \.self, selection: $controller.section) { section in
                HStack {
                    Label(section.label, systemImage: section.icon)
                        .font(Theme.ui(13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if section == .pending, controller.plan.ready.count > 0 {
                        Text(verbatim: "\(controller.plan.ready.count)")
                            .font(Theme.ui(11, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                            .monospacedDigit()
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(height: 112)

            Spacer(minLength: 0)
            StatusBlock()
                .padding(.horizontal, 18)
                .padding(.bottom, controller.hotKeyEnabled ? 6 : 18)
            if controller.hotKeyEnabled {
                ShortcutFooter(HotKeyController.shared.shortcut)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Etat du rangement en pied de barre laterale : automatique, sur demande, en pause ou arrete.
private struct StatusBlock: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if RangePaths.isTrial {
                Chip("Essai : dossiers jetables", icon: "flask", color: Theme.coral)
            }
            HStack(spacing: 7) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(title).font(Theme.ui(12.5, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            Text(detail)
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if controller.initialDone && controller.automatic && controller.blocker == nil {
                Button(controller.paused ? "Reprendre" : "Suspendre") { controller.paused.toggle() }
                    .buttonStyle(.link)
                    .font(Theme.ui(11.5, weight: .semibold))
            }
        }
    }

    private var title: String {
        if controller.blocker != nil { return "Arr\u{00EA}t\u{00E9}" }
        if !controller.initialDone { return "Aper\u{00E7}u" }
        if !controller.automatic { return "Sur demande" }
        return controller.paused ? "En pause" : "Automatique"
    }

    private var dotColor: Color {
        if controller.blocker != nil { return Theme.danger }
        if controller.canRunAutomatically { return Theme.pine }
        return controller.paused ? Theme.sun : Theme.inkFaint
    }

    private var detail: String {
        let folder = controller.paths.folderDisplayName
        if controller.blocker != nil { return "Voir le message dans \u{00C0} ranger." }
        if !controller.initialDone { return "Rien ne bouge avant votre premier clic sur \u{00AB}\u{00A0}Ranger\u{00A0}\u{00BB}." }
        if let date = controller.lastBatchDate {
            return "\(folder) \u{00B7} rang\u{00E9} \(RangeController.relative.localizedString(for: date, relativeTo: Date()))"
        }
        return "Surveille \(folder)"
    }
}
