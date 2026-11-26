import Foundation

/// A model an AI service offers to the connected key.
public struct AIModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// Reads the model lists of the services that connect with an API key, and picks a sensible default,
/// so nobody has to type a model identifier.
public enum AIModels {
    public enum Service: String, Sendable { case claude, gemini, groq }

    public static func parse(_ data: Data, service: Service) throws -> [AIModel] {
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        var seen = Set<String>()
        func keep(_ id: String, _ name: String) -> AIModel? {
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return AIModel(id: id, name: name.isEmpty ? id : name)
        }
        switch service {
        case .claude:
            return root["data"].array.compactMap { keep($0["id"].string, $0["display_name"].string) }
        case .gemini:
            let unwanted = ["embedding", "tts", "image", "live", "audio", "robotics", "computer-use", "aqa"]
            return root["models"].array.compactMap { entry in
                let id = entry["name"].string.replacingOccurrences(of: "models/", with: "", options: .anchored)
                guard id.hasPrefix("gemini"), !unwanted.contains(where: id.contains),
                      entry["supportedGenerationMethods"].array.contains(where: { $0.string == "generateContent" }) else { return nil }
                return keep(id, entry["displayName"].string)
            }
        case .groq:
            let unwanted = ["whisper", "guard", "tts", "playai", "orpheus", "safeguard", "embed"]
            return root["data"].array.compactMap { entry in
                let id = entry["id"].string
                guard !unwanted.contains(where: id.lowercased().contains), entry["active"] != .bool(false) else { return nil }
                return keep(id, "")
            }
        }
    }

    /// The model proposed first: capable, fast, and not a preview.
    public static func preferred(from models: [AIModel], service: Service) -> String? {
        let ids = models.map(\.id)
        switch service {
        case .claude:
            return ids.first { $0.contains("sonnet") } ?? ids.first
        case .gemini:
            let stable = ids.filter { !$0.contains("preview") && !$0.contains("exp") && !$0.contains("lite") }
            let flash = stable.filter { $0.contains("flash") }
            return (flash.isEmpty ? stable : flash).max { version($0) < version($1) } ?? ids.first
        case .groq:
            return ids.first { $0 == "llama-3.3-70b-versatile" } ?? ids.first { $0.contains("70b") } ?? ids.first
        }
    }

    private static func version(_ id: String) -> Double {
        guard let range = id.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return 0 }
        return Double(id[range]) ?? 0
    }
}

public enum QuizAIText {
    /// Removes the global ```markdown fence some models put around their whole answer.
    public static func unfenced(_ text: String) -> String {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if lines.count > 1, ["```markdown", "```md", "```"].contains(lines[0].trimmingCharacters(in: .whitespaces).lowercased()),
           lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast(); lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An assistant's summary for `Text` with inline Markdown: its `#` headings become bold lines, which Text cannot draw as headings.
    public static func readableSummary(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hashes = trimmed.prefix { $0 == "#" }
            let rest = trimmed.dropFirst(hashes.count)
            guard (1...6).contains(hashes.count), rest.hasPrefix(" ") else { return line }
            let title = rest.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
            return title.isEmpty ? line : "**\(title)**"
        }.joined(separator: "\n")
    }

    /// What the questionnaire request adds to the source: size and free-form instructions.
    public static func brief(questionCount: Int, instructions: String) -> String {
        var text = "Écris environ \(questionCount) questions."
        let extra = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            text += " Consignes de l’enseignant, à respecter si elles ne contredisent pas le format Markdown :\n\(extra.prefix(1_000))"
        }
        return text
    }
}
