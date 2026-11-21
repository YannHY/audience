import Foundation
import CryptoKit

public struct SyncRecord: Codable, Equatable, Sendable {
    public var account: String
    public var localFingerprint: String
    public var remoteFingerprint: String
    public var remoteDeleted: Bool
    /// Website `updatedAt` seen with this version. An unchanged value avoids downloading it again.
    public var remoteStamp: String?
    /// Folder, color and tags last exchanged with the website.
    public var organization: QuizOrganization?
    public init(account: String, local: Quiz, remote: Quiz, stamp: String? = nil) {
        self.account = account
        localFingerprint = local.syncFingerprint
        remoteFingerprint = remote.remoteFingerprint
        remoteDeleted = remote.isDeleted
        remoteStamp = stamp
    }
}

public struct SyncMetadata: Codable, Equatable, Sendable {
    public var activeAccount: String?
    public var owners: [String: String] = [:]
    public var records: [String: SyncRecord] = [:]
    public var pendingPurges: [String: String] = [:]
    public init() {}
}

public extension Quiz {
    /// Excludes live state, timestamps and server bookkeeping. Images are compared by bytes.
    var syncFingerprint: String {
        var content: [String: JSONValue] = [
            "title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "favorite": .bool(isFavorite), "deleted": .bool(isDeleted),
            "requireName": .bool(fields["requireParticipantName"]?.bool ?? true),
            "report": .bool(self["participantReportEnabled"].bool)
        ]
        content["questions"] = .array(questions.map { q in
            var rich = q["question"].string.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<b>", with: "<strong>").replacingOccurrences(of: "</b>", with: "</strong>")
                .replacingOccurrences(of: "<i>", with: "<em>").replacingOccurrences(of: "</i>", with: "</em>")
            if rich.hasPrefix("<p>"), rich.hasSuffix("</p>"), rich.components(separatedBy: "<p>").count == 2 {
                rich = String(rich.dropFirst(3).dropLast(4))
            }
            var fields: [String: JSONValue] = ["type": .string(q.kind.rawValue), "question": .string(rich),
                "timeLimitSec": .number(Double(q.fields["timeLimitSec"]?.int ?? 30)),
                "participantResponsesVisible": .bool(q.fields["participantResponsesVisible"]?.bool ?? true)]
            if q.kind.hasAnswers { fields["answers"] = .array(q.answers.map(JSONValue.string)) }
            switch q.kind {
            case .multiple:
                let poll = q["isPollMode"].bool
                fields["isPollMode"] = .bool(poll)
                fields["correctIndex"] = poll ? .null : .number(Double(q["correctIndex"].int))
            case .checkbox:
                fields["correctIndexes"] = .array(Set(q["correctIndexes"].array.map(\.int)).sorted().map { .number(Double($0)) })
            case .open: fields["responseFormat"] = .string(q["responseFormat"].string == "math" ? "math" : "text")
            case .cloze: fields["clozeText"] = q["clozeText"]
            case .rating: fields["maxRating"] = .number(Double(q.fields["maxRating"]?.int ?? 5))
            case .video:
                fields["youtubeUrl"] = q["youtubeUrl"]
                fields["videoStartSec"] = q["videoStartSec"].int > 0 ? q["videoStartSec"] : .null
                fields["videoEndSec"] = q["videoEndSec"].int > 0 ? q["videoEndSec"] : .null
            case .labelimage: fields["legendLabels"] = q["legendLabels"]
            default: break
            }
            if [.multiple, .checkbox, .open, .cloze, .labelimage].contains(q.kind) {
                let source = q["questionImage"].string
                fields["questionImage"] = .string(source)
                fields["questionImageZoom"] = .number(q.fields["questionImageZoom"]?.double ?? 1)
                if source.hasPrefix("data:"), let comma = source.firstIndex(of: ","),
                   let bytes = Data(base64Encoded: String(source[source.index(after: comma)...])) {
                    fields["questionImage"] = .string(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
                }
            }
            return .object(fields)
        })
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(JSONValue.object(content))) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    var remoteFingerprint: String { isDeleted ? "deleted:\(code)" : syncFingerprint }
}

public struct RemoteItem: Sendable {
    public var fields: JSONValue
    public var code: String { fields["code"].string }
    public var isDeleted: Bool { !fields["deletedAt"].string.isEmpty }
    public init(fields: JSONValue) { self.fields = fields }
}
public struct RemoteQuiz: Sendable {
    public var quiz: Quiz
    public var results: JSONValue?
    public var warning: String?
    public init(quiz: Quiz, results: JSONValue? = nil, warning: String? = nil) { self.quiz = quiz; self.results = results; self.warning = warning }
}
public protocol SyncRemote: Sendable {
    func inventory() async throws -> [RemoteItem]
    func read(_ item: RemoteItem) async throws -> RemoteQuiz
    func write(_ quiz: Quiz, replacing item: RemoteItem?) async throws -> RemoteQuiz
    func setDeleted(code: String, deleted: Bool) async throws
    func purge(code: String) async throws
}

public enum SyncDecision: Equatable, Sendable {
    case unchanged, pull, push, conflict, restore, deferDraft
}
public enum SyncPlanner {
    public static func decision(local: Quiz?, remote: Quiz, record: SyncRecord?) -> SyncDecision {
        guard let local else { return .pull }
        if let record {
            let localChanged = local.syncFingerprint != record.localFingerprint
            let remoteChanged = remote.remoteFingerprint != record.remoteFingerprint
            if !localChanged { return remoteChanged ? .pull : .unchanged }
            if remoteChanged {
                return local.syncFingerprint == remote.syncFingerprint ? .unchanged : .conflict
            }
            if !local.isDeleted && remote.isDeleted { return .restore }
            return local.isDeleted || local.validationMessage == nil ? .push : .deferDraft
        }
        if local.syncFingerprint == remote.syncFingerprint { return .unchanged }
        return .conflict
    }
}

public struct SyncEvent: Sendable {
    public enum Kind: Sendable { case pull, pushed, conflict, unchanged, purged }
    public var kind: Kind
    public var account: String
    public var expectedLocal: Quiz?
    public var remote: RemoteQuiz
    public var record: SyncRecord?
    public var stamp: String?
    public init(kind: Kind, account: String, expectedLocal: Quiz?, remote: RemoteQuiz, record: SyncRecord? = nil, stamp: String? = nil) {
        self.kind = kind; self.account = account; self.expectedLocal = expectedLocal; self.remote = remote; self.record = record; self.stamp = stamp
    }
}

public struct SyncReport: Sendable {
    public var received = 0
    public var sent = 0
    public var conflicts = 0
    public var drafts = 0
    public var failures: [String] = []
    /// The website inventory used by this exchange.
    public var items: [RemoteItem] = []
    public init() {}
}

public extension LibraryArchive {
    /// Apply a network result only if it cannot overwrite edits made during the request.
    @discardableResult mutating func apply(_ event: SyncEvent) -> Bool {
        let code = event.remote.quiz.code
        let current = quizzes[code]
        if event.kind == .purged {
            synchronization.pendingPurges.removeValue(forKey: code)
            synchronization.records.removeValue(forKey: code)
            synchronization.owners.removeValue(forKey: code)
            return true
        }
        if let owner = synchronization.owners[code], owner != event.account { return false }
        let previous = synchronization.records[code].flatMap { $0.account == event.account ? $0 : nil }
        if event.kind == .pushed {
            // An upload acknowledges the captured version. Newer local edits stay pending.
            guard current != nil else { return false }
            var record = event.record
            record?.organization = previous?.organization
            synchronization.records[code] = record
            synchronization.owners[code] = event.account
            return true
        }
        guard current?.syncFingerprint == event.expectedLocal?.syncFingerprint else { return false }
        if event.kind == .conflict, var copy = current {
            let copyCode = Quiz().code
            copy["code"] = .string(copyCode)
            copy["deletedAt"] = .null
            copy["liveActive"] = .bool(false)
            copy.title += " (conflit sur ce Mac)"
            copy["updatedAt"] = .string(Quiz.timestamp)
            quizzes[copyCode] = copy
            synchronization.owners[copyCode] = event.account
            if let responses = responses[code] { self.responses[copyCode] = responses }
        }
        var kept = event.kind == .unchanged ? (current ?? event.remote.quiz) : event.remote.quiz
        if let current, event.kind != .unchanged {
            // Folder, color and tags are exchanged separately by OrganizationSync.
            for key in Quiz.organizationKeys { kept.fields[key] = current.fields[key] }
        }
        quizzes[code] = kept
        synchronization.owners[code] = event.account
        var record = SyncRecord(account: event.account, local: kept, remote: event.remote.quiz, stamp: event.stamp)
        record.organization = previous?.organization
        synchronization.records[code] = record
        if let results = event.remote.results { responses[code] = results }
        return true
    }
}

public struct SyncEngine: Sendable {
    public init() {}
    /// - Parameter fullRefresh: when `false`, a questionnaire whose website date and local
    ///   content are unchanged since the last exchange is not downloaded again.
    public func run(account: String, snapshot: LibraryArchive, remote: any SyncRemote, fullRefresh: Bool = true,
                    receive: @Sendable (SyncEvent) async throws -> Void) async throws -> SyncReport {
        let items = try await remote.inventory()
        var report = SyncReport()
        report.items = items
        var seen = Set<String>()
        for (code, owner) in snapshot.synchronization.pendingPurges where owner == account {
            seen.insert(code)
            do {
                if let item = items.first(where: { $0.code == code }) {
                    if !item.isDeleted { try await remote.setDeleted(code: code, deleted: true) }
                    try await remote.purge(code: code)
                }
                try await receive(SyncEvent(kind: .purged, account: account, expectedLocal: nil, remote: RemoteQuiz(quiz: Quiz(code: code))))
            } catch { report.failures.append("\(code) : \(error.localizedDescription)") }
        }
        for item in items where !seen.contains(item.code) {
            try Task.checkCancellation()
            let code = item.code; seen.insert(code)
            if let owner = snapshot.synchronization.owners[code], owner != account { continue }
            let local = snapshot.quizzes[code]
            let record = snapshot.synchronization.records[code].flatMap { $0.account == account ? $0 : nil }
            let stamp = item.fields["updatedAt"].string.isEmpty ? nil : item.fields["updatedAt"].string
            if !fullRefresh, !item.isDeleted, let local, let record, let stamp, !record.remoteDeleted,
               record.remoteStamp == stamp, local.syncFingerprint == record.localFingerprint { continue }
            do {
                let received: RemoteQuiz
                if item.isDeleted {
                    var deleted = local ?? Quiz(code: code)
                    deleted.title = item.fields["title"].string
                    deleted["deletedAt"] = item.fields["deletedAt"]
                    if local == nil { deleted["nativeTrashPlaceholder"] = .bool(true) }
                    received = RemoteQuiz(quiz: deleted)
                } else { received = try await remote.read(item) }
                if let warning = received.warning { report.failures.append("\(code) : \(warning)") }
                let decision = SyncPlanner.decision(local: local, remote: received.quiz, record: record)
                switch decision {
                case .pull, .conflict, .unchanged:
                    let kind: SyncEvent.Kind = decision == .pull ? .pull : decision == .conflict ? .conflict : .unchanged
                    try await receive(SyncEvent(kind: kind, account: account, expectedLocal: local, remote: received, stamp: item.isDeleted ? nil : stamp))
                    if decision != .unchanged { report.received += 1 }
                    if decision == .conflict { report.conflicts += 1 }
                case .deferDraft: report.drafts += 1
                case .push, .restore:
                    guard let local else { continue }
                    if received.quiz["liveActive"].bool { continue } // Never interrupt a presentation on the website.
                    if local.isDeleted {
                        try await remote.setDeleted(code: code, deleted: true)
                        var tombstone = local; tombstone["deletedAt"] = .string(Quiz.timestamp)
                        let saved = RemoteQuiz(quiz: tombstone)
                        if let warning = saved.warning { report.failures.append("\(code) : \(warning)") }
                        try await receive(SyncEvent(kind: .pushed, account: account, expectedLocal: local, remote: saved,
                                                   record: SyncRecord(account: account, local: local, remote: tombstone)))
                    } else {
                        if decision == .restore {
                            try await remote.setDeleted(code: code, deleted: false)
                            if local["nativeTrashPlaceholder"].bool {
                                let restored = try await remote.read(RemoteItem(fields: .object(["code": .string(code)])))
                                try await receive(SyncEvent(kind: .pull, account: account, expectedLocal: local, remote: restored))
                                report.received += 1; continue
                            }
                        }
                        guard local.validationMessage == nil else { report.drafts += 1; continue }
                        var expected = item.fields.object
                        expected["expectedFingerprint"] = .string(received.quiz.syncFingerprint)
                        let saved = try await remote.write(local, replacing: decision == .restore ? nil : RemoteItem(fields: .object(expected)))
                        if let warning = saved.warning { report.failures.append("\(code) : \(warning)") }
                        try await receive(SyncEvent(kind: .pushed, account: account, expectedLocal: local, remote: saved,
                                                   record: SyncRecord(account: account, local: local, remote: saved.quiz)))
                    }
                    report.sent += 1
                }
            } catch { report.failures.append("\(code) : \(error.localizedDescription)") }
        }
        for quiz in snapshot.quizzes.values where !seen.contains(quiz.code) && !quiz.isDeleted {
            try Task.checkCancellation()
            if let owner = snapshot.synchronization.owners[quiz.code], owner != account { continue }
            // Absence from capped server lists is not proof of deletion. Do not resurrect
            // a known server questionnaire or overwrite one outside this inventory.
            if snapshot.synchronization.records[quiz.code] != nil { continue }
            guard quiz.validationMessage == nil else { report.drafts += 1; continue }
            do {
                let saved = try await remote.write(quiz, replacing: nil)
                if let warning = saved.warning { report.failures.append("\(quiz.code) : \(warning)") }
                try await receive(SyncEvent(kind: .pushed, account: account, expectedLocal: quiz, remote: saved,
                                           record: SyncRecord(account: account, local: quiz, remote: saved.quiz)))
                report.sent += 1
            } catch { report.failures.append("\(quiz.code) : \(error.localizedDescription)") }
        }
        return report
    }
}
