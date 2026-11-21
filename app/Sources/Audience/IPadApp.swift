#if os(iOS)
import SwiftUI

@main
struct AudienceIPadApp: App {
    @State private var store = LibraryStore()
    @State private var localAI = LocalAIStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            IPadLibraryView(store: store)
                .environment(localAI)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
    }
}

struct IPadLibraryView: View {
    @Bindable var store: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("librarySort") private var sort: QuizSort = .modified
    @State private var column: NavigationSplitViewColumn = .content
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var expandedColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var mode = 0
    @State private var showSettings = false
    @State private var showInspector = false
    @State private var presentation: PresentationSelection?
    @State private var purgeCodes: Set<String> = []

    private var selection: Binding<String?> {
        Binding(get: { store.selection.first }, set: { store.selection = $0.map { [$0] } ?? [] })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $column) {
            IPadSidebar(store: store)
        } content: {
            quizList
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $store.search, prompt: "Titre, code ou étiquette")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Réglages", systemImage: "gearshape") { showSettings = true }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Importer", systemImage: "square.and.arrow.down") { store.importing = true }
                    .disabled(store.readOnly)
            }
        }
        .sheet(isPresented: $showSettings) { IPadSettingsView(store: store) }
        .sheet(isPresented: Binding(get: { !showSettings && store.importing }, set: { if !$0 && !showSettings { store.importing = false } })) { ImportSheet(store: store) }
        .sheet(isPresented: $showInspector) {
            NavigationStack {
                if let quiz = store.selectedQuiz {
                    QuizInspector(store: store, code: quiz.code)
                        .navigationTitle("Réglages du questionnaire")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { showInspector = false } } }
                }
            }
        }
        .fullScreenCover(item: $presentation) { item in
            PresentationView(store: store, code: item.id)
                .interactiveDismissDisabled(store.liveCode != nil)
        }
        .modifier(AudienceDialogs(store: store, active: !showSettings && presentation == nil && !showInspector && !store.importing))
        .confirmationDialog("Supprimer définitivement ces questionnaires et leurs réponses ?", isPresented: Binding(
            get: { !purgeCodes.isEmpty }, set: { if !$0 { purgeCodes = [] } }), titleVisibility: .visible) {
                Button("Supprimer définitivement", role: .destructive) { store.purge(purgeCodes); purgeCodes = [] }
            }
        .overlay(alignment: .bottom) {
            if let notice = store.notice {
                Text(notice).font(.callout).padding(14)
                    .glassEffect(.regular, in: .capsule).padding(.bottom, 60)
                    .accessibilityAddTraits(.updatesFrequently)
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(4))
                        if store.notice == notice { store.notice = nil }
                    }
            }
        }
        .task {
            #if DEBUG
            if let screen = ProcessInfo.processInfo.environment["AUDIENCE_IPAD_PREVIEW"] {
                preparePreview(screen)
                return
            }
            #endif
            await store.connectSaved()
        }
        .task { await store.automaticSyncLoop() }
        .onChange(of: store.selection) { if store.selectedQuiz != nil { column = .detail } }
        .onChange(of: scenePhase) {
            if scenePhase == .background { store.flush() }
            if scenePhase == .active {
                Task {
                    if store.savedLoginPending { await store.connectSaved() }
                    await store.synchronize()
                }
            }
        }
    }

    private var quizList: some View {
        let quizzes = store.listedQuizzes(sort: sort)
        return List(selection: selection) {
            ForEach(quizzes, id: \.code) { quiz in
                NavigationLink(value: quiz.code) {
                    QuizRow(store: store, quiz: quiz, highlighted: sizeClass == .regular && selection.wrappedValue == quiz.code)
                }
                    .draggable(quiz.code)
                    .contextMenu {
                        QuizActions(store: store, codes: [quiz.code], purge: { purgeCodes = $0 }, present: present)
                    }
            }
        }
        .navigationTitle(store.title(of: store.sidebar ?? .all))
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        .overlay {
            if quizzes.isEmpty {
                if store.syncing { ProgressView("Chargement…") }
                else {
                    ContentUnavailableView(store.search.isEmpty ? "Aucun questionnaire" : "Aucun résultat", systemImage: "rectangle.stack",
                        description: Text(store.search.isEmpty ? "Créez ou importez un questionnaire." : "Essayez un autre titre, code ou étiquette."))
                }
            }
        }
        .toolbar {
            if sizeClass == .regular, store.selectedQuiz != nil {
                ToolbarItem(placement: .primaryAction) {
                    libraryToggle
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Trier", systemImage: "arrow.up.arrow.down") {
                    Picker("Trier par", selection: $sort) { ForEach(QuizSort.allCases) { Text($0.title).tag($0) } }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Nouveau questionnaire", systemImage: "square.and.pencil", action: store.create)
                    .disabled(store.readOnly).keyboardShortcut("n")
            }
        }
        .onChange(of: store.sidebar) {
            store.selection = []
            column = .content
        }
    }

    @ViewBuilder private var detail: some View {
        if let quiz = store.selectedQuiz {
            VStack(spacing: 0) {
                if !quiz.isDeleted {
                    Picker("Affichage", selection: $mode) {
                        Text("Éditeur").tag(0)
                        Text("Résultats").tag(1)
                        Text("Statistiques").tag(2)
                    }.pickerStyle(.segmented).padding()
                }
                if quiz.isDeleted {
                    ContentUnavailableView {
                        Label("Dans la corbeille", systemImage: "trash")
                    } description: { Text(quiz.title) } actions: {
                        Button("Remettre en place") { store.restore([quiz.code]) }
                        Button("Supprimer définitivement…", role: .destructive) { purgeCodes = [quiz.code] }
                    }
                } else {
                    switch mode {
                    case 1: ResultsView(store: store, quiz: quiz)
                    case 2: StatisticsView(store: store, quiz: quiz).id(quiz.code)
                    default: QuizEditor(store: store, code: quiz.code).id(quiz.code)
                    }
                }
            }
            .navigationTitle(quiz.title.isEmpty ? "Sans titre" : quiz.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !quiz.isDeleted {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Présenter", systemImage: "play.fill") { present(quiz) }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Actions", systemImage: "ellipsis.circle") {
                            Button("Réglages du questionnaire", systemImage: "slider.horizontal.3") { showInspector = true }
                            Divider()
                            QuizActions(store: store, codes: [quiz.code], purge: { purgeCodes = $0 }, present: present)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("Votre espace de questions", systemImage: "rectangle.stack")
            } description: { Text("Sélectionnez un questionnaire ou créez-en un nouveau.") } actions: {
                Button("Nouveau questionnaire", action: store.create).buttonStyle(.glassProminent).disabled(store.readOnly)
            }
        }
    }

    private var libraryToggle: some View {
        Button(columnVisibility == .detailOnly ? "Afficher les questionnaires" : "Masquer les questionnaires", systemImage: "sidebar.left") {
            withAnimation {
                if columnVisibility == .detailOnly {
                    columnVisibility = expandedColumnVisibility
                } else {
                    expandedColumnVisibility = columnVisibility
                    columnVisibility = .detailOnly
                }
            }
        }
        .help(columnVisibility == .detailOnly ? "Afficher les questionnaires" : "Masquer les questionnaires")
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }

    #if DEBUG
    /// Isolated simulator fixtures, using a separate library supplied by the build scripts.
    private func preparePreview(_ screen: String) {
        guard ProcessInfo.processInfo.environment["AUDIENCE_LIBRARY"] != nil else { return }
        if store.archive.quizzes.isEmpty {
            _ = store.importText(ImportSheet.example.replacingOccurrences(of: "Titre du questionnaire", with: "Le vocabulaire du théâtre"))
        }
        let wanted = ProcessInfo.processInfo.environment["AUDIENCE_IPAD_QUIZ"]
        guard let quiz = store.visibleQuizzes.first(where: { $0.code == wanted }) ?? store.visibleQuizzes.first else { return }
        store.selection = [quiz.code]
        store.notice = nil
        if screen == "statistics" || screen == "results" {
            store.archive.responses[quiz.code] = .object(["questions": .array([.object([
                "questionIndex": .number(0), "results": .object(["0": .number(3), "1": .number(12)]), "total": .number(15)
            ])])])
            mode = screen == "results" ? 1 : 2
        }
        switch screen {
        case "presentation": presentation = PresentationSelection(id: quiz.code)
        case "settings": showSettings = true
        case "import": store.importing = true
        case "inspector": showInspector = true
        default: break
        }
    }
    #endif

    private func present(_ quiz: Quiz) {
        if let message = quiz.validationMessage { store.report(message) }
        else { presentation = PresentationSelection(id: quiz.code) }
    }
    private struct PresentationSelection: Identifiable { let id: String }
}

struct IPadSidebar: View {
    @Bindable var store: LibraryStore
    @State private var folderToRename: String?
    @State private var name = ""
    @State private var folderToDelete: String?
    @State private var emptyTrash = false

    var body: some View {
        VStack(spacing: 0) {
            sidebarList
                .frame(maxHeight: .infinity)
            Divider()
            syncFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle("Audience")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        .alert("Nom du dossier", isPresented: Binding(get: { folderToRename != nil }, set: { if !$0 { folderToRename = nil } })) {
            TextField("Nom", text: $name)
            Button("Enregistrer") { if let id = folderToRename { store.renameFolder(id, to: name) }; folderToRename = nil }
            Button("Annuler", role: .cancel) { folderToRename = nil }
        }
        .confirmationDialog("Supprimer ce dossier ? Les questionnaires seront conservés.", isPresented: Binding(
            get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }), titleVisibility: .visible) {
                Button("Supprimer le dossier", role: .destructive) { if let id = folderToDelete { store.deleteFolder(id) }; folderToDelete = nil }
            }
        .confirmationDialog("Vider la corbeille et supprimer définitivement ses réponses ?", isPresented: $emptyTrash, titleVisibility: .visible) {
            Button("Vider la corbeille", role: .destructive) { store.emptyTrash() }
        }
    }

    private var sidebarList: some View {
        List(selection: $store.sidebar) {
            row(.all)
            row(.favorites)
            Section("Dossiers") {
                ForEach(store.visibleFolders) { folder in
                    NavigationLink(value: SidebarItem.folder(folder.id)) {
                        Label(folder.name, systemImage: "folder.fill").foregroundStyle(folder.quizColor.color)
                    }
                    .dropDestination(for: String.self) { codes, _ in store.move(Set(codes), to: folder.id); return true }
                    .contextMenu {
                        Button("Renommer", systemImage: "pencil") { name = folder.name; folderToRename = folder.id }
                        Menu("Couleur", systemImage: "paintpalette") {
                            ForEach(QuizColor.allCases) { color in Button(color.title) { store.setFolderColor(folder.id, color) } }
                        }
                        Button("Supprimer le dossier…", systemImage: "trash", role: .destructive) { folderToDelete = folder.id }
                    }
                }
                Button("Nouveau dossier", systemImage: "folder.badge.plus") {
                    folderToRename = store.createFolder(rename: false)
                    name = "Nouveau dossier"
                }.disabled(store.readOnly)
            }
            if !store.allTags.isEmpty {
                Section("Étiquettes") { ForEach(store.allTags, id: \.self) { row(.tag($0)) } }
            }
            Section {
                row(.trash).contextMenu {
                    Button("Vider la corbeille…", systemImage: "trash.slash", role: .destructive) { emptyTrash = true }
                        .disabled(store.quizzes(in: .trash).isEmpty)
                }
            }
        }
    }
    private func row(_ item: SidebarItem) -> some View {
        NavigationLink(value: item) { Label(store.title(of: item), systemImage: item.symbol).badge(store.quizzes(in: item).count) }
    }

    private var syncFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: store.connected ? (store.syncError == nil ? "checkmark.icloud" : "exclamationmark.icloud") : "internaldrive")
                .foregroundStyle(store.syncError == nil ? Color.secondary : Color.orange)
                .symbolEffect(.pulse, isActive: store.syncing)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.connected ? store.accountName : "Sur cet iPad")
                    .font(.callout).lineLimit(1)
                Text(store.syncStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if store.connected {
                Button("Synchroniser", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.synchronize(showErrors: true) }
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(store.syncing || store.busy || store.liveCode != nil)
                .help(store.syncError ?? "Synchroniser maintenant")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .background(.bar, ignoresSafeAreaEdges: [])
    }
}
#endif
