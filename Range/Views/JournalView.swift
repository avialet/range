import RangeCore
import SwiftUI
import VialetKit

/// Journal : chaque lot (une passe, un clic) se defait d'un coup, ou fichier par fichier. Une ligne
/// grisee ne peut plus etre defaite (corbeille videe, fichier deplace ou remplace depuis).
struct JournalView: View {
    @Environment(RangeController.self) private var controller

    var body: some View {
        Screen(title: "Journal",
               subtitle: "Chaque rangement se d\u{00E9}fait d\u{2019}un clic. La corbeille garde les fichiers jet\u{00E9}s tant qu\u{2019}elle n\u{2019}est pas vid\u{00E9}e.") {
            EmptyView()
        } content: {
                if controller.batches.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Theme.inkFaint)
                        Text("Aucun rangement pour l\u{2019}instant.")
                            .font(Theme.ui(12.5)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
                ForEach(sections, id: \.title) { section in
                    SectionHeader(section.title)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                    ForEach(section.batches) { batch in
                        BatchCard(summary: batch)
                    }
                }
        }
        .onAppear { controller.reloadJournal() }
    }

    private var sections: [(title: String, batches: [BatchSummary])] {
        var result: [(title: String, batches: [BatchSummary])] = []
        let now = Date()
        for batch in controller.batches {
            let title = TimeBucket.bucket(for: batch.batch.date, now: now).sectionLabel
            if result.last?.title == title {
                result[result.count - 1].batches.append(batch)
            } else {
                result.append((title, [batch]))
            }
        }
        return result
    }
}

private struct BatchCard: View {
    @Environment(RangeController.self) private var controller
    let summary: BatchSummary
    @State private var expanded = false
    static let preview = 5

    var body: some View {
        let moves = summary.moves
        let shown = expanded ? moves : Array(moves.prefix(Self.preview))
        let undoable = moves.contains { controller.undoStates[$0.id ?? 0] == .undoable }
        CardBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.batch.trigger.label)
                            .font(Theme.ui(13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text("\(Format.day(summary.batch.date)) \u{00E0} \(Format.time(summary.batch.date)) \u{00B7} \(Format.files(moves.count))\(trashNote)")
                            .font(Theme.ui(11.5)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 8)
                    if summary.batch.undoneAt != nil && !undoable {
                        Chip("Annul\u{00E9}", icon: "arrow.uturn.backward", color: Theme.inkSoft)
                    } else if undoable {
                        PillButton(title: "Annuler ce lot", icon: "arrow.uturn.backward") {
                            if let id = summary.batch.id { controller.undoBatch(id) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                ForEach(shown) { move in
                    Divider().overlay(Theme.line).padding(.leading, 46)
                    MoveRow(move: move, state: controller.undoStates[move.id ?? 0] ?? .gone)
                }
                if moves.count > Self.preview {
                    Divider().overlay(Theme.line).padding(.leading, 46)
                    Button(expanded ? "Afficher moins" : "Afficher les \(moves.count - Self.preview) autres") {
                        withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.ui(12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.leading, 46)
                    .padding(.vertical, 9)
                }
            }
        }
    }

    private var trashNote: String {
        let n = summary.moves.filter { $0.kind == .trash }.count
        return n == 0 ? "" : " dont \(n) \u{00E0} la corbeille"
    }
}

private struct MoveRow: View {
    @Environment(RangeController.self) private var controller
    let move: MoveRecord
    let state: UndoState
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if state == .undoable {
                    FileIcon(path: move.destination, size: 20)
                } else {
                    Image(systemName: move.kind == .trash ? "trash" : "doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(move.name)
                    .font(Theme.ui(12.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(destination)
                    .font(Theme.ui(11)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 10)
            if state == .undoable {
                Button("Annuler") { controller.undoMove(move) }
                    .buttonStyle(.plain)
                    .font(Theme.ui(11.5, weight: .semibold))
                    .foregroundStyle(hovered ? Theme.accent : Theme.inkSoft)
                    .accessibilityLabel("Remettre \(move.name) en place")
            } else {
                Text(stateLabel).font(Theme.ui(11.5)).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .opacity(state == .undoable ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .help(state == .undoable ? Destination.abbreviate(move.destination, home: controller.paths.home) : stateLabel)
    }

    private var destination: String {
        if move.kind == .trash {
            return move.reason == TrashReason.alreadyAtDestination.rawValue
                ? "\u{2192} Corbeille (d\u{00E9}j\u{00E0} rang\u{00E9})" : "\u{2192} Corbeille"
        }
        return "\u{2192} " + Format.folder(of: move.destination, home: controller.paths.home)
    }

    private var stateLabel: String {
        switch state {
        case .undoable: ""
        case .undone: "Remis en place"
        case .gone: move.kind == .trash ? "Corbeille vid\u{00E9}e" : "D\u{00E9}plac\u{00E9} depuis"
        case .changed: "Remplac\u{00E9} depuis"
        }
    }
}
