import Foundation
import UniformTypeIdentifiers

/// Nature d'un element du dossier surveille, deduite de son extension (UTType), jamais de son contenu.
public enum FileKind: String, Codable, Sendable, CaseIterable {
    case folder, application, installer, diskImage, archive, image, movie, audio, pdf
    case spreadsheet, presentation, document, font, other

    /// Paquets d'installation : pas de constante UTType publique.
    static let installerExtensions: Set<String> = ["pkg", "mpkg"]

    public static func classify(extension rawExtension: String, isDirectory: Bool, isPackage: Bool) -> FileKind {
        let ext = rawExtension.lowercased()
        if isDirectory {
            if ext == "app" { return .application }
            if !isPackage { return .folder }
        }
        if installerExtensions.contains(ext) { return .installer }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return isDirectory ? .folder : .other }
        if type.conforms(to: .applicationBundle) { return .application }
        if type.conforms(to: UTType("com.apple.installer-package-archive") ?? .package) { return .installer }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .archive) || type.conforms(to: .zip) { return .archive }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .movie }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .spreadsheet) || type.conforms(to: .commaSeparatedText)
            || type.conforms(to: .tabSeparatedText) { return .spreadsheet }
        if type.conforms(to: .presentation) { return .presentation }
        if type.conforms(to: .font) { return .font }
        if type.conforms(to: .text) || type.conforms(to: .compositeContent) || type.conforms(to: .rtf)
            || ["doc", "docx", "odt", "pages"].contains(ext) { return .document }
        return isDirectory ? .folder : .other
    }

    /// Libelle au singulier, en minuscules (" image ", " installeur ").
    public var label: String {
        switch self {
        case .folder: "dossier"
        case .application: "app"
        case .installer: "installeur"
        case .diskImage: "image disque"
        case .archive: "archive"
        case .image: "image"
        case .movie: "vid\u{00E9}o"
        case .audio: "son"
        case .pdf: "PDF"
        case .spreadsheet: "tableur"
        case .presentation: "pr\u{00E9}sentation"
        case .document: "document"
        case .font: "police"
        case .other: "fichier"
        }
    }
}
