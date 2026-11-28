import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct QuizEditor: View {
    @Bindable var store: LibraryStore
    let code: String
    @State private var selected: Int? = Self.initialQuestion
    @State private var deleteIndex: Int?
    @State private var showQuestions = false
    #if os(iOS)
    @State private var questionEditMode = EditMode.inactive
    #endif
    @ScaledMetric(relativeTo: .body) private var scaledNavigatorWidth = IPadColumn.width
    @ScaledMetric(relativeTo: .body) private var minimumFormWidth: CGFloat = 400
    @ScaledMetric(relativeTo: .body) private var questionButtonSize: CGFloat = 44
    /// Same width as the sidebar and questionnaire columns.
    private var navigatorWidth: CGFloat { min(scaledNavigatorWidth, IPadColumn.maximum) }
    /// The first question, except in Debug where AUDIENCE_SNAPSHOT_QUESTION=<n> opens question n (from 1), for screenshots.
    private static var initialQuestion: Int? {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["AUDIENCE_SNAPSHOT_QUESTION"], let number = Int(value), number > 0 { return number - 1 }
        #endif
        return 0
    }
    private var quiz: Quiz { store.archive.quizzes[code] ?? Quiz(code: code) }
    private var index: Int? {
        guard let selected, quiz.questions.indices.contains(selected) else { return nil }
        return selected
    }
    private func question(at index: Int) -> Binding<Question> {
        Binding(get: { quiz.questions.indices.contains(index) ? quiz.questions[index] : Question() },
                set: { value in store.update(code) { q in var questions = q.questions; if questions.indices.contains(index) { questions[index] = value; q.questions = questions } } })
    }
    private var locked: Bool { store.liveCode == code || store.readOnly }

    var body: some View {
        #if os(iOS)
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if store.liveCode == code {
                    Label("Session en direct · Édition suspendue", systemImage: "dot.radiowaves.left.and.right")
                        .font(.callout).padding(12)
                }
                if geometry.size.width >= navigatorWidth + minimumFormWidth {
                    HStack(spacing: 0) {
                        // No edit button: questions are reordered by dragging, and the context menu does the rest.
                        navigator
                            .frame(width: navigatorWidth)
                        Divider()
                        editorForm
                    }
                } else {
                    compactNavigator
                    Divider()
                    editorForm
                }
            }
        }
        .sheet(isPresented: $showQuestions) {
            NavigationStack {
                navigator
                    .navigationTitle("Questions")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { DoneButton { showQuestions = false } }
                        ToolbarItem(placement: .primaryAction) { EditButton().disabled(locked) }
                    }
                    .onChange(of: selected) { if !questionEditMode.isEditing { showQuestions = false } }
            }
            .environment(\.editMode, $questionEditMode)
        }
        .onChange(of: quiz.questions.count) { _, count in
            if let selected, selected >= count { self.selected = count > 0 ? count - 1 : nil }
        }
        #else
        GeometryReader { geometry in
            if geometry.size.width >= navigatorWidth + minimumFormWidth {
                HStack(spacing: 0) {
                    navigator.frame(width: navigatorWidth)
                    Divider()
                    editorForm
                }
            } else {
                VStack(spacing: 0) {
                    compactNavigator.padding(.top, 8)
                    Divider()
                    editorForm
                }
            }
        }
        .sheet(isPresented: $showQuestions) {
            VStack(spacing: 0) {
                HStack {
                    Text("Questions").font(.headline)
                    Spacer()
                    Button("Terminé") { showQuestions = false }.keyboardShortcut(.defaultAction)
                }
                .padding()
                Divider()
                navigator
            }
            .frame(width: 360, height: 480)
        }
        .overlay(alignment: .top) {
            if store.liveCode == code {
                Label("Session en direct · Arrêtez-la pour modifier le questionnaire.", systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout).padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule).padding(10)
            }
        }
        .onChange(of: quiz.questions.count) { _, count in
            if let selected, selected >= count { self.selected = count > 0 ? count - 1 : nil }
        }
        .confirmationDialog("Supprimer la question \((deleteIndex ?? 0) + 1) ?", isPresented: Binding(
            get: { deleteIndex != nil }, set: { if !$0 { deleteIndex = nil } }), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { if let deleteIndex { remove(deleteIndex) } }
        } message: { Text("Les réponses déjà recueillies pour cette question resteront sur le site.") }
        #endif
    }

    private var compactNavigator: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(index.map { "Question \($0 + 1) sur \(quiz.questions.count)" } ?? "Aucune question")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Organiser les questions", systemImage: "list.bullet") { showQuestions = true }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    .help("Organiser les questions")
                addMenu.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 16)
            if !quiz.questions.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(quiz.questions.enumerated()), id: \.offset) { i, question in
                                Button { selected = i } label: {
                                    Text("\(i + 1)")
                                        .font(.body.monospacedDigit().weight(selected == i ? .semibold : .regular))
                                        .frame(minWidth: questionButtonSize, minHeight: questionButtonSize)
                                        .background(selected == i ? Color.accentColor : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
                                        .foregroundStyle(selected == i ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Question \(i + 1), \(question.text.isEmpty ? "Nouvelle question" : RichText.plainText(question["question"].string))")
                                .accessibilityValue(question.validationMessage == nil ? "" : "Question incomplète")
                                .accessibilityAddTraits(selected == i ? [.isSelected] : [])
                                .id(i)
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    .frame(height: questionButtonSize + 8)
                    .scrollIndicators(.hidden)
                    .onAppear { if let index { proxy.scrollTo(index) } }
                    .onChange(of: selected) { if let index { proxy.scrollTo(index) } }
                    .onChange(of: quiz.questions.count) { if let index { proxy.scrollTo(index) } }
                }
            }
        }
        .disabled(locked)
    }

    private var editorForm: some View {
        Form {
            Section {
                TextField("Titre", text: Binding(get: { quiz.title }, set: { value in store.update(code) { $0.title = value } }),
                          prompt: Text("Titre du questionnaire"))
                    .font(.title3.weight(.semibold))
                    .labelsHidden()
            }
            if let index {
                QuestionEditor(question: question(at: index), number: index + 1)
            } else {
                Section { noQuestionState }
            }
        }
        .formStyle(.grouped)
        .disabled(locked)
    }

    @ViewBuilder private var noQuestionState: some View {
        let title = quiz.questions.isEmpty ? "La première question" : "Aucune question sélectionnée"
        let hint = quiz.questions.isEmpty ? "Choisissez un format pour commencer." : "Sélectionnez une question dans la liste."
        #if os(iOS)
        // On the iPad, a ContentUnavailableView in a Form row gives its action the whole height of the
        // row (the button becomes a tall, empty pill), and the row tints the icon of a button label like
        // the button itself. The same layout is drawn by hand, with a white label.
        VStack(spacing: 12) {
            Image(systemName: "text.badge.plus").font(.system(size: 48)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(hint).foregroundStyle(.secondary)
            if quiz.questions.isEmpty {
                addMenu.foregroundStyle(.white).buttonStyle(.glassProminent).padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        #else
        ContentUnavailableView {
            Label(title, systemImage: "text.badge.plus")
        } description: {
            Text(hint)
        } actions: {
            if quiz.questions.isEmpty {
                addMenu.buttonStyle(.glassProminent).fixedSize()
            }
        }
        #endif
    }

    private var navigator: some View {
        List(selection: $selected) {
            ForEach(Array(quiz.questions.enumerated()), id: \.offset) { i, question in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(question.text.isEmpty ? AttributedString("Nouvelle question") : RichText.attributed(question["question"].string))
                            .lineLimit(2).foregroundStyle(question.text.isEmpty ? .secondary : .primary)
                        Label(question.kind.title, systemImage: question.kind.symbol)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let message = question.validationMessage {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).help(message)
                            .accessibilityLabel("Question incomplète")
                    }
                }
                .padding(.vertical, 3)
                .tag(i)
                .contextMenu {
                    Button("Dupliquer", systemImage: "plus.square.on.square") { duplicate(i) }
                    Button("Monter", systemImage: "arrow.up") { move(from: i, to: i - 1) }.disabled(i == 0)
                    Button("Descendre", systemImage: "arrow.down") { move(from: i, to: i + 1) }.disabled(i >= quiz.questions.count - 1)
                    Divider()
                    Button("Supprimer…", systemImage: "trash", role: .destructive) { deleteIndex = i }
                }
            }
            .onMove { source, destination in
                guard !locked else { return }
                let moved = source.first
                store.update(code) { q in var questions = q.questions; questions.move(fromOffsets: source, toOffset: destination); q.questions = questions }
                if let moved, source.count == 1 { selected = moved < destination ? destination - 1 : destination }
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        #endif
        #if os(macOS)
        .onDeleteCommand { if let index, !locked { deleteIndex = index } }
        #endif
        .disabled(locked)
        .safeAreaBar(edge: .bottom) {
            HStack {
                addMenu.buttonStyle(.borderless).fixedSize()
                Spacer()
                Text(quiz.questions.count == 1 ? "1 question" : "\(quiz.questions.count) questions")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .disabled(locked)
        }
        #if os(iOS)
        .confirmationDialog("Supprimer cette question ?", isPresented: Binding(
            get: { deleteIndex != nil }, set: { if !$0 { deleteIndex = nil } }), titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { if let deleteIndex { remove(deleteIndex) }; deleteIndex = nil }
            }
        #endif
    }

    private var addMenu: some View {
        Menu {
            ForEach(QuestionKind.allCases) { kind in
                Button(kind.title, systemImage: kind.symbol) { add(kind) }
            }
        } label: {
            #if os(iOS)
            Label("Ajouter", systemImage: "plus").accessibilityLabel("Ajouter une question")
            #else
            Label("Ajouter une question", systemImage: "plus")
            #endif
        }
    }
    private func add(_ kind: QuestionKind) {
        let insertion = index.map { $0 + 1 } ?? quiz.questions.count
        store.update(code) { var q = $0.questions; q.insert(Question(kind: kind), at: min(insertion, q.count)); $0.questions = q }
        selected = min(insertion, quiz.questions.count - 1)
    }
    private func duplicate(_ i: Int) {
        guard quiz.questions.indices.contains(i) else { return }
        store.update(code) { var q = $0.questions; q.insert(q[i], at: i + 1); $0.questions = q }
        selected = i + 1
    }
    private func move(from: Int, to: Int) {
        guard quiz.questions.indices.contains(from), quiz.questions.indices.contains(to) else { return }
        store.update(code) { var q = $0.questions; q.swapAt(from, to); $0.questions = q }
        selected = to
    }
    private func remove(_ i: Int) {
        store.update(code) { var q = $0.questions; if q.indices.contains(i) { q.remove(at: i) }; $0.questions = q }
        let count = quiz.questions.count
        selected = count == 0 ? nil : min(i, count - 1)
    }
}

struct QuestionEditor: View {
    @Binding var question: Question
    var number = 1
    @State private var imageError: String?
    @State private var imageTargeted = false
    @State private var choosingImage = false
    @State private var showingImage = false
    /// The statement as typed, in Markdown. The question keeps the website's HTML.
    @State private var statement = ""
    private static let timeLimits = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
    var body: some View {
        Section("Question \(number)") {
            Picker("Format", selection: $question.kind) {
                ForEach(QuestionKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            } currentValueLabel: {
                #if os(iOS)
                // The iPad menu button flattens its label to a symbol set against the text and ignores
                // view spacing: an en space keeps them apart, at any text size.
                Label("\u{2002}" + question.kind.title, systemImage: question.kind.symbol)
                #else
                Label(question.kind.title, systemImage: question.kind.symbol)
                #endif
            }
            // The site stores the statement as HTML (<em>, l&#39;origine): it is edited as Markdown.
            TextField("Énoncé", text: $statement, prompt: Text("Énoncé de la question"), axis: .vertical)
                .lineLimit(3...8).labelsHidden()
                .onAppear(perform: loadStatement)
                .onChange(of: question["question"].string) { loadStatement() }
                .onChange(of: statement) {
                    // Showing a question must not modify it: only a different text is saved.
                    let stored = question["question"].string
                    if statement != RichText.markdown(fromHTML: stored) {
                        question["question"] = .string(RichText.html(fromMarkdown: statement))
                    }
                }
            if RichText.isFormatted(question["question"].string) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aperçu").font(.caption).foregroundStyle(.secondary)
                    Text(RichText.attributed(question["question"].string))
                }
                .accessibilityElement(children: .combine)
            }
            #if os(macOS)
            timeLimitPicker
            #endif
            if let message = question.validationMessage {
                Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        if question.kind.hasAnswers {
            Section(question.kind == .ranking ? "Éléments à classer" : "Réponses") {
                if question.kind == .multiple { Toggle("Sondage sans bonne réponse", isOn: bool("isPollMode")) }
                ForEach(question.answers.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        if question.kind != .ranking && !(question.kind == .multiple && question["isPollMode"].bool) {
                            Button {
                                if question.kind == .multiple { question["correctIndex"] = .number(Double(i)) }
                                else {
                                    var indices = question["correctIndexes"].array.map(\.int)
                                    if indices.contains(i) { indices.removeAll { $0 == i } } else { indices.append(i) }
                                    question["correctIndexes"] = .array(indices.map { .number(Double($0)) })
                                }
                            } label: {
                                Image(systemName: isCorrect(i) ? "checkmark.circle.fill" : "circle").foregroundStyle(isCorrect(i) ? Color.green : Color.secondary)
                            }.buttonStyle(.plain).help("Marquer comme bonne réponse").accessibilityLabel("Réponse \(i + 1) correcte").accessibilityValue(isCorrect(i) ? "Oui" : "Non")
                        } else { Text("\(i + 1)").foregroundStyle(.secondary).frame(width: 20) }
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("Réponse \(i + 1)", text: Binding(get: { question.answers.indices.contains(i) ? question.answers[i].unformattedText : "" }, set: { value in
                                var answers = question.answers; guard answers.indices.contains(i) else { return }; answers[i] = value.htmlEscaped; question.answers = answers
                            }), prompt: Text("Réponse \(i + 1)")).labelsHidden()
                            // The *italique* and **gras** marks are shown as the presentation shows them.
                            if question.answers.indices.contains(i), RichText.answerIsFormatted(question.answers[i]) {
                                Text(RichText.attributedAnswer(question.answers[i])).font(.callout).foregroundStyle(.secondary)
                                    .accessibilityLabel("Aperçu : \(RichText.answerPlainText(question.answers[i]))")
                            }
                        }
                        Button("Supprimer la réponse", systemImage: "minus.circle") { question.removeAnswer(at: i) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(question.answers.count <= 2)
                    }
                }
                Button("Ajouter une réponse", systemImage: "plus") { var answers = question.answers; answers.append(""); question.answers = answers }
                if question.kind == .ranking { Text("Placez les éléments dans l’ordre attendu.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        if question.kind == .open {
            Section("Réponse libre") {
                Picker("Format de réponse", selection: string("responseFormat", fallback: "text")) {
                    Text("Texte").tag("text"); Text("Mathématiques (LaTeX)").tag("math")
                }
            }
        }
        if question.kind == .cloze {
            Section("Texte à compléter") {
                TextField("Texte", text: string("clozeText"), prompt: Text("Texte avec [trous]"), axis: .vertical)
                    .lineLimit(5...14).labelsHidden()
                Text("Un trou : [réponse]. Un choix : {{réponse, autre choix}}.").font(.caption).foregroundStyle(.secondary)
            }
        }
        if question.kind == .video {
            Section("Vidéo YouTube") {
                TextField("URL", text: string("youtubeUrl"))
                let link = question["youtubeUrl"].string
                if let video = YouTubeVideo(url: link, start: question["videoStartSec"].int, end: question["videoEndSec"].int) {
                    // The presentation's player, to check the link and the extract while editing.
                    YouTubePlayer(video: video)
                        .padding(.vertical, 6)
                        .id(video.embedURL)
                } else if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Ce lien n’est pas une vidéo YouTube reconnue.", systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Stepper("Début : \(question["videoStartSec"].int) s", value: int("videoStartSec"), in: 0...43200, step: 5)
                Stepper("Fin : \(question["videoEndSec"].int) s (0 = fin de la vidéo)", value: int("videoEndSec"), in: 0...43200, step: 5)
            }
        }
        if question.kind == .rating {
            Section { Text("Les participants attribuent une note de 1 à 5 étoiles.").foregroundStyle(.secondary) }
        }
        if [.multiple, .checkbox, .open, .cloze, .labelimage].contains(question.kind) {
            Section("Image") {
                VStack(alignment: .leading, spacing: 16) {
                    if !question["questionImage"].string.isEmpty {
                        Button { showingImage = true } label: {
                            QuestionImage(source: question["questionImage"].string)
                                .frame(maxWidth: .infinity, maxHeight: 440)
                                .padding(12)
                                .background(.background, in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Agrandir l’image de la question")
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                imageActions
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                imageActions
                            }
                        }
                    } else {
                        Button("Choisir une image…", systemImage: "photo") { chooseImage() }
                    }
                    Text("Glissez une image ici · 2 Mo maximum")
                        .font(.caption).foregroundStyle(.secondary)
                    if let imageError { Text(imageError).font(.caption).foregroundStyle(.red) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $showingImage) {
                QuestionImageViewer(source: question["questionImage"].string)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                loadImage(url); return true
            } isTargeted: { imageTargeted = $0 }
            .listRowBackground(imageTargeted ? Color.accentColor.opacity(0.15) : nil)
            #if os(iOS)
            .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.png, .jpeg, .gif, .webP]) { result in
                switch result {
                case .success(let url): loadImage(url)
                case .failure(let error): imageError = error.localizedDescription
                }
            }
            #endif
        }
        if question.kind == .labelimage {
            Section("Étiquettes") {
                Text("Les positions sont exprimées en pourcentage de l’image.").font(.caption).foregroundStyle(.secondary)
                ForEach(question["legendLabels"].array.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Étiquette \(i + 1)", text: labelText(i), prompt: Text("Étiquette \(i + 1)")).labelsHidden()
                            Button("Retirer", systemImage: "minus.circle") {
                                var labels = question["legendLabels"].array
                                if labels.indices.contains(i) { labels.remove(at: i) }
                                question["legendLabels"] = .array(labels)
                            }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                        HStack {
                            Text("X").foregroundStyle(.secondary); Slider(value: coordinate(i, "x"), in: 0...100)
                            Text("Y").foregroundStyle(.secondary); Slider(value: coordinate(i, "y"), in: 0...100)
                        }
                        Text("X : \(Int(coordinate(i, "x").wrappedValue)) % · Y : \(Int(coordinate(i, "y").wrappedValue)) %").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Ajouter une étiquette", systemImage: "plus") {
                    var labels = question["legendLabels"].array
                    labels.append(.object(["id": .string(UUID().uuidString), "text": .string(""), "x": .number(50), "y": .number(50)]))
                    question["legendLabels"] = .array(labels)
                }
            }
        }
        #if os(iOS)
        // On the iPad, the settings that are rarely changed close the question, under one heading.
        Section("Réglages de la question") {
            timeLimitPicker
            Toggle("Montrer les résultats aux participants", isOn: bool("participantResponsesVisible", fallback: true))
        }
        #else
        Section {
            Toggle("Montrer les résultats aux participants", isOn: bool("participantResponsesVisible", fallback: true))
        }
        #endif
    }
    private var timeLimitPicker: some View {
        let limit = question.fields["timeLimitSec"]?.int ?? 30
        return Picker("Temps de réponse", selection: int("timeLimitSec", fallback: 30)) {
            // Keep a nonstandard value from an older questionnaire selectable.
            ForEach(Self.timeLimits.contains(limit) ? Self.timeLimits : (Self.timeLimits + [limit]).sorted(), id: \.self) {
                Text($0 < 60 || $0 % 60 != 0 ? "\($0) secondes" : $0 == 60 ? "1 minute" : "\($0 / 60) minutes").tag($0)
            }
        }
    }
    @ViewBuilder private var imageActions: some View {
        Button("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right") { showingImage = true }
        Button("Remplacer…", systemImage: "photo") { chooseImage() }
        Button("Retirer", systemImage: "trash", role: .destructive) {
            question["questionImage"] = .string("")
            imageError = nil
        }
    }
    private func isCorrect(_ i: Int) -> Bool { question.kind == .multiple ? question["correctIndex"].int == i : question["correctIndexes"].array.map(\.int).contains(i) }
    /// Another question, an import or a synchronization changed the statement: show it as Markdown,
    /// unless it is exactly what is being typed (trailing spaces included).
    private func loadStatement() {
        let stored = question["question"].string
        if RichText.html(fromMarkdown: statement) != stored { statement = RichText.markdown(fromHTML: stored) }
    }
    private func string(_ key: String, fallback: String = "") -> Binding<String> {
        Binding(get: { question.fields[key]?.string ?? fallback }, set: { question[key] = .string($0) })
    }
    private func int(_ key: String, fallback: Int = 0) -> Binding<Int> {
        Binding(get: { question.fields[key]?.int ?? fallback }, set: { question[key] = .number(Double($0)) })
    }
    private func bool(_ key: String, fallback: Bool = false) -> Binding<Bool> {
        Binding(get: { question.fields[key]?.bool ?? fallback }, set: { question[key] = .bool($0) })
    }
    private func labelText(_ i: Int) -> Binding<String> {
        Binding(get: { question["legendLabels"].array.indices.contains(i) ? question["legendLabels"].array[i]["text"].string : "" }, set: { value in
            var labels = question["legendLabels"].array; guard labels.indices.contains(i) else { return }; var f = labels[i].object; f["text"] = .string(value); labels[i] = .object(f); question["legendLabels"] = .array(labels)
        })
    }
    private func coordinate(_ i: Int, _ axis: String) -> Binding<Double> {
        Binding(get: { question["legendLabels"].array.indices.contains(i) ? question["legendLabels"].array[i][axis].double : 50 }, set: { value in
            var labels = question["legendLabels"].array; guard labels.indices.contains(i) else { return }; var f = labels[i].object; f[axis] = .number(value); labels[i] = .object(f); question["legendLabels"] = .array(labels)
        })
    }
    private func chooseImage() {
        #if os(macOS)
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImage(url)
        #else
        choosingImage = true
        #endif
    }
    private func loadImage(_ url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension), [UTType.png, .jpeg, .gif, .webP].contains(where: { type.conforms(to: $0) }) else {
            imageError = "Choisissez une image PNG, JPEG, GIF ou WebP."; return
        }
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= 2 * 1024 * 1024 else { imageError = "Choisissez une image de 2 Mo maximum."; return }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            question["questionImage"] = .string("data:\(mime);base64,\(data.base64EncodedString())"); imageError = nil
        } catch { imageError = error.localizedDescription }
    }
}

/// Decoding a 2 MB data URL on every keystroke would make typing sluggish.
@MainActor private let decodedImages: NSCache<NSString, PlatformImage> = { let cache = NSCache<NSString, PlatformImage>(); cache.countLimit = 40; return cache }()

struct QuestionImage: View, Equatable {
    let source: String
    private var embedded: PlatformImage? {
        guard source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") else { return nil }
        let key = source as NSString
        if let image = decodedImages.object(forKey: key) { return image }
        guard let data = Data(base64Encoded: String(source[source.index(after: comma)...])), let image = PlatformImage(data: data) else { return nil }
        decodedImages.setObject(image, forKey: key)
        return image
    }
    var body: some View {
        if let image = embedded {
            Image(platformImage: image).resizable().scaledToFit().accessibilityLabel("Image de la question")
        } else if let url = URL(string: source), url.scheme == "https" {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().accessibilityLabel("Image de la question")
                case .failure:
                    unavailable
                default:
                    ProgressView().accessibilityLabel("Chargement de l’image")
                }
            }
        } else {
            unavailable
        }
    }
    private var unavailable: some View {
        Label("Image indisponible", systemImage: "photo").foregroundStyle(.secondary)
    }
}

struct QuestionImageViewer: View {
    let source: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Image de la question").font(.headline)
                Spacer()
                CloseButton { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    #if os(iOS)
                    .buttonStyle(.glass)
                    #endif
            }
            .padding()
            Divider()
            GeometryReader { geometry in
                QuestionImage(source: source)
                    .frame(width: max(0, geometry.size.width - 32), height: max(0, geometry.size.height - 32))
                    .padding(16)
            }
        }
        .background(.background)
        #if os(macOS)
        .frame(width: 1000, height: 700)
        #endif
    }
}
