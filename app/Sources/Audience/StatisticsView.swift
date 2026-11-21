import SwiftUI
#if os(macOS)
import AppKit
#endif
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct StatisticsView: View {
    @Bindable var store: LibraryStore
    let quiz: Quiz
    @Environment(LocalAIStore.self) private var ai
    @State private var refreshing = false
    @State private var refreshError: String?
    @State private var showModels = false
    @State private var generation: Task<Void, Never>?
    @State private var generationID: UUID?
    @State private var partial = ""
    @State private var generationError: String?

    private var responses: JSONValue { store.archive.responses[quiz.code] ?? .null }
    private var statistics: QuizStatistics { QuizStatistics(quiz: quiz, responses: responses) }
    private var synthesis: LocalAIStore.Synthesis? {
        guard let report = ai.syntheses[quiz.code], report.statistics == statistics, report.title == quiz.title else { return nil }
        return report
    }
    var body: some View {
        let stats = statistics
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Statistiques").font(.largeTitle.bold())
                        Text("\(stats.questions.count) question(s) · Code \(quiz.code)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if refreshing { ProgressView().controlSize(.small) }
                    Button("Actualiser", systemImage: "arrow.clockwise") { Task { await refresh() } }
                        .disabled(!store.connected || refreshing)
                }
                if let refreshError { Text(refreshError).font(.callout).foregroundStyle(.orange) }
                if !stats.hasResponses {
                    ContentUnavailableView("Aucune réponse à analyser", systemImage: "chart.bar.xaxis",
                                           description: Text("Recueillez des réponses en direct ou importez une sauvegarde avec ses résultats."))
                        .frame(maxWidth: .infinity, minHeight: 230)
                } else {
                    overview(stats)
                    #if os(macOS)
                    synthesisSection(stats)
                    #endif
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Par question").font(.title2.bold())
                        ForEach(stats.questions) { question in
                            StatisticsQuestionCard(statistics: question)
                            if question.id != stats.questions.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(30).frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(.background)
        .task(id: quiz.code) { if store.connected { await refresh() } }
        .onChange(of: responses) { cancelGeneration() }
        .onChange(of: quiz) { cancelGeneration() }
        .onDisappear { cancelGeneration() }
        .sheet(isPresented: $showModels) {
            VStack(spacing: 0) {
                HStack {
                    Text("Modèles locaux").font(.title2.bold())
                    Spacer()
                    Button("Terminé") { showModels = false }.keyboardShortcut(.cancelAction)
                }.padding(20)
                LocalModelsView()
            }.frame(width: 640, height: 680)
        }
    }
    private func overview(_ stats: QuizStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 20) {
                metric("Réponses reçues", value: stats.submissions.map(String.init) ?? "Indéterminé")
                metric("Réponses justes", value: "\(stats.correct)", color: .green)
                metric("Réponses fausses", value: "\(stats.incorrect)", color: .red)
                metric("Réussite", value: stats.successRate.map { "\(Int(($0 * 100).rounded())) %" } ?? "—")
            }
            if let people = stats.participants {
                Text("\(people) participant(s) identifié(s) dans les réponses.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Une réponse correspond à une soumission à une question. Le taux de réussite porte uniquement sur les réponses évaluées. Réponses libres, sondages et données insuffisantes restent non évalués.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
    private func synthesisSection(_ stats: QuizStatistics) -> some View {
        @Bindable var ai = ai
        return GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Synthèse locale", systemImage: "text.alignleft").font(.title3.bold())
                    Spacer()
                    Button("Modèles…", systemImage: "internaldrive") { showModels = true }
                }
                Text("Résumé des résultats, difficultés fréquentes et pistes de reprise.").foregroundStyle(.secondary)
                HStack {
                    if !ai.models.isEmpty {
                        Picker("Modèle", selection: $ai.selectedModel) {
                            ForEach(ai.models) { Text($0.name).tag($0.name) }
                        }.frame(maxWidth: 320)
                    } else {
                        Text("Choisissez ou téléchargez un modèle dans Modèles…").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if generationID != nil {
                        ProgressView().controlSize(.small)
                        Button("Annuler", action: cancelGeneration)
                    } else {
                        Button(synthesis == nil ? "Générer la synthèse" : "Régénérer", systemImage: "text.badge.plus") { generate(stats) }
                            .disabled(ai.checking || !ai.available || !ai.models.contains(where: { $0.name == ai.selectedModel }) || ai.downloading != nil)
                    }
                }
                if let error = generationError { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
                if generationID != nil {
                    Text(partial.isEmpty ? "Le modèle prépare la synthèse…" : partial).textSelection(.enabled)
                } else if let report = synthesis {
                    Text(report.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text("\(report.model) · \(report.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Copier", systemImage: "doc.on.doc") {
                            PlatformClipboard.copy(report.text)
                        }
                    }
                    Text("Synthèse générée par un modèle : vérifiez ses interprétations avant de les utiliser.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(12)
        }
        .task { await ai.refresh() }
    }
    private func generate(_ stats: QuizStatistics) {
        cancelGeneration()
        generationError = nil
        let id = UUID(), model = ai.selectedModel, title = quiz.title, code = quiz.code
        generationID = id
        generation = Task { @MainActor in
            defer { if generationID == id { generationID = nil; generation = nil; partial = "" } }
            do {
                let text = try await ai.client.synthesize(model: model, evidence: stats.synthesisEvidence(title: title)) { text in
                    await updatePartial(text, id: id)
                }
                try Task.checkCancellation()
                guard generationID == id, stats == statistics, title == quiz.title else { return }
                ai.syntheses[code] = .init(statistics: stats, title: title, text: text, model: model, date: Date())
            } catch is CancellationError {} catch {
                if generationID == id, !Task.isCancelled { generationError = ai.message(error) }
            }
        }
    }
    @MainActor private func updatePartial(_ text: String, id: UUID) { if generationID == id { partial = text } }
    private func cancelGeneration() {
        generation?.cancel(); generation = nil; generationID = nil; partial = ""
    }
    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do { try await store.refreshResults(quiz.code); refreshError = nil }
        catch is CancellationError {} catch { refreshError = "Résultats non actualisés : \(error.localizedDescription)" }
    }
}

struct StatisticsQuestionCard: View {
    let statistics: QuestionStatistics
    var body: some View {
        let q = statistics
        VStack(alignment: .leading, spacing: 12) {
            Label("Question \(q.index + 1) · \(q.kind.title)", systemImage: q.kind.symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(q.title).font(.title3.weight(.semibold)).textSelection(.enabled)
            FlowLayout(spacing: 18) {
                Text(q.submissions.map { "\($0) réponse(s)" } ?? "\(q.selections) choix sélectionnés")
                Label("\(q.correct) justes", systemImage: "checkmark.circle").foregroundStyle(.green)
                Label("\(q.incorrect) fausses", systemImage: "xmark.circle").foregroundStyle(.red)
                if let ungraded = q.ungraded, ungraded > 0 { Text("\(ungraded) non évaluée(s)").foregroundStyle(.secondary) }
            }.font(.callout)
            if let note = q.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            if q.frequencies.isEmpty { Text("Aucune réponse enregistrée.").foregroundStyle(.secondary) }
            else {
                Text(q.kind == .checkbox ? "Choix les plus fréquents" : "Réponses les plus fréquentes").font(.subheadline.weight(.medium))
                ForEach(q.frequencies.prefix(5)) { answer in
                    HStack(alignment: .firstTextBaseline) {
                        Text(answer.label).lineLimit(3).textSelection(.enabled)
                        Spacer(minLength: 20)
                        Text("\(answer.count)").monospacedDigit().fontWeight(.semibold)
                    }
                }
                if q.frequencies.count > 5 {
                    DisclosureGroup("Voir les \(q.frequencies.count - 5) autres réponses") {
                        ForEach(q.frequencies.dropFirst(5)) { answer in
                            HStack { Text(answer.label).textSelection(.enabled); Spacer(); Text("\(answer.count)").monospacedDigit() }.padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}
