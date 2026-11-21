import Foundation

/// Builds the same final-report CSV as the website (`buildFinalReportCsv` in audience.js):
/// one row per question, one column per participant.
public enum ResultsCSV {
    /// Returns nil when the questionnaire has no question to export.
    public static func build(quiz: Quiz, responses: JSONValue) -> String? {
        let questions = reportQuestions(quiz: quiz, responses: responses)
        guard !questions.isEmpty else { return nil }
        let roster = participantRoster(questions)
        var lines: [[String]]
        if roster.isEmpty {
            // Without participant details (older backups), responses fill anonymous columns.
            let collected = questions.map(collectResponses)
            let width = collected.map(\.count).max() ?? 0
            lines = [["question"] + (0..<width).map { "participant_\($0 + 1)" }]
            for (question, values) in zip(questions, collected) {
                lines.append([question["question"].string.plainText] + (0..<width).map { $0 < values.count ? values[$0] : "" })
            }
        } else {
            lines = [["question"] + roster.map(\.label)]
            for question in questions {
                var answers: [String: String] = [:]
                for entry in question["participantResponses"].array {
                    let key = entry["participantKey"].string.trimmed
                    let text = entry["responseText"].string.trimmed
                    guard !key.isEmpty, !text.isEmpty else { continue }
                    answers[key] = answers[key].map { "\($0) | \(text)" } ?? text
                }
                lines.append([question["question"].string.plainText] + roster.map { answers[$0.key] ?? "" })
            }
        }
        return lines.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
    }

    public static func filename(code: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "audience-bilan-\(code.isEmpty ? "session" : code)-\(formatter.string(from: date)).csv"
    }

    /// Server results carry a `questions` array; Electron backups keep one bucket per question index.
    static func reportQuestions(quiz: Quiz, responses: JSONValue) -> [JSONValue] {
        if case .array(let rows) = responses["questions"] {
            return rows.enumerated().map { offset, row in
                let index = row.object["questionIndex"]?.int ?? offset
                guard quiz.questions.indices.contains(index) else { return row }
                // Fill anything the server row lacks from the local question.
                return .object(quiz.questions[index].fields.merging(row.object) { _, server in server })
            }
        }
        return quiz.questions.indices.map { index in
            var fields = quiz.questions[index].fields
            let bucket = responses[String(index)]
            fields["results"] = bucket["counts"]
            fields["openResponses"] = bucket["openResponses"]
            fields["participantResponses"] = .array([])
            return .object(fields)
        }
    }

    static func collectResponses(_ question: JSONValue) -> [String] {
        let counts = question["results"]
        switch QuestionKind(rawValue: question["type"].string.lowercased()) ?? .multiple {
        case .open, .wordcloud, .cloze, .labelimage, .ranking:
            return question["openResponses"].array
                .map { ($0.string.isEmpty ? $0["text"].string : $0.string).trimmed }
                .filter { !$0.isEmpty }
        case .video:
            return []
        case .rating:
            let declared = question["maxRating"].int
            let maxRating = declared >= 2 ? declared : 5
            return (1...maxRating).flatMap { Array(repeating: String($0), count: max(0, counts[String($0)].int)) }
        case .multiple, .checkbox:
            return question["answers"].array.enumerated().flatMap { index, answer in
                Array(repeating: answer.string.plainText, count: max(0, counts[String(index)].int))
            }
        }
    }

    static func participantRoster(_ questions: [JSONValue]) -> [(key: String, label: String)] {
        var roster: [(key: String, label: String)] = []
        var keys = Set<String>(), labels = Set<String>()
        for question in questions {
            for (offset, entry) in question["participantResponses"].array.enumerated() {
                var key = entry["participantKey"].string.trimmed
                if key.isEmpty { key = "participant-\(roster.count + offset + 1)" }
                guard keys.insert(key).inserted else { continue }
                let name = entry["participantName"].string.trimmed
                let base = name.isEmpty ? "participant_\(roster.count + 1)" : name
                var label = base, duplicate = 2
                while labels.contains(label) { label = "\(base) (\(duplicate))"; duplicate += 1 }
                labels.insert(label)
                roster.append((key, label))
            }
        }
        return roster
    }

    static func escape(_ value: String) -> String {
        // Scalars, not Characters: "\r\n" is a single Character in Swift.
        guard value.unicodeScalars.contains(where: { "\",\n\r".unicodeScalars.contains($0) }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
