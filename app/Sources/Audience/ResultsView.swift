import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct ResultRow: Identifiable {
    var id: String { badge + label }
    /// Letter of the answer, as on the presentation screen (A, B, C…), or the star rating.
    let badge: String
    let label: String
    /// The label with its bold and italic parts, for answers written in Markdown.
    var styled: AttributedString? = nil
    let count: Int
    var correct = false
}

/// A cloze text split into plain text and blanks: `[réponse]` or `{{réponse, leurre…}}`.
struct ClozeTemplate {
    enum Part { case text(String), blank(String) }
    let parts: [Part]

    init(_ source: String) {
        var parts: [Part] = []
        var rest = Substring(source)
        let pattern = /\[([^\]]*)\]|\{\{([^}]*)\}\}/
        while let match = rest.firstMatch(of: pattern) {
            if match.range.lowerBound > rest.startIndex { parts.append(.text(String(rest[..<match.range.lowerBound]))) }
            let answer = match.output.1.map(String.init)
                ?? String(match.output.2?.split(separator: ",", maxSplits: 1).first ?? "")
            parts.append(.blank(answer.trimmingCharacters(in: .whitespaces)))
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { parts.append(.text(String(rest))) }
        self.parts = parts
    }

    var hasBlanks: Bool { parts.contains { if case .blank = $0 { true } else { false } } }

    /// The text with blanks hidden, or with the expected words highlighted for the correction.
    func rendered(reveal: Bool) -> AttributedString {
        parts.reduce(into: AttributedString()) { text, part in
            switch part {
            case .text(let s): text += AttributedString(s)
            case .blank(let answer):
                if reveal { text += Self.mark(answer, good: true) } else { text += AttributedString("________") }
            }
        }
    }

    /// A participant's full text, with each word written in a blank marked right or wrong.
    /// Returns nil when the text does not follow the template (then it is shown as is).
    func graded(_ response: String) -> AttributedString? {
        guard hasBlanks else { return nil }
        var regex = "^"
        for part in parts {
            switch part {
            case .text(let s): regex += NSRegularExpression.escapedPattern(for: s)
            case .blank: regex += "(.*?)"
            }
        }
        regex += "$"
        guard let re = try? NSRegularExpression(pattern: regex, options: [.dotMatchesLineSeparators]),
              let match = re.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)) else { return nil }
        var group = 0
        return parts.reduce(into: AttributedString()) { text, part in
            switch part {
            case .text(let s): text += AttributedString(s)
            case .blank(let answer):
                group += 1
                let written = Range(match.range(at: group), in: response).map { String(response[$0]) } ?? ""
                text += Self.mark(written.isEmpty ? "—" : written, good: Self.same(written, answer))
            }
        }
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).compare(b.trimmingCharacters(in: .whitespaces),
                                                       options: [.caseInsensitive], locale: Locale(identifier: "fr")) == .orderedSame
    }

    private static func mark(_ word: String, good: Bool) -> AttributedString {
        var piece = AttributedString(word)
        piece.foregroundColor = good ? .green : .red
        piece.backgroundColor = (good ? Color.green : Color.red).opacity(0.15)
        piece.inlinePresentationIntent = .stronglyEmphasized
        return piece
    }
}

struct ResultsView: View {
    @Bindable var store: LibraryStore
    let quiz: Quiz
    @State private var refreshing = false
    @State private var refreshError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ViewThatFits(in: .horizontal) {
                    HStack { reportTitle; reportActions }
                    VStack(alignment: .leading, spacing: 16) { reportTitle; reportActions }
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
            }.padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(.background)
        .task(id: quiz.code) { if canRefresh { await refresh() } }
    }
    private var reportTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Résultats").font(.largeTitle.bold())
            Text("\(quiz.questions.count) question(s) · Code \(quiz.code)").foregroundStyle(.secondary)
        }
    }
    private var reportActions: some View {
        HStack {
            if refreshing { ProgressView().controlSize(.small) }
            Button("Exporter en CSV", systemImage: "square.and.arrow.up") { store.exportResultsCSV(quiz) }
                .disabled(resultQuestions.isEmpty)
            Button("Actualiser", systemImage: "arrow.clockwise") { Task { await refresh() } }
                .disabled(!canRefresh || refreshing).iPadIconOnly()
        }.fixedSize(horizontal: true, vertical: false)
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
    /// Highlights the expected answers, as the correction does on the presentation screen.
    var showCorrect = true
    var scale: CGFloat = 1

    static func hasResponses(question: Question, result: JSONValue) -> Bool {
        result["results"].values.contains { $0.int > 0 } || !result["openResponses"].array.isEmpty
    }
    private var rows: [ResultRow] {
        let counts = result["results"]
        if question.kind == .rating {
            let declared = result["maxRating"].int
            return (1...(declared >= 2 ? declared : 5)).map {
                ResultRow(badge: "\($0)", label: $0 == 1 ? "1 étoile" : "\($0) étoiles", count: counts[String($0)].int)
            }
        }
        if question.kind.hasAnswers && question.kind != .ranking {
            return question.answers.indices.map {
                ResultRow(badge: Self.letter($0), label: RichText.answerPlainText(question.answers[$0]), styled: RichText.attributedAnswer(question.answers[$0]),
                          count: counts[String($0)].int, correct: showCorrect && isCorrect($0))
            }
        }
        return counts.object.keys.sorted().map { ResultRow(badge: "", label: $0.plainText, count: counts[$0].int) }
    }
    /// People who answered: for multiple choices, each person can count in several rows.
    private var respondents: Int {
        let people = result["participantResponses"].array.count
        if question.kind == .checkbox, people > 0 { return people }
        return max(result["total"].int, rows.reduce(0) { $0 + $1.count })
    }
    private func isCorrect(_ i: Int) -> Bool {
        guard !question["isPollMode"].bool else { return false }
        switch question.kind {
        case .multiple: return question["correctIndex"] != .null && question["correctIndex"].int == i
        case .checkbox: return question["correctIndexes"].array.map(\.int).contains(i)
        default: return false
        }
    }
    private static func letter(_ i: Int) -> String { i < 26 ? String(UnicodeScalar(UInt8(65 + i))) : "\(i + 1)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16 * scale) {
            if !compact {
                Label("Question \(index + 1) · \(question.kind.title)", systemImage: question.kind.symbol).font(.subheadline).foregroundStyle(.secondary)
                Text(RichText.attributed(question["question"].string)).font(.title3.weight(.semibold)).textSelection(.enabled)
            }
            let rows = rows
            if rows.contains(where: { $0.count > 0 }) {
                let total = max(respondents, 1)
                VStack(spacing: 14 * scale) {
                    ForEach(rows) { row in ResultBar(row: row, total: total, scale: scale) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Répartition des réponses")
            }
            let open = compact ? Array(result["openResponses"].array.suffix(12)) : result["openResponses"].array
            if !open.isEmpty {
                let cloze = question.kind == .cloze && showCorrect && !question["isPollMode"].bool
                    ? ClozeTemplate(question["clozeText"].string) : nil
                ForEach(open.indices, id: \.self) { i in
                    let response = open[i].string.isEmpty ? open[i]["text"].string : open[i].string
                    Text(cloze?.graded(response) ?? AttributedString(response))
                        .font(.system(size: 16 * scale))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12 * scale).background(.quaternary, in: .rect(cornerRadius: 10 * scale))
                }
            }
            if !rows.contains(where: { $0.count > 0 }) && open.isEmpty { Text("Aucune réponse pour cette question.").foregroundStyle(.secondary) }
        }
    }
}

/// One answer: its letter, its text, and a bar filled in proportion to the people who chose it.
struct ResultBar: View {
    let row: ResultRow
    let total: Int
    var scale: CGFloat = 1
    private var share: Double { min(1, Double(row.count) / Double(max(total, 1))) }
    private var tint: Color { row.correct ? .green : .accentColor }
    var body: some View {
        HStack(alignment: .center, spacing: 14 * scale) {
            if !row.badge.isEmpty {
                Text(row.badge)
                    .font(.system(size: 15 * scale, weight: .bold).monospacedDigit())
                    .foregroundStyle(row.correct ? Color.white : Color.secondary)
                    .frame(width: 32 * scale, height: 32 * scale)
                    .background(row.correct ? Color.green : Color.secondary.opacity(0.15), in: .circle)
            }
            VStack(alignment: .leading, spacing: 8 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
                    Text(row.styled ?? AttributedString(row.label)).font(.system(size: 17 * scale)).lineLimit(2)
                    if row.correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    Spacer(minLength: 12 * scale)
                    Text("\(row.count)").font(.system(size: 17 * scale, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("\(Int((share * 100).rounded())) %")
                        .font(.system(size: 15 * scale).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(minWidth: 48 * scale, alignment: .trailing)
                }
                Capsule().fill(Color.secondary.opacity(0.12))
                    .frame(height: 12 * scale)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule().fill(tint.gradient)
                                .frame(width: row.count > 0 ? max(12 * scale, geometry.size.width * share) : 0)
                        }
                    }
                    .clipShape(.capsule)
            }
        }
        .animation(.smooth(duration: 0.5), value: row.count)
        .animation(.smooth, value: row.correct)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.badge.isEmpty ? "" : row.badge + ", ")\(row.label) : \(row.count) réponse(s), \(Int((share * 100).rounded())) %\(row.correct ? ", bonne réponse" : "")")
    }
}
