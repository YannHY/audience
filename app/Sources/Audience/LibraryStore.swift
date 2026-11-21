import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import AudienceCore
#endif

enum SidebarItem: Hashable {
    case all, favorites, trash
    case folder(String)
    case tag(String)

    var title: String {
        switch self {
        case .all: "Questionnaires"
        case .favorites: "Favoris"
        case .trash: "Corbeille"
        case .folder: "Dossier"
        case .tag(let tag): "#\(tag)"
        }
    }
    var symbol: String {
        switch self {
        case .all: "rectangle.stack"
        case .favorites: "star"
        case .trash: "trash"
        case .folder: "folder"
        case .tag: "number"
        }
    }
}

struct LiveTiming: Equatable {
    var startedAt: Date
    var limit: Int
    var endsAt: Date { startedAt.addingTimeInterval(TimeInterval(limit)) }
}

enum QuizSort: String, CaseIterable, Identifiable {
    case modified, title
    var id: Self { self }
    var title: String { self == .modified ? "Date de modification" : "Titre" }
}

extension QuizColor {
    var color: Color {
        switch self {
        case .indigo: .indigo
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .amber: .orange
        case .rose: .pink
        case .slate: .gray
        }
    }
}

/// Writes the library off the main thread, in order, never replacing a newer version by an older one.
final class ArchiveWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fr.audience.native.save", qos: .utility)
    private var written = 0 // Only accessed on `queue`.
    let url: URL
    init(url: URL) { self.url = url }
    func write(_ archive: LibraryArchive, generation: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try self.perform(archive, generation: generation); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func writeNow(_ archive: LibraryArchive, generation: Int) throws {
        try queue.sync { try perform(archive, generation: generation) }
    }
    private func perform(_ archive: LibraryArchive, generation: Int) throws {
        guard generation > written else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(archive).write(to: url, options: .atomic)
        written = generation
    }
}

@MainActor @Observable final class LibraryStore {
    var archive = LibraryArchive()
    var sidebar: SidebarItem? = .all
    var selection: Set<String> = []
    var search = ""
    var notice: String?
    var busy = false
    var connected = false
    var accountName = ""
    var liveCode: String?
    var liveIndex = 0
    /// Timer of the question on screen, in this Mac's clock.
    var liveTiming: LiveTiming?
    var liveParticipants: Int?
    @ObservationIgnored private var liveRunID: String?
    var syncing = false
    var syncError: String?
    var syncSummary = ""
    var lastSyncAt: Date?
    var syncDrafts = 0
    /// Folder whose name is being edited in the sidebar.
    var renamingFolder: String?
    private(set) var readOnly = false

    let remote = RemoteClient()
    let dataURL: URL
    @ObservationIgnored private let writer: ArchiveWriter
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledSync: Task<Void, Never>?
    @ObservationIgnored private var editRevision = 0
    @ObservationIgnored private var retryAfterSync = false
    @ObservationIgnored private var lastFullRefresh: Date?
    @ObservationIgnored private var fingerprints: [String: (quiz: Quiz, value: String)] = [:]
    @ObservationIgnored private var alerts: [String] = []
    @ObservationIgnored private var alertVisible = false

    init() {
        // AUDIENCE_LIBRARY lets developers open a test library without touching real data.
        if let custom = ProcessInfo.processInfo.environment["AUDIENCE_LIBRARY"], !custom.isEmpty {
            dataURL = URL(filePath: custom)
        } else {
            dataURL = URL.applicationSupportDirectory.appending(path: "AudienceNative/library.json")
        }
        writer = ArchiveWriter(url: dataURL)
        do {
            if FileManager.default.fileExists(atPath: dataURL.path) {
                archive = try JSONDecoder().decode(LibraryArchive.self, from: Data(contentsOf: dataURL))
            } else {
                let legacy = URL.applicationSupportDirectory.appending(path: "Audience/audience-local-store.json")
                if FileManager.default.fileExists(atPath: legacy.path) {
                    archive = try Self.migrate(legacy)
                    generation += 1
                    try writer.writeNow(archive, generation: generation)
                    notice = "Les données de l’ancienne app ont été récupérées."
                }
            }
        } catch {
            readOnly = true
            alerts.append("Lecture des données impossible : \(error.localizedDescription). Le fichier existant est conservé et les modifications sont bloquées. Récupérez-le dans le Finder avant de relancer l’app.")
            DispatchQueue.main.async { [weak self] in self?.presentNextAlert() }
        }
    }

    private static func migrate(_ legacy: URL) throws -> LibraryArchive {
        var old = try JSONDecoder().decode(LibraryArchive.self, from: Data(contentsOf: legacy))
        // Legacy uploads live beside Electron's store; embed them in the new archive.
        let folder = legacy.deletingLastPathComponent()
        for code in Array(old.quizzes.keys) {
            guard var quiz = old.quizzes[code] else { continue }
            var questions = quiz.questions
            for i in questions.indices {
                let path = questions[i]["questionImage"].string
                guard path.hasPrefix("/uploads/") || path.hasPrefix("uploads/") else { continue }
                let relative = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let imageURL = folder.appending(path: relative).standardizedFileURL
                guard imageURL.path.hasPrefix(folder.path + "/"), let bytes = try? Data(contentsOf: imageURL) else {
                    throw AudienceError.message("Une ancienne image est introuvable. Importez une sauvegarde pour terminer la migration.")
                }
                let mime = UTType(filenameExtension: imageURL.pathExtension)?.preferredMIMEType ?? "image/png"
                questions[i]["questionImage"] = .string("data:\(mime);base64,\(bytes.base64EncodedString())")
            }
            quiz.questions = questions; quiz["liveActive"] = .bool(false); old.quizzes[code] = quiz
        }
        return old
    }

    // MARK: - Alerts

    /// Shows one alert at a time, attached to the active window.
    func report(_ message: String) {
        guard !alerts.contains(message) else { return }
        alerts.append(message)
        presentNextAlert()
    }
    private func presentNextAlert() {
        guard !alertVisible, let message = alerts.first else { return }
        alertVisible = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        if message.count <= 90 { alert.messageText = message }
        else { alert.messageText = "Audience"; alert.informativeText = message }
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            if !self.alerts.isEmpty { self.alerts.removeFirst() }
            self.alertVisible = false
            self.presentNextAlert()
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { _ in MainActor.assumeIsolated { finish() } }
        } else {
            alert.runModal(); finish()
        }
    }

    // MARK: - Persistence

    @discardableResult func commit(_ change: (inout LibraryArchive) -> Void) -> Bool {
        guard !readOnly else {
            report("Le fichier de données n’a pas pu être lu. Les modifications sont bloquées pour le préserver.")
            return false
        }
        change(&archive)
        generation += 1
        scheduleSave()
        return true
    }
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.saveNow()
        }
    }
    private func saveNow() async {
        defer { saveTask = nil }
        var saved = 0
        while saved < generation {
            saved = generation
            do { try await writer.write(archive, generation: saved) }
            catch { report("Enregistrement impossible : \(error.localizedDescription)"); return }
        }
    }
    /// Synchronous save used when the app quits or goes to the background.
    func flush() {
        guard !readOnly, generation > 0 else { return }
        do { try writer.writeNow(archive, generation: generation) }
        catch { report("Enregistrement impossible : \(error.localizedDescription)") }
    }

    // MARK: - Library contents

    private var activeAccount: String? { archive.synchronization.activeAccount }
    var visibleQuizzes: [Quiz] {
        archive.quizzes.values.filter {
            guard let owner = archive.synchronization.owners[$0.code] else { return true }
            return owner == activeAccount
        }
    }
    var visibleFolders: [QuizFolder] {
        archive.folders.values.filter { !$0.pendingDeletion && ($0.account == nil || $0.account == activeAccount) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var allTags: [String] {
        var seen = Set<String>(), tags: [String] = []
        for quiz in visibleQuizzes where !quiz.isDeleted {
            for tag in quiz.tags where seen.insert(tag.lowercased()).inserted { tags.append(tag) }
        }
        return tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    func folder(of quiz: Quiz) -> QuizFolder? {
        quiz.folderID.flatMap { archive.folders[$0] }.flatMap { $0.pendingDeletion ? nil : $0 }
    }
    func displayColor(of quiz: Quiz) -> QuizColor? { quiz.cardColor ?? folder(of: quiz)?.quizColor }
    func quizzes(in item: SidebarItem) -> [Quiz] {
        visibleQuizzes.filter { quiz in
            switch item {
            case .all: !quiz.isDeleted
            case .favorites: !quiz.isDeleted && quiz.isFavorite
            case .trash: quiz.isDeleted
            case .folder(let id): !quiz.isDeleted && folder(of: quiz)?.id == id
            case .tag(let tag): !quiz.isDeleted && quiz.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        }
    }
    func listedQuizzes(sort: QuizSort) -> [Quiz] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return quizzes(in: sidebar ?? .all).filter { quiz in
            query.isEmpty || quiz.title.localizedStandardContains(query) || quiz.code.localizedStandardContains(query)
                || quiz.tags.contains { $0.localizedStandardContains(query.trimmingCharacters(in: CharacterSet(charactersIn: "#"))) }
        }.sorted {
            switch sort {
            case .modified: $0.updatedAt > $1.updatedAt
            case .title: $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }
    var selectedQuizzes: [Quiz] { selection.compactMap { archive.quizzes[$0] } }
    var selectedQuiz: Quiz? { selection.count == 1 ? selection.first.flatMap { archive.quizzes[$0] } : nil }
    func title(of item: SidebarItem) -> String {
        if case .folder(let id) = item { return archive.folders[id]?.name ?? "Dossier" }
        return item.title
    }

    private func fingerprint(_ quiz: Quiz) -> String {
        if let cached = fingerprints[quiz.code], cached.quiz == quiz { return cached.value }
        let value = quiz.syncFingerprint
        fingerprints[quiz.code] = (quiz, value)
        return value
    }
    func isPending(_ quiz: Quiz) -> Bool {
        guard let record = archive.synchronization.records[quiz.code] else { return !quiz.isDeleted }
        return record.localFingerprint != fingerprint(quiz)
    }
    var syncStatus: String {
        if syncing { return "Synchronisation en cours…" }
        if syncError != nil { return "Synchronisation à réessayer" }
        guard connected else { return "Disponible hors ligne" }
        let pending = visibleQuizzes.contains(where: isPending)
            || archive.synchronization.pendingPurges.values.contains(activeAccount ?? "")
        if pending { return syncDrafts > 0 ? "\(syncDrafts) brouillon(s) sur ce Mac" : "Modifications en attente" }
        return "À jour"
    }

    // MARK: - Questionnaires

    func update(_ code: String, touch: Bool = true, _ change: (inout Quiz) -> Void) {
        var changed = false
        let saved = commit { archive in
            guard var quiz = archive.quizzes[code] else { return }
            let before = quiz
            change(&quiz)
            guard quiz != before else { return }
            if touch { quiz["updatedAt"] = .string(Quiz.timestamp) }
            archive.quizzes[code] = quiz
            changed = true
        }
        if saved && changed { localChange() }
    }
    private func updateAll(_ codes: some Sequence<String>, touch: Bool = false, _ change: (inout Quiz) -> Void) {
        for code in codes { update(code, touch: touch, change) }
    }
    /// Creates a questionnaire in the folder, tag or favorites currently shown.
    func create() {
        var quiz = Quiz()
        switch sidebar {
        case .folder(let id): quiz.folderID = id
        case .tag(let tag): quiz.tags = [tag]
        case .favorites: quiz.isFavorite = true
        default: break
        }
        if sidebar == .trash { sidebar = .all }
        if commit({ archive in
            archive.quizzes[quiz.code] = quiz
            archive.synchronization.owners[quiz.code] = archive.synchronization.activeAccount
        }) { search = ""; selection = [quiz.code]; localChange() }
    }
    func duplicate(_ codes: Set<String>) {
        var copies: Set<String> = []
        for code in codes {
            guard var copy = archive.quizzes[code], !copy.isDeleted else { continue }
            let newCode = Quiz().code
            copy["code"] = .string(newCode); copy.title += " (copie)"; copy["deletedAt"] = .null
            copy["liveActive"] = .bool(false); copy["updatedAt"] = .string(Quiz.timestamp)
            if commit({ archive in
                archive.quizzes[newCode] = copy
                archive.synchronization.owners[newCode] = archive.synchronization.activeAccount
            }) { copies.insert(newCode) }
        }
        if !copies.isEmpty { selection = copies; localChange() }
    }
    func moveToTrash(_ codes: Set<String>) {
        if let liveCode, codes.contains(liveCode) { report("Arrêtez la session en direct avant de supprimer ce questionnaire."); return }
        updateAll(codes, touch: true) { if !$0.isDeleted { $0["deletedAt"] = .string(Quiz.timestamp) } }
        selection.subtract(codes)
    }
    func restore(_ codes: Set<String>) {
        updateAll(codes, touch: true) { $0["deletedAt"] = .null }
        selection.subtract(codes)
    }
    func purge(_ codes: Set<String>) {
        if commit({ archive in
            for code in codes {
                if let owner = archive.synchronization.owners[code] {
                    archive.synchronization.pendingPurges[code] = owner
                }
                archive.quizzes.removeValue(forKey: code)
                archive.responses.removeValue(forKey: code)
            }
        }) { selection.subtract(codes); localChange() }
    }
    func emptyTrash() { purge(Set(quizzes(in: .trash).map(\.code))) }
    func setFavorite(_ codes: Set<String>, _ favorite: Bool) {
        updateAll(codes) { $0.isFavorite = favorite }
    }

    // MARK: - Folders, colors and tags

    @discardableResult func createFolder(with codes: Set<String> = [], rename: Bool = true) -> String? {
        let base = "Nouveau dossier"
        let names = Set(visibleFolders.map(\.name))
        var name = base, n = 2
        while names.contains(name) { name = "\(base) \(n)"; n += 1 }
        let folder = QuizFolder(name: name, account: activeAccount)
        guard commit({ $0.folders[folder.id] = folder }) else { return nil }
        if !codes.isEmpty { move(codes, to: folder.id) } else { localChange() }
        if rename { sidebar = .folder(folder.id); renamingFolder = folder.id }
        return folder.id
    }
    func renameFolder(_ id: String, to name: String) {
        let name = OrganizationText.folderName(name)
        guard archive.folders[id]?.name != name else { return }
        if commit({ $0.folders[id]?.name = name }) { localChange() }
    }
    func setFolderColor(_ id: String, _ color: QuizColor) {
        if commit({ $0.folders[id]?.color = color.rawValue }) { localChange() }
    }
    func deleteFolder(_ id: String) {
        guard let folder = archive.folders[id] else { return }
        let ok = commit { archive in
            for (code, quiz) in archive.quizzes where quiz.folderID == id { archive.quizzes[code]?.folderID = nil }
            if folder.remoteID != nil { archive.folders[id]?.pendingDeletion = true }
            else { archive.folders.removeValue(forKey: id) }
        }
        guard ok else { return }
        if sidebar == .folder(id) { sidebar = .all }
        localChange()
    }
    func move(_ codes: Set<String>, to folderID: String?) {
        updateAll(codes.filter { archive.quizzes[$0]?.isDeleted == false }) { $0.folderID = folderID }
    }
    func setColor(_ codes: Set<String>, _ color: QuizColor?) {
        updateAll(codes) { $0.cardColor = color }
    }
    func setTags(_ code: String, _ tags: [String]) {
        update(code, touch: false) { $0.tags = tags }
    }
    func addTag(_ tag: String, to codes: Set<String>) {
        updateAll(codes) { $0.tags = $0.tags + [tag] }
    }
    func removeTag(_ tag: String, from codes: Set<String>? = nil) {
        let targets = codes ?? Set(visibleQuizzes.map(\.code))
        updateAll(targets) { quiz in quiz.tags = quiz.tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame } }
        if sidebar == .tag(tag), codes == nil { sidebar = .all }
    }

    // MARK: - Backups

    func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try JSONDecoder().decode(LibraryArchive.self, from: Data(contentsOf: url))
            var count = 0
            if commit({ count = $0.merge(incoming) }) {
                notice = "\(count) questionnaire(s) importé(s)."; sidebar = .all; localChange()
            }
        } catch { report(error.localizedDescription) }
    }
    func exportBackup(only codes: Set<String>? = nil) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        if let codes, codes.count == 1, let code = codes.first { panel.nameFieldStringValue = "Audience-\(code).json" }
        else { panel.nameFieldStringValue = "Audience-sauvegarde.json" }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var output = LibraryArchive()
            let quizzes = visibleQuizzes.filter { codes?.contains($0.code) ?? true }
            for quiz in quizzes {
                output.quizzes[quiz.code] = quiz
                output.responses[quiz.code] = archive.responses[quiz.code]
                if let folder = folder(of: quiz), output.folders[folder.id] == nil {
                    // Backups carry folder names and colors, never website identifiers.
                    output.folders[folder.id] = QuizFolder(id: folder.id, name: folder.name, color: folder.quizColor)
                }
            }
            if codes == nil {
                for folder in visibleFolders where output.folders[folder.id] == nil {
                    output.folders[folder.id] = QuizFolder(id: folder.id, name: folder.name, color: folder.quizColor)
                }
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(output).write(to: url, options: .atomic)
            notice = "Sauvegarde exportée."
        } catch { report(error.localizedDescription) }
    }
    func revealData() {
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: dataURL.path) ? dataURL : dataURL.deletingLastPathComponent()])
    }

    // MARK: - Account and synchronization

    func perform(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await action() }
        catch is CancellationError {} catch { report(error.localizedDescription) }
    }
    private func localChange() {
        editRevision += 1
        scheduleSync()
    }
    private func scheduleSync() {
        guard connected else { return }
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self else { return }
            self.scheduledSync = nil
            await self.synchronize()
        }
    }
    func connect(email: String, password: String) async {
        await perform {
            connected = false
            accountName = try await remote.connect(address: RemoteClient.siteURL.absoluteString, email: email, password: password)
            let account = try await remote.accountIdentity()
            guard commit({ archive in
                archive.synchronization.activeAccount = account
                for code in archive.quizzes.keys where archive.synchronization.owners[code] == nil {
                    archive.synchronization.owners[code] = account
                }
            }) else { await remote.disconnect(); return }
            connected = true
            sidebar = .all; search = ""; selection = []
            syncError = nil; lastFullRefresh = nil
        }
        if connected { await synchronize() }
    }
    func disconnect() async {
        guard !syncing && !busy && liveCode == nil else { return }
        scheduledSync?.cancel()
        await remote.disconnect()
        connected = false; accountName = ""; syncError = nil
    }
    func synchronize(showErrors: Bool = false) async {
        guard connected, !busy, liveCode == nil, let account = archive.synchronization.activeAccount else { return }
        if syncing { retryAfterSync = true; return }
        syncing = true
        let revision = editRevision
        defer {
            syncing = false
            if retryAfterSync || revision != editRevision { retryAfterSync = false; scheduleSync() }
        }
        // Unchanged questionnaires are downloaded again every ten minutes, or on request.
        let fullRefresh = showErrors || lastFullRefresh.map { Date().timeIntervalSince($0) > 600 } ?? true
        do {
            let report = try await SyncEngine().run(account: account, snapshot: archive, remote: remote, fullRefresh: fullRefresh) { [weak self] event in
                try await self?.receiveSync(event)
            }
            var failures = report.failures
            if let folders = await remote.remoteFolders() {
                failures += await OrganizationSync().run(
                    account: account, items: report.items, folders: folders, remote: remote,
                    current: { [weak self] in await self?.archive ?? LibraryArchive() },
                    receive: { [weak self] event in await self?.receiveOrganization(event) })
            }
            if fullRefresh { lastFullRefresh = Date() }
            syncDrafts = report.drafts
            syncSummary = "\(report.received) reçu(s) · \(report.sent) envoyé(s)"
            if report.conflicts > 0 {
                notice = "\(report.conflicts) conflit(s) : les versions du Mac ont été conservées dans des questionnaires séparés."
            }
            syncError = failures.isEmpty ? nil : failures.joined(separator: "\n")
            if failures.isEmpty {
                lastSyncAt = Date()
            } else if showErrors, let syncError { self.report(syncError) }
        } catch is CancellationError {
        } catch {
            syncError = error.localizedDescription
            if showErrors { self.report(error.localizedDescription) }
        }
    }
    private func receiveSync(_ event: SyncEvent) throws {
        var next = archive
        let applied = next.apply(event)
        if next != archive {
            guard commit({ $0 = next }) else { throw AudienceError.message("Impossible d’enregistrer les questionnaires sur ce Mac.") }
        }
        if !applied || event.kind == .conflict { retryAfterSync = true }
    }
    private func receiveOrganization(_ event: OrganizationEvent) {
        var next = archive
        next.apply(event)
        if next != archive { commit { $0 = next } }
    }
    func automaticSyncLoop() async {
        while !Task.isCancelled {
            await synchronize()
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }

    // MARK: - Live sessions

    func startLive(_ quiz: Quiz, at index: Int = 0, resetResponses: Bool) async {
        while syncing { do { try await Task.sleep(for: .milliseconds(100)) } catch { return } }
        await perform {
            if let liveCode, liveCode != quiz.code { throw AudienceError.message("Une session est déjà en direct. Arrêtez-la d’abord.") }
            guard let latest = archive.quizzes[quiz.code], !latest.isDeleted else { throw AudienceError.message("Ce questionnaire n’est plus disponible.") }
            let start = latest.questions.indices.contains(index) ? index : 0
            let runID = RemoteClient.makeRunID()
            let response = try await remote.send(latest, index: start, live: true, runID: runID, resetResponses: resetResponses)
            liveRunID = runID; liveCode = quiz.code; liveIndex = start; liveParticipants = nil
            applyTiming(response)
            if resetResponses { commit { $0.responses.removeValue(forKey: quiz.code) } }
        }
    }
    func stopLive() async {
        // A window may close while a publish request is still in flight.
        // Finish that request before sending the stop, so it cannot reopen the session.
        while busy {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard let code = liveCode else { return }
        await perform {
            try await remote.stop(code: code)
            liveCode = nil; liveRunID = nil; liveTiming = nil; liveParticipants = nil
        }
        if liveCode == nil { scheduleSync() }
    }
    func goLive(index: Int, quiz: Quiz) async {
        await perform {
            let latest = archive.quizzes[quiz.code] ?? quiz
            let response = try await remote.send(latest, index: index, live: true, runID: liveRunID)
            liveIndex = index
            applyTiming(response)
        }
    }
    /// Gives participants a new answering window for the question on screen.
    func restartQuestion() async {
        guard let code = liveCode else { return }
        await perform { applyTiming(try await remote.restartQuestion(code: code)) }
    }
    private func applyTiming(_ response: JSONValue) {
        let startedMs = response["questionStartedAtMs"].double
        guard startedMs > 0 else { liveTiming = nil; return }
        // Convert the server clock to this Mac's clock.
        let serverNow = response["serverNowMs"].double
        let offset = serverNow > 0 ? Date().timeIntervalSince1970 - serverNow / 1000 : 0
        liveTiming = LiveTiming(startedAt: Date(timeIntervalSince1970: startedMs / 1000 + offset),
                                limit: max(1, response["timeLimitSec"].int))
    }
    /// Results and connected participants of the live session.
    func refreshLive(_ code: String) async throws {
        try await refreshResults(code)
        if let count = try? await remote.presence(code: code) { liveParticipants = count }
    }
    func refreshResults(_ code: String) async throws {
        let results = try await remote.results(code: code)
        if archive.responses[code] != results { commit { $0.responses[code] = results } }
    }
    func participantURL(code: String) -> URL? { RemoteClient.participantURL(code: code) }
}
