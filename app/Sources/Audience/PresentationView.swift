import SwiftUI
import CoreImage.CIFilterBuiltins
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct PresentationView: View {
    @Bindable var store: LibraryStore
    let code: String
    @State private var index = 0
    @State private var previewStarted = false
    @State private var reveal = false
    @State private var showResults = false
    @State private var showJoin = false
    @State private var showingImage = false
    @State private var liveError: String?
    @State private var confirmLive = false
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismissWindow) private var dismissWindow
    #else
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @State private var confirmClose = false
    #endif
    private var quiz: Quiz? { store.archive.quizzes[code] }
    private var isLive: Bool { store.liveCode == code }
    // Opening a presentation always shows how to join, even before a live session is prepared.
    private var inLobby: Bool { isLive ? store.liveLobby : !previewStarted }

    var body: some View {
        Group {
            if let quiz, !quiz.isDeleted, quiz.questions.indices.contains(index) {
                let question = quiz.questions[index]
                GeometryReader { geometry in
                    let scale = min(max(geometry.size.width / 1200, 0.6), 1.8)
                    if inLobby, let url = store.participantURL(code: code) {
                        LobbyView(title: quiz.title, code: code, url: url, participants: store.liveParticipants, participationActive: isLive)
                    } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28 * scale) {
                            header(quiz)
                            Text(RichText.attributed(question["question"].string))
                                .font(.system(size: 38 * scale, weight: .semibold))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if !question["questionImage"].string.isEmpty {
                                Button { showingImage = true } label: {
                                    QuestionImage(source: question["questionImage"].string)
                                        .frame(maxWidth: .infinity, maxHeight: min(geometry.size.height * 0.6, 560 * scale))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Agrandir l’image de la question")
                                .help("Agrandir l’image")
                            }
                            content(question, scale: scale, videoMaxHeight: max(200, geometry.size.height - 80 - 210 * scale))
                            if showResults {
                                resultsPanel(question, scale: scale)
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
                .sheet(isPresented: $showingImage) {
                    QuestionImageViewer(source: question["questionImage"].string)
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
                    Button("Fermer") { closePresentation() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 860, minHeight: 580)
        #endif
        .background(.background)
        #if os(macOS)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        .safeAreaInset(edge: .top, alignment: .trailing) {
            HStack {
                Spacer()
                CloseButton {
                    if isLive { confirmClose = true } else { closePresentation() }
                }.buttonStyle(.glass).controlSize(.large).padding(.horizontal)
            }.frame(minHeight: 48)
        }
        .confirmationDialog("Arrêter la session et fermer la présentation ?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Arrêter et fermer", role: .destructive) {
                Task { await store.stopLive(); if !isLive { closePresentation() } }
            }
        }
        .sheet(isPresented: $showSettings) { IPadSettingsView(store: store) }
        .modifier(AudienceDialogs(store: store, active: !showSettings && !showJoin))
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
        .onChange(of: store.liveIndex) { if isLive { index = store.liveIndex; reveal = false } }
        .onChange(of: quiz?.questions.count ?? 0) { _, count in if index >= count { index = max(0, count - 1) } }
        .onDisappear {
            if isLive { Task { await store.stopLive() } }
        }
    }

    private func header(_ quiz: Quiz) -> some View {
        FlowLayout(spacing: 14) {
            Text(quiz.title).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if isLive {
                FlowLayout(spacing: 14) {
                    Label("En direct · \(code)", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    if let count = store.liveParticipants {
                        Label(count == 1 ? "1 participant" : "\(count) participants", systemImage: "person.2.fill")
                            .foregroundStyle(.secondary).contentTransition(.numericText())
                    }
                    let answers = responseCount
                    if !inLobby {
                    Label(answers == 1 ? "1 réponse" : "\(answers) réponses", systemImage: "checkmark.bubble.fill")
                        .foregroundStyle(.secondary).contentTransition(.numericText())
                    }
                    if let timing = store.liveTiming { CountdownView(timing: timing) }
                }
                .animation(.smooth, value: store.liveParticipants)
                .animation(.smooth, value: responseCount)
            } else {
                Label("Aperçu", systemImage: "play.rectangle").foregroundStyle(.secondary)
            }
        }
        .font(.headline)
    }

    @ViewBuilder private func content(_ question: Question, scale: CGFloat, videoMaxHeight: CGFloat) -> some View {
        if question.kind.hasAnswers {
            // A ranking is stored in the expected order: never show that order before the correction.
            let order = question.kind == .ranking && !reveal
                ? question.answers.indices.sorted { question.answers[$0].plainText.localizedStandardCompare(question.answers[$1].plainText) == .orderedAscending }
                : Array(question.answers.indices)
            VStack(spacing: 12 * scale) {
                ForEach(Array(order.enumerated()), id: \.element) { position, i in
                    let good = reveal && correct(question, i)
                    FlowLayout(spacing: 14) {
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
            Text(ClozeTemplate(question["clozeText"].string).rendered(reveal: reveal))
                .font(.system(size: 26 * scale)).lineSpacing(12)
        } else if question.kind == .video {
            if let video = YouTubeVideo(url: question["youtubeUrl"].string,
                                        start: question["videoStartSec"].int, end: question["videoEndSec"].int) {
                YouTubePlayer(video: video)
                    .frame(maxWidth: videoMaxHeight * 16 / 9, alignment: .leading)
                    .id("\(index)-\(video.embedURL.absoluteString)")
            } else {
                Label("Saisissez une URL YouTube valide dans l’éditeur.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
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

    @ViewBuilder private func resultsPanel(_ question: Question, scale: CGFloat) -> some View {
        let result = currentResult
        VStack(alignment: .leading, spacing: 18 * scale) {
            HStack {
                Label("Réponses reçues", systemImage: "chart.bar.fill")
                Spacer()
                let count = responseCount
                Text(count == 1 ? "1 réponse" : "\(count) réponses").monospacedDigit().contentTransition(.numericText())
            }
            .font(.system(size: 17 * scale, weight: .semibold)).foregroundStyle(.secondary)
            .animation(.smooth, value: responseCount)
            if let result, ResultCard.hasResponses(question: question, result: result) {
                ResultCard(question: question, index: index, result: result, compact: true, showCorrect: reveal, scale: scale)
            } else {
                Text(isLive ? "En attente des premières réponses…" : "Aucune réponse enregistrée pour cette question.")
                    .font(.system(size: 18 * scale)).foregroundStyle(.secondary)
            }
        }
        .padding(26 * scale)
        .glassEffect(.regular, in: .rect(cornerRadius: 24 * scale))
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
            if isLive { index = store.liveIndex; reveal = false }
        }
    }

    private func beginPresentation() {
        if isLive {
            Task {
                await store.beginLive()
                if !store.liveLobby { index = store.liveIndex; reveal = false }
            }
        } else {
            index = 0
            reveal = false
            showResults = false
            previewStarted = true
        }
    }

    private var launchLiveButton: some View {
        Button("Lancer en direct", systemImage: "dot.radiowaves.left.and.right") {
            if store.connected { confirmLive = true } else { openAccountSettings() }
        }
        .disabled(store.busy || store.liveCode != nil)
        .help(store.liveCode != nil ? "Une autre session est déjà en direct." : store.connected ? "Recueillir les réponses des participants" : "Connectez-vous pour lancer une session en direct")
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

    @ViewBuilder private func controls(_ quiz: Quiz) -> some View {
        #if os(iOS)
        iPadControls(quiz)
        #else
        if inLobby { lobbyControls } else { questionControls(quiz) }
        #endif
    }

    #if os(macOS)
    private var lobbyControls: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Button(action: beginPresentation) {
                    Label(!isLive || store.liveIndex == 0 ? "Commencer" : "Commencer à la question \(store.liveIndex + 1)", systemImage: "play.fill")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.glassProminent).controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction).disabled(store.busy)
                .help(isLive ? "Afficher la première question sur les téléphones (Entrée ou espace)" : "Afficher la première question en aperçu (Entrée ou espace)").presentationControl()

                HStack(spacing: 10) {
                    if let url = store.participantURL(code: code) {
                        Button("Copier le lien", systemImage: "doc.on.doc") {
                            PlatformClipboard.copy(url.absoluteString)
                        }.presentationControl()
                    }
                    if isLive {
                        Button("Arrêter", systemImage: "stop.fill") { Task { await store.stopLive() } }
                            .disabled(store.busy).tint(.red).presentationControl()
                    } else {
                        launchLiveButton.presentationControl()
                    }
                    Button("Plein écran", systemImage: "arrow.up.left.and.arrow.down.right") {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    }
                    .labelStyle(.iconOnly).keyboardShortcut("f", modifiers: [.command, .control])
                    .help("Plein écran (⌃⌘F)").presentationControl()
                }
                .buttonStyle(.borderless).controlSize(.large)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            Button("Commencer", action: beginPresentation)
                .keyboardShortcut(.space, modifiers: []).disabled(store.busy).hidden()
        }
    }

    private func questionControls(_ quiz: Quiz) -> some View {
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
                        launchLiveButton.presentationControl()
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

    #endif

    private func closePresentation() {
        #if os(macOS)
        dismissWindow()
        #else
        dismiss()
        #endif
    }

    #if os(iOS)
    private func iPadControls(_ quiz: Quiz) -> some View {
        VStack(spacing: 12) {
            if inLobby {
                HStack {
                    Button("Commencer", systemImage: "play.fill", action: beginPresentation)
                        .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    if isLive {
                        Button("Arrêter", systemImage: "stop.fill") { Task { await store.stopLive() } }.tint(.red)
                            .labelStyle(.iconOnly)
                    } else {
                        launchLiveButton
                    }
                    if let url = store.participantURL(code: code) {
                        Button("Copier le lien", systemImage: "doc.on.doc") { PlatformClipboard.copy(url.absoluteString) }
                            .labelStyle(.iconOnly)
                    }
                }
            } else {
                HStack(spacing: 24) {
                    Button("Précédente", systemImage: "chevron.left") { navigate(-1, quiz: quiz) }
                        .disabled(index == 0).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    Text("\(index + 1) / \(quiz.questions.count)").monospacedDigit()
                    Button("Suivante", systemImage: "chevron.right") { navigate(1, quiz: quiz) }
                        .disabled(index >= quiz.questions.count - 1).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    Spacer(minLength: 0)
                    Menu("Session", systemImage: "ellipsis.circle") {
                        if isLive {
                            Button("Participer", systemImage: "qrcode") { showJoin = true }
                            Button("Relancer le minuteur", systemImage: "timer") { Task { await store.restartQuestion() } }
                            Button("Arrêter", systemImage: "stop.fill", role: .destructive) { Task { await store.stopLive() } }
                        } else {
                            launchLiveButton
                        }
                    }.frame(minWidth: 44, minHeight: 44)
                }
                HStack {
                    Toggle("Correction", systemImage: "checkmark.circle", isOn: $reveal)
                    Toggle("Résultats", systemImage: "chart.bar", isOn: $showResults)
                }.toggleStyle(.button)
            }
        }
        .buttonStyle(.glass).controlSize(.large)
        .disabled(store.busy).padding(.horizontal, 20).padding(.vertical, 10)
    }
    #endif

    private func openAccountSettings() {
        UserDefaults.standard.set(1, forKey: "settingsTab")
        #if os(macOS)
        openSettings()
        #else
        showSettings = true
        #endif
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
}

struct JoinSheet: View {
    let url: URL
    let code: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Text("Rejoindre la session").font(.title2.bold())
            if let image = qrImage {
                Image(platformImage: image).interpolation(.none).resizable().frame(width: 240, height: 240)
                    .padding(16).background(.white, in: .rect(cornerRadius: 16)).accessibilityLabel("QR code pour rejoindre la session")
            }
            Text(code).font(.title.monospaced().bold()).textSelection(.enabled)
            Text(url.absoluteString).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
            HStack {
                Button("Copier le lien", systemImage: "doc.on.doc") { PlatformClipboard.copy(url.absoluteString) }
                    .iPadIconOnly().presentationControl()
                ShareLink(item: url) { Label("Partager", systemImage: "square.and.arrow.up") }
                    .iPadIconOnly().presentationControl()
                DoneButton { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.glassProminent)
                    .presentationControl()
            }
        }.padding(24).frame(idealWidth: 430, maxWidth: 480)
    }
    private var qrImage: PlatformImage? { qrCode(for: url) }
}

/// QR code generated on this Mac, with a quiet zone so phones read it from a projector.
func qrCode(for url: URL) -> PlatformImage? {
    let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.absoluteString.utf8); filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
          let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
    #if os(macOS)
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    #else
    return UIImage(cgImage: cg)
    #endif
}

/// Waiting room shown before the first question: how to join, and who already did.
struct LobbyView: View {
    let title: String
    let code: String
    let url: URL
    let participants: Int?
    var participationActive = true
    /// The participant page without the code, for people typing the address by hand.
    private var entryAddress: String {
        let host = (url.host ?? "").replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        return host + url.path
    }
    var body: some View {
        GeometryReader { geometry in
            let fit = Self.fit(geometry.size)
            ScrollView {
                lobbyLayout(horizontal: fit.horizontal, scale: fit.scale)
                    // Centred in the window, instead of leaving the bottom half empty.
                    .frame(minHeight: geometry.size.height)
            }
        }
    }
    /// The layout and scale that show the lobby largest in this space. Its content is about
    /// 1160 × 660 points side by side at scale 1, and 700 × 1100 points stacked.
    private static func fit(_ size: CGSize) -> (horizontal: Bool, scale: CGFloat) {
        let side = min(size.width / 1160, size.height / 660)
        let stacked = min(size.width / 700, size.height / 1100)
        let horizontal = side >= stacked
        return (horizontal, min(max(horizontal ? side : stacked, 0.5), 2.2))
    }
    private func lobbyLayout(horizontal: Bool, scale: CGFloat) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .center, spacing: 64 * scale)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 24 * scale))
        return layout {
            VStack(alignment: .leading, spacing: 30 * scale) {
                VStack(alignment: .leading, spacing: 10 * scale) {
                    Text(title).font(.system(size: 22 * scale, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
                    Text("Rejoignez le questionnaire").font(.system(size: 54 * scale, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 16 * scale) {
                    step(1, scale: scale, Text("Scannez le QR code avec votre téléphone"))
                    step(2, scale: scale, Text("ou ouvrez **\(entryAddress)** et saisissez le code"))
                }
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text("CODE").font(.system(size: 16 * scale, weight: .semibold)).tracking(2 * scale).foregroundStyle(.secondary)
                    Text(code).font(.system(size: 88 * scale, weight: .bold, design: .rounded).monospacedDigit())
                        .tracking(8 * scale).textSelection(.enabled)
                }
                if participationActive { participantBadge(scale: scale) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let image = qrCode(for: url) {
                Image(platformImage: image).interpolation(.none).resizable().aspectRatio(1, contentMode: .fit)
                    .frame(width: 360 * scale)
                    .padding(26 * scale)
                    .background(.white, in: .rect(cornerRadius: 30 * scale))
                    .shadow(color: .black.opacity(0.12), radius: 24 * scale, y: 8 * scale)
                    .accessibilityLabel("QR code pour rejoindre le questionnaire")
            }
        }
        .frame(maxWidth: 1240 * scale)
        .padding(.horizontal, 60 * scale).padding(.vertical, 40 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func step(_ number: Int, scale: CGFloat, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14 * scale) {
            Text("\(number)").font(.system(size: 17 * scale, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 30 * scale, height: 30 * scale)
                .background(Color.accentColor, in: .circle)
            text.font(.system(size: 24 * scale)).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func participantBadge(scale: CGFloat) -> some View {
        let count = participants ?? 0
        return HStack(spacing: 12 * scale) {
            Circle().fill(count > 0 ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 12 * scale, height: 12 * scale)
                .phaseAnimator([1.0, 0.35]) { dot, opacity in dot.opacity(count > 0 ? 1 : opacity) } animation: { _ in .easeInOut(duration: 0.9) }
            Text(count == 0 ? "En attente des participants…" : count == 1 ? "1 participant connecté" : "\(count) participants connectés")
                .contentTransition(.numericText())
        }
        .font(.system(size: 22 * scale, weight: .semibold))
        .padding(.horizontal, 20 * scale).padding(.vertical, 12 * scale)
        .glassEffect(.regular, in: .capsule)
        .animation(.smooth, value: count)
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
                    Label("Temps écoulé", systemImage: "timer").foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .accessibilityLabel(left > 0 ? "Temps restant : \(left) secondes" : "Temps écoulé")
        }
    }
}
