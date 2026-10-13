import RangeCore
import SwiftUI
import VialetKit

/// À ranger : apercu vivant de la prochaine passe, groupe par regle. Les lignes pretes se decochent ;
/// celles qui attendent (delai de grace, age, verification, image montee) montrent pourquoi et jusqu'a quand.
struct PendingView: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        Screen(title: "\u{00C0} ranger", subtitle: subtitle) {
                    if showsList {
                        HStack(spacing: 8) {
                            Button { controller.scan() } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.inkSoft)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Theme.ink.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            .help("Relire le dossier")
                            let n = controller.selectedReady.count
                            PillButton(title: n == 0 ? "Rien \u{00E0} ranger" : "Ranger \(Format.files(n))",
                                       icon: "tray.and.arrow.down", primary: n > 0) { controller.applySelection() }
                                .disabled(n == 0 || controller.isApplying)
                                .opacity(n == 0 ? 0.5 : 1)
                        }
                    }
        } content: {
                if let blocker = controller.blocker, blocker == .documentsDenied {
                    WelcomeCard(kind: .documentsDenied)
                }
                if !showsList {
                    WelcomeCard(kind: welcomeKind)
                } else {
                    if !controller.initialDone, !controller.plan.actions.isEmpty {
                        FirstCleanNote()
                    }
                    if controller.initialDone, !controller.automatic, !controller.autoOffered {
                        AutoOfferCard()
                    }
                    if controller.plan.actions.isEmpty {
                        EmptyPending()
                    } else {
                        ForEach(groups, id: \.rule.id) { group in
                            RuleGroup(rule: group.rule, actions: group.actions)
                        }
                        footnote
                    }
                }
        }
    }

    private var showsList: Bool {
        controller.access == .granted && controller.blocker != .folderMissing
            && { if case .folderDenied = controller.blocker { return false }; return true }()
    }

    private var welcomeKind: WelcomeCard.Kind {
        switch controller.blocker {
        case .folderDenied(let afterUpdate)?: return afterUpdate ? .lostAfterUpdate : .denied
        case .folderMissing?: return .missing
        default: return .ask
        }
    }

    private var subtitle: String {
        let folder = controller.paths.folderDisplayName
        guard let last = controller.lastScan else { return folder }
        if controller.isScanning { return "\(folder) \u{00B7} lecture\u{2026}" }
        return "\(folder) \u{00B7} lu \(RangeController.relative.localizedString(for: last, relativeTo: Date()))"
    }

    private var groups: [(rule: Rule, actions: [PlannedAction])] {
        let byRule = Dictionary(grouping: controller.plan.actions, by: \.ruleId)
        return controller.rules.compactMap { rule in
            guard let actions = byRule[rule.id], !actions.isEmpty else { return nil }
            return (rule, actions)
        }
    }

    private var footnote: some View {
        let p = controller.plan
        var parts: [String] = []
        if p.untouched > 0 { parts.append("\(Format.files(p.untouched)) sans r\u{00E8}gle restent en place") }
        if p.skipped > 0 { parts.append("\(p.skipped) ignor\u{00E9}\(p.skipped > 1 ? "s" : "") (t\u{00E9}l\u{00E9}chargements en cours, fichiers cach\u{00E9}s)") }
        return Text(parts.joined(separator: " \u{00B7} "))
            .font(Theme.ui(11.5))
            .foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, 4)
    }
}

/// Note du premier menage : rien ne bouge avant le clic.
private struct FirstCleanNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GlyphPlate(size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Premier m\u{00E9}nage")
                    .font(Theme.display(16))
                    .foregroundStyle(Theme.ink)
                Text("Voici ce que Range ferait. D\u{00E9}cochez ce qui doit rester, puis rangez. Rien n\u{2019}est supprim\u{00E9} : la corbeille seulement, et chaque rangement se d\u{00E9}fait depuis le Journal.")
                    .font(Theme.ui(12.5))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.accent.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1))
    }
}

/// Plaque de l'app (glyphe blanc sur l'accent), en petit.
struct GlyphPlate: View {
    var size: CGFloat = 34

    var body: some View {
        Image(nsImage: GlyphImage.plate(Brand.palette, glyph: Brand.glyph, pixels: Int(size * 2), strokeDeep: Brand.strokeDeep))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// Apres le premier menage : proposer (sans imposer) le rangement automatique.
private struct AutoOfferCard: View {
    @Environment(RangeController.self) private var controller
    @State private var atLogin = true

    var body: some View {
        CardBox {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.13)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ranger automatiquement d\u{00E9}sormais\u{00A0}?")
                        .font(Theme.ui(13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("Range rangera chaque nouveau t\u{00E9}l\u{00E9}chargement \(controller.graceMinutes)\u{00A0}min apr\u{00E8}s son arriv\u{00E9}e, avec les m\u{00EA}mes r\u{00E8}gles. Tout reste annulable dans le Journal.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Ouvrir Range \u{00E0} la connexion", isOn: $atLogin)
                        .toggleStyle(.checkbox)
                        .font(Theme.ui(12))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    PillButton(title: "Activer", primary: true) {
                        if atLogin { _ = LaunchAtLogin.set(true) }
                        controller.automatic = true
                        controller.autoOffered = true
                    }
                    Button("Plus tard") { controller.autoOffered = true }
                        .buttonStyle(.plain)
                        .font(Theme.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(16)
        }
    }
}

private struct EmptyPending: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        VStack(spacing: 12) {
            GlyphPlate(size: 46).opacity(0.9)
            Text("Rien \u{00E0} ranger")
                .font(Theme.display(18)).foregroundStyle(Theme.ink)
            Text(controller.plan.untouched > 0
                 ? "\(controller.paths.folderDisplayName) est en ordre. \(Format.files(controller.plan.untouched)) sans r\u{00E8}gle restent o\u{00F9} ils sont."
                 : "\(controller.paths.folderDisplayName) est en ordre.")
                .font(Theme.ui(12.5)).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// Les actions d'une regle : en-tete (destination, compte, tout cocher) puis les fichiers.
private struct RuleGroup: View {
    @Environment(RangeController.self) private var controller
    let rule: Rule
    let actions: [PlannedAction]
    @State private var expanded = false
    static let preview = 6

    var body: some View {
        let ready = actions.filter(\.isReady)
        let checked = ready.filter { !controller.excluded.contains($0.id) }
        let shown = expanded ? actions : Array(actions.prefix(Self.preview))
        CardBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    if ready.isEmpty {
                        Color.clear.frame(width: 18, height: 18)
                    } else {
                        CheckCircle(checked: checked.count == ready.count, color: Theme.accent, size: 18) {
                            controller.setGroup(ready, checked: checked.count < ready.count)
                        }
                        .help(checked.count == ready.count ? "Tout d\u{00E9}cocher" : "Tout cocher")
                    }
                    RuleBadge(ruleId: rule.id, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.title).font(Theme.ui(13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(destination).font(Theme.ui(11.5)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(counts(ready: ready.count, total: actions.count))
                        .font(Theme.ui(11.5, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                ForEach(shown) { action in
                    Divider().overlay(Theme.line).padding(.leading, 43)
                    PendingRow(action: action, rule: rule)
                }
                if actions.count > Self.preview {
                    Divider().overlay(Theme.line).padding(.leading, 43)
                    Button(expanded ? "Afficher moins" : "Afficher les \(actions.count - Self.preview) autres") {
                        withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.ui(12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 43)
                    .padding(.vertical, 9)
                }
            }
        }
    }

    private var destination: String {
        switch rule.action {
        case .trash: "\u{2192} Corbeille"
        case .move(let destination, let subfolder): "\u{2192} " + Destination.display(destination, subfolder: subfolder)
        }
    }

    private func counts(ready: Int, total: Int) -> String {
        if ready == total { return "\(total)" }
        if ready == 0 { return "\(total) en attente" }
        return "\(ready) sur \(total)"
    }
}

private struct PendingRow: View {
    @Environment(RangeController.self) private var controller
    let action: PlannedAction
    let rule: Rule

    var body: some View {
        HStack(spacing: 11) {
            if action.isReady {
                CheckCircle(checked: !controller.excluded.contains(action.id), color: Theme.accent, size: 16) {
                    controller.toggle(action)
                }
                .frame(width: 18)
            } else {
                Image(systemName: waitSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(width: 18)
            }
            FileIcon(path: action.facts.path, size: 20)
            Text(action.facts.name)
                .font(Theme.ui(12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 10)
            if case .waiting(.held) = action.status {
                Button("Ranger quand m\u{00EA}me") { controller.release(action) }
                    .buttonStyle(.plain)
                    .font(Theme.ui(11.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(detail)
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.inkSoft)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .opacity(action.isReady && !controller.excluded.contains(action.id) ? 1 : 0.6)
        .help(help)
    }

    private var waitSymbol: String {
        switch action.status {
        case .waiting(.mounted): "externaldrive"
        case .waiting(.held): "hand.raised"
        case .waiting(.stability): "hourglass"
        default: "clock"
        }
    }

    private var detail: String {
        switch action.status {
        case .ready:
            if case .trash(.alreadyAtDestination) = action.operation { return "d\u{00E9}j\u{00E0} rang\u{00E9}" }
            return action.facts.isDirectory ? Format.age(action.facts.added) : "\(Format.size(action.facts.size)) \u{00B7} \(Format.age(action.facts.added))"
        case .waiting(.grace(let until)), .waiting(.age(let until)): return Format.countdown(until)
        case .waiting(.stability): return "v\u{00E9}rification\u{2026}"
        case .waiting(.mounted): return "image mont\u{00E9}e"
        case .waiting(.held): return "gard\u{00E9} ici"
        }
    }

    private var help: String {
        switch action.operation {
        case .move(let path): "Vers " + Destination.abbreviate(path, home: controller.paths.home)
        case .trash(.alreadyAtDestination): "D\u{00E9}j\u{00E0} pr\u{00E9}sent \u{00E0} destination : cette copie va \u{00E0} la corbeille"
        case .trash(.rule): "Vers la corbeille"
        }
    }
}
