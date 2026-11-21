import Compression
import Foundation

/// Reads the Markdown format of the website: the files it exports (one per questionnaire,
/// alone or in its ZIP archive) and the questionnaires typed by hand in the same format.
/// The rules follow `parseQuizMarkdown` in audience.js so a file reads the same in both.
public enum QuizMarkdown {
    public static func parse(_ markdown: String) throws -> Quiz {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var quiz = Quiz()
        if let line = lines.first(where: { $0.trimmed.matches("^#\\s+") }) {
            quiz.title = unescape(line.trimmed.substituting("^#\\s+"))
        } else {
            quiz.title = "Questionnaire importé"
        }
        if quiz.title.isEmpty { quiz.title = "Questionnaire importé" }
        var report = false, requireName = true
        for line in lines {
            if let value = line.trimmed.capture("^-\\s*rapport\\s+participant\\s*:\\s*(.+)$")?[0] {
                report = parseFlag(unescape(value), falseWords: offWords, trueWords: onWords) ?? false
                break
            }
        }
        for line in lines {
            if let value = line.trimmed.capture("^-\\s*nom\\s+participant\\s*:\\s*(.+)$")?[0] {
                requireName = parseFlag(unescape(value), falseWords: offWords + ["optionnel", "anonyme"],
                                        trueWords: onWords + ["requis", "obligatoire"]) ?? true
                break
            }
        }
        quiz["participantReportEnabled"] = .bool(report)
        quiz["requireParticipantName"] = .bool(requireName)

        let headers = lines.indices.filter { lines[$0].trimmed.matches("^##\\s+question\\b") }
        guard !headers.isEmpty else { throw AudienceError.message("Aucune section « Question » trouvée dans ce fichier Markdown.") }
        var questions: [Question] = []
        for (n, start) in headers.enumerated() {
            let end = n + 1 < headers.count ? headers[n + 1] : lines.count
            if let question = parseQuestion(lines[(start + 1)..<end].map(\.trimmed)) { questions.append(question) }
        }
        guard !questions.isEmpty else { throw AudienceError.message("Aucune question exploitable trouvée dans le fichier.") }
        quiz.questions = questions
        return quiz
    }

    /// Questionnaires of a ZIP archive exported from the website, in the archive's order.
    public static func parseArchive(_ data: Data) throws -> [Quiz] {
        let files = try ZipReader.entries(data).filter { entry in
            let name = entry.name.lowercased()
            return name.hasSuffix(".md") && !name.hasPrefix("__macosx/") && !(name as NSString).lastPathComponent.hasPrefix(".")
        }
        guard !files.isEmpty else { throw AudienceError.message("Cette archive ne contient aucun questionnaire Markdown (.md).") }
        return try files.map { file in
            guard let text = String(data: file.data, encoding: .utf8) else {
                throw AudienceError.message("Le fichier \(file.name) n’est pas encodé en UTF-8.")
            }
            do { return try parse(text) } catch {
                throw AudienceError.message("\(file.name) : \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Questions

    private static func parseQuestion(_ block: [String]) -> Question? {
        let text = unescape(block.first(where: { !$0.isEmpty && !$0.hasPrefix("-") }) ?? "")
        guard !text.isEmpty else { return nil }
        let bullets = block.filter { $0.matches("^-\\s+") }
        var choices: [String] = [], correct: [Int] = []
        var explicitType = "", mathFormat = false, imageURL = "", zoom = 1.0, visible = true
        var videoStart: Int?, videoEnd: Int?

        for line in bullets {
            if let c = line.capture("^-\\s+\\[([xX ])\\]\\s+(.+)$") {
                let answer = unescape(c[1])
                if !answer.isEmpty {
                    if c[0].lowercased() == "x" { correct.append(choices.count) }
                    choices.append(answer)
                }
                continue
            }
            if let value = line.capture("^-\\s*Type\\s*:\\s*(.+)$")?[0] { explicitType = value.lowercased() }
            if let value = (line.capture("^-\\s*(?:format|type)\\s+de\\s+r[ée]ponse\\s*:\\s*(.+)$")
                            ?? line.capture("^-\\s*r[ée]ponse\\s*:\\s*(.+)$"))?[0] {
                let format = value.trimmed.lowercased()
                mathFormat = ["math", "maths", "mathématique", "mathematique", "réponse mathématique",
                              "reponse mathematique", "latex"].contains(format)
            }
            if let value = line.capture("^-\\s*(?:URL\\s*)?image\\s*:\\s*(.+)$")?[0] { imageURL = unescape(value) }
            if let value = line.capture("^-\\s*(?:d[ée]but|debut)\\s*vid[ée]o(?:\\s*\\(s\\))?\\s*:\\s*(.+)$")?[0] {
                videoStart = videoSeconds(unescape(value))
            }
            if let value = line.capture("^-\\s*fin\\s*vid[ée]o(?:\\s*\\(s\\))?\\s*:\\s*(.+)$")?[0] {
                videoEnd = videoSeconds(unescape(value))
            }
            if let value = line.capture("^-\\s*(?:zoom(?:\\s+image)?|image\\s+zoom)\\s*:\\s*(.+)$")?[0],
               let number = Double(value.trimmed.replacingOccurrences(of: ",", with: ".")), number.isFinite {
                zoom = min(2.2, max(0.6, number))
            }
            if let value = (line.capture("^-\\s*r[ée]ponses?\\s+des\\s+participants\\s*:\\s*(.+)$")
                            ?? line.capture("^-\\s*afficher\\s+les\\s+r[ée]ponses?\\s+des\\s+participants\\s*:\\s*(.+)$"))?[0] {
                visible = parseFlag(unescape(value),
                                    falseWords: ["false", "0", "non", "no", "masquer", "masquées", "masquees", "cacher", "cachées", "cachees"],
                                    trueWords: ["true", "1", "oui", "yes", "afficher", "visibles"]) ?? true
            }
        }

        let cloze = section(block, "^-\\s*Texte\\s*(?:a|à)\\s*trous\\s*:") ?? ""
        let youtube = block.lazy.compactMap { $0.capture("^-\\s*URL\\s*vid[eé]o\\s*:\\s*(.+)$")?[0] }.first.map(unescape) ?? ""
        var ranking = (section(block, "^-\\s*[ée]l[ée]ments?\\s*[aà]\\s*classer\\s*:", inlineSeparator: "\\s*\\|\\s*") ?? "")
            .components(separatedBy: "\n").map(\.trimmed).filter { !$0.isEmpty }
        let labels = legendLabels(section(block, "^-\\s*[ée]tiquettes?\\s*:", inlineSeparator: "\\s*;\\s*") ?? "")

        let kind = questionKind(explicitType)
        let rankingHint = text.matches("class(?:e|er|ez|ement)|ordre|chronolog")
        if ranking.count < 2 && choices.count >= 2 && (kind == .ranking || (correct.isEmpty && rankingHint)) { ranking = choices }

        var q: Question
        func make(_ kind: QuestionKind) -> Question {
            var q = Question(kind: kind)
            q.text = text
            q.answers = []
            q["correctIndex"] = .null
            q["correctIndexes"] = .array([])
            q["participantResponsesVisible"] = .bool(visible)
            return q
        }
        switch kind {
        case .wordcloud, .rating: q = make(kind)
        case .cloze: q = make(.cloze); q["clozeText"] = .string(cloze)
        case .open: q = make(.open); q["responseFormat"] = .string(mathFormat ? "math" : "text")
        case _ where kind == .ranking || ranking.count >= 2: q = make(.ranking); q.answers = ranking
        case .video:
            q = make(.video)
            q["participantResponsesVisible"] = .bool(true)
            q["youtubeUrl"] = .string(youtube)
            let start = videoStart.flatMap { $0 > 0 ? $0 : nil }
            var end = videoEnd.flatMap { $0 > 0 ? $0 : nil }
            if let s = start, let e = end, e <= s { end = nil }
            q["videoStartSec"] = start.map { .number(Double($0)) } ?? .null
            q["videoEndSec"] = end.map { .number(Double($0)) } ?? .null
        case .labelimage:
            q = make(.labelimage)
            q["questionImage"] = .string(isValidImage(imageURL) ? imageURL : "")
            q["questionImageZoom"] = .number(zoom)
            q["legendLabels"] = .array(labels)
        case _ where choices.count >= 2 && (kind == .checkbox || correct.count > 1):
            q = make(.checkbox); q.answers = choices
            q["correctIndexes"] = .array(correct.map { .number(Double($0)) })
        case _ where choices.count >= 2 && kind != .checkbox:
            q = make(.multiple); q.answers = choices
            q["correctIndex"] = .number(Double(correct.last ?? 0))
        default: q = make(.open); q["responseFormat"] = .string("text")
        }
        return q
    }

    /// Same keyword detection as the website, so "notation en étoiles (1 à 5)" becomes a rating.
    static func questionKind(_ raw: String) -> QuestionKind {
        let t = raw.trimmed.lowercased()
        if t == "open" || t.contains("ouverte") || t.contains("open") { return .open }
        if t == "wordcloud" || t.contains("nuage") { return .wordcloud }
        if t == "rating" || t.contains("notation") || t.contains("etoile") || t.contains("étoile") { return .rating }
        if t == "cloze" || t.contains("trou") { return .cloze }
        if t == "video" || t.contains("vidéo") || t.contains("video") || t.contains("youtube") { return .video }
        if t == "ranking" || t == "rank" || ["classement", "classer", "ordre"].contains(where: t.contains) { return .ranking }
        if t == "labelimage" || ["legender", "légender", "étiquette", "etiquette"].contains(where: t.contains) { return .labelimage }
        if t == "checkbox" || t.contains("cocher") { return .checkbox }
        return .multiple
    }

    /// The value after `marker` on the same line, or the lines of the code block that follows it.
    private static func section(_ block: [String], _ marker: String, inlineSeparator: String? = nil) -> String? {
        if let value = block.lazy.compactMap({ $0.capture(marker + "\\s*(.+)$")?[0] }).first {
            let text = unescape(value)
            return inlineSeparator.map { text.substituting($0, with: "\n") } ?? text
        }
        guard let index = block.firstIndex(where: { $0.matches(marker + "\\s*$") }),
              index + 1 < block.count, block[index + 1].hasPrefix("```"),
              let close = block[(index + 2)...].firstIndex(of: "```") else { return nil }
        return block[(index + 2)..<close].joined(separator: "\n").trimmed
    }

    /// Labels written as JSON (website export), as "id | text | x | y", "text | x | y" or one text per line.
    static func legendLabels(_ source: String) -> [JSONValue] {
        let source = source.trimmed
        guard !source.isEmpty else { return [] }
        func coordinate(_ value: JSONValue?) -> Double? {
            switch value {
            case .number(let n)?: n
            case .string(let s)?: Double(s.trimmed.replacingOccurrences(of: ",", with: "."))
            default: nil
            }
        }
        var raw: [(id: String, text: String, x: Double?, y: Double?)] = []
        if source.hasPrefix("[") || source.hasPrefix("{"),
           let json = try? JSONDecoder().decode(JSONValue.self, from: Data(source.utf8)) {
            let entries = json.array.isEmpty ? json["labels"].array : json.array
            for (i, entry) in entries.enumerated() {
                switch entry {
                case .object(let f): raw.append((f["id"]?.string ?? "", f["text"]?.string ?? "", coordinate(f["x"]), coordinate(f["y"])))
                case .array(let a): raw.append((a.first?.string ?? "", a.count > 1 ? a[1].string : "",
                                                coordinate(a.count > 2 ? a[2] : nil), coordinate(a.count > 3 ? a[3] : nil)))
                default: raw.append(("lbl\(i + 1)", entry.string, nil, nil))
                }
            }
        } else {
            for line in source.components(separatedBy: "\n").map(\.trimmed) where !line.isEmpty {
                let clean = line.substituting("^-\\s+")
                let parts = clean.components(separatedBy: "|").map(\.trimmed)
                if parts.count >= 4 { raw.append((parts[0], parts[1], coordinate(.string(parts[2])), coordinate(.string(parts[3])))) }
                else if parts.count == 3 { raw.append(("", parts[0], coordinate(.string(parts[1])), coordinate(.string(parts[2])))) }
                else { raw.append(("", clean, nil, nil)) }
            }
        }
        return raw.enumerated().map { i, label in
            var id = label.id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
            if id.isEmpty { id = "lbl\(i + 1)" }
            var x = label.x.map { min(100, max(0, $0)) }, y = label.y.map { min(100, max(0, $0)) }
            // Older exports placed unpositioned labels at (0, 0).
            if let px = x, let py = y, px <= 1, py <= 1 { x = nil; y = nil }
            return .object(["id": .string(id), "text": .string(label.text.trimmed),
                            "x": x.map(JSONValue.number) ?? .null, "y": y.map(JSONValue.number) ?? .null])
        }
    }

    /// Accepts 90, "1:30", "1:02:03" or "1.30" (minutes.seconds).
    static func videoSeconds(_ raw: String) -> Int? {
        let raw = raw.trimmed
        guard !raw.isEmpty else { return nil }
        var seconds: Int
        if let c = raw.capture("^(\\d+):(\\d{1,2})(?::(\\d{1,2}))?$") {
            guard let a = Int(c[0]), let b = Int(c[1]), b <= 59 else { return nil }
            if c[2].isEmpty { seconds = a * 60 + b }
            else { guard let s = Int(c[2]), s <= 59 else { return nil }; seconds = a * 3600 + b * 60 + s }
        } else if let c = raw.capture("^(\\d+)[.,](\\d{1,2})$") {
            guard let m = Int(c[0]), let s = Int(c[1]), s <= 59 else { return nil }
            seconds = m * 60 + s
        } else {
            guard let n = Double(raw), n.isFinite, abs(n) < 1e9 else { return nil }
            seconds = Int(n)
        }
        return seconds < 0 ? nil : min(43_200, seconds)
    }

    private static func isValidImage(_ value: String) -> Bool {
        let v = value.trimmed
        return ["data:image/png;base64,", "data:image/jpeg;base64,", "data:image/webp;base64,", "data:image/gif;base64,",
                "uploads/"].contains(where: v.hasPrefix) || v.matches("^https?://")
    }

    private static let offWords = ["false", "0", "non", "no", "off", "disabled", "desactive", "desactivee", "désactivé", "désactivée"]
    private static let onWords = ["true", "1", "oui", "yes", "on", "active", "activee", "activé", "activée"]
    private static func parseFlag(_ value: String, falseWords: [String], trueWords: [String]) -> Bool? {
        let v = value.trimmed.lowercased()
        return falseWords.contains(v) ? false : trueWords.contains(v) ? true : nil
    }
    /// Removes the backslash the website puts before \, | and `.
    private static func unescape(_ value: String) -> String { value.substituting("\\\\([\\\\|`])", with: "$1").trimmed }
}

// MARK: - ZIP

/// Minimal reader for the ZIP archives of the website (stored or deflated entries).
enum ZipReader {
    static func entries(_ data: Data) throws -> [(name: String, data: Data)] {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { i + 2 <= bytes.count ? Int(bytes[i]) | Int(bytes[i + 1]) << 8 : 0 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        let invalid = AudienceError.message("Ce fichier n’est pas une archive ZIP valide.")
        guard bytes.count >= 22,
              let eocd = stride(from: bytes.count - 22, through: max(0, bytes.count - 22 - 65_535), by: -1)
                .first(where: { u32($0) == 0x0605_4B50 }) else { throw invalid }
        let count = u16(eocd + 10)
        var offset = u32(eocd + 16)
        var result: [(String, Data)] = []
        for _ in 0..<count {
            guard u32(offset) == 0x0201_4B50, offset + 46 <= bytes.count else { throw invalid }
            let flags = u16(offset + 8), method = u16(offset + 10)
            let compressed = u32(offset + 20), size = u32(offset + 24)
            let nameLength = u16(offset + 28), extra = u16(offset + 30), comment = u16(offset + 32)
            let local = u32(offset + 42)
            guard offset + 46 + nameLength <= bytes.count else { throw invalid }
            let nameBytes = Data(bytes[(offset + 46)..<(offset + 46 + nameLength)])
            let name = String(data: nameBytes, encoding: flags & 0x800 != 0 ? .utf8 : .isoLatin1)
                ?? String(decoding: nameBytes, as: UTF8.self)
            offset += 46 + nameLength + extra + comment
            if name.hasSuffix("/") { continue }
            guard u32(local) == 0x0403_4B50 else { throw invalid }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count, size <= 50_000_000 else { throw invalid }
            let payload = Data(bytes[start..<(start + compressed)])
            switch method {
            case 0: result.append((name, payload))
            case 8: result.append((name, try inflate(payload, size: size)))
            default: throw AudienceError.message("Méthode de compression non prise en charge dans \(name).")
            }
        }
        return result
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw AudienceError.message("Archive ZIP endommagée.") }
        return output
    }
}

// MARK: - Regular expressions

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
    private func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants of this file.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
    func matches(_ pattern: String) -> Bool {
        regex(pattern).firstMatch(in: self, range: NSRange(startIndex..., in: self)) != nil
    }
    /// Capture groups of the first match; a group that did not take part is "".
    func capture(_ pattern: String) -> [String]? {
        guard let m = regex(pattern).firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: self).map { String(self[$0]) } ?? "" }
    }
    func substituting(_ pattern: String, with template: String = "") -> String {
        regex(pattern).stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: template)
    }
}
