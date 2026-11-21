import Foundation

// MARK: - Colors, folders and tags (mirrors quiz_organize.php)

/// The colors accepted by the website for folders and questionnaire cards.
public enum QuizColor: String, CaseIterable, Identifiable, Sendable {
    case indigo, blue, teal, green, amber, rose, slate
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .indigo: "Indigo"
        case .blue: "Bleu"
        case .teal: "Sarcelle"
        case .green: "Vert"
        case .amber: "Ambre"
        case .rose: "Rose"
        case .slate: "Ardoise"
        }
    }
    public init?(key: String?) {
        guard let key else { return nil }
        self.init(rawValue: key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// Text helpers that reproduce the server normalization, so both sides agree
/// and a value never bounces between the Mac and the website.
public enum OrganizationText {
    /// PHP: trim(preg_replace('/\s+/u', ' ', $value)).
    static func collapsed(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
    /// PHP mb_substr counts code points, not grapheme clusters.
    static func prefix(_ value: String, _ length: Int) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: value.unicodeScalars.prefix(length))
        return String(scalars)
    }
    public static func folderName(_ value: String) -> String {
        let name = collapsed(value)
        return name.isEmpty ? "Nouveau dossier" : prefix(name, 80)
    }
    /// At most 12 tags of 30 characters, without leading #, case-insensitive duplicates removed.
    public static func tags(_ values: [String]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for value in values {
            var tag = Substring(collapsed(value))
            while tag.first == "#" { tag = tag.dropFirst() }
            guard !tag.isEmpty else { continue }
            let normalized = prefix(String(tag), 30)
            guard seen.insert(normalized.lowercased()).inserted else { continue }
            result.append(normalized)
            if result.count >= 12 { break }
        }
        return result
    }
}

public struct FolderState: Codable, Equatable, Sendable {
    public var name: String
    public var color: String
    public init(name: String, color: String) {
        self.name = OrganizationText.folderName(name)
        self.color = (QuizColor(key: color) ?? .indigo).rawValue
    }
}

public struct QuizFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var color: String
    /// Identifier of the folder on the website, once it exists there.
    public var remoteID: Int?
    /// Account the folder belongs to. `nil` until the Mac is connected.
    public var account: String?
    /// Last name and color exchanged with the website.
    public var synced: FolderState?
    /// Deleted on this Mac, still to be deleted on the website.
    public var pendingDeletion: Bool

    public init(id: String = UUID().uuidString, name: String, color: QuizColor = .indigo, account: String? = nil) {
        self.id = id; self.name = OrganizationText.folderName(name); self.color = color.rawValue
        self.account = account; pendingDeletion = false
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Nouveau dossier"
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? QuizColor.indigo.rawValue
        remoteID = try c.decodeIfPresent(Int.self, forKey: .remoteID)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        synced = try c.decodeIfPresent(FolderState.self, forKey: .synced)
        pendingDeletion = try c.decodeIfPresent(Bool.self, forKey: .pendingDeletion) ?? false
    }
    public var state: FolderState { FolderState(name: name, color: color) }
    public var quizColor: QuizColor { QuizColor(key: color) ?? .indigo }
}

/// Organization of one questionnaire as the website stores it.
public struct QuizOrganization: Codable, Equatable, Sendable {
    public var folder: Int?
    public var color: String?
    public var tags: [String]
    public init(folder: Int? = nil, color: String? = nil, tags: [String] = []) {
        self.folder = folder
        self.color = QuizColor(key: color)?.rawValue
        self.tags = OrganizationText.tags(tags)
    }
    public init(item: RemoteItem) {
        let folder = item.fields["folderId"]
        let id: Int? = if case .null = folder { nil } else { folder.int > 0 ? folder.int : nil }
        self.init(folder: id, color: item.fields["color"].string, tags: item.fields["tags"].array.map(\.string))
    }
    public var isEmpty: Bool { folder == nil && color == nil && tags.isEmpty }
}

public struct RemoteFolder: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var color: String
    public init(id: Int, name: String, color: String) { self.id = id; self.name = name; self.color = color }
    public init?(json: JSONValue) {
        guard json["id"].int > 0 else { return nil }
        self.init(id: json["id"].int, name: json["name"].string, color: json["color"].string)
    }
    public var state: FolderState { FolderState(name: name, color: color) }
}

// MARK: - Local fields

public extension Quiz {
    /// Local organization keys. They are never sent to save_question.php.
    static let organizationKeys = ["localFolder", "cardColor", "tags"]
    var folderID: String? {
        get { self["localFolder"].string.isEmpty ? nil : self["localFolder"].string }
        set { self["localFolder"] = newValue.map(JSONValue.string) ?? .null }
    }
    var cardColor: QuizColor? {
        get { QuizColor(key: self["cardColor"].string) }
        set { self["cardColor"] = newValue.map { .string($0.rawValue) } ?? .null }
    }
    var tags: [String] {
        get { self["tags"].array.map(\.string).filter { !$0.isEmpty } }
        set { self["tags"] = .array(OrganizationText.tags(newValue).map(JSONValue.string)) }
    }
}

public extension LibraryArchive {
    func folder(remoteID: Int, account: String) -> QuizFolder? {
        folders.values.first { $0.remoteID == remoteID && $0.account == account && !$0.pendingDeletion }
    }
    /// The organization in the website's terms, or `nil` while its folder only exists on this Mac.
    func organization(of quiz: Quiz) -> QuizOrganization? {
        var remoteFolder: Int?
        if let id = quiz.folderID, let folder = folders[id], !folder.pendingDeletion {
            guard let remoteID = folder.remoteID else { return nil }
            remoteFolder = remoteID
        }
        return QuizOrganization(folder: remoteFolder, color: quiz.cardColor?.rawValue, tags: quiz.tags)
    }
}

// MARK: - Synchronization

public enum OrganizationDecision: Equatable, Sendable { case same, pull, push }

public enum OrganizationPlanner {
    /// Three-way comparison with the last exchanged value. A change made on this Mac wins.
    public static func decision<Value: Equatable>(local: Value, remote: Value, base: Value?, localIsEmpty: Bool = false, remoteIsEmpty: Bool = false) -> OrganizationDecision {
        if local == remote { return .same }
        guard let base else { return !localIsEmpty && remoteIsEmpty ? .push : .pull }
        return local == base ? .pull : .push
    }
}

public protocol OrganizationRemote: Sendable {
    func organize(_ request: JSONValue) async throws -> JSONValue
}

public enum OrganizationEvent: Sendable {
    case folderPulled(RemoteFolder, account: String)
    case folderLinked(localID: String, remoteID: Int, state: FolderState, account: String)
    case folderSynced(localID: String, state: FolderState)
    case folderRemoved(localID: String)
    case quizPulled(code: String, organization: QuizOrganization, expected: QuizOrganization, account: String)
    case quizSynced(code: String, organization: QuizOrganization, account: String)
}

public extension LibraryArchive {
    /// Applies a network result unless it would overwrite a change made during the request.
    mutating func apply(_ event: OrganizationEvent) {
        switch event {
        case .folderPulled(let remote, let account):
            let state = remote.state
            if let existing = folders.values.first(where: { $0.remoteID == remote.id && $0.account == account }) {
                guard !existing.pendingDeletion, existing.synced == nil || existing.state == existing.synced else { return }
                var folder = existing
                folder.name = state.name; folder.color = state.color; folder.synced = state
                folders[folder.id] = folder
            } else {
                var folder = QuizFolder(name: state.name, color: QuizColor(key: state.color) ?? .indigo, account: account)
                folder.remoteID = remote.id; folder.synced = state
                folders[folder.id] = folder
            }
        case .folderLinked(let localID, let remoteID, let state, let account):
            var folder = folders[localID] ?? {
                // Deleted on this Mac while it was being created: delete it on the website next time.
                var tombstone = QuizFolder(id: localID, name: state.name, account: account)
                tombstone.pendingDeletion = true
                return tombstone
            }()
            folder.remoteID = remoteID; folder.account = account; folder.synced = state
            folders[localID] = folder
        case .folderSynced(let localID, let state):
            folders[localID]?.synced = state
        case .folderRemoved(let localID):
            folders.removeValue(forKey: localID)
            for (code, quiz) in quizzes where quiz.folderID == localID { quizzes[code]?.folderID = nil }
        case .quizPulled(let code, let organization, let expected, let account):
            guard var quiz = quizzes[code], synchronization.owners[code] == account,
                  self.organization(of: quiz) == expected else { return }
            quiz.folderID = organization.folder.flatMap { folder(remoteID: $0, account: account)?.id }
            quiz.cardColor = QuizColor(key: organization.color)
            quiz.tags = organization.tags
            quizzes[code] = quiz
            synchronization.records[code]?.organization = organization
        case .quizSynced(let code, let organization, let account):
            guard synchronization.records[code]?.account == account else { return }
            synchronization.records[code]?.organization = organization
        }
    }
}

public struct OrganizationSync: Sendable {
    public init() {}

    /// Exchanges folders, card colors and tags. Content is handled by `SyncEngine`.
    public func run(account: String, items: [RemoteItem], folders remoteFolders: [RemoteFolder],
                    remote: any OrganizationRemote,
                    current: @Sendable () async -> LibraryArchive,
                    receive: @Sendable (OrganizationEvent) async -> Void) async -> [String] {
        var failures: [String] = []
        var archive = await current()
        let mine = archive.folders.values.filter { $0.account == account || $0.account == nil }
        var deletedRemotely = Set<Int>()

        for folder in mine where folder.pendingDeletion {
            if let id = folder.remoteID, remoteFolders.contains(where: { $0.id == id }) {
                do { _ = try await remote.organize(.object(["action": .string("delete_folder"), "id": .number(Double(id))])) }
                catch { failures.append("Dossier « \(folder.name) » : \(error.localizedDescription)"); continue }
                deletedRemotely.insert(id)
            }
            await receive(.folderRemoved(localID: folder.id))
        }
        for remoteFolder in remoteFolders where !deletedRemotely.contains(remoteFolder.id) {
            guard let local = mine.first(where: { $0.remoteID == remoteFolder.id && $0.account == account }) else {
                await receive(.folderPulled(remoteFolder, account: account)); continue
            }
            if local.pendingDeletion { continue }
            switch OrganizationPlanner.decision(local: local.state, remote: remoteFolder.state, base: local.synced) {
            case .same:
                if local.synced != remoteFolder.state { await receive(.folderSynced(localID: local.id, state: remoteFolder.state)) }
            case .pull:
                await receive(.folderPulled(remoteFolder, account: account))
            case .push:
                do {
                    _ = try await remote.organize(.object(["action": .string("update_folder"), "id": .number(Double(remoteFolder.id)),
                                                           "name": .string(local.state.name), "color": .string(local.state.color)]))
                    await receive(.folderSynced(localID: local.id, state: local.state))
                } catch { failures.append("Dossier « \(local.name) » : \(error.localizedDescription)") }
            }
        }
        for local in mine where !local.pendingDeletion {
            if let id = local.remoteID {
                if local.account == account && !remoteFolders.contains(where: { $0.id == id }) {
                    await receive(.folderRemoved(localID: local.id)) // Deleted on the website.
                }
                continue
            }
            do {
                let response = try await remote.organize(.object(["action": .string("create_folder"), "name": .string(local.state.name),
                                                                  "color": .string(local.state.color), "codes": .array([])]))
                let id = response["folder"]["id"].int
                guard id > 0 else { throw AudienceError.message("Le site n’a pas créé le dossier.") }
                await receive(.folderLinked(localID: local.id, remoteID: id, state: local.state, account: account))
            } catch { failures.append("Dossier « \(local.name) » : \(error.localizedDescription)") }
        }

        archive = await current()
        for item in items where !item.isDeleted {
            try? Task.checkCancellation()
            let code = item.code
            guard let quiz = archive.quizzes[code], !quiz.isDeleted,
                  archive.synchronization.owners[code] == account,
                  let record = archive.synchronization.records[code], record.account == account,
                  let local = archive.organization(of: quiz) else { continue }
            let remoteValue = QuizOrganization(item: item)
            // A folder this Mac does not know yet must not be mistaken for "no folder".
            if let folder = remoteValue.folder, archive.folder(remoteID: folder, account: account) == nil { continue }
            switch OrganizationPlanner.decision(local: local, remote: remoteValue, base: record.organization,
                                                localIsEmpty: local.isEmpty, remoteIsEmpty: remoteValue.isEmpty) {
            case .same:
                if record.organization != remoteValue { await receive(.quizSynced(code: code, organization: remoteValue, account: account)) }
            case .pull:
                await receive(.quizPulled(code: code, organization: remoteValue, expected: local, account: account))
            case .push:
                do {
                    if local.folder != remoteValue.folder {
                        _ = try await remote.organize(.object(["action": .string("move"), "code": .string(code),
                                                               "folderId": local.folder.map { .number(Double($0)) } ?? .null]))
                    }
                    if local.color != remoteValue.color {
                        _ = try await remote.organize(.object(["action": .string("set_color"), "code": .string(code),
                                                               "color": local.color.map(JSONValue.string) ?? .null]))
                    }
                    if local.tags != remoteValue.tags {
                        _ = try await remote.organize(.object(["action": .string("set_tags"), "code": .string(code),
                                                               "tags": .array(local.tags.map(JSONValue.string))]))
                    }
                    await receive(.quizSynced(code: code, organization: local, account: account))
                } catch { failures.append("\(code) : \(error.localizedDescription)") }
            }
        }
        return failures
    }
}
