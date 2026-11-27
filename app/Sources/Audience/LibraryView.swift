#if os(macOS)
import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

enum DetailMode: String, CaseIterable, Identifiable {
    case editor, results, statistics
    var id: Self { self }
    var title: String { switch self { case .editor: "Éditeur"; case .results: "Résultats"; case .statistics: "Statistiques" } }
    var symbol: String { switch self { case .editor: "square.and.pencil"; case .results: "chart.bar"; case .statistics: "chart.bar.xaxis" } }
}

struct LibraryView: View {
    @Bindable var store: LibraryStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("librarySort") private var sort: QuizSort = .modified
    @AppStorage("inspectorVisible") private var inspectorVisible = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var mode: DetailMode = .editor
    @State private var confirmPurge = false

    var body: some View {
        Group {
            if store.showingHome {
                IPadHomeView(
                    store: store,
                    newQuiz: { store.sidebar = .all; store.create(); openEditor() },
                    createWithAI: { store.showingAssistant = true },
                    openLibrary: showLibrary,
                    openQuiz: { code in store.sidebar = .all; store.selection = [code]; openEditor() },
                    showImport: { store.importing = true },
                    showSettings: { openSettings() })
                    .transition(.opacity)
            } else {
                library.transition(.opacity)
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .task { await store.connectSaved() }
        .task { await store.automaticSyncLoop() }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                Task {
                    if store.savedLoginPending { await store.connectSaved() }
                    await store.synchronize()
                }
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
        .sheet(isPresented: $store.showingAssistant) {
            QuizCreationView(store: store) { store.showingAssistant = false; openEditor() }
        }
        .sheet(isPresented: Binding(get: { !store.showingAssistant && store.importing }, set: { if !$0 { store.importing = false } })) {
            ImportSheet(store: store)
        }
        .sheet(isPresented: Binding(get: { !store.showingAssistant && !store.importing && store.termsPending }, set: { _ in })) {
            TermsSheet(store: store)
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: DebugSnapshots.present)) { note in
            if let code = note.object as? String { openWindow(id: "presentation", value: code) }
        }
        #endif
    }

    private var library: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
        .onChange(of: store.selection) { foldColumns() }
    }

    private func openEditor() {
        mode = .editor
        store.showingHome = false
        foldColumns()
    }

    private func showLibrary() {
        store.selection = []
        columnVisibility = .all
        withAnimation(.smooth) { store.showingHome = false }
    }

    /// Opening a questionnaire folds the sidebar so the editor gets the room; with nothing open, it comes back.
    /// Only the full three-column layout is folded, so a library the user hid stays hidden.
    private func foldColumns() {
        let open = !store.selection.isEmpty
        if open, columnVisibility == .all {
            withAnimation { columnVisibility = .doubleColumn }
        } else if !open, columnVisibility == .doubleColumn {
            withAnimation { columnVisibility = .all }
        }
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
                    } message: { Text("Ses réponses seront aussi supprimées, sur cet appareil et sur le compte synchronisé.") }
                } else if mode == .results {
                    ResultsView(store: store, quiz: quiz)
                } else if mode == .statistics {
                    StatisticsView(store: store, quiz: quiz).id(quiz.code)
                } else {
                    QuizEditor(store: store, code: quiz.code).id(quiz.code)
                }
            }
            .navigationTitle(quiz.title.isEmpty ? "Sans titre" : quiz.title)
            .navigationSubtitle(subtitle(for: quiz))
            .toolbar {
                detailHomeButton
                if !quiz.isDeleted { quizToolbar(quiz) } else { inspectorToolbar }
            }
        } else if selected.count > 1 {
            MultipleSelectionView(store: store, quizzes: selected)
                .navigationTitle("\(selected.count) questionnaires")
                .toolbar {
                    detailHomeButton
                    inspectorToolbar
                }
        } else {
            ContentUnavailableView {
                Label("Votre espace de questions", systemImage: "rectangle.stack")
            } description: {
                Text("Sélectionnez un questionnaire ou créez-en un nouveau.")
            } actions: {
                Button("Nouveau questionnaire", action: store.create).buttonStyle(.glassProminent).disabled(store.readOnly)
                Button("Créer avec une IA…") { store.showingAssistant = true }.buttonStyle(.glass).disabled(store.readOnly)
            }
            .toolbar {
                detailHomeButton
                inspectorToolbar
            }
        }
    }

    @ToolbarContentBuilder private var detailHomeButton: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { withAnimation(.smooth) { store.showingHome = true } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.backward").font(.body.weight(.semibold))
                    Text("Accueil")
                }
            }
            .keyboardShortcut("[", modifiers: .command)
            .help("Retour à l’écran d’accueil (⌘[)")
            .accessibilityHint("Retourne à l’écran d’accueil.")
        }
    }

    @ToolbarContentBuilder private func quizToolbar(_ quiz: Quiz) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Affichage", selection: $mode) {
                ForEach(DetailMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleOnly)
            .help("Afficher l’éditeur, les résultats ou les statistiques")
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

#endif
