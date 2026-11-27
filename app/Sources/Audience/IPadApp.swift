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
    @ScaledMetric(relativeTo: .body) private var columnWidth = IPadColumn.width
    @AppStorage("librarySort") private var sort: QuizSort = .modified
    @State private var column: NavigationSplitViewColumn = .content
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var mode = 0
    @State private var home = ["home", "assistant", nil].contains(ProcessInfo.processInfo.environment["AUDIENCE_IPAD_PREVIEW"])
    @State private var assistant = false
    @State private var showSettings = false
    @State private var showInspector = false
    @State private var presentation: PresentationSelection?
    @State private var purgeCodes: Set<String> = []
    @State private var tagCodes: Set<String> = []
    @State private var tagName = ""
    @State private var detailWidth: CGFloat = 0

    private var selection: Binding<String?> {
        Binding(get: { store.selection.first }, set: { store.selection = $0.map { [$0] } ?? [] })
    }

    var body: some View {
        Group {
            if home {
                IPadHomeView(
                    store: store,
                    newQuiz: { store.sidebar = .all; store.create(); openEditor() },
                    createWithAI: { assistant = true },
                    openLibrary: showLibrary,
                    openQuiz: { code in store.sidebar = .all; store.selection = [code]; openEditor() },
                    showImport: { store.importing = true },
                    showSettings: { showSettings = true })
                    .transition(.opacity)
            } else { library.transition(.opacity) }
        }
        .sheet(isPresented: $assistant) { QuizCreationView(store: store) { assistant = false; openEditor() } }
        .sheet(isPresented: $showSettings) { IPadSettingsView(store: store) }
        .sheet(isPresented: Binding(get: { !showSettings && !assistant && store.importing }, set: { if !$0 && !showSettings { store.importing = false } })) { ImportSheet(store: store) }
        .modifier(AudienceDialogs(store: store, active: !showSettings && !assistant && presentation == nil && !showInspector && tagCodes.isEmpty && !store.importing))
        .overlay(alignment: .bottom) {
            if let notice = store.notice {
                Text(notice).font(.callout).padding(14)
                    .glassEffect(.regular, in: .capsule).padding(.bottom, home ? 28 : 60)
                    .accessibilityAddTraits(.updatesFrequently)
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(4))
                        if store.notice == notice { store.notice = nil }
                    }
            }
        }
        .task {
            #if DEBUG
            if let screen = ProcessInfo.processInfo.environment["AUDIENCE_IPAD_PREVIEW"] { preparePreview(screen); return }
            #endif
            await store.connectSaved()
        }
        .task { await store.automaticSyncLoop() }
        .onChange(of: scenePhase) {
            if scenePhase == .background { store.flush() }
            if scenePhase == .active { Task { if store.savedLoginPending { await store.connectSaved() }; await store.synchronize() } }
        }
    }

    private func openEditor() { mode = 0; home = false; foldColumns() }

    private var library: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $column) {
            IPadSidebar(store: store)
        } content: {
            quizList
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showInspector) {
            NavigationStack {
                if let quiz = store.selectedQuiz {
                    QuizInspector(store: store, code: quiz.code)
                        .navigationTitle("Réglages du questionnaire")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { DoneButton { showInspector = false } } }
                }
            }
        }
        .fullScreenCover(item: $presentation) { item in
            PresentationView(store: store, code: item.id)
                .interactiveDismissDisabled(store.liveCode != nil)
        }
        .confirmationDialog("Supprimer définitivement ces questionnaires et leurs réponses ?", isPresented: Binding(
            get: { !purgeCodes.isEmpty }, set: { if !$0 { purgeCodes = [] } }), titleVisibility: .visible) {
                Button("Supprimer définitivement", role: .destructive) { store.purge(purgeCodes); purgeCodes = [] }
            }
        .alert("Nouvelle étiquette", isPresented: Binding(get: { !tagCodes.isEmpty }, set: { if !$0 { tagCodes = [] } })) {
            TextField("Nom", text: $tagName)
            Button("Ajouter") { store.addTag(tagName, to: tagCodes); tagCodes = [] }
            Button("Annuler", role: .cancel) { tagCodes = [] }
        }
        .onChange(of: store.selection) { foldColumns() }
    }

    /// Asked from the long-press menu, so adding a tag needs no button of its own.
    private func askTag(_ codes: Set<String>) { tagName = ""; tagCodes = codes }

    private var quizList: some View {
        let quizzes = store.listedQuizzes(sort: sort)
        return List(selection: selection) {
            ForEach(quizzes, id: \.code) { quiz in
                NavigationLink(value: quiz.code) {
                    QuizRow(store: store, quiz: quiz, highlighted: sizeClass == .regular && selection.wrappedValue == quiz.code)
                }
                    .draggable(quiz.code)
                    .contextMenu {
                        QuizActions(store: store, codes: [quiz.code], purge: { purgeCodes = $0 }, present: present, newTag: askTag)
                    }
            }
        }
        .navigationTitle(store.title(of: store.sidebar ?? .all))
        .navigationSplitViewColumnWidth(min(columnWidth, IPadColumn.maximum))
        // The search belongs to the list, so it stays out of the editor's toolbar.
        .searchable(text: $store.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Titre, code ou étiquette")
        // Pull to refresh replaces the sync button: the status itself is in Settings.
        .refreshable {
            if store.connected { await store.synchronize(showErrors: true) } else { await store.connectSaved() }
        }
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
            // Side by side, these live in the editor's Actions menu; stacked, the editor is out of sight.
            if sizeClass == .compact {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Actions", systemImage: "ellipsis.circle") { libraryItems }
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
            .navigationTitle(quiz.title.isEmpty ? "Sans titre" : quiz.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                detailHomeButton
                if !quiz.isDeleted {
                    // The title is already the first field of the editor: the bar shows the three views instead.
                    ToolbarItem(placement: .principal) {
                        Picker("Affichage", selection: $mode) {
                            Text("Éditeur").tag(0)
                            Text("Résultats").tag(1)
                            Text("Statistiques").tag(2)
                        }
                        .pickerStyle(.segmented).fixedSize()
                    }
                    // The app's main action: tinted, with its name, apart from the secondary menu.
                    ToolbarItem(placement: .primaryAction) {
                        // A plain HStack: the toolbar would otherwise reduce a Label to its icon.
                        Button { present(quiz) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                // The name only when the bar has room for it beside the three views.
                                if detailWidth >= 720 { Text("Présenter") }
                            }
                            .fontWeight(.semibold).foregroundStyle(.white)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Présenter")
                    }
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                actionsMenu(quiz.isDeleted ? nil : quiz)
            }
        } else {
            ContentUnavailableView {
                Label("Votre espace de questions", systemImage: "rectangle.stack")
            } description: { Text("Sélectionnez un questionnaire ou créez-en un nouveau.") } actions: {
                Button("Nouveau questionnaire", action: store.create).buttonStyle(.glassProminent).disabled(store.readOnly)
            }
            .toolbar { detailHomeButton; actionsMenu(nil) }
        }
    }

    /// The only “…” menu: the open questionnaire's actions, then the library's occasional ones.
    @ToolbarContentBuilder private func actionsMenu(_ quiz: Quiz?) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("Actions", systemImage: "ellipsis.circle") {
                if let quiz {
                    Button("Réglages du questionnaire", systemImage: "slider.horizontal.3") { showInspector = true }
                    Divider()
                    QuizActions(store: store, codes: [quiz.code], purge: { purgeCodes = $0 }, present: present, newTag: askTag, showsPresent: false)
                }
                libraryItems
            }
        }
    }

    /// Sorting, import and settings are occasional: a section of the menu instead of three buttons.
    private var libraryItems: some View {
        Section("Bibliothèque") {
            Picker("Trier par", systemImage: "arrow.up.arrow.down", selection: $sort) {
                ForEach(QuizSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            Button("Importer…", systemImage: "square.and.arrow.down") { store.importing = true }
                .disabled(store.readOnly)
            Button("Réglages", systemImage: "gearshape") { showSettings = true }
        }
    }

    /// Back to the home screen, shown as a house so it is not mistaken for the system back chevron. It sits
    /// in the editor column, which stays visible when the sidebar is folded; the selection is kept, so coming
    /// back resumes the same questionnaire.
    @ToolbarContentBuilder private var detailHomeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Accueil", systemImage: "house") { withAnimation(.smooth) { home = true } }
                .labelStyle(.iconOnly)
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityHint("Retourne à l’écran d’accueil.")
        }
    }

    private func showLibrary() {
        store.selection = []
        column = .content
        if sizeClass == .regular { columnVisibility = .all }
        withAnimation(.smooth) { home = false }
    }

    /// Opening a questionnaire gives the editor the whole screen, like a document; the system button at
    /// the top left brings the lists back. With nothing open, they come back on their own.
    private func foldColumns() {
        let open = store.selectedQuiz != nil
        if open { column = .detail }
        guard sizeClass == .regular else { return }
        if open, columnVisibility != .detailOnly {
            withAnimation { columnVisibility = .detailOnly }
        } else if !open, columnVisibility == .detailOnly {
            withAnimation { columnVisibility = .all }
        }
    }

    #if DEBUG
    /// Isolated simulator fixtures, using a separate library supplied by the build scripts.
    private func preparePreview(_ screen: String) {
        guard ProcessInfo.processInfo.environment["AUDIENCE_LIBRARY"] != nil else { return }
        if screen == "home" || screen == "assistant" {
            seedHomePreview()
            if screen == "assistant" {
                // AUDIENCE_IPAD_FAKEKEY=claude shows that service as connected, with an unusable key.
                if let service = ProcessInfo.processInfo.environment["AUDIENCE_IPAD_FAKEKEY"] {
                    UserDefaults.standard.set(service, forKey: "ai.provider")
                }
                assistant = true
            }
            return
        }
        if store.archive.quizzes.isEmpty {
            _ = store.importText(ImportSheet.example.replacingOccurrences(of: "Titre du questionnaire", with: "Le vocabulaire du théâtre"))
        }
        let wanted = ProcessInfo.processInfo.environment["AUDIENCE_IPAD_QUIZ"]
        guard let quiz = store.visibleQuizzes.first(where: { $0.code == wanted }) ?? store.visibleQuizzes.first else { return }
        store.selection = [quiz.code]
        store.notice = nil
        // AUDIENCE_IPAD_FOLD=1 folds the columns as opening a questionnaire from the home screen does.
        if ProcessInfo.processInfo.environment["AUDIENCE_IPAD_FOLD"] != nil {
            Task { try? await Task.sleep(for: .seconds(1)); foldColumns() }
        }
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

    /// A library with varied questionnaires, to judge the home screen; AUDIENCE_IPAD_EMPTY keeps it empty.
    private func seedHomePreview() {
        guard ProcessInfo.processInfo.environment["AUDIENCE_IPAD_EMPTY"] == nil, store.archive.quizzes.isEmpty else { return }
        let titles = ["L’intelligence artificielle", "Le vocabulaire du théâtre", "Le passé simple", "Molière et la comédie", "Les caractéristiques du conte"]
        let colors: [QuizColor?] = [nil, .teal, .rose, .amber, .green]
        for (index, title) in titles.enumerated() {
            let text = index == 0 ? QuizMarkdown.generationExample : ImportSheet.example.replacingOccurrences(of: "Titre du questionnaire", with: title)
            _ = store.importText(text)
        }
        let quizzes = store.visibleQuizzes.sorted { $0.title < $1.title }
        for (index, quiz) in quizzes.enumerated() {
            store.archive.quizzes[quiz.code]?.cardColor = colors[index % colors.count]
            store.archive.quizzes[quiz.code]?.isFavorite = index == 1
        }
        store.notice = nil
    }

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
    @ScaledMetric(relativeTo: .body) private var columnWidth = IPadColumn.width

    // The account and synchronization status live in Settings, not in the sidebar.
    var body: some View {
        sidebarList
        .navigationTitle("Audience")
        .navigationSplitViewColumnWidth(min(columnWidth, IPadColumn.maximum))
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
            Section {
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
                        Divider()
                        newFolderButton
                    }
                }
                if store.visibleFolders.isEmpty {
                    Text("Appui long pour créer un dossier.")
                        .font(.caption).foregroundStyle(.secondary).selectionDisabled()
                }
            } header: {
                Text("Dossiers").contextMenu { newFolderButton }
            }
            if !store.allTags.isEmpty {
                Section("Étiquettes") { ForEach(store.allTags, id: \.self) { tagRow($0) } }
            }
            Section {
                row(.trash).contextMenu {
                    Button("Vider la corbeille…", systemImage: "trash.slash", role: .destructive) { emptyTrash = true }
                        .disabled(store.quizzes(in: .trash).isEmpty)
                }
            }
        }
    }
    private var newFolderButton: some View {
        Button("Nouveau dossier", systemImage: "folder.badge.plus") {
            folderToRename = store.createFolder(rename: false)
            name = "Nouveau dossier"
        }.disabled(store.readOnly)
    }
    /// A tag is a filter, not a place: touching the selected one again lifts the filter.
    private func tagRow(_ tag: String) -> some View {
        let item = SidebarItem.tag(tag)
        let selected = store.sidebar == item
        return Button { store.sidebar = selected ? .all : item } label: {
            Label(tag, systemImage: item.symbol).badge(store.quizzes(in: item).count)
        }
        .foregroundStyle(.primary)
        .listRowBackground(selected ? Color.accentColor.opacity(0.25) : nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func row(_ item: SidebarItem) -> some View {
        let title: String = if case .tag(let tag) = item { tag } else { store.title(of: item) }
        return NavigationLink(value: item) { Label(title, systemImage: item.symbol).badge(store.quizzes(in: item).count) }
    }
}
#endif
