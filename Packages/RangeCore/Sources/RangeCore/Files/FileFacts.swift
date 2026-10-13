import Foundation

/// Ce que Range sait d'un element du premier niveau du dossier surveille. Tout le reste
/// (detection, regles, plan) travaille sur ces faits, sans toucher au disque.
public struct FileFacts: Sendable, Equatable, Hashable {
    public var url: URL
    public var name: String
    public var isDirectory: Bool
    public var kind: FileKind
    /// Octets (0 pour un dossier).
    public var size: Int64
    public var modified: Date
    /// Arrivee dans le dossier (`addedToDirectoryDate`), a defaut la creation.
    public var added: Date
    public var inode: UInt64
    /// Adresses d'origine (`kMDItemWhereFroms`), la page puis le fichier.
    public var sources: [String]
    /// Agent de la quarantaine (« Safari », « Google Chrome »).
    public var agent: String?
    public var isScreenCapture: Bool

    public init(url: URL, name: String, isDirectory: Bool, kind: FileKind, size: Int64, modified: Date, added: Date,
                inode: UInt64, sources: [String] = [], agent: String? = nil, isScreenCapture: Bool = false) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.kind = kind
        self.size = size
        self.modified = modified
        self.added = added
        self.inode = inode
        self.sources = sources
        self.agent = agent
        self.isScreenCapture = isScreenCapture
    }

    public var path: String { url.path }

    /// Ce qui doit rester identique entre l'aperçu et le deplacement.
    public var signature: FileSignature { FileSignature(inode: inode, size: size, modified: modified) }
}

public struct FileSignature: Sendable, Equatable, Hashable {
    public var inode: UInt64
    public var size: Int64
    public var modified: Date
}
