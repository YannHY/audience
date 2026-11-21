import Foundation

public enum QuestionKind: String, CaseIterable, Identifiable, Sendable {
    case multiple, checkbox, open, wordcloud, rating, cloze, video, ranking, labelimage
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .multiple: "Choix unique"
        case .checkbox: "Choix multiples"
        case .open: "Réponse libre"
        case .wordcloud: "Nuage de mots"
        case .rating: "Évaluation"
        case .cloze: "Texte à trous"
        case .video: "Vidéo"
        case .ranking: "Classement"
        case .labelimage: "Image à légender"
        }
    }
    public var symbol: String {
        switch self {
        case .multiple: "list.bullet.circle"
        case .checkbox: "checklist"
        case .open: "text.alignleft"
        case .wordcloud: "cloud"
        case .rating: "star"
        case .cloze: "text.badge.plus"
        case .video: "play.rectangle"
        case .ranking: "list.number"
        case .labelimage: "photo.badge.plus"
        }
    }
    public var hasAnswers: Bool { [.multiple, .checkbox, .ranking].contains(self) }
}

public struct Question: Codable, Equatable, Sendable {
    public var fields: [String: JSONValue]
    public init(kind: QuestionKind = .multiple) {
        fields = ["type": .string(kind.rawValue), "question": .string(""),
                  "answers": .array(kind.hasAnswers ? [.string(""), .string("")] : []),
                  "correctIndex": .number(0), "correctIndexes": .array([.number(0)]),
                  "timeLimitSec": .number(30), "participantResponsesVisible": .bool(true),
                  "maxRating": .number(5)]
    }
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(from decoder: Decoder) throws { fields = try [String: JSONValue](from: decoder) }
    public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    public subscript(_ key: String) -> JSONValue {
        get { fields[key] ?? .null }
        set { fields[key] = newValue }
    }
    public var kind: QuestionKind {
        get { QuestionKind(rawValue: self["type"].string) ?? .multiple }
        set { self["type"] = .string(newValue.rawValue); if newValue.hasAnswers && answers.count < 2 { answers = ["", ""] } }
    }
    public var text: String {
        get { self["question"].string.unformattedText }
        set { self["question"] = .string(newValue.htmlEscaped) }
    }
    public var answers: [String] {
        get { self["answers"].array.map(\.string) }
        set { self["answers"] = .array(newValue.map(JSONValue.string)) }
    }
    public var validationMessage: String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Saisissez l’énoncé de la question." }
        if kind.hasAnswers && (answers.count < 2 || answers.contains(where: { $0.plainText.isEmpty })) { return "Complétez au moins deux réponses." }
        if kind == .ranking && Set(answers).count != answers.count { return "Les éléments du classement doivent être différents." }
        if kind == .cloze && !self["clozeText"].string.contains("[") && !self["clozeText"].string.contains("{{") { return "Marquez un trou avec [réponse] ou {{réponse, autre choix}}." }
        if kind == .video {
            guard let url = URL(string: self["youtubeUrl"].string), let host = url.host,
                  ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"].contains(host) else { return "Saisissez une URL YouTube valide." }
        }
        if kind == .labelimage && (self["questionImage"].string.isEmpty || self["legendLabels"].array.isEmpty) { return "Ajoutez une image et au moins une étiquette." }
        if kind == .labelimage && self["legendLabels"].array.contains(where: { $0["text"].string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return "Complétez le texte des étiquettes." }
        return nil
    }
    public mutating func removeAnswer(at index: Int) {
        guard answers.indices.contains(index), answers.count > 2 else { return }
        var values = answers; values.remove(at: index); answers = values
        let correct = self["correctIndex"].int
        self["correctIndex"] = .number(Double(correct == index ? 0 : correct > index ? correct - 1 : correct))
        self["correctIndexes"] = .array(self["correctIndexes"].array.map(\.int).filter { $0 != index }.map { .number(Double($0 > index ? $0 - 1 : $0)) })
    }
}

public struct Quiz: Codable, Identifiable, Equatable, Sendable {
    public var fields: [String: JSONValue]
    public var id: String { code }
    public init(code: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).uppercased()) {
        fields = ["code": .string(code), "quizTitle": .string("Nouveau questionnaire"), "batch": .array([]),
                  "updatedAt": .string(Self.timestamp), "requireParticipantName": .bool(true), "liveActive": .bool(false)]
    }
    public init(fields: [String: JSONValue]) { self.fields = fields }
    public init(from decoder: Decoder) throws { fields = try [String: JSONValue](from: decoder) }
    public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    public subscript(_ key: String) -> JSONValue {
        get { fields[key] ?? .null }
        set { fields[key] = newValue }
    }
    public var code: String { self["code"].string }
    public var title: String {
        get { self["quizTitle"].string }
        set { self["quizTitle"] = .string(newValue) }
    }
    public var questions: [Question] {
        get { self["batch"].array.map { Question(fields: $0.object) } }
        set { self["batch"] = .array(newValue.map { .object($0.fields) }) }
    }
    public var isFavorite: Bool {
        get { self["isFavorite"].bool }
        set { self["isFavorite"] = .bool(newValue) }
    }
    public var isDeleted: Bool { !self["deletedAt"].string.isEmpty }
    public var updatedAt: Date { Self.date(from: self["updatedAt"].string) }
    /// Parses ISO 8601 (this app) and MySQL "yyyy-MM-dd HH:mm:ss" (website) dates.
    /// Sorting calls this for every comparison, so formatters are never recreated here.
    public static func date(from value: String) -> Date {
        if let date = try? Date(value, strategy: .iso8601) { return date }
        let parts = value.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" }).compactMap { Int($0) }
        guard parts.count == 6 else { return .distantPast }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4], second: parts[5])
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }
    public static var timestamp: String { Date().formatted(.iso8601) }
    public var validationMessage: String? {
        if questions.isEmpty { return "Ajoutez une question avant de présenter ou d’envoyer ce questionnaire." }
        for (index, q) in questions.enumerated() {
            if let message = q.validationMessage { return "Question \(index + 1) : \(message)" }
        }
        return nil
    }
    public func payload(index: Int = 0, live: Bool = false) -> JSONValue {
        var f = fields
        for key in Self.organizationKeys + ["nativeTrashPlaceholder"] { f.removeValue(forKey: key) }
        f["mode"] = .string("batch")
        f["currentIndex"] = .number(Double(index))
        f["liveActive"] = .bool(live)
        f["resetAllResponses"] = .bool(false)
        return .object(f)
    }
}

public struct LibraryArchive: Codable, Equatable, Sendable {
    public var quizzes: [String: Quiz] = [:]
    public var folders: [String: QuizFolder] = [:]
    public var responses: [String: JSONValue] = [:]
    public var sync: [String: JSONValue] = [:]
    public var synchronization = SyncMetadata()
    public init() {}
    public init(from decoder: Decoder) throws {
        let f = try [String: JSONValue](from: decoder)
        guard case .object(let raw) = f["quizzes"] else { throw AudienceError.message("Ce fichier n’est pas une sauvegarde Audience.") }
        var quizzes: [String: Quiz] = [:]
        for (key, value) in raw {
            guard case .object(var fields) = value, case .array = fields["batch"] else {
                throw AudienceError.message("Questionnaire invalide dans la sauvegarde : \(key).")
            }
            let code = fields["code"]?.string.isEmpty == false ? fields["code"]!.string : key
            guard !code.isEmpty, code.count <= 16, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
                throw AudienceError.message("Code de questionnaire invalide : \(code).")
            }
            fields["code"] = .string(code)
            quizzes[code] = Quiz(fields: fields)
        }
        self.quizzes = quizzes
        responses = f["responses"]?.object ?? [:]
        sync = f["sync"]?.object ?? [:]
        if let folders = f["folders"], case .object = folders {
            self.folders = try JSONDecoder().decode([String: QuizFolder].self, from: JSONEncoder().encode(folders))
        }
        if let metadata = f["synchronization"] {
            synchronization = try JSONDecoder().decode(SyncMetadata.self, from: JSONEncoder().encode(metadata))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var f: [String: JSONValue] = ["app": .string("Audience"), "version": .number(3), "exportedAt": .string(Quiz.timestamp),
            "quizzes": .object(quizzes.mapValues { .object($0.fields) }), "responses": .object(responses), "sync": .object(sync)]
        // No session cookies or credentials are included in a backup.
        f["sync"] = .object(sync.filter { ["remoteBase", "lastSyncAt"].contains($0.key) })
        f["synchronization"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(synchronization))
        f["folders"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(folders))
        try f.encode(to: encoder)
    }
    /// An import never overwrites an existing local questionnaire or its results.
    public mutating func merge(_ incoming: LibraryArchive) -> Int {
        // Imported folders become local folders. A folder with the same name is reused.
        var folderMap: [String: String] = [:]
        for folder in incoming.folders.values where !folder.pendingDeletion {
            let account = synchronization.activeAccount
            if let existing = folders.values.first(where: { !$0.pendingDeletion && ($0.account == nil || $0.account == account)
                && $0.name.localizedCaseInsensitiveCompare(folder.name) == .orderedSame }) {
                folderMap[folder.id] = existing.id
            } else {
                let copy = QuizFolder(name: folder.name, color: folder.quizColor)
                folders[copy.id] = copy
                folderMap[folder.id] = copy.id
            }
        }
        for (original, var quiz) in incoming.quizzes {
            quiz.folderID = quiz.folderID.flatMap { folderMap[$0] }
            var code = original
            if quizzes[code] != nil {
                code = Quiz().code
                quiz["code"] = .string(code)
                quiz.title += " (importé)"
            }
            quiz["liveActive"] = .bool(false)
            quizzes[code] = quiz
            if let responses = incoming.responses[original] { self.responses[code] = responses }
        }
        return incoming.quizzes.count
    }
}

public enum AudienceError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let message): message } }
}
