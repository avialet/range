import AppKit
import RangeCore
import SwiftUI
import VialetKit

/// Bouton en pastille : principal (comme sur les sites) ou discret.
struct PillButton: View {
    let title: String
    var icon: String?
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
                Text(title).font(Theme.ui(12.5, weight: .semibold))
            }
            .foregroundStyle(primary ? Theme.accentPrimaryButtonForeground : Theme.ink)
            .padding(.horizontal, primary ? 14 : 12)
            .padding(.vertical, primary ? 7 : 6)
            .background(Capsule().fill(primary ? Theme.accentPrimaryButtonBackground : Theme.ink.opacity(0.07)))
            .fixedSize()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Carte de contenu : fond `card`, coins `Radius.card`, contour `line`.
struct CardBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Pictogramme d'une regle, dans un carre teinte a l'accent.
struct RuleBadge: View {
    let ruleId: String
    var size: CGFloat = 28

    static func symbol(_ id: String) -> String {
        switch id {
        case "installers": "shippingbox"
        case "duplicates": "plus.square.on.square"
        case "opened-archives": "archivebox"
        case "invoices": "doc.text"
        case "screenshots": "camera.viewfinder"
        case "images": "photo"
        case "movies": "film"
        default: "tray"
        }
    }

    var body: some View {
        Image(systemName: Self.symbol(ruleId))
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.accent.opacity(0.13)))
    }
}

/// Icone du Finder d'un fichier (mise en cache).
struct FileIcon: View {
    let path: String
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: IconCache.icon(path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(_ path: String) -> NSImage {
        if let image = cache[path] { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        if cache.count > 2000 { cache.removeAll() }
        cache[path] = image
        return image
    }
}

enum Format {
    static func size(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    /// " il y a 9 j ", " il y a 3 h ".
    static func age(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 3600 { return "il y a \(max(1, Int(s / 60)))\u{00A0}min" }
        if s < 86400 * 2 { return "il y a \(Int(s / 3600))\u{00A0}h" }
        return "il y a \(Int(s / 86400))\u{00A0}j"
    }

    /// " dans 7 min ", " dans 3 j ".
    static func countdown(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, date.timeIntervalSince(now))
        if s < 60 { return "dans un instant" }
        if s < 3600 { return "dans \(Int((s / 60).rounded(.up)))\u{00A0}min" }
        if s < 86400 * 2 { return "dans \(Int((s / 3600).rounded(.up)))\u{00A0}h" }
        return "dans \(Int((s / 86400).rounded(.up)))\u{00A0}j"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_FR")))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
    }

    static func files(_ n: Int) -> String { "\(n)\u{00A0}fichier\(n > 1 ? "s" : "")" }

    /// Dossier de destination lisible : " Images > Telechargees > 2026-10 ".
    static func folder(of path: String, home: String) -> String {
        Destination.display(Destination.abbreviate(FilePath.parent(path), home: home))
    }
}

/// " 5 fichiers ranges - Annuler ", quelques secondes en bas de la fenetre.
struct ToastView: View {
    @Environment(RangeController.self) private var controller
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.text).font(Theme.ui(12.5, weight: .medium)).foregroundStyle(Theme.ink)
            if let id = toast.undoBatch {
                Button("Annuler") { controller.undoBatch(id); controller.toast = nil }
                    .buttonStyle(.plain).font(Theme.ui(12.5, weight: .bold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }
}

/// En-tete d'un ecran : titre, phrase, et a droite les actions.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.display(26)).foregroundStyle(Theme.ink)
                Text(subtitle).font(Theme.ui(12.5)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

/// Ecran de la fenetre : en-tete fixe (titre, phrase, actions) puis contenu defilant, centre a 760 pt.
/// L'en-tete reste hors du defilement : toujours visible, et la zone de defilement ne passe pas sous
/// la barre de titre masquee.
struct Screen<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: title, subtitle: subtitle) { trailing }
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 14)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    .padding(.bottom, 60)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
