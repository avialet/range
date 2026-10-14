import Carbon.HIToolbox
import SwiftUI
import VialetKit

/// Identite de l'app : le seul fichier Swift qui connait son nom, ses teintes et son glyphe.
enum Brand {
    static let name = "Range"
    static let displayName = "Range"
    /// Teintes de l'affiche (sites, plaques, DMG, interface), calculees par scripts/teintes.py :
    /// texte `deep` sur `background`. Une teinte par ligne `cle: 0x...` (lue par les scripts du socle).
    static let palette = AccentPalette(accent: 0xB26B2E, background: 0xB26B2E,
                                       deep: 0x210C00, pale: 0xFFEEE3,
                                       night: 0x2A1504, nightInk: 0xF7CEB1)
    /// Pictogramme de la plaque : sous-ensemble SVG absolu (M L H V C Q Z), boite 0-100, trait non rempli.
    /// Commode a deux tiroirs (poignees au centre de chaque tiroir).
    static let glyph = "M 18 16 H 82 V 86 H 18 Z M 18 51 H 82 M 40 33.5 H 60 M 40 68.5 H 60"
    /// Trait du glyphe en `deep` plutot qu'en blanc (accent trop clair pour un trait blanc).
    static let strokeDeep = false
    static let identity = AppIdentity(name: name, displayName: displayName, repository: "avialet/range",
                                      bundleIdentifier: "fr.vialet.range", palette: palette, glyph: glyph,
                                      strokeDeep: strokeDeep)
    static let updater = UpdaterConfiguration(identity)

    /// Cles UserDefaults, prefixees par le nom de l'app.
    static func key(_ suffix: String) -> String { identity.key(suffix) }
}

extension Updater {
    static let shared = Updater(configuration: Brand.updater)
}

extension HotKeyController {
    /// Ouvre la fenetre de Range : ctrl-opt-cmd-R (libre dans le portefeuille), eteint par defaut
    /// (cle `RangeHotKeyEnabled`). La touche R est au meme endroit en AZERTY et en QWERTY.
    static let shared = HotKeyController(defaultsKey: Brand.key("HotKey"), logName: Brand.displayName,
                                         initial: HotKeyShortcut(keyCode: UInt16(kVK_ANSI_R),
                                                                 modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue,
                                                                 keyName: "R"))
}

extension MenuBarPresence {
    static let shared = MenuBarPresence(app: Brand.identity)
}

/// Icone du Dock : seulement pendant qu'une fenetre est ouverte (reglage Toujours).
extension DockPresence {
    static let shared = DockPresence(app: Brand.identity)
}

/// Phrase des Reglages sur les echanges reseau : l'app peut tenir le menu rassembleur des apps vialet.app.
extension HubPresence {
    static let updateNote = "\u{00C9}changes r\u{00E9}seau de \(Brand.displayName) : la derni\u{00E8}re version publi\u{00E9}e sur GitHub et, quand son ic\u{00F4}ne rassemble vos apps vialet.app, celle de ces apps et le catalogue de vialet.app une fois par jour. Aucune donn\u{00E9}e n'est envoy\u{00E9}e."
}
