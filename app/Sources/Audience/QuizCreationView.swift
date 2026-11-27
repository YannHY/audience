import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// "Créer avec une IA": give the content to the connected assistant, then review what it wrote.
/// Connecting an assistant belongs to the settings; the sheet only links there when none is connected.
struct QuizCreationView: View {
    let store: LibraryStore
    let finished: () -> Void

    private enum Step { case content, review }
    private enum Busy { case generating }
    private enum SourceKind { case document, photos, video }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var chatGPT = ChatGPTAuth.shared
    private let keys = AIKeyStore.shared
    @AppStorage("ai.provider") private var providerID = QuizProvider.chatGPT.rawValue
    @State private var step = Step.content
    @State private var showAssistants = false
    @State private var showProfile = false
    @AppStorage(AICustomInstructions.key) private var profile = ""
    @State private var source: SourceKind?
    @State private var document = ""
    @State private var filename = ""
    @State private var address = ""
    @State private var transcript = ""
    @State private var questionCount = 10
    @State private var instructions = ""
    @State private var draft = ""
    @State private var editMarkdown = false
    @State private var error: String?
    @State private var busy: Busy?
    @State private var operation: Task<Void, Never>?
    @State private var chooseFile = false
    @State private var dropTargeted = false
    @State private var photos: [AttachedPhoto] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    #if os(macOS)
    private let deviceLabel = "ce Mac"
    private let deviceArticle = "le Mac"
    private let tapVerb = "Cliquez sur"
    private let tapLower = "cliquez sur"
    #else
    private let deviceLabel = "cet iPad"
    private let deviceArticle = "l’iPad"
    private let tapVerb = "Touchez"
    private let tapLower = "touchez"
    #endif

    private var large: Bool { typeSize.isAccessibilitySize }
    private var provider: QuizProvider { QuizProvider(rawValue: providerID) ?? .chatGPT }
    private var connectedProviders: [QuizProvider] { QuizProvider.allCases.filter(isConnected) }
    private var video: URL? { YouTubeVideo(url: address)?.watchURL }
    private var trimmedTranscript: String { transcript.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func isConnected(_ service: QuizProvider) -> Bool {
        service.usesAccount ? chatGPT.activeAccount?.canUsePlan == true : keys.connected.contains(service)
    }
    private func status(_ service: QuizProvider) -> String {
        guard isConnected(service) else { return "Non connecté" }
        return service.usesAccount ? (chatGPT.activeAccount?.label ?? "Connecté") : "Clé enregistrée"
    }
    /// What is still missing before the questionnaire can be requested.
    private var contentIssue: String? {
        switch source {
        case nil: return trimmedRequest.isEmpty ? "Décrivez le questionnaire souhaité." : nil
        case .document: return document.isEmpty ? "Choisissez un document, ou retirez la pièce jointe." : nil
        case .photos:
            if loadingPhotos { return "Préparation des photos…" }
            if photos.isEmpty { return "Ajoutez au moins une photo." }
            if photos.count > provider.photoLimit { return "\(provider.name) accepte \(provider.photoLimit) photos au maximum : retirez-en." }
            if keys.photoModel(for: provider) == nil, !provider.usesAccount {
                return "Aucun modèle \(provider.name) de cette clé ne lit les images. Choisissez un autre assistant."
            }
            return nil
        case .video:
            if video == nil { return "Collez l’adresse d’une vidéo YouTube, ou retirez-la." }
            if !provider.readsVideo && trimmedTranscript.isEmpty { return "Collez la transcription de la vidéo." }
            return nil
        }
    }
    private var trimmedRequest: String { instructions.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedProfile: String { profile.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        if connectedProviders.isEmpty && draft.isEmpty && busy == nil { setupStep }
                        else if step == .content { contentStep }
                        else { reviewStep }
                    }
                    .transition(.opacity)
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) { if !connectedProviders.isEmpty || !draft.isEmpty { actionBar } }
            }
            .navigationTitle("Créer avec une IA")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CloseButton { operation?.cancel(); dismiss() } }
                if !connectedProviders.isEmpty, step == .content { ToolbarItem(placement: .primaryAction) { providerMenu } }
            }
            .navigationDestination(isPresented: $showAssistants) { assistantsPage }
            .navigationDestination(isPresented: $showProfile) {
                Form { AICustomInstructionsSection() }.formStyle(.grouped).navigationTitle("Instructions personnalisées")
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 760, minHeight: 620, idealHeight: 720)
        #endif
        .presentationSizing(.page)
        .presentationBackground { AudienceBackdrop() }
        .interactiveDismissDisabled(busy != nil || !draft.isEmpty)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
        .task(id: providerID) { await keys.refreshModels(provider) }
        .onAppear(perform: chooseConnectedProvider)
        .onChange(of: connectedProviders) { old, new in
            chooseConnectedProvider()
            // A fresh connection made from the settings page shows its confirmation, then comes back here.
            if showAssistants, new.count > old.count {
                if let added = new.first(where: { !old.contains($0) }) { providerID = added.rawValue }
                Task { try? await Task.sleep(for: .milliseconds(1100)); showAssistants = false }
            }
        }
        .onChange(of: providerID) { error = nil }
        .onDisappear { operation?.cancel() }
        #if DEBUG
        .task { applyPreviewState() }
        #endif
        .fileImporter(isPresented: $chooseFile, allowedContentTypes: source == .photos ? [.image] : Self.documentTypes,
                      allowsMultipleSelection: source == .photos) { result in
            switch result {
            case .success(let urls):
                if source == .photos { loadPhotoFiles(urls) } else if let url = urls.first { loadDocument(url) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription }
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            source = .photos
            loadPhotos(items)
        }
    }

    // MARK: Photos

    private static let maximumPhotos = 10
    private var remainingPhotos: Int { max(0, Self.maximumPhotos - photos.count) }

    /// Photos chosen in the Photos library, read one after the other and reduced before sending.
    private func loadPhotos(_ items: [PhotosPickerItem]) {
        loadingPhotos = true; error = nil
        Task { @MainActor in
            defer { loadingPhotos = false }
            var failed = 0
            for item in items.prefix(remainingPhotos) {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { failed += 1; continue }
                    photos.append(try await Self.prepare(data))
                } catch { failed += 1 }
            }
            if failed > 0 { error = failed == 1 ? "Une photo n’a pas pu être lue." : "\(failed) photos n’ont pas pu être lues." }
        }
    }

    /// Image files from the Files app or dropped on the panel.
    private func loadPhotoFiles(_ urls: [URL]) {
        loadingPhotos = true; error = nil
        Task { @MainActor in
            defer { loadingPhotos = false }
            var failed = 0
            for url in urls.prefix(remainingPhotos) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 40_000_000 else { failed += 1; continue }
                    photos.append(try await Self.prepare(Data(contentsOf: url)))
                } catch { failed += 1 }
            }
            if failed > 0 { error = failed == 1 ? "Une image n’a pas pu être lue." : "\(failed) images n’ont pas pu être lues." }
        }
    }

    /// Reducing a photo takes a moment: it is done away from the interface.
    private nonisolated static func prepare(_ data: Data) async throws -> AttachedPhoto {
        try await Task.detached(priority: .userInitiated) { try AttachedPhoto(data) }.value
    }

    private func loadDocument(_ url: URL) {
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 12_000_000 else {
                throw AudienceError.message("Le fichier dépasse 12 Mo.")
            }
            let content = try Self.text(of: url).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, content.utf8.count <= 240_000 else {
                throw AudienceError.message("Le document ne contient pas de texte lisible ou est trop long. Choisissez un extrait.")
            }
            document = content; filename = url.lastPathComponent; error = nil
        } catch { self.error = error.localizedDescription }
    }

    #if DEBUG
    /// AUDIENCE_IPAD_ASSISTANT_STEP opens the assistant on a given state, to inspect it in the simulator.
    private func applyPreviewState() {
        switch ProcessInfo.processInfo.environment["AUDIENCE_IPAD_ASSISTANT_STEP"] {
        case "content": step = .content
        case "video": step = .content; source = .video; address = "https://youtu.be/ARJ8cAGm6JE"
        case "review": step = .review; draft = QuizMarkdown.generationExample
        case "generating": step = .review; busy = .generating
        case "docx":
            // AUDIENCE_IPAD_DOCX=<path> loads that file as the document picker would.
            step = .content; source = .document
            if let path = ProcessInfo.processInfo.environment["AUDIENCE_IPAD_DOCX"] {
                let url = URL(filePath: path)
                do { document = try Self.text(of: url); filename = url.lastPathComponent }
                catch { self.error = error.localizedDescription }
            }
        default: break
        }
    }
    #endif

    // MARK: Documents

    /// PDF, Word (.docx), plain text and Markdown. Old .doc files can be picked, to explain why they are not read.
    private static let documentTypes = [UTType.pdf, .plainText, UTType(filenameExtension: "md"),
                                        UTType(filenameExtension: "docx"), UTType(filenameExtension: "doc")].compactMap { $0 }

    private static func text(of url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return PDFDocument(url: url)?.string ?? ""
        case "docx": return try DocxText.extract(from: Data(contentsOf: url))
        case "doc":
            throw AudienceError.message("Les anciens fichiers Word (.doc) ne sont pas lus. Ouvrez-le dans Word ou Pages, enregistrez-le au format .docx, puis choisissez-le ici.")
        default: return try String(contentsOf: url, encoding: .utf8)
        }
    }

    // MARK: Progress and actions

    private var actionBar: some View {
        GlassEffectContainer(spacing: 12) {
            let layout = large ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                if step == .review, busy != .generating {
                    Button("Retour", systemImage: "chevron.left") {
                        withAnimation { step = .content }
                    }.buttonStyle(.glass).controlSize(.large).disabled(busy != nil).iPadIconOnly()
                }
                if !large { Spacer(minLength: 0) }
                if let hint = primaryHint {
                    Text(hint).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                primaryButton
            }
        }
        .frame(maxWidth: 680).padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: .infinity)
        // A veil that fades in above the buttons, so the content scrolling under them stays out of the way.
        .background(alignment: .bottom) {
            Rectangle().fill(.regularMaterial)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45)], startPoint: .top, endPoint: .bottom))
                .padding(.top, -28).ignoresSafeArea()
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case .content:
            Button("Générer le questionnaire", systemImage: "sparkles", action: generate)
                .buttonStyle(.glassProminent).controlSize(.large)
                .disabled(contentIssue != nil || store.readOnly || busy != nil)
        case .review:
            if busy != .generating, !draft.isEmpty {
                Button("Ajouter à ma bibliothèque", systemImage: "plus", action: add)
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(reviewIssue != nil || store.readOnly)
            }
        }
    }

    private var primaryHint: String? {
        switch step {
        case .content: contentIssue
        case .review: busy == .generating ? nil : reviewIssue
        }
    }

    // MARK: Assistant

    /// Keeps the chosen assistant when it is connected, otherwise takes the first one that is.
    private func chooseConnectedProvider() {
        if !isConnected(provider), let first = connectedProviders.first { providerID = first.rawValue; error = nil }
    }

    /// Shown only when no assistant is connected yet: one way forward, to the assistants settings.
    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("Connectez d’abord un assistant", "Audience confie la rédaction à ChatGPT, Claude, Gemini ou Groq. La connexion se fait une seule fois, dans les réglages.")
            HStack(spacing: 10) { ForEach(QuizProvider.allCases) { ProviderLogo(provider: $0, size: 40) } }
            Button("Connecter un assistant", systemImage: "link") { showAssistants = true }
                .buttonStyle(.glassProminent).controlSize(.large)
        }
    }

    /// The assistant in use, changed from the toolbar; managing connections stays in the settings.
    private var providerMenu: some View {
        Menu {
            Picker("Assistant", selection: $providerID) {
                ForEach(connectedProviders) { Text($0.name).tag($0.rawValue) }
            }
            Divider()
            Button("Gérer les assistants…", systemImage: "gearshape") { showAssistants = true }
        } label: {
            HStack(spacing: 8) {
                ProviderLogo(provider: provider, size: 22)
                Text(provider.name)
            }
        }
        .accessibilityLabel("Assistant : \(provider.name)")
    }

    @ViewBuilder private var assistantsPage: some View {
        #if os(macOS)
        AIAssistantsMacView().navigationTitle("Assistants IA")
        #else
        Form { AIAssistantsSection() }
            .navigationTitle("Assistants IA")
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Step 2 — content

    private var contentStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("Quel questionnaire voulez-vous ?", "Décrivez-le à \(provider.name). Un document, des photos ou une vidéo peuvent servir de source, sans obligation.")
            requestPanel
            if let source {
                VStack(alignment: .leading, spacing: 14) {
                    switch source {
                    case .document: documentPanel
                    case .photos: attachmentHeader("Photos", "photo.on.rectangle.angled"); photosPanel
                    case .video: attachmentHeader("Vidéo YouTube", "play.rectangle.fill"); videoPanel
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
            profileLine
            footnote("Rien n’est envoyé à \(provider.company) avant que vous \(tapLower) « Générer le questionnaire ».")
            if let error { errorLabel(error) }
        }
    }

    /// The request is the heart of the step: what to ask, for whom, how; a source is optional.
    private var requestPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextEditor(text: $instructions)
                .font(.body).frame(minHeight: large ? 200 : 140).scrollContentBackground(.hidden)
                .padding(8).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
                .overlay(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text("Par exemple : un quiz sur la photosynthèse, avec un texte à trous et deux questions ouvertes. Avec un document joint : « uniquement sur le chapitre 2 ».")
                            .foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
                    }
                }
                .onChange(of: instructions) { _, new in
                    if new.count > QuizAIText.requestLimit { instructions = String(new.prefix(QuizAIText.requestLimit)) }
                }
                .accessibilityLabel("Demande à l’assistant")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { attachButtons; Spacer(minLength: 12); countPicker }
                VStack(alignment: .leading, spacing: 12) { HStack(spacing: 10) { attachButtons }; countPicker }
                VStack(alignment: .leading, spacing: 10) { attachButtons; countPicker }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    /// One optional source at a time: the buttons step aside while one is attached.
    @ViewBuilder private var attachButtons: some View {
        if source == nil {
            Button("Document", systemImage: "paperclip") { source = .document; chooseFile = true; error = nil }
                .buttonStyle(.glass).accessibilityLabel("Joindre un document")
            PhotosPicker(selection: $photoItems, maxSelectionCount: Self.maximumPhotos, matching: .images) {
                Label("Photos", systemImage: "photo")
            }
            .buttonStyle(.glass).accessibilityLabel("Joindre des photos")
            Button("Vidéo", systemImage: "play.rectangle") { source = .video; error = nil }
                .buttonStyle(.glass).accessibilityLabel("Partir d’une vidéo YouTube")
        }
    }

    private var countPicker: some View {
        Picker("Nombre de questions", selection: $questionCount) {
            ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) questions").tag($0) }
        }
        .pickerStyle(.menu).labelsHidden().fixedSize()
    }

    /// The custom instructions, shown so the user knows they are sent, with a way to write or change it.
    private var profileLine: some View {
        Button { showProfile = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.text.rectangle").foregroundStyle(.tint)
                Text(trimmedProfile.isEmpty
                     ? "Indiquez une fois pour toutes qui vous êtes et à quel public vous vous adressez, dans vos instructions personnalisées."
                     : "Instructions personnalisées jointes : « \(trimmedProfile.prefix(80))\(trimmedProfile.count > 80 ? "…" : "") »")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre les instructions personnalisées")
    }

    private var removeAttachment: some View {
        Button("Retirer", systemImage: "xmark.circle.fill") {
            source = nil
            document = ""; filename = ""; address = ""; transcript = ""; photos = []; error = nil
        }
        .labelStyle(.iconOnly).foregroundStyle(.secondary).buttonStyle(.plain).font(.title2)
        .disabled(loadingPhotos)
    }

    private func attachmentHeader(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            Spacer()
            removeAttachment.accessibilityLabel("Retirer \(title == "Photos" ? "les photos" : "la vidéo")")
        }
    }

    private var documentPanel: some View {
        HStack(spacing: 14) {
            HomeTile(symbol: "doc.text.fill", tint: Color.accentColor, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(filename.isEmpty ? "Aucun document choisi" : filename).font(.headline).lineLimit(2)
                Text(document.isEmpty ? "PDF, Word (.docx), TXT ou MD · 12 Mo au maximum" : "\(document.count.formatted()) caractères lus")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(filename.isEmpty ? "Choisir" : "Changer") { chooseFile = true }.buttonStyle(.glass)
            removeAttachment.accessibilityLabel("Retirer le document")
        }
        .padding(dropTargeted ? 6 : 0)
        .background(dropTargeted ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 16))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            loadDocument(url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder private var photosPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Image(decorative: photo.thumbnail, scale: 1)
                            .resizable().scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity).frame(height: 104).clipped()
                            .clipShape(.rect(cornerRadius: 14))
                            .overlay(alignment: .topTrailing) {
                                Button { photos.removeAll { $0.id == photo.id } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3)
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .buttonStyle(.plain).padding(6)
                                .accessibilityLabel("Retirer la photo \(index + 1)")
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Photo \(index + 1)")
                    }
                }
            }
            if loadingPhotos {
                HStack(spacing: 10) { ProgressView(); Text("Préparation des photos…").foregroundStyle(.secondary) }
            }
            if remainingPhotos > 0 {
                let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: remainingPhotos, matching: .images) {
                        Label(photos.isEmpty ? "Choisir des photos" : "Ajouter des photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.glassProminent)
                    Button("Choisir des fichiers", systemImage: "folder") { chooseFile = true }.buttonStyle(.glass)
                }
                .disabled(loadingPhotos)
            }
            Text(photos.isEmpty
                 ? "Une page de manuel, le tableau, une fiche d’exercices… \(Self.maximumPhotos) photos au maximum. \(provider.name) lit le texte et les schémas visibles."
                 : "\(photos.count) photo\(photos.count > 1 ? "s" : "") sur \(Self.maximumPhotos). Précisez au besoin ce qu’il faut en tirer dans votre demande.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(dropTargeted ? 8 : 0)
        .background(dropTargeted ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 20))
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            loadPhotoFiles(files)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder private var videoPanel: some View {
        HStack(spacing: 10) {
            TextField("Adresse de la vidéo, par exemple https://youtu.be/…", text: $address)
                .codeEntryField(url: true)
            PasteButton(payloadType: String.self) { values in
                let pasted = values.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Task { @MainActor in if !pasted.isEmpty { address = pasted } }
            }.labelStyle(.iconOnly).buttonBorderShape(.capsule)
        }
        .padding(12).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        if !address.isEmpty {
            if video != nil {
                Label("Vidéo reconnue", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.green)
            } else {
                Label("Cette adresse n’est pas celle d’une vidéo YouTube.", systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline).foregroundStyle(.orange)
            }
        }
        if provider.readsVideo {
            Label("Gemini regarde directement la vidéo : aucune transcription à fournir.", systemImage: "sparkle")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcription de la vidéo").font(.headline)
                Text("\(provider.name) ne peut pas regarder une vidéo. Collez son texte : sur YouTube, ouvrez la description puis \(tapLower) « Afficher la transcription ».")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $transcript).frame(minHeight: 120).scrollContentBackground(.hidden)
                    .padding(8).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
                if isConnected(.gemini) {
                    Button("Utiliser Gemini pour lire la vidéo directement", systemImage: "sparkle") {
                        providerID = QuizProvider.gemini.rawValue
                    }.buttonStyle(.glass)
                }
            }
        }
    }

    private func generate() {
        let service = provider, kind = source, brief = QuizAIText.brief(questionCount: questionCount, instructions: instructions)
        let youtube = video, text = kind == .document ? document : trimmedTranscript
        let images = kind == .photos ? photos.map(\.jpeg) : []
        let system = QuizAIText.quizInstructions(hasSource: kind != nil, profile: profile)
        guard busy == nil, contentIssue == nil else { return }
        step = .review; draft = ""; editMarkdown = false
        run(.generating) {
            let key = service.usesAccount ? "" : try keys.key(for: service)
            let model = service.usesAccount ? "" : ((kind == .photos ? keys.photoModel(for: service) : keys.model(for: service)) ?? "")
            guard service.usesAccount || !model.isEmpty else { throw AudienceError.message("Aucun modèle n’est choisi pour \(service.name).") }
            let block: String
            if kind == nil {
                block = ""
            } else if kind == .photos {
                block = "<source type=\"photos\">La source est constituée \(images.count == 1 ? "de la photo jointe" : "des \(images.count) photos jointes, dans l’ordre"). Appuie-toi sur le texte, les schémas et les données qu’elles montrent ; ignore ce qui est illisible.</source>"
            } else if kind == .video, service.readsVideo, let youtube {
                block = "<source type=\"video\">La source est la vidéo YouTube jointe : \(youtube.absoluteString)</source>"
            } else {
                guard text.utf8.count <= 240_000 else { throw AudienceError.message("La source est trop longue. Choisissez un extrait.") }
                block = "<source type=\"\(kind == .video ? "transcription" : "document")\">\n\(text)\n</source>"
            }
            let result = try await service.complete(model: model, key: key, system: system,
                                                    prompt: block.isEmpty ? brief : "\(brief)\n\n\(block)",
                                                    video: kind == .video && service.readsVideo ? youtube : nil, images: images)
            try Task.checkCancellation()
            let markdown = QuizAIText.unfenced(result)
            guard !markdown.isEmpty else { throw AudienceError.message("Le service n’a renvoyé aucun questionnaire. Réessayez.") }
            draft = markdown
        }
    }

    // MARK: Step 3 — review

    private var parsed: Result<Quiz, Error> { Result { try QuizMarkdown.parse(draft) } }

    /// Why the questionnaire cannot be added yet, when something needs fixing.
    private var reviewIssue: String? {
        switch parsed {
        case .failure: "Le Markdown n’est pas lisible : corrigez-le."
        case .success(let quiz):
            if quiz.questions.isEmpty { "Aucune question détectée : corrigez le Markdown." }
            else if quiz.questions.contains(where: { $0.validationMessage != nil }) { "Corrigez les questions signalées en orange." }
            else { nil }
        }
    }

    @ViewBuilder private var reviewStep: some View {
        if busy == .generating {
            VStack(spacing: 18) {
                Image(systemName: "sparkles").font(.system(size: 46)).foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                Text("\(provider.name) rédige votre questionnaire…").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text("Cela prend en général de vingt secondes à une minute. Vous pourrez tout relire et modifier avant de l’ajouter.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                ProgressView()
                Button("Annuler") { operation?.cancel(); step = .content }.buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity).padding(40)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        } else if draft.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                if let error { errorLabel(error) }
                Button("Revenir au contenu") { step = .content }.buttonStyle(.glass)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                switch parsed {
                case .success(let quiz):
                    stepTitle("Votre questionnaire est prêt", "« \(quiz.title) » · \(quiz.questions.count == 1 ? "1 question" : "\(quiz.questions.count) questions"). Relisez-le, puis ajoutez-le à votre bibliothèque.")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(quiz.questions.enumerated()), id: \.offset) { index, question in
                            questionRow(index, question)
                            if index < quiz.questions.count - 1 { Divider().padding(.leading, 40) }
                        }
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))
                case .failure(let failure):
                    stepTitle("Relisez le questionnaire", "Le texte reçu n’a pas pu être lu comme un questionnaire.")
                    errorLabel(failure.localizedDescription)
                }
                DisclosureGroup("Modifier le Markdown", isExpanded: Binding(
                    get: { editMarkdown || parsed.isFailure }, set: { editMarkdown = $0 })) {
                        TextEditor(text: $draft).font(.body.monospaced()).frame(minHeight: 320)
                            .scrollContentBackground(.hidden).padding(8)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
                    }
                    .padding(20).glassEffect(.regular, in: .rect(cornerRadius: 28))
                if let error { errorLabel(error) }
            }
        }
    }

    private func questionRow(_ index: Int, _ question: Question) -> some View {
        let issue = question.validationMessage
        return HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(issue == nil ? Color.accentColor : Color.orange, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(question.text.isEmpty ? "Question sans énoncé" : question.text).lineLimit(3)
                Label(question.kind.title, systemImage: question.kind.symbol).font(.caption).foregroundStyle(.secondary)
                if let issue { Label(issue, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func add() {
        if let message = store.importText(draft) { error = message } else { finished() }
    }

    // MARK: Pieces

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
    }

    private func footnote(_ text: String) -> some View { AIFootnote(text: text) }

    private func errorLabel(_ text: String) -> some View { AIErrorLabel(text: text) }

    private func run(_ kind: Busy, _ action: @escaping @MainActor () async throws -> Void) {
        error = nil; busy = kind
        operation = Task { @MainActor in
            defer { busy = nil; operation = nil }
            do { try await action() } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                if provider == .chatGPT { chatGPT.handleAPIError(error) }
                self.error = error.localizedDescription
                step = .content
            }
        }
    }
}

private extension Result {
    var isFailure: Bool { if case .failure = self { true } else { false } }
}
