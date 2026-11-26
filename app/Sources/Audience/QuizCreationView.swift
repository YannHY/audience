import SwiftUI
import PDFKit
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// "Créer avec une IA" in three steps: connect a service, give it the content, review what it wrote.
struct QuizCreationView: View {
    let store: LibraryStore
    let finished: () -> Void

    private enum Step: Int, CaseIterable {
        case service, content, review
        var title: String { ["Service", "Contenu", "Questionnaire"][rawValue] }
    }
    private enum Busy { case generating }
    private enum SourceKind { case document, video }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var chatGPT = ChatGPTAuth.shared
    private let keys = AIKeyStore.shared
    @AppStorage("ai.provider") private var providerID = QuizProvider.chatGPT.rawValue
    @State private var step = Step.service
    @State private var source = SourceKind.document
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
    private var cardColumns: [GridItem] { large ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 250), spacing: 14)] }
    private var provider: QuizProvider { QuizProvider(rawValue: providerID) ?? .chatGPT }
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
        case .document: return document.isEmpty ? "Choisissez un document." : nil
        case .video:
            if video == nil { return "Collez l’adresse d’une vidéo YouTube." }
            if !provider.readsVideo && trimmedTranscript.isEmpty { return "Collez la transcription de la vidéo." }
            return nil
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepBar.padding(.top, 8).padding(.bottom, 4)
                ScrollView {
                    Group {
                        switch step {
                        case .service: serviceStep
                        case .content: contentStep
                        case .review: reviewStep
                        }
                    }
                    .transition(.opacity)
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) { actionBar }
            }
            .navigationTitle("Créer avec une IA")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { operation?.cancel(); dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 760, minHeight: 620, idealHeight: 720)
        #endif
        .presentationSizing(.page)
        .presentationBackground { AudienceBackdrop() }
        .interactiveDismissDisabled(busy != nil || !draft.isEmpty)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: step)
        .task(id: providerID) { await keys.refreshModels(provider) }
        .onChange(of: providerID) { error = nil }
        .onDisappear { operation?.cancel() }
        #if DEBUG
        .task { applyPreviewState() }
        #endif
        .fileImporter(isPresented: $chooseFile, allowedContentTypes: Self.documentTypes) { result in
            switch result {
            case .success(let url): loadDocument(url)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription }
            }
        }
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
            step = .content
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

    private func reachable(_ target: Step) -> Bool {
        switch target {
        case .service: true
        case .content: isConnected(provider)
        case .review: !draft.isEmpty
        }
    }

    private var stepBar: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                let current = item == step, done = item.rawValue < step.rawValue
                Button { if busy == nil, reachable(item) { step = item } } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(current || done ? Color.accentColor : Color.secondary.opacity(0.25))
                            if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                            else { Text("\(item.rawValue + 1)").font(.caption.bold()).foregroundStyle(current ? .white : .secondary) }
                        }.frame(width: 26, height: 26)
                        if !large || current {
                            Text(item.title).font(.subheadline.weight(current ? .semibold : .regular))
                                .foregroundStyle(current ? .primary : .secondary)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassEffect(current ? .regular.tint(Color.accentColor.opacity(0.2)) : .regular, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Étape \(item.rawValue + 1) : \(item.title)")
                .accessibilityValue(current ? "en cours" : done ? "terminée" : "")
                if item != Step.allCases.last { Capsule().fill(.secondary.opacity(0.3)).frame(width: 22, height: 2) }
            }
        }
    }

    private var actionBar: some View {
        GlassEffectContainer(spacing: 12) {
            let layout = large ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                if step != .service, busy != .generating {
                    Button("Retour", systemImage: "chevron.left") {
                        withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .service }
                    }.buttonStyle(.glass).controlSize(.large).disabled(busy != nil)
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
        case .service:
            Button("Continuer") { withAnimation { step = .content } }
                .buttonStyle(.glassProminent).controlSize(.large)
                .disabled(!isConnected(provider) || busy != nil)
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
        case .service: isConnected(provider) ? nil : "Connectez \(provider.name) pour continuer."
        case .content: contentIssue
        case .review: busy == .generating ? nil : reviewIssue
        }
    }

    // MARK: Step 1 — service

    private var serviceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("Choisissez votre assistant", "Il rédigera le questionnaire à partir de votre document ou de votre vidéo.")
            LazyVGrid(columns: cardColumns, spacing: 14) {
                ForEach(QuizProvider.allCases) { providerCard($0) }
            }
            connectionPanel
        }
    }

    private func providerCard(_ item: QuizProvider) -> some View {
        let selected = item == provider, connected = isConnected(item)
        return Button { providerID = item.rawValue; error = nil } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ProviderLogo(provider: item, size: 44)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(selected ? item.tint : Color.secondary.opacity(0.5))
                }
                Text(item.name).font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Circle().fill(connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                    Text(status(item)).font(.subheadline).foregroundStyle(connected ? .primary : .secondary).lineLimit(1)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(selected ? .regular.tint(item.tint.opacity(0.18)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 26))
            .overlay { if selected { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(item.tint, lineWidth: 2) } }
            .contentShape(.rect(cornerRadius: 26))
            .platformHoverEffect()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "sélectionné" : "")
    }

    private var connectionPanel: some View {
        AIConnectionPanel(provider: provider) { await advanceAfterConnection() }
            .id(provider)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    /// A fresh connection shows its confirmation for a moment, then moves on to the content.
    private func advanceAfterConnection() async {
        try? await Task.sleep(for: .milliseconds(1100))
        guard !Task.isCancelled, step == .service, isConnected(provider) else { return }
        withAnimation(.smooth) { step = .content }
    }

    // MARK: Step 2 — content

    private var contentStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            serviceChip
            stepTitle("Sur quoi porte le questionnaire ?", "Choisissez le contenu que \(provider.name) va lire.")
            LazyVGrid(columns: cardColumns, spacing: 14) {
                sourceCard(.document, "Document", "PDF, Word, TXT ou MD", "doc.text.fill")
                sourceCard(.video, "Vidéo YouTube", "À partir de son adresse", "play.rectangle.fill")
            }
            VStack(alignment: .leading, spacing: 14) {
                if source == .document { documentPanel } else { videoPanel }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            optionsPanel
            footnote("Le contenu est envoyé à \(provider.company) uniquement quand vous \(tapLower) « Générer le questionnaire ».")
            if let error { errorLabel(error) }
        }
    }

    private var serviceChip: some View {
        HStack(spacing: 12) {
            ProviderLogo(provider: provider, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name).font(.subheadline.weight(.semibold))
                Label(status(provider), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            }
            Spacer()
            Button("Changer") { withAnimation { step = .service } }.buttonStyle(.glass)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    private func sourceCard(_ kind: SourceKind, _ title: String, _ subtitle: String, _ symbol: String) -> some View {
        let selected = source == kind
        return Button { source = kind; error = nil } label: {
            HStack(spacing: 14) {
                HomeTile(symbol: symbol, tint: Color.accentColor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(selected ? .regular.tint(Color.accentColor.opacity(0.18)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 26))
            .overlay { if selected { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2) } }
            .contentShape(.rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "sélectionné" : "")
    }

    @ViewBuilder private var documentPanel: some View {
        Group {
            if filename.isEmpty {
                Button { chooseFile = true } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc").font(.system(size: 34, weight: .light)).foregroundStyle(.tint)
                        Text("Choisir un fichier").font(.headline)
                        Text("PDF, Word (.docx), TXT ou MD · 12 Mo au maximum").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                    .background(dropTargeted ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(dropTargeted ? Color.accentColor : .secondary.opacity(0.4),
                                          style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1.5, dash: [7, 7]))
                    }
                    .contentShape(.rect)
                }.buttonStyle(.plain)
            } else {
                HStack(spacing: 14) {
                    HomeTile(symbol: "doc.text.fill", tint: Color.accentColor, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(filename).font(.headline).lineLimit(2)
                        Text("\(document.count.formatted()) caractères lus").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Changer") { chooseFile = true }.buttonStyle(.glass)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            loadDocument(url)
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
                TextEditor(text: $transcript).frame(minHeight: 150).scrollContentBackground(.hidden)
                    .padding(8).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
                Button(keys.connected.contains(.gemini) ? "Utiliser Gemini pour lire la vidéo directement" : "Connecter Gemini pour lire la vidéo directement",
                       systemImage: "sparkle") {
                    providerID = QuizProvider.gemini.rawValue
                    if !isConnected(.gemini) { withAnimation { step = .service } }
                }.buttonStyle(.glass)
            }
        }
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Options").font(.headline)
            LabeledContent("Nombre de questions") {
                Picker("Nombre de questions", selection: $questionCount) {
                    ForEach([5, 10, 15, 20], id: \.self) { Text("\($0)").tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
            }
            TextField("Consignes facultatives : niveau, ton, types de questions…", text: $instructions, axis: .vertical)
                .lineLimit(2...5).padding(12).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func generate() {
        let service = provider, kind = source, brief = QuizAIText.brief(questionCount: questionCount, instructions: instructions)
        let youtube = video, text = kind == .document ? document : trimmedTranscript
        guard busy == nil, contentIssue == nil else { return }
        step = .review; draft = ""; editMarkdown = false
        run(.generating) {
            let key = service.usesAccount ? "" : try keys.key(for: service)
            let model = service.usesAccount ? "" : (keys.model(for: service) ?? "")
            guard service.usesAccount || !model.isEmpty else { throw AudienceError.message("Aucun modèle n’est choisi pour \(service.name).") }
            let block: String
            if kind == .video, service.readsVideo, let youtube {
                block = "<source type=\"video\">La source est la vidéo YouTube jointe : \(youtube.absoluteString)</source>"
            } else {
                guard text.utf8.count <= 240_000 else { throw AudienceError.message("La source est trop longue. Choisissez un extrait.") }
                block = "<source type=\"\(kind == .video ? "transcription" : "document")\">\n\(text)\n</source>"
            }
            let result = try await service.generate(model: model, key: key, prompt: "\(brief)\n\n\(block)",
                                                    video: kind == .video && service.readsVideo ? youtube : nil)
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
