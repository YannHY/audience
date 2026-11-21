import SwiftUI
import CoreImage.CIFilterBuiltins
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct PresentationView: View {
    @Bindable var store: LibraryStore
    let code: String
    @State private var index = 0
    @State private var reveal = false
    @State private var showResults = false
    @State private var showJoin = false
    @State private var liveError: String?
    @State private var confirmLive = false
    @Environment(\.openURL) private var openURL
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismissWindow) private var dismissWindow
    private var quiz: Quiz? { store.archive.quizzes[code] }
    private var isLive: Bool { store.liveCode == code }

    var body: some View {
        Group {
            if let quiz, !quiz.isDeleted, quiz.questions.indices.contains(index) {
                let question = quiz.questions[index]
                GeometryReader { geometry in
                    let scale = min(max(geometry.size.width / 1200, 0.85), 1.8)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28 * scale) {
                            header(quiz)
                            Text(question.text.plainText)
                                .font(.system(size: 38 * scale, weight: .semibold))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if !question["questionImage"].string.isEmpty {
                                QuestionImage(source: question["questionImage"].string)
                                    .frame(maxWidth: .infinity, maxHeight: 340 * scale)
                            }
                            content(question, scale: scale)
                            if showResults {
                                resultsPanel(question)
                            }
                            if let liveError {
                                Label(liveError, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                            }
                        }
                        .frame(maxWidth: 1100 * scale, alignment: .leading)
                        .padding(.horizontal, 50 * scale).padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollEdgeEffectStyle(.soft, for: .all)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { controls(quiz) }
                .navigationTitle(quiz.title)
                .confirmationDialog("Lancer la participation en ligne ?", isPresented: $confirmLive, titleVisibility: .visible) {
                    Button("Nouvelle session") { launch(quiz, resetResponses: true) }
                    Button("Conserver les réponses précédentes") { launch(quiz, resetResponses: false) }
                } message: {
                    Text("Le questionnaire sera envoyé sur le site. Une nouvelle session efface les réponses déjà recueillies pour ce questionnaire, comme sur le site. Chaque question dispose du temps de réponse choisi dans l’éditeur.")
                }
                .sheet(isPresented: $showJoin) {
                    if let url = store.participantURL(code: code) { JoinSheet(url: url, code: code) }
                }
                .task(id: isLive) {
                    guard isLive else { return }
                    while !Task.isCancelled {
                        do { try await store.refreshLive(code); liveError = nil }
                        catch is CancellationError { return }
                        catch { liveError = error.localizedDescription }
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Questionnaire indisponible", systemImage: "rectangle.stack")
                } description: {
                    Text("Ce questionnaire a été supprimé ou ne contient plus de question.")
                } actions: {
                    Button("Fermer la fenêtre") { dismissWindow() }
                }
            }
        }
        .frame(minWidth: 860, minHeight: 580)
        .background(.background)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: store.liveIndex) { if isLive { index = store.liveIndex; reveal = false } }
        .onChange(of: quiz?.questions.count ?? 0) { _, count in if index >= count { index = max(0, count - 1) } }
        .onDisappear {
            if isLive { Task { await store.stopLive() } }
        }
    }

    private func header(_ quiz: Quiz) -> some View {
        HStack {
            Text(quiz.title).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if isLive {
                HStack(spacing: 18) {
                    Label("En direct · \(code)", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    if let count = store.liveParticipants {
                        Label(count == 1 ? "1 participant" : "\(count) participants", systemImage: "person.2.fill")
                            .foregroundStyle(.secondary).contentTransition(.numericText())
                    }
                    let answers = responseCount
                    Label(answers == 1 ? "1 réponse" : "\(answers) réponses", systemImage: "checkmark.bubble.fill")
                        .foregroundStyle(.secondary).contentTransition(.numericText())
                    if let timing = store.liveTiming { CountdownView(timing: timing) }
                }
                .animation(.smooth, value: store.liveParticipants)
                .animation(.smooth, value: responseCount)
            } else {
                Label("Aperçu sur ce Mac", systemImage: "desktopcomputer").foregroundStyle(.secondary)
            }
        }
        .font(.headline)
    }

    @ViewBuilder private func content(_ question: Question, scale: CGFloat) -> some View {
        if question.kind.hasAnswers {
            // A ranking is stored in the expected order: never show that order before the correction.
            let order = question.kind == .ranking && !reveal
                ? question.answers.indices.sorted { question.answers[$0].plainText.localizedStandardCompare(question.answers[$1].plainText) == .orderedAscending }
                : Array(question.answers.indices)
            VStack(spacing: 12 * scale) {
                ForEach(Array(order.enumerated()), id: \.element) { position, i in
                    let good = reveal && correct(question, i)
                    HStack(spacing: 18) {
                        Text(question.kind == .ranking && reveal ? "\(i + 1)" : answerLetter(position))
                            .font(.system(size: 20 * scale, weight: .bold).monospacedDigit())
                            .foregroundStyle(good ? Color.white : Color.secondary)
                            .frame(width: 40 * scale, height: 40 * scale)
                            .background(good ? Color.green : Color.secondary.opacity(0.15), in: .circle)
                        Text(question.answers[i].plainText).font(.system(size: 24 * scale))
                        Spacer()
                        if good { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 24 * scale)) }
                    }
                    .padding(18 * scale)
                    .background(good ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 16))
                    .animation(.smooth, value: reveal)
                }
            }
        } else if question.kind == .cloze {
            Text(reveal ? clozeAnswer(question["clozeText"].string) : question["clozeText"].string.replacingOccurrences(of: "\\[[^\\]]*\\]|\\{\\{[^}]*\\}\\}", with: "________", options: .regularExpression))
                .font(.system(size: 26 * scale)).lineSpacing(12)
        } else if question.kind == .video {
            Button("Lire la vidéo dans le navigateur", systemImage: "play.rectangle") {
                if let url = videoURL(question) { openURL(url) }
            }
            .buttonStyle(.glass).controlSize(.extraLarge)
        } else if question.kind == .labelimage && reveal {
            ForEach(question["legendLabels"].array.indices, id: \.self) { i in
                let label = question["legendLabels"].array[i]
                Text("\(i + 1). \(label["text"].string) · X \(label["x"].int) %, Y \(label["y"].int) %").font(.title3)
            }
        } else {
            Label(question.kind == .rating ? "Une note de 1 à 5 étoiles" : "À vous de répondre", systemImage: question.kind.symbol)
                .font(.system(size: 24 * scale)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func resultsPanel(_ question: Question) -> some View {
        let result = currentResult
        VStack(alignment: .leading, spacing: 12) {
            Label("Réponses reçues", systemImage: "chart.bar").font(.headline).foregroundStyle(.secondary)
            if let result {
                ResultCard(question: question, index: index, result: result, compact: true)
            } else {
                Text(isLive ? "En attente des premières réponses…" : "Aucune réponse enregistrée pour cette question.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// Answers received for the question on screen.
    private var responseCount: Int {
        guard let result = currentResult else { return 0 }
        if result["total"].int > 0 { return result["total"].int }
        return result["results"].values.reduce(0) { $0 + $1.int } + result["openResponses"].array.count
    }

    private func launch(_ quiz: Quiz, resetResponses: Bool) {
        Task {
            await store.startLive(quiz, at: index, resetResponses: resetResponses)
            if isLive { index = store.liveIndex; showJoin = true }
        }
    }

    private var currentResult: JSONValue? {
        guard let source = store.archive.responses[code] else { return nil }
        if case .array(let rows) = source["questions"] {
            return rows.enumerated().last { offset, row in (row.object["questionIndex"]?.int ?? offset) == index }?.element
        }
        guard case .object(var fields) = source[String(index)] else { return nil }
        fields["results"] = fields["counts"]
        return .object(fields)
    }

    private func controls(_ quiz: Quiz) -> some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Button("Précédente", systemImage: "chevron.left") { navigate(-1, quiz: quiz) }
                        .disabled(index == 0 || store.busy).keyboardShortcut(.leftArrow, modifiers: []).presentationControl()
                    Text("\(index + 1) / \(quiz.questions.count)").monospacedDigit().foregroundStyle(.secondary)
                        .frame(minWidth: 54)
                    Button("Suivante", systemImage: "chevron.right") { navigate(1, quiz: quiz) }
                        .disabled(index >= quiz.questions.count - 1 || store.busy).keyboardShortcut(.rightArrow, modifiers: []).presentationControl()
                }
                .labelStyle(.iconOnly)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)

                HStack(spacing: 10) {
                    Toggle("Correction", systemImage: "checkmark.circle", isOn: $reveal)
                        .keyboardShortcut("c", modifiers: [])
                        .help("Afficher la correction (C)").presentationControl()
                    Toggle("Résultats", systemImage: "chart.bar", isOn: $showResults)
                        .keyboardShortcut("r", modifiers: [])
                        .help("Afficher les réponses reçues (R)").presentationControl()
                }
                .toggleStyle(.button)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)

                HStack(spacing: 10) {
                    if isLive {
                        Button("Relancer", systemImage: "timer") { Task { await store.restartQuestion() } }
                            .disabled(store.busy).keyboardShortcut("t", modifiers: [])
                            .help("Redonner du temps pour répondre à cette question (T)").presentationControl()
                        Button("Participer", systemImage: "qrcode") { showJoin = true }.presentationControl()
                        Button("Arrêter", systemImage: "stop.fill") { Task { await store.stopLive() } }
                            .disabled(store.busy).tint(.red).presentationControl()
                    } else {
                        Button("Lancer en direct", systemImage: "dot.radiowaves.left.and.right") {
                            if store.connected { confirmLive = true } else { openAccountSettings() }
                        }
                        .disabled(store.busy || store.liveCode != nil)
                        .presentationControl()
                        .help(store.liveCode != nil ? "Une autre session est déjà en direct." : store.connected ? "Recueillir les réponses des participants" : "Connectez-vous pour lancer une session en direct")
                    }
                    Button("Plein écran", systemImage: "arrow.up.left.and.arrow.down.right") {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    }
                    .labelStyle(.iconOnly).keyboardShortcut("f", modifiers: [.command, .control])
                    .help("Plein écran (⌃⌘F)").presentationControl()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        // Space advances like in Keynote.
        .background {
            Button("Suivante") { navigate(1, quiz: quiz) }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(index >= quiz.questions.count - 1 || store.busy)
                .hidden()
        }
    }

    private func openAccountSettings() {
        UserDefaults.standard.set(1, forKey: "settingsTab")
        openSettings()
    }
    private func navigate(_ delta: Int, quiz: Quiz) {
        let next = index + delta
        guard quiz.questions.indices.contains(next) else { return }
        if isLive { Task { await store.goLive(index: next, quiz: quiz); if store.liveIndex == next { index = next; reveal = false } } }
        else { index = next; reveal = false }
    }
    private func answerLetter(_ i: Int) -> String {
        i < 26 ? String(UnicodeScalar(UInt8(65 + i))) : "\(i + 1)"
    }
    private func correct(_ q: Question, _ i: Int) -> Bool {
        if q["isPollMode"].bool { return false }
        switch q.kind {
        case .multiple: return q["correctIndex"].int == i
        case .checkbox: return q["correctIndexes"].array.map(\.int).contains(i)
        case .ranking: return true
        default: return false
        }
    }
    private func clozeAnswer(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\\{\\{([^,}]+)[^}]*\\}\\}", with: "$1", options: .regularExpression)
    }
    private func videoURL(_ question: Question) -> URL? {
        guard let url = URL(string: question["youtubeUrl"].string), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "t" }
        if question["videoStartSec"].int > 0 { items.append(URLQueryItem(name: "t", value: "\(question["videoStartSec"].int)")) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}

struct JoinSheet: View {
    let url: URL
    let code: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Text("Rejoindre la session").font(.title2.bold())
            if let image = qrImage {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 240, height: 240)
                    .padding(16).background(.white, in: .rect(cornerRadius: 16)).accessibilityLabel("QR code pour rejoindre la session")
            }
            Text(code).font(.title.monospaced().bold()).textSelection(.enabled)
            Text(url.absoluteString).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
            HStack {
                Button("Copier le lien", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) }
                    .presentationControl()
                ShareLink(item: url) { Label("Partager", systemImage: "square.and.arrow.up") }
                    .presentationControl()
                Button("Terminé") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.glassProminent)
                    .presentationControl()
            }
        }.padding(32).frame(width: 430)
    }
    private var qrImage: NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 240, height: 240))
    }
}

private extension View {
    /// Presentation controls are driven by the mouse and keyboard shortcuts. Without keyboard focus,
    /// no focus ring appears on the projected screen and Space never activates a focused button.
    func presentationControl() -> some View { focusable(false).focusEffectDisabled() }
}

/// Time left to answer, as the participants see it.
struct CountdownView: View {
    let timing: LiveTiming
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let now = context.date
            let left = Int(timing.endsAt.timeIntervalSince(now).rounded(.up))
            Group {
                if now < timing.startedAt {
                    Label("Départ…", systemImage: "timer").foregroundStyle(.secondary)
                } else if left > 0 {
                    Label(String(format: "%d:%02d", left / 60, left % 60), systemImage: "timer")
                        .monospacedDigit()
                        .foregroundStyle(left <= 5 ? Color.orange : Color.primary)
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    Label("Temps écoulé · T pour relancer", systemImage: "timer").foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .accessibilityLabel(left > 0 ? "Temps restant : \(left) secondes" : "Temps écoulé")
        }
    }
}
