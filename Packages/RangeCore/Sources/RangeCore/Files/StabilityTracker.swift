import Foundation

/// Un fichier n'est stable que s'il a ete vu deux fois, a au moins `window` secondes d'ecart, avec
/// le meme inode, la meme taille et la meme date de modification. Pas de raccourci : un fichier
/// jamais vu attend la passe suivante.
public struct StabilityTracker: Sendable {
    public static let window: TimeInterval = 15

    private struct Seen: Sendable {
        var signature: FileSignature
        var since: Date
    }
    private var seen: [String: Seen] = [:]

    public init() {}

    /// Note la passe : une signature nouvelle repart de zero, un chemin absent est oublie.
    public mutating func observe(_ facts: [FileFacts], now: Date) {
        var next: [String: Seen] = [:]
        for f in facts {
            if let old = seen[f.path], old.signature == f.signature {
                next[f.path] = old
            } else {
                next[f.path] = Seen(signature: f.signature, since: now)
            }
        }
        seen = next
    }

    public func isStable(_ f: FileFacts, now: Date) -> Bool {
        guard let s = seen[f.path], s.signature == f.signature else { return false }
        return now.timeIntervalSince(s.since) >= Self.window
    }

    /// Moment ou le fichier pourra etre declare stable s'il ne change plus.
    public func nextCheck(for f: FileFacts) -> Date? {
        guard let s = seen[f.path], s.signature == f.signature else { return nil }
        return s.since.addingTimeInterval(Self.window)
    }
}
