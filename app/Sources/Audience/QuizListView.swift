import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct QuizListView: View {
    @Bindable var store: LibraryStore
    @Binding var sort: QuizSort
    var present: (Quiz) -> Void
    @State private var purgeCodes: Set<String> = []

    var body: some View {
        let quizzes = store.listedQuizzes(sort: sort)
        let section = store.sidebar ?? .all
        let showsFolder = !isFolder(section)
        // The row identity includes what sets its height: macOS keeps a row's first measured
        // height, so adding a tag or lengthening the title would otherwise clip the row.
        List(selection: $store.selection) {
            ForEach(quizzes, id: \.layoutKey) { quiz in
                QuizRow(store: store, quiz: quiz, showsFolder: showsFolder)
                    .tag(quiz.code)
                    .draggable(quiz.code) {
                        Label(quiz.title.isEmpty ? "Sans titre" : quiz.title, systemImage: "doc.text")
                            .padding(8).glassEffect(.regular, in: .rect(cornerRadius: 10))
                    }
            }
        }
        .contextMenu(forSelectionType: String.self) { codes in
            QuizActions(store: store, codes: codes, purge: { purgeCodes = $0 }, present: present)
        } primaryAction: { codes in
            if codes.count == 1, let quiz = codes.first.flatMap({ store.archive.quizzes[$0] }), !quiz.isDeleted { present(quiz) }
        }
        .onDeleteCommand {
            if section == .trash { purgeCodes = store.selection } else { store.moveToTrash(store.selection) }
        }
        .overlay {
            if quizzes.isEmpty {
                if store.syncing && section == .all && store.search.isEmpty {
                    ProgressView("Chargement des questionnaires…")
                } else {
                    ContentUnavailableView {
                        Label(store.search.isEmpty ? emptyTitle(section) : "Aucun résultat", systemImage: store.search.isEmpty ? section.symbol : "magnifyingglass")
                    } description: {
                        Text(emptyMessage(section))
                    } actions: {
                        if store.search.isEmpty && section != .trash {
                            Button("Nouveau questionnaire", action: store.create).disabled(store.readOnly)
                            if section == .all {
                                Button("Importer un questionnaire…") { store.importing = true }.buttonStyle(.link).disabled(store.readOnly)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(store.title(of: section))
        .navigationSubtitle(quizzes.count == 1 ? "1 questionnaire" : "\(quizzes.count) questionnaires")
        .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 420)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Trier par", selection: $sort) {
                        ForEach(QuizSort.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.inline)
                } label: { Label("Trier", systemImage: "arrow.up.arrow.down") }
                .help("Trier les questionnaires")
                if section == .trash {
                    Button("Vider la corbeille", systemImage: "trash.slash") { purgeCodes = Set(quizzes.map(\.code)) }
                        .disabled(quizzes.isEmpty).help("Supprimer définitivement tout le contenu de la corbeille")
                } else {
                    Button("Nouveau questionnaire", systemImage: "square.and.pencil", action: store.create)
                        .disabled(store.readOnly).help("Nouveau questionnaire (⌘N)")
                }
            }
        }
        .onChange(of: store.sidebar) {
            let visible = Set(store.listedQuizzes(sort: sort).map(\.code))
            store.selection = store.selection.filter(visible.contains)
        }
        .confirmationDialog(purgeCodes.count > 1 ? "Supprimer définitivement \(purgeCodes.count) questionnaires ?" : "Supprimer définitivement ce questionnaire ?",
                            isPresented: Binding(get: { !purgeCodes.isEmpty }, set: { if !$0 { purgeCodes = [] } }), titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) { store.purge(purgeCodes); purgeCodes = [] }
        } message: { Text("Les réponses associées seront aussi supprimées, sur ce Mac et sur le compte synchronisé. Cette action est irréversible.") }
    }

    private func isFolder(_ item: SidebarItem) -> Bool { if case .folder = item { true } else { false } }
    private func emptyTitle(_ item: SidebarItem) -> String {
        switch item {
        case .all: "Aucun questionnaire"
        case .favorites: "Aucun favori"
        case .trash: "La corbeille est vide"
        case .folder: "Dossier vide"
        case .tag: "Aucun questionnaire"
        }
    }
    private func emptyMessage(_ item: SidebarItem) -> String {
        if !store.search.isEmpty { return "Essayez un autre titre, code ou étiquette." }
        switch item {
        case .all: return "Créez vos questions, même sans connexion."
        case .favorites: return "Retrouvez ici les questionnaires marqués d’une étoile."
        case .trash: return "Les questionnaires supprimés apparaîtront ici."
        case .folder: return "Glissez des questionnaires sur ce dossier dans la barre latérale, ou créez-en un ici."
        case .tag: return "Aucun questionnaire ne porte cette étiquette."
        }
    }
}

struct QuizRow: View {
    let store: LibraryStore
    let quiz: Quiz
    var showsFolder = true
    @Environment(\.backgroundProminence) private var prominence

    private var selected: Bool { prominence == .increased }

    var body: some View {
        let tint = store.displayColor(of: quiz)?.color
        let folder = showsFolder ? store.folder(of: quiz) : nil
        HStack(alignment: .top, spacing: 12) {
            QuizTile(symbol: dominantSymbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(quiz.title.isEmpty ? "Sans titre" : quiz.title).font(.headline).lineLimit(2)
                    Spacer(minLength: 4)
                    if store.liveCode == quiz.code {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(selected ? .white : .green)
                            .symbolEffect(.variableColor.iterative, isActive: true).accessibilityLabel("En direct")
                    }
                    if quiz.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(selected ? .white : .orange).accessibilityLabel("Favori")
                    }
                }
                HStack(spacing: 5) {
                    Text(relativeDate)
                    Text("·").foregroundStyle(.tertiary)
                    Text(quiz.questions.count == 1 ? "1 question" : "\(quiz.questions.count) questions")
                }
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if folder != nil || !quiz.tags.isEmpty {
                    FlowLayout(spacing: 5) {
                        if let folder {
                            Chip(text: folder.name, symbol: "folder.fill", tint: folder.quizColor.color, selected: selected)
                        }
                        ForEach(quiz.tags.prefix(3), id: \.self) { tag in
                            Chip(text: "#\(tag)", symbol: nil, tint: nil, selected: selected)
                        }
                        if quiz.tags.count > 3 {
                            Text("+\(quiz.tags.count - 3)").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// The most frequent question kind gives the tile its symbol.
    private var dominantSymbol: String {
        let counts = Dictionary(grouping: quiz.questions.map(\.kind), by: { $0 }).mapValues(\.count)
        guard let kind = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue })?.key else {
            return "doc.text"
        }
        return switch kind {
        case .multiple: "list.bullet"
        case .checkbox: "checklist"
        case .open: "text.alignleft"
        case .wordcloud: "cloud.fill"
        case .rating: "star.fill"
        case .cloze: "text.badge.plus"
        case .video: "play.fill"
        case .ranking: "list.number"
        case .labelimage: "photo.fill"
        }
    }

    private var relativeDate: String {
        let date = quiz.updatedAt, calendar = Calendar.current
        if date == .distantPast { return "Sans date" }
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Hier" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// Rounded tile in the questionnaire color, showing its main question kind.
private struct QuizTile: View {
    let symbol: String
    let tint: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            .frame(width: 34, height: 34)
            .background {
                if let tint {
                    shape.fill(tint.gradient)
                } else {
                    shape.fill(.quaternary)
                }
            }
            .overlay { shape.strokeBorder(.white.opacity(tint == nil ? 0 : 0.18), lineWidth: 0.5) }
            .shadow(color: (tint ?? .clear).opacity(0.25), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

/// Small capsule for a folder or a tag; tinted, or white on a selected row.
private struct Chip: View {
    let text: String
    let symbol: String?
    let tint: Color?
    let selected: Bool

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7).padding(.vertical, 2)
        .foregroundStyle(selected ? AnyShapeStyle(.white) : tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
        .background(Capsule().fill(selected ? AnyShapeStyle(.white.opacity(0.2)) : tint.map { AnyShapeStyle($0.opacity(0.14)) } ?? AnyShapeStyle(.quinary)))
    }
}

private extension Quiz {
    /// Changes whenever the row's height may change; used as the list row identity.
    var layoutKey: String { [code, title, folderID ?? "", tags.joined(separator: "\u{1F}")].joined(separator: "\u{1E}") }
}

/// Actions shared by the list's context menu, the toolbar and the menu bar.
struct QuizActions: View {
    let store: LibraryStore
    let codes: Set<String>
    var purge: (Set<String>) -> Void
    var present: (Quiz) -> Void

    var body: some View {
        let quizzes = codes.compactMap { store.archive.quizzes[$0] }
        if quizzes.isEmpty {
            Button("Nouveau questionnaire", systemImage: "square.and.pencil", action: store.create)
        } else if quizzes.allSatisfy(\.isDeleted) {
            Button("Remettre en place", systemImage: "arrow.uturn.backward") { store.restore(codes) }
            Button("Supprimer définitivement…", systemImage: "trash.slash", role: .destructive) { purge(codes) }
        } else {
            let active = Set(quizzes.filter { !$0.isDeleted }.map(\.code))
            if quizzes.count == 1, let quiz = quizzes.first {
                Button("Présenter", systemImage: "play.rectangle") { present(quiz) }
                Divider()
            }
            let allFavorite = quizzes.allSatisfy(\.isFavorite)
            Button(allFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: allFavorite ? "star.slash" : "star") {
                store.setFavorite(active, !allFavorite)
            }
            Menu {
                Button("Aucun dossier") { store.move(active, to: nil) }
                if !store.visibleFolders.isEmpty { Divider() }
                ForEach(store.visibleFolders) { folder in
                    Button(folder.name, systemImage: "folder") { store.move(active, to: folder.id) }
                }
                Divider()
                Button("Nouveau dossier avec la sélection", systemImage: "folder.badge.plus") { store.createFolder(with: active) }
            } label: { Label("Déplacer vers", systemImage: "folder") }
            Menu {
                Button("Automatique") { store.setColor(active, nil) }
                Divider()
                ForEach(QuizColor.allCases) { color in
                    Button { store.setColor(active, color) } label: {
                        Label { Text(color.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(color.color) }
                    }
                }
            } label: { Label("Couleur", systemImage: "paintpalette") }
            Button("Dupliquer", systemImage: "plus.square.on.square") { store.duplicate(active) }
            Button(active.count > 1 ? "Exporter ces questionnaires…" : "Exporter ce questionnaire…", systemImage: "square.and.arrow.up") {
                store.exportBackup(only: active)
            }
            Divider()
            Button("Placer dans la corbeille", systemImage: "trash", role: .destructive) { store.moveToTrash(active) }
        }
    }
}
