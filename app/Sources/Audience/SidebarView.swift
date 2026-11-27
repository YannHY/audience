#if os(macOS)
import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct SidebarView: View {
    @Bindable var store: LibraryStore
    @Environment(\.openSettings) private var openSettings
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool
    @State private var folderToDelete: QuizFolder?
    @State private var confirmEmptyTrash = false
    @ScaledMetric(relativeTo: .body) private var columnWidth = IPadColumn.width

    var body: some View {
        List(selection: $store.sidebar) {
            Section {
                row(.all)
                row(.favorites)
                    .dropDestination(for: String.self) { codes, _ in store.setFavorite(Set(codes), true); return true }
            }
            Section("Dossiers") {
                ForEach(store.visibleFolders) { folder in folderRow(folder) }
                if store.visibleFolders.isEmpty {
                    Text("Glissez des questionnaires dans un nouveau dossier pour les ranger.")
                        .font(.caption).foregroundStyle(.secondary).selectionDisabled()
                }
            }
            let tags = store.allTags
            if !tags.isEmpty {
                Section("Étiquettes") {
                    ForEach(tags, id: \.self) { tag in
                        row(.tag(tag))
                            .contextMenu {
                                Button("Retirer l’étiquette de tous les questionnaires", systemImage: "tag.slash") { store.removeTag(tag) }
                            }
                            .dropDestination(for: String.self) { codes, _ in store.addTag(tag, to: Set(codes)); return true }
                    }
                }
            }
            Section {
                row(.trash)
                    .contextMenu {
                        Button("Vider la corbeille…", systemImage: "trash.slash", role: .destructive) { confirmEmptyTrash = true }
                            .disabled(store.quizzes(in: .trash).isEmpty)
                    }
                    .dropDestination(for: String.self) { codes, _ in store.moveToTrash(Set(codes)); return true }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: min(columnWidth, IPadColumn.maximum), max: IPadColumn.maximum)
        .safeAreaBar(edge: .bottom) { footer }
        .onChange(of: store.renamingFolder) {
            if let id = store.renamingFolder, let folder = store.archive.folders[id] {
                renameText = folder.name
                DispatchQueue.main.async { renameFocused = true }
            }
        }
        .onChange(of: renameFocused) { if !renameFocused { commitRename() } }
        .confirmationDialog("Supprimer le dossier « \(folderToDelete?.name ?? "") » ?", isPresented: Binding(
            get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }), titleVisibility: .visible) {
            Button("Supprimer le dossier", role: .destructive) { if let folder = folderToDelete { store.deleteFolder(folder.id) } }
        } message: { Text("Les questionnaires qu’il contient ne sont pas supprimés : ils restent dans la bibliothèque.") }
        .confirmationDialog("Vider la corbeille ?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
            Button("Supprimer définitivement", role: .destructive) { store.emptyTrash() }
        } message: { Text("Les questionnaires et leurs réponses seront supprimés de cet appareil et du compte synchronisé. Cette action est irréversible.") }
    }

    private func row(_ item: SidebarItem) -> some View {
        // The # symbol already marks a tag: the label shows the bare name.
        let title: String = if case .tag(let tag) = item { tag } else { store.title(of: item) }
        return Label(title, systemImage: item.symbol)
            .badge(store.quizzes(in: item).count)
            .tag(item)
    }

    private func folderRow(_ folder: QuizFolder) -> some View {
        Label {
            if store.renamingFolder == folder.id {
                TextField("Nom du dossier", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { renameFocused = false }
                    .onExitCommand { store.renamingFolder = nil }
            } else {
                Text(folder.name)
            }
        } icon: {
            Image(systemName: "folder.fill").foregroundStyle(folder.quizColor.color)
        }
        .badge(store.quizzes(in: .folder(folder.id)).count)
        .tag(SidebarItem.folder(folder.id))
        .dropDestination(for: String.self) { codes, _ in store.move(Set(codes), to: folder.id); return true }
        .contextMenu {
            Button("Renommer", systemImage: "pencil") { store.renamingFolder = folder.id }
            Picker(selection: Binding(get: { folder.quizColor }, set: { store.setFolderColor(folder.id, $0) })) {
                ForEach(QuizColor.allCases) { color in
                    Label { Text(color.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(color.color) }.tag(color)
                }
            } label: { Label("Couleur", systemImage: "paintpalette") }
            Divider()
            Button("Nouveau questionnaire dans ce dossier", systemImage: "square.and.pencil") {
                store.sidebar = .folder(folder.id); store.create()
            }
            Divider()
            Button("Supprimer le dossier…", systemImage: "folder.badge.minus", role: .destructive) { folderToDelete = folder }
        }
    }

    private func commitRename() {
        guard let id = store.renamingFolder else { return }
        store.renamingFolder = nil
        store.renameFolder(id, to: renameText)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Nouveau dossier", systemImage: "folder.badge.plus") { store.createFolder() }
                .buttonStyle(.borderless)
                .disabled(store.readOnly)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: store.connected ? (store.syncError == nil ? "checkmark.icloud" : "exclamationmark.icloud") : "internaldrive")
                    .foregroundStyle(store.syncError == nil ? Color.secondary : Color.orange)
                    .symbolEffect(.pulse, isActive: store.syncing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.connected ? store.accountName : "Sur ce Mac").font(.callout).lineLimit(1)
                    Text(store.syncStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if store.connected {
                    Button("Synchroniser", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await store.synchronize(showErrors: true) }
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(store.syncing || store.busy || store.liveCode != nil)
                    .help(store.syncError ?? "Synchroniser maintenant")
                } else if store.savedLoginPending {
                    Button("Réessayer la connexion", systemImage: "arrow.clockwise") {
                        Task { await store.connectSaved() }
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .disabled(store.busy).help("Se reconnecter avec le compte enregistré")
                } else {
                    Button("Se connecter", systemImage: "person.crop.circle.badge.plus") {
                        UserDefaults.standard.set(1, forKey: "settingsTab"); openSettings()
                    }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Se connecter au site Audience")
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

#endif
