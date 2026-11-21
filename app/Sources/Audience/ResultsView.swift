import SwiftUI
import Charts
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct ResultRow: Identifiable {
    var id: String { label }
    let label: String
    let count: Int
}

struct ResultsView: View {
    @Bindable var store: LibraryStore
    let quiz: Quiz
    @State private var refreshing = false
    @State private var refreshError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Résultats").font(.largeTitle.bold())
                        Text("\(quiz.questions.count) question(s) · Code \(quiz.code)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if refreshing { ProgressView().controlSize(.small) }
                    Button("Actualiser", systemImage: "arrow.clockwise") { Task { await refresh() } }
                        .disabled(!canRefresh || refreshing)
                        .help(canRefresh ? "Télécharger les dernières réponses" : "Connectez-vous pour récupérer les réponses")
                }
                if let refreshError {
                    Label(refreshError, systemImage: "exclamationmark.icloud").font(.callout).foregroundStyle(.orange)
                }
                let results = resultQuestions
                if results.isEmpty {
                    ContentUnavailableView("Aucune réponse enregistrée", systemImage: "chart.bar",
                        description: Text("Les résultats des sessions en ligne et des sauvegardes importées apparaîtront ici."))
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(quiz.questions.indices, id: \.self) { i in
                        if let result = results[i] {
                            ResultCard(question: quiz.questions[i], index: i, result: result)
                            if i < quiz.questions.count - 1 { Divider() }
                        }
                    }
                }
            }.padding(30).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(.background)
        .task(id: quiz.code) { if canRefresh { await refresh() } }
    }
    private var canRefresh: Bool { store.connected }
    private func refresh() async {
        refreshing = true; defer { refreshing = false }
        do { try await store.refreshResults(quiz.code); refreshError = nil }
        catch is CancellationError {}
        catch { refreshError = "Résultats non actualisés : \(error.localizedDescription)" }
    }
    private var resultQuestions: [Int: JSONValue] {
        guard let source = store.archive.responses[quiz.code] else { return [:] }
        if case .array(let rows) = source["questions"] {
            return Dictionary(rows.enumerated().map { index, row in (row.object["questionIndex"]?.int ?? index, row) }, uniquingKeysWith: { _, last in last })
        }
        // Electron stores one bucket per question rather than the server's questions array.
        var result: [Int: JSONValue] = [:]
        for (key, bucket) in source.object {
            guard let i = Int(key) else { continue }
            var fields = bucket.object
            fields["results"] = bucket["counts"]
            result[i] = .object(fields)
        }
        return result
    }
}

struct ResultCard: View {
    let question: Question
    let index: Int
    let result: JSONValue
    var compact = false
    private var rows: [ResultRow] {
        let counts = result["results"]
        if question.kind == .rating {
            return (1...5).map { ResultRow(label: "\($0) étoile(s)", count: counts[String($0)].int) }
        }
        if question.kind.hasAnswers {
            return question.answers.indices.map { ResultRow(label: "\($0 + 1). \(question.answers[$0].plainText)", count: counts[String($0)].int) }
        }
        return counts.object.keys.sorted().map { ResultRow(label: $0.plainText, count: counts[$0].int) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !compact {
                Label("Question \(index + 1) · \(question.kind.title)", systemImage: question.kind.symbol).font(.subheadline).foregroundStyle(.secondary)
                Text(question.text.plainText).font(.title3.weight(.semibold)).textSelection(.enabled)
            }
            if rows.contains(where: { $0.count > 0 }) {
                Chart(rows) { row in
                    BarMark(x: .value("Réponses", row.count), y: .value("Choix", row.label))
                        .foregroundStyle(Color.accentColor.gradient).cornerRadius(4)
                        .annotation(position: .trailing) { Text("\(row.count)").font(.caption).foregroundStyle(.secondary) }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: CGFloat(max(150, rows.count * 44)))
                .accessibilityLabel("Répartition des réponses")
            }
            let open = compact ? Array(result["openResponses"].array.suffix(12)) : result["openResponses"].array
            if !open.isEmpty {
                ForEach(open.indices, id: \.self) { i in
                    Text(open[i].string.isEmpty ? open[i]["text"].string : open[i].string)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(.quaternary, in: .rect(cornerRadius: 8))
                }
            }
            if !rows.contains(where: { $0.count > 0 }) && open.isEmpty { Text("Aucune réponse pour cette question.").foregroundStyle(.secondary) }
        }
    }
}
