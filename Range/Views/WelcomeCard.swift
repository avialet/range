import RangeCore
import SwiftUI
import VialetKit

/// Carte d'accueil et d'alerte : autorisation de lire Telechargements (premier lancement, ou perdue
/// apres une mise a jour), dossier introuvable, Documents refuse.
struct WelcomeCard: View {
    @Environment(RangeController.self) private var controller

    enum Kind {
        case ask, denied, lostAfterUpdate, missing, documentsDenied
    }

    let kind: Kind

    var body: some View {
        CardBox {
            HStack(alignment: .top, spacing: 16) {
                if kind == .ask {
                    GlyphPlate(size: 44)
                } else {
                    Image(systemName: kind == .missing ? "questionmark.folder" : "lock.trianglebadge.exclamationmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(kind == .documentsDenied ? Theme.coral : Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill((kind == .documentsDenied ? Theme.coral : Theme.accent).opacity(0.13)))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Theme.display(kind == .ask ? 19 : 16))
                        .foregroundStyle(Theme.ink)
                    Text(text)
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if kind == .ask {
                        VStack(alignment: .leading, spacing: 6) {
                            point("tray.full", "Un aper\u{00E7}u d\u{2019}abord : rien ne bouge avant votre clic.")
                            point("trash", "Jamais de suppression : la corbeille seulement.")
                            point("arrow.uturn.backward", "Chaque rangement se d\u{00E9}fait depuis le Journal.")
                            point("arrow.down.circle.dotted", "Les t\u{00E9}l\u{00E9}chargements en cours ne sont jamais touch\u{00E9}s.")
                        }
                        .padding(.top, 6)
                    }
                    HStack(spacing: 10) { buttons }
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(kind == .ask ? 22 : 16)
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            Text(text).font(Theme.ui(12.5)).foregroundStyle(Theme.ink)
        }
    }

    private var folder: String { controller.paths.folderDisplayName }

    private var title: String {
        switch kind {
        case .ask: "Range a besoin d\u{2019}ouvrir \(folder)"
        case .denied: "Acc\u{00E8}s \u{00E0} \(folder) refus\u{00E9}"
        case .lostAfterUpdate: "Range a \u{00E9}t\u{00E9} mis \u{00E0} jour : macOS redemande l\u{2019}acc\u{00E8}s"
        case .missing: "Dossier surveill\u{00E9} introuvable"
        case .documentsDenied: "Acc\u{00E8}s \u{00E0} Documents refus\u{00E9}"
        }
    }

    private var text: String {
        switch kind {
        case .ask:
            "Pour proposer un rangement, Range lit le contenu de \(folder) et range les factures dans Documents. macOS va vous demander l\u{2019}autorisation, une fois pour chaque dossier."
        case .denied:
            "Range ne peut rien lire. Rouvrez l\u{2019}acc\u{00E8}s dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Confidentialit\u{00E9} et s\u{00E9}curit\u{00E9} \u{203A} Fichiers et dossiers \u{203A} Range."
        case .lostAfterUpdate:
            "Chaque nouvelle version de Range est une nouvelle app aux yeux de macOS. Le rangement automatique est suspendu tant que l\u{2019}acc\u{00E8}s \u{00E0} \(folder) n\u{2019}est pas rendu."
        case .missing:
            "\(controller.paths.folder) n\u{2019}existe plus. Choisissez un autre dossier, ou revenez \u{00E0} T\u{00E9}l\u{00E9}chargements."
        case .documentsDenied:
            "Les fichiers destin\u{00E9}s \u{00E0} Documents restent dans \(folder) et le rangement automatique est suspendu. Rouvrez l\u{2019}acc\u{00E8}s dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Confidentialit\u{00E9} et s\u{00E9}curit\u{00E9} \u{203A} Fichiers et dossiers."
        }
    }

    @ViewBuilder private var buttons: some View {
        switch kind {
        case .ask:
            PillButton(title: "Autoriser et analyser", icon: "lock.open", primary: true) { controller.requestAccess() }
        case .denied, .lostAfterUpdate:
            PillButton(title: "Ouvrir les R\u{00E9}glages", primary: true) { Access.openPrivacySettings() }
            PillButton(title: "R\u{00E9}essayer") { controller.requestAccess() }
        case .missing:
            PillButton(title: "Choisir un dossier\u{2026}", primary: true) { controller.chooseFolder() }
            if !controller.paths.isDefaultFolder {
                PillButton(title: "Revenir \u{00E0} T\u{00E9}l\u{00E9}chargements") { controller.resetFolder() }
            }
        case .documentsDenied:
            PillButton(title: "Ouvrir les R\u{00E9}glages", primary: true) { Access.openPrivacySettings() }
            PillButton(title: "R\u{00E9}essayer") { controller.retryAfterBlocker() }
        }
    }
}
