import AppKit
import RangeCore
import SwiftUI
import VialetKit

/// Regles : dans l'ordre, la premiere qui correspond l'emporte. Interrupteur, destination,
/// sous-dossier et age minimal se reglent ; les conditions sont celles de Range.
struct RulesView: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        Screen(title: "R\u{00E8}gles",
               subtitle: "Dans l\u{2019}ordre : la premi\u{00E8}re qui correspond l\u{2019}emporte. \u{00AB}\u{00A0}Corbeille\u{00A0}\u{00BB} veut dire la corbeille du Finder, jamais une suppression.") {
            EmptyView()
        } content: {
                CardBox {
                    VStack(spacing: 0) {
                        ForEach(Array(controller.rules.enumerated()), id: \.element.id) { index, rule in
                            if index > 0 { Divider().overlay(Theme.line).padding(.leading, 58) }
                            RuleRow(rule: rule, position: index + 1)
                        }
                    }
                }
                Text("Les t\u{00E9}l\u{00E9}chargements en cours, les fichiers cach\u{00E9}s et les images disque mont\u{00E9}es ne sont jamais touch\u{00E9}s. Un fichier attend le d\u{00E9}lai de gr\u{00E2}ce (\(controller.graceMinutes)\u{00A0}min, dans les R\u{00E9}glages) avant d\u{2019}\u{00EA}tre rang\u{00E9}.")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
        }
    }
}

private struct RuleRow: View {
    @Environment(RangeController.self) private var controller
    let rule: Rule
    let position: Int

    static let ages: [(Double, String)] = [
        (0, "Apr\u{00E8}s le d\u{00E9}lai de gr\u{00E2}ce"), (1, "Apr\u{00E8}s 1 jour"), (3, "Apr\u{00E8}s 3 jours"), (7, "Apr\u{00E8}s 7 jours"),
        (14, "Apr\u{00E8}s 14 jours"), (30, "Apr\u{00E8}s 30 jours"), (90, "Apr\u{00E8}s 90 jours"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RuleBadge(ruleId: rule.id, size: 32)
                .opacity(rule.enabled ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.title).font(Theme.ui(13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(rule.summary).font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: binding(\.enabled))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.accent)
                        .labelsHidden()
                }
                HStack(spacing: 8) {
                    destination
                    if case .move = rule.action { subfolderMenu }
                    ageMenu
                }
                .disabled(!rule.enabled)
                .opacity(rule.enabled ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var destination: some View {
        switch rule.action {
        case .trash:
            Chip("Corbeille", icon: "trash", color: Theme.inkSoft)
        case .move(let path, _):
            Button { choose(current: path) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 10, weight: .bold))
                    Text(Destination.display(path)).font(Theme.ui(11.5, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Choisir le dossier de destination")
        }
    }

    private var subfolderMenu: some View {
        Menu {
            ForEach(Subfolder.allCases, id: \.self) { s in
                Button(s.label) { setSubfolder(s) }
            }
        } label: {
            menuLabel(subfolderLabel)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private var ageMenu: some View {
        Menu {
            ForEach(Self.ages, id: \.0) { days, label in
                Button(label) { var r = rule; r.olderThanDays = days; controller.update(r) }
            }
        } label: {
            menuLabel(Self.ages.first { $0.0 == rule.olderThanDays }?.1 ?? "Apr\u{00E8}s \(Int(rule.olderThanDays)) jours")
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(Theme.ui(11.5, weight: .semibold))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(Theme.ink.opacity(0.06)))
    }

    private var subfolderLabel: String {
        guard case .move(_, let s) = rule.action else { return "" }
        switch s {
        case .none: return "Sans sous-dossier"
        case .year: return "Par ann\u{00E9}e"
        case .month: return "Par mois"
        }
    }

    private func binding(_ key: WritableKeyPath<Rule, Bool>) -> Binding<Bool> {
        Binding(get: { rule[keyPath: key] }, set: { var r = rule; r[keyPath: key] = $0; controller.update(r) })
    }

    private func setSubfolder(_ s: Subfolder) {
        guard case .move(let path, _) = rule.action else { return }
        var r = rule
        r.action = .move(destination: path, subfolder: s)
        controller.update(r)
    }

    private func choose(current: String) {
        let home = controller.paths.home
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choisir"
        let resolved = Destination.resolve(current, home: home)
        var start = resolved
        while !FileOps.exists(start), start != "/" { start = FilePath.parent(start) }
        panel.directoryURL = URL(fileURLWithPath: start)
        guard panel.runModal() == .OK, let url = panel.url, case .move(_, let s) = rule.action else { return }
        var r = rule
        r.action = .move(destination: Destination.abbreviate(url.path, home: home), subfolder: s)
        controller.update(r)
    }
}
