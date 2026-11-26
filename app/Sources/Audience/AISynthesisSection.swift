import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// The summary of a questionnaire's results by an online assistant (ChatGPT with the account,
/// or Claude, Gemini or Groq with an API key).
struct AISynthesisSection: View {
    let quiz: Quiz
    let statistics: QuizStatistics

    /// The summaries already written, kept for the session and dropped when the results change.
    @Environment(LocalAIStore.self) private var cache
    @ObservedObject private var chatGPT = ChatGPTAuth.shared
    private let keys = AIKeyStore.shared
    @AppStorage("ai.provider") private var providerID = QuizProvider.chatGPT.rawValue
    @State private var generation: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var error: String?
    @State private var managing = false
    #if os(macOS)
    private let tapVerb = "cliquez sur"
    #else
    private let tapVerb = "touchez"
    #endif

    private var generating: Bool { generationID != nil }

    private func isConnected(_ service: QuizProvider) -> Bool {
        service.usesAccount ? chatGPT.activeAccount?.canUsePlan == true : keys.connected.contains(service)
    }
    private var connectedProviders: [QuizProvider] { QuizProvider.allCases.filter(isConnected) }
    /// The preferred assistant when it is connected, otherwise the first one that is.
    private var provider: QuizProvider? {
        if let saved = QuizProvider(rawValue: providerID), isConnected(saved) { return saved }
        return connectedProviders.first
    }
    private var synthesis: LocalAIStore.Synthesis? {
        guard let report = cache.assistantSyntheses[quiz.code], report.statistics == statistics, report.title == quiz.title else { return nil }
        return report
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Synthèse par un assistant IA", systemImage: "sparkles").font(.title3.bold())
                Text("Résumé des résultats, difficultés fréquentes et pistes de reprise.").foregroundStyle(.secondary)
                if let provider { controls(provider) } else { connectPrompt }
                if let error { AIErrorLabel(text: error) }
                if generating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("\(provider?.name ?? "L’assistant") rédige la synthèse…").foregroundStyle(.secondary)
                    }
                } else if let report = synthesis {
                    result(report)
                }
            }.padding(12)
        }
        .task(id: provider?.rawValue) { if let provider { await keys.refreshModels(provider) } }
        .onChange(of: statistics) { cancel() }
        .onChange(of: quiz) { cancel() }
        .onDisappear { cancel() }
        .sheet(isPresented: $managing) {
            NavigationStack {
                Form { AIAssistantsSection() }
                    .formStyle(.grouped)
                    .navigationTitle("Assistants IA")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { managing = false } } }
            }
            #if os(macOS)
            .frame(width: 640, height: 520)
            #endif
            .presentationSizing(.form)
        }
    }

    // MARK: Pieces

    private var connectPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connectez ChatGPT avec votre compte, ou Claude, Gemini ou Groq avec une clé API, pour obtenir une synthèse de ces résultats.")
                .foregroundStyle(.secondary)
            Button("Connecter un assistant…", systemImage: "link") { managing = true }.buttonStyle(.borderedProminent)
        }
    }

    private func controls(_ service: QuizProvider) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("Assistant", selection: Binding(get: { service.rawValue }, set: { providerID = $0 })) {
                    ForEach(connectedProviders) { Text($0.name).tag($0.rawValue) }
                }.pickerStyle(.menu).disabled(generating)
                Button("Gérer…", systemImage: "slider.horizontal.3") { managing = true }.disabled(generating)
                Spacer(minLength: 0)
            }
            if generating {
                Button("Annuler", action: cancel).buttonStyle(.bordered)
            } else {
                Button(synthesis == nil ? "Générer la synthèse" : "Régénérer", systemImage: "text.badge.plus") { generate(service) }
                    .buttonStyle(.borderedProminent)
            }
            AIFootnote(text: "Quand vous \(tapVerb) le bouton, les énoncés, les chiffres et les réponses les plus fréquentes (réponses libres comprises) sont envoyés à \(service.company). Les noms et identifiants des participants ne le sont jamais.")
        }
    }

    private func result(_ report: LocalAIStore.Synthesis) -> some View {
        let text = Self.attributed(report.text)
        return VStack(alignment: .leading, spacing: 12) {
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("\(report.model) · \(report.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copier", systemImage: "doc.on.doc") { PlatformClipboard.copy(String(text.characters)) }
            }
            Text("Synthèse générée par un modèle : vérifiez ses interprétations avant de les utiliser.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private static func attributed(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }

    // MARK: Generation

    private func generate(_ service: QuizProvider) {
        cancel(); error = nil
        let id = UUID(), stats = statistics, title = quiz.title, code = quiz.code
        generationID = id
        generation = Task { @MainActor in
            defer { if generationID == id { generationID = nil; generation = nil } }
            do {
                let key = service.usesAccount ? "" : try keys.key(for: service)
                let model = service.usesAccount ? "" : (keys.model(for: service) ?? "")
                guard service.usesAccount || !model.isEmpty else { throw AudienceError.message("Aucun modèle n’est choisi pour \(service.name).") }
                let reply = try await service.complete(model: model, key: key, system: QuizStatistics.synthesisInstructions,
                                                       prompt: stats.synthesisEvidence(title: title))
                try Task.checkCancellation()
                // The results may have changed while the assistant was writing: that summary would describe old figures.
                guard generationID == id, stats == statistics, title == quiz.title else { return }
                let text = QuizAIText.readableSummary(reply)
                guard !text.isEmpty else { throw AudienceError.message("\(service.name) n’a renvoyé aucune synthèse. Réessayez.") }
                cache.assistantSyntheses[code] = .init(statistics: stats, title: title, text: text,
                                              model: model.isEmpty ? service.name : "\(service.name) · \(model)", date: Date())
            } catch is CancellationError {} catch {
                guard generationID == id, !Task.isCancelled else { return }
                if service == .chatGPT { chatGPT.handleAPIError(error) }
                self.error = error.localizedDescription
            }
        }
    }

    private func cancel() {
        generation?.cancel(); generation = nil; generationID = nil
    }
}
