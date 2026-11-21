import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

enum DetailMode: String, CaseIterable, Identifiable {
    case editor, results
    var id: Self { self }
    var title: String { self == .editor ? "Éditeur" : "Résultats" }
    var symbol: String { self == .editor ? "square.and.pencil" : "chart.bar" }
}

struct LibraryView: View {
    @Bindable var store: LibraryStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("librarySort") private var sort: QuizSort = .modified
    @AppStorage("inspectorVisible") private var inspectorVisible = false
    @State private var mode: DetailMode = .editor
    @State private var confirmPurge = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } content: {
            QuizListView(store: store, sort: $sort, present: present)
        } detail: {
            detail
                .inspector(isPresented: $inspectorVisible) {
                    Group {
                        if let quiz = store.selectedQuiz, !quiz.isDeleted {
                            QuizInspector(store: store, code: quiz.code)
                        } else {
                            ContentUnavailableView("Aucune sélection", systemImage: "info.circle",
                                                   description: Text("Sélectionnez un questionnaire pour voir son rangement et ses réglages."))
                        }
                    }
                    .inspectorColumnWidth(min: 260, ideal: 290, max: 380)
                }
        }
        .searchable(text: $store.search, placement: .toolbar, prompt: "Titre, code ou étiquette")
        .frame(minWidth: 1000, minHeight: 640)
        .task { await store.automaticSyncLoop() }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active: Task { await store.synchronize() }
            case .background: store.flush()
            default: break
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = store.notice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.callout)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .glassEffect(.regular, in: .capsule)
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(5))
                        if store.notice == notice { withAnimation { store.notice = nil } }
                    }
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.smooth, value: store.notice)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: DebugSnapshots.present)) { note in
            if let code = note.object as? String { openWindow(id: "presentation", value: code) }
        }
        #endif
    }

    @ViewBuilder private var detail: some View {
        let selected = store.selectedQuizzes
        if let quiz = store.selectedQuiz {
            Group {
                if quiz.isDeleted {
                    ContentUnavailableView {
                        Label(quiz.title.isEmpty ? "Sans titre" : quiz.title, systemImage: "trash")
                    } description: { Text("Ce questionnaire se trouve dans la corbeille.") }
                    actions: {
                        Button("Remettre en place") { store.restore([quiz.code]) }.buttonStyle(.glassProminent)
                        Button("Supprimer définitivement…", role: .destructive) { confirmPurge = true }
                    }
                    .confirmationDialog("Supprimer définitivement ce questionnaire ?", isPresented: $confirmPurge, titleVisibility: .visible) {
                        Button("Supprimer définitivement", role: .destructive) { store.purge([quiz.code]) }
                    } message: { Text("Ses réponses seront aussi supprimées, sur ce Mac et sur le compte synchronisé.") }
                } else if mode == .results {
                    ResultsView(store: store, quiz: quiz)
                } else {
                    QuizEditor(store: store, code: quiz.code).id(quiz.code)
                }
            }
            .navigationTitle(quiz.title.isEmpty ? "Sans titre" : quiz.title)
            .navigationSubtitle(subtitle(for: quiz))
            .toolbar { if !quiz.isDeleted { quizToolbar(quiz) } }
        } else if selected.count > 1 {
            MultipleSelectionView(store: store, quizzes: selected)
                .navigationTitle("\(selected.count) questionnaires")
                .toolbar { inspectorToolbar }
        } else {
            ContentUnavailableView {
                Label("Votre espace de questions", systemImage: "rectangle.stack")
            } description: {
                Text("Sélectionnez un questionnaire ou créez-en un nouveau.")
            } actions: {
                Button("Nouveau questionnaire", action: store.create).buttonStyle(.glassProminent).disabled(store.readOnly)
            }
            .toolbar { inspectorToolbar }
        }
    }

    @ToolbarContentBuilder private func quizToolbar(_ quiz: Quiz) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Affichage", selection: $mode) {
                ForEach(DetailMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleOnly)
            .help("Basculer entre l’éditeur et les résultats")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Présenter", systemImage: "play.fill") { present(quiz) }
                .buttonStyle(.glassProminent)
                .help("Présenter le questionnaire (⌥⌘P)")
            Menu {
                QuizActions(store: store, codes: [quiz.code], purge: { _ in }, present: present)
            } label: { Label("Actions", systemImage: "ellipsis") }
            .menuIndicator(.hidden)
            .help("Autres actions")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        inspectorToolbar
    }

    private var inspectorToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Inspecteur", systemImage: "sidebar.trailing") { withAnimation { inspectorVisible.toggle() } }
                .help(inspectorVisible ? "Masquer l’inspecteur" : "Afficher l’inspecteur")
        }
    }

    private func subtitle(for quiz: Quiz) -> String {
        if store.liveCode == quiz.code { return "Session en direct" }
        var parts = [quiz.questions.count == 1 ? "1 question" : "\(quiz.questions.count) questions"]
        if let folder = store.folder(of: quiz) { parts.append(folder.name) }
        if store.connected && store.isPending(quiz) { parts.append("modifications à synchroniser") }
        return parts.joined(separator: " · ")
    }

    private func present(_ quiz: Quiz) {
        if let message = quiz.validationMessage { store.report(message) }
        else { openWindow(id: "presentation", value: quiz.code) }
    }
}

struct MultipleSelectionView: View {
    let store: LibraryStore
    let quizzes: [Quiz]
    var body: some View {
        let codes = Set(quizzes.map(\.code))
        let deleted = quizzes.allSatisfy(\.isDeleted)
        ContentUnavailableView {
            Label("\(quizzes.count) questionnaires sélectionnés", systemImage: "square.stack.3d.up")
        } description: {
            Text(deleted ? "Ces questionnaires se trouvent dans la corbeille." : "Rangez-les dans un dossier, ajoutez-les aux favoris ou exportez-les ensemble.")
        } actions: {
            if deleted {
                Button("Remettre en place") { store.restore(codes) }.buttonStyle(.glassProminent)
            } else {
                Menu("Déplacer vers") {
                    Button("Aucun dossier") { store.move(codes, to: nil) }
                    ForEach(store.visibleFolders) { folder in Button(folder.name) { store.move(codes, to: folder.id) } }
                    Divider()
                    Button("Nouveau dossier avec la sélection") { store.createFolder(with: codes) }
                }
                .fixedSize()
                Button("Exporter…") { store.exportBackup(only: codes) }
            }
        }
    }
}
