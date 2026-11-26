import Compression
import Foundation

/// Reads the Markdown format of the website: the files it exports (one per questionnaire,
/// alone or in its ZIP archive) and the questionnaires typed by hand in the same format.
/// The rules follow `parseQuizMarkdown` in audience.js so a file reads the same in both.
public enum QuizMarkdown {
    public static let generationExample = #"""
    # L'intelligence artificielle

    ## Question 1

    À quelle année est généralement attribuée la naissance de l'expression « intelligence artificielle » ?

    - [ ] 1945
    - [x] 1956
    - [ ] 1972

    ## Question 2

    Qui a inventé l'acronyme IA ?

    - [x] John McCarthy
    - [ ] Yann Le Cun
    - [ ] Alan Turing

    ## Question 3

    Vrai ou faux ? Les réseaux de neurones naissent dans les années 80 ?

    - [x] VRAI
    - [ ] FAUX

    ## Question 4

    Complète la phrase suivante.

    - Type: texte à trous
    - Texte à trous:
    ```
    Un [LLM] est un modèle de langage de grande [taille] entraîné sur de très nombreux textes.
    ```

    ## Question 5

    Comment fonctionne chatGPT ?

    - Type: légender une image
    - Image: uploads/questions/395129/3f22d86ea5ce7ae17a837473dec35f3db1474269.jpg
    - Zoom image: 1.00
    - Étiquettes:
    ```json
    [
      {
        "id": "lbl1",
        "text": "Prompt",
        "x": 6.9,
        "y": 55.04
      },
      {
        "id": "lbl17717528421362",
        "text": "Tokenization",
        "x": 26.29,
        "y": 57.2
      },
      {
        "id": "lbl17717531087543",
        "text": "Embeddings",
        "x": 37.43,
        "y": 58.01
      },
      {
        "id": "lbl17717531905554",
        "text": "Transformer",
        "x": 47,
        "y": 59.7
      },
      {
        "id": "lbl17717532680985",
        "text": "Réponse en langage naturel",
        "x": 92.47,
        "y": 48.61
      }
    ]
    ```

    ## Question 6

    Classez ces films évoquant une IA par ordre de parution.

    - Type: classement
    - Éléments à classer:
    ```
    Metropolis
    2001 l'Odyssée de l'espace
    Terminator
    Matrix
    Her
    ```

    ## Question 7

    Regardez cette vidéo

    - Type: vidéo YouTube
    - URL vidéo: https://youtu.be/ARJ8cAGm6JE?si=zKQdR6Wd4IGzhup1

    ## Question 8

    Mon nom est celui de l'IA dans le film 2001 Odyssée de l'espace

    - Type: question ouverte

    ## Question 9

    Écris la formule de la prédiction d’un modèle de régression linéaire simple.

    - Type: question ouverte
    - Format de réponse: mathématique

    ## Question 10

    Quels personnages sont des IA au cinéma ?

    - Type: cases à cocher
    - [ ] Eleven
    - [x] Skynet
    - [ ] Robocop
    - [x] Samantha
    - [x] Agent Smith
    - [x] JARVIS

    ## Question 11

    Cite en un mot un usage de l'IA dans la vie quotidienne.

    - Type: nuage de mots

    ## Question 12

    À ton avis, l'IA peut-elle t'aider à apprendre mieux et plus vite ?

    - Type: notation en étoiles (1 à 5)

    ## Question 13

    Comment note-t-on la prédiction du modèle ?

    - [ ] \\(x + y\\)
    - [x] \\(\\hat{y} = wx + b\\)
    - [ ] \\(\\int_0^1 x^2\\,dx\\)
    """#

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

/// Minimal reader for ZIP archives (stored or deflated entries): those of the website and Word documents.
enum ZipReader {
    /// `include` is asked before an entry is read, so unwanted entries (images in a Word file) are never inflated.
    static func entries(_ data: Data, where include: (String) -> Bool = { _ in true }) throws -> [(name: String, data: Data)] {
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
            if name.hasSuffix("/") || !include(name) { continue }
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

// MARK: - Formatted statements

/// Question statements. The website stores a small subset of HTML (strong, em, u, br, p, ul/ol/li)
/// written by its rich-text editor, while Markdown imports keep the text as typed. The app shows both
/// with their formatting, edits them as Markdown and sends the website HTML, so participants see the
/// same thing: **gras** or __gras__, *italique* or _italique_, <u>souligné</u>, "- " for a list item.
///
/// Emphasis needs a non-letter on both sides, so "2*3*4", "nom_de_variable" and "_____" stay text;
/// a backslash keeps a character literal (\*).
public enum RichText {
    public struct Run: Equatable, Sendable {
        public var text: String
        public var bold = false, italic = false, underline = false
        public init(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
            self.text = text; self.bold = bold; self.italic = italic; self.underline = underline
        }
    }

    /// The statement as the editor shows it. Markdown typed earlier stays as it was written.
    public static func markdown(fromHTML html: String) -> String {
        guard html.contains("<") else { return html.unformattedText }
        // One buffer per open inline element, so "<strong>gras </strong>" becomes "**gras** ".
        var stack: [(tag: String, text: String)] = [("", "")]
        var lists: [(ordered: Bool, count: Int)] = []
        func append(_ string: String) { stack[stack.count - 1].text += string }
        func close(through index: Int) {
            while stack.count > index {
                let element = stack.removeLast()
                append(wrap(element.text, in: element.tag))
            }
        }
        for token in tokens(html) {
            switch token {
            case .text(let text): append(text.unformattedText)
            case .open(let tag):
                switch tag {
                case "strong", "b", "em", "i", "u": stack.append((tag, ""))
                case "br": append("\n")
                case "p", "div": if lists.isEmpty { append("\n\n") }
                case "ul", "ol": lists.append((tag == "ol", 0)); append("\n\n")
                case "li":
                    if lists.isEmpty { lists.append((false, 0)) }
                    lists[lists.count - 1].count += 1
                    append("\n" + (lists[lists.count - 1].ordered ? "\(lists[lists.count - 1].count). " : "- "))
                default: break
                }
            case .close(let tag):
                switch tag {
                case "strong", "b", "em", "i", "u":
                    // A stray closing tag is ignored; elements left open inside it are closed with it.
                    if let index = stack.lastIndex(where: { $0.tag == tag }), index > 0 { close(through: index) }
                case "p", "div": if lists.isEmpty { append("\n\n") }
                case "ul", "ol": if !lists.isEmpty { lists.removeLast() }; append("\n\n")
                default: break
                }
            }
        }
        close(through: 1)
        return stack[0].text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Markers go around each line of the element, inside its outer spaces.
    private static func wrap(_ text: String, in tag: String) -> String {
        let (open, close) = tag == "strong" || tag == "b" ? ("**", "**") : tag == "u" ? ("<u>", "</u>") : ("*", "*")
        return text.components(separatedBy: "\n").map { line in
            let core = line.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return line }
            let lead = line.prefix(while: \.isWhitespace), trail = String(line.reversed().prefix(while: \.isWhitespace))
            return lead + open + core + close + trail
        }.joined(separator: "\n")
    }

    /// The HTML the website stores and shows to participants. A single paragraph keeps the
    /// form the app has always sent (escaped text and <br>), so unformatted statements do not change.
    public static func html(fromMarkdown markdown: String) -> String {
        enum Block { case paragraph([String]), list([String]) }
        var blocks: [Block] = []
        for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if let item = bulletItem(line) {
                if case .list(let items)? = blocks.last { blocks[blocks.count - 1] = .list(items + [item]) }
                else { blocks.append(.list([item])) }
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if case .paragraph(let lines)? = blocks.last, !lines.isEmpty { blocks.append(.paragraph([])) }
            } else if case .paragraph(let lines)? = blocks.last {
                blocks[blocks.count - 1] = .paragraph(lines + [line])
            } else {
                blocks.append(.paragraph([line]))
            }
        }
        let rendered: [(html: String, list: Bool)] = blocks.compactMap { block in
            switch block {
            case .paragraph(let lines): lines.isEmpty ? nil : (lines.map(inline).joined(separator: "<br>"), false)
            case .list(let items): ("<ul>" + items.map { "<li>\(inline($0))</li>" }.joined() + "</ul>", true)
            }
        }
        if rendered.count == 1, !rendered[0].list { return rendered[0].html }
        return rendered.map { $0.list ? $0.html : "<p>\($0.html)</p>" }.joined()
    }

    /// One line: escaped for HTML, then emphasis. Private-use characters protect escapes and <u> tags.
    private static func inline(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "\\\\", with: "\u{F8F0}")
            .replacingOccurrences(of: "\\*", with: "\u{F8F1}").replacingOccurrences(of: "\\_", with: "\u{F8F2}")
            .replacingOccurrences(of: "<u>", with: "\u{F8F3}", options: .caseInsensitive)
            .replacingOccurrences(of: "</u>", with: "\u{F8F4}", options: .caseInsensitive)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        for (pattern, tag) in emphasis {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "<\(tag)>$1</\(tag)>")
        }
        return text.replacingOccurrences(of: "\u{F8F0}", with: "\\").replacingOccurrences(of: "\u{F8F1}", with: "*")
            .replacingOccurrences(of: "\u{F8F2}", with: "_")
            .replacingOccurrences(of: "\u{F8F3}", with: "<u>").replacingOccurrences(of: "\u{F8F4}", with: "</u>")
    }
    private static let emphasis: [(NSRegularExpression, String)] = [
        (#"(?<![\w*])\*\*(?=\S)(.+?)(?<=\S)\*\*(?![\w*])"#, "strong"),
        (#"(?<![\w_])__(?=[^\s_])(.+?)(?<=[^\s_])__(?![\w_])"#, "strong"),
        (#"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])"#, "em"),
        (#"(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])"#, "em"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    private static let bullet = try! NSRegularExpression(pattern: #"^\s*[-•]\s+(\S.*)$"#)
    private static func bulletItem(_ line: String) -> String? {
        guard let match = bullet.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    /// True when the statement holds Markdown that the website would show as typed.
    public static func containsMarkdown(_ text: String) -> Bool {
        let plain = text.unformattedText
        let range = NSRange(plain.startIndex..., in: plain)
        return emphasis.contains { $0.0.firstMatch(in: plain, range: range) != nil }
            || plain.components(separatedBy: "\n").contains { bulletItem($0) != nil }
    }
    /// The statement as the website should receive it: Markdown becomes HTML, anything else is unchanged.
    public static func normalized(_ text: String) -> String {
        containsMarkdown(text) ? html(fromMarkdown: markdown(fromHTML: text)) : text
    }

    /// Styled pieces of a statement, whether it was written in the website's HTML or in Markdown.
    public static func runs(_ text: String) -> [Run] {
        let html = normalized(text)
        guard html.contains("<") else {
            let plain = html.unformattedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return plain.isEmpty ? [] : [Run(plain)]
        }
        var runs: [Run] = []
        var bold = 0, italic = 0, underline = 0
        var lists: [(ordered: Bool, count: Int)] = []
        // Line breaks asked by block tags wait for the next text: none at the edges, at most one empty line.
        var breaks = 0
        func append(_ string: String) {
            if breaks > 0, string.allSatisfy(\.isWhitespace) { return }
            let text = (runs.isEmpty ? "" : String(repeating: "\n", count: breaks)) + string
            breaks = 0
            guard !text.isEmpty else { return }
            if let last = runs.last, last.bold == (bold > 0), last.italic == (italic > 0), last.underline == (underline > 0) {
                runs[runs.count - 1].text += text
            } else {
                runs.append(Run(text, bold: bold > 0, italic: italic > 0, underline: underline > 0))
            }
        }
        func lineBreak(_ count: Int) { breaks = min(2, max(breaks, count)) }
        for token in tokens(html) {
            switch token {
            case .text(let text): append(text.unformattedText)
            case .open(let tag):
                switch tag {
                case "strong", "b": bold += 1
                case "em", "i": italic += 1
                case "u": underline += 1
                case "br": breaks = min(2, breaks + 1)
                case "p", "div": if lists.isEmpty { lineBreak(2) }
                case "ul", "ol": lists.append((tag == "ol", 0)); lineBreak(1)
                case "li":
                    if lists.isEmpty { lists.append((false, 0)) }
                    lists[lists.count - 1].count += 1
                    lineBreak(1)
                    let marker = lists[lists.count - 1].ordered ? "\(lists[lists.count - 1].count). " : "• "
                    let (b, i, u) = (bold, italic, underline)
                    bold = 0; italic = 0; underline = 0
                    append(marker)
                    (bold, italic, underline) = (b, i, u)
                default: break
                }
            case .close(let tag):
                switch tag {
                case "strong", "b": bold = max(0, bold - 1)
                case "em", "i": italic = max(0, italic - 1)
                case "u": underline = max(0, underline - 1)
                case "p", "div": if lists.isEmpty { lineBreak(2) }
                case "ul", "ol": if !lists.isEmpty { lists.removeLast() }; lineBreak(2)
                default: break
                }
            }
        }
        if let last = runs.indices.last {
            runs[last].text = String(runs[last].text.reversed().drop(while: \.isWhitespace).reversed())
            if runs[last].text.isEmpty { runs.removeLast() }
        }
        if let first = runs.indices.first {
            runs[first].text = String(runs[first].text.drop(while: \.isWhitespace))
            if runs[first].text.isEmpty { runs.removeFirst() }
        }
        return runs
    }
    /// The statement without formatting marks, for lists, titles and accessibility.
    public static func plainText(_ text: String) -> String { runs(text).map(\.text).joined() }
    /// True when the statement shows bold, italic, underlined text or a list.
    public static func isFormatted(_ text: String) -> Bool {
        runs(text).contains { $0.bold || $0.italic || $0.underline } || normalized(text).range(of: "<li", options: .caseInsensitive) != nil
    }

    private enum Token { case text(String), open(String), close(String) }
    private static let tag = try! NSRegularExpression(pattern: #"<(/?)([A-Za-z][A-Za-z0-9]*)\b[^>]*>"#)
    private static func tokens(_ html: String) -> [Token] {
        var result: [Token] = []
        var position = html.startIndex
        for match in tag.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html), let slash = Range(match.range(at: 1), in: html),
                  let name = Range(match.range(at: 2), in: html) else { continue }
            if position < range.lowerBound { result.append(.text(String(html[position..<range.lowerBound]))) }
            result.append(html[slash].isEmpty ? .open(html[name].lowercased()) : .close(html[name].lowercased()))
            position = range.upperBound
        }
        if position < html.endIndex { result.append(.text(String(html[position...]))) }
        return result
    }
}
