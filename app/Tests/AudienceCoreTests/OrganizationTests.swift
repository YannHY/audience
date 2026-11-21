import Foundation
import Testing
@testable import AudienceCore

private func sample(_ code: String) -> Quiz {
    var quiz = Quiz(code: code); quiz.title = "Quiz \(code)"
    var question = Question(); question.text = "Capitale de la France ?"; question.answers = ["Paris", "Lyon"]
    quiz.questions = [question]
    return quiz
}

/// In-memory imitation of quiz_organize.php and list_quizzes.php.
private actor OrganizeServer: OrganizationRemote {
    var folders: [Int: RemoteFolder] = [:]
    var placement: [String: QuizOrganization] = [:]
    var nextID = 10
    var requests: [String] = []
    func organize(_ request: JSONValue) throws -> JSONValue {
        let action = request["action"].string
        requests.append(action)
        switch action {
        case "create_folder":
            let id = nextID; nextID += 1
            let state = FolderState(name: request["name"].string, color: request["color"].string)
            folders[id] = RemoteFolder(id: id, name: state.name, color: state.color)
            return .object(["success": .bool(true), "folder": .object(["id": .number(Double(id)), "name": .string(state.name), "color": .string(state.color)])])
        case "update_folder":
            let id = request["id"].int
            guard folders[id] != nil else { throw AudienceError.message("Dossier introuvable") }
            folders[id] = RemoteFolder(id: id, name: request["name"].string, color: request["color"].string)
        case "delete_folder":
            let id = request["id"].int
            folders.removeValue(forKey: id)
            for (code, value) in placement where value.folder == id { placement[code]?.folder = nil }
        case "move":
            let code = request["code"].string
            var value = placement[code] ?? QuizOrganization()
            value.folder = request["folderId"].int > 0 ? request["folderId"].int : nil
            placement[code] = value
        case "set_color":
            let code = request["code"].string
            var value = placement[code] ?? QuizOrganization()
            value.color = QuizColor(key: request["color"].string)?.rawValue
            placement[code] = value
        case "set_tags":
            let code = request["code"].string
            var value = placement[code] ?? QuizOrganization()
            value.tags = OrganizationText.tags(request["tags"].array.map(\.string))
            placement[code] = value
        default: throw AudienceError.message("Action inconnue")
        }
        return .object(["success": .bool(true)])
    }
    func items(_ codes: [String]) -> [RemoteItem] {
        codes.map { code in
            let value = placement[code] ?? QuizOrganization()
            return RemoteItem(fields: .object([
                "code": .string(code),
                "folderId": value.folder.map { .number(Double($0)) } ?? .null,
                "color": value.color.map(JSONValue.string) ?? .null,
                "tags": .array(value.tags.map(JSONValue.string))
            ]))
        }
    }
    func list() -> [RemoteFolder] { folders.values.sorted { $0.id < $1.id } }
    func addFolder(_ name: String, color: String = "teal") -> Int {
        let id = nextID; nextID += 1
        folders[id] = RemoteFolder(id: id, name: name, color: color); return id
    }
    func place(_ code: String, _ value: QuizOrganization) { placement[code] = value }
    func rename(_ id: Int, _ name: String) { folders[id]?.name = name }
    func remove(_ id: Int) { folders.removeValue(forKey: id); for (code, value) in placement where value.folder == id { placement[code]?.folder = nil } }
    func value(_ code: String) -> QuizOrganization { placement[code] ?? QuizOrganization() }
    func folder(_ id: Int) -> RemoteFolder? { folders[id] }
    func log() -> [String] { requests }
}

private actor Library {
    var archive: LibraryArchive
    init(_ archive: LibraryArchive) { self.archive = archive }
    func snapshot() -> LibraryArchive { archive }
    func apply(_ event: OrganizationEvent) { archive.apply(event) }
    func edit(_ change: (inout LibraryArchive) -> Void) { change(&archive) }
}

struct OrganizationTests {
    let account = "account-A"

    private func tracked(_ codes: [String]) -> LibraryArchive {
        var archive = LibraryArchive()
        archive.synchronization.activeAccount = account
        for code in codes {
            let quiz = sample(code)
            archive.quizzes[code] = quiz
            archive.synchronization.owners[code] = account
            archive.synchronization.records[code] = SyncRecord(account: account, local: quiz, remote: quiz)
        }
        return archive
    }
    private func cycle(_ library: Library, _ server: OrganizeServer, _ codes: [String]) async -> [String] {
        await OrganizationSync().run(account: account, items: await server.items(codes), folders: await server.list(), remote: server,
                                     current: { await library.snapshot() }, receive: { await library.apply($0) })
    }

    @Test func tagsAndFolderNamesFollowTheWebsiteRules() {
        #expect(OrganizationText.tags(["  #Maths ", "maths", "", "##", "Géo  graphie"]) == ["Maths", "Géo graphie"])
        #expect(OrganizationText.tags((1...20).map { "t\($0)" }).count == 12)
        #expect(OrganizationText.tags([String(repeating: "a", count: 40)]).first?.count == 30)
        #expect(OrganizationText.folderName("   ") == "Nouveau dossier")
        #expect(OrganizationText.folderName(" Cours\n de  maths ") == "Cours de maths")
        #expect(QuizColor(key: " Rose ") == .rose)
        #expect(QuizColor(key: "purple") == nil)
    }

    @Test func plannerPrefersTheMacWhenBothSidesChanged() {
        #expect(OrganizationPlanner.decision(local: 1, remote: 1, base: 0) == .same)
        #expect(OrganizationPlanner.decision(local: 0, remote: 2, base: 0) == .pull)
        #expect(OrganizationPlanner.decision(local: 1, remote: 0, base: 0) == .push)
        #expect(OrganizationPlanner.decision(local: 1, remote: 2, base: 0) == .push)
        #expect(OrganizationPlanner.decision(local: 1, remote: 2, base: nil) == .pull)
        #expect(OrganizationPlanner.decision(local: 1, remote: 0, base: nil, localIsEmpty: false, remoteIsEmpty: true) == .push)
    }

    @Test func websiteFoldersAndPlacementsAppearOnTheMac() async {
        let server = OrganizeServer()
        let id = await server.addFolder("Histoire", color: "amber")
        await server.place("Q1", QuizOrganization(folder: id, color: "rose", tags: ["bac"]))
        let library = Library(tracked(["Q1", "Q2"]))
        let failures = await cycle(library, server, ["Q1", "Q2"])
        #expect(failures.isEmpty)
        let archive = await library.snapshot()
        let folder = archive.folders.values.first
        #expect(archive.folders.count == 1)
        #expect(folder?.name == "Histoire" && folder?.quizColor == .amber && folder?.remoteID == id)
        #expect(archive.quizzes["Q1"]?.folderID == folder?.id)
        #expect(archive.quizzes["Q1"]?.cardColor == .rose)
        #expect(archive.quizzes["Q1"]?.tags == ["bac"])
        #expect(archive.quizzes["Q2"]?.folderID == nil)
        #expect(await server.log().isEmpty, "Pulling must not send anything back")
        // A second exchange is a no-op.
        #expect(await cycle(library, server, ["Q1", "Q2"]).isEmpty)
        #expect(await server.log().isEmpty)
    }

    @Test func folderCreatedOnTheMacIsCreatedOnTheWebsiteBeforeMovingQuizzes() async {
        let server = OrganizeServer()
        var archive = tracked(["Q1"])
        let folder = QuizFolder(name: "Sciences", color: .green, account: account)
        archive.folders[folder.id] = folder
        archive.quizzes["Q1"]?.folderID = folder.id
        archive.quizzes["Q1"]?.tags = ["labo"]
        let library = Library(archive)
        #expect(await cycle(library, server, ["Q1"]).isEmpty)
        let remoteID = await library.snapshot().folders[folder.id]?.remoteID
        #expect(remoteID != nil)
        #expect(await server.folder(remoteID ?? 0)?.name == "Sciences")
        #expect(await server.value("Q1") == QuizOrganization(folder: remoteID, tags: ["labo"]))
        #expect(await server.log() == ["create_folder", "move", "set_tags"])
        #expect(await cycle(library, server, ["Q1"]).isEmpty)
        #expect(await server.log().count == 3, "Nothing left to send")
    }

    @Test func renamesTravelBothWaysAndRemoteDeletionEmptiesTheFolder() async {
        let server = OrganizeServer()
        let id = await server.addFolder("Brouillon")
        await server.place("Q1", QuizOrganization(folder: id))
        let library = Library(tracked(["Q1"]))
        _ = await cycle(library, server, ["Q1"])
        let localID = await library.snapshot().folders.values.first!.id

        await library.edit { $0.folders[localID]?.name = "Définitif" }
        _ = await cycle(library, server, ["Q1"])
        #expect(await server.folder(id)?.name == "Définitif")

        await server.rename(id, "Renommé sur le site")
        _ = await cycle(library, server, ["Q1"])
        #expect(await library.snapshot().folders[localID]?.name == "Renommé sur le site")

        await server.remove(id)
        _ = await cycle(library, server, ["Q1"])
        let archive = await library.snapshot()
        #expect(archive.folders.isEmpty)
        #expect(archive.quizzes["Q1"]?.folderID == nil)
        #expect(!(await server.log().contains("move")), "A deletion on the website must not be sent back")
    }

    @Test func deletingAFolderOnTheMacDeletesItOnTheWebsite() async {
        let server = OrganizeServer()
        let id = await server.addFolder("Ancien")
        await server.place("Q1", QuizOrganization(folder: id))
        let library = Library(tracked(["Q1"]))
        _ = await cycle(library, server, ["Q1"])
        let localID = await library.snapshot().folders.values.first!.id
        await library.edit { archive in
            archive.folders[localID]?.pendingDeletion = true
            archive.quizzes["Q1"]?.folderID = nil
        }
        #expect(await cycle(library, server, ["Q1"]).isEmpty)
        #expect(await server.folder(id) == nil)
        #expect(await library.snapshot().folders.isEmpty)
        #expect(await server.value("Q1").folder == nil)
    }

    @Test func editsMadeDuringAnExchangeAreKept() {
        var archive = tracked(["Q1"])
        archive.quizzes["Q1"]?.tags = ["local"]
        // The exchange read an empty organization, but the user tagged the quiz meanwhile.
        archive.apply(.quizPulled(code: "Q1", organization: QuizOrganization(tags: ["site"]), expected: QuizOrganization(), account: account))
        #expect(archive.quizzes["Q1"]?.tags == ["local"])
    }

    @Test func contentDownloadKeepsLocalOrganization() {
        var archive = tracked(["Q1"])
        archive.quizzes["Q1"]?.tags = ["gardé"]
        var remote = sample("Q1"); remote.title = "Nouveau titre"
        let local = archive.quizzes["Q1"]
        archive.apply(SyncEvent(kind: .pull, account: account, expectedLocal: local, remote: RemoteQuiz(quiz: remote), stamp: "2026-11-21 10:00:00"))
        #expect(archive.quizzes["Q1"]?.title == "Nouveau titre")
        #expect(archive.quizzes["Q1"]?.tags == ["gardé"])
        #expect(archive.synchronization.records["Q1"]?.remoteStamp == "2026-11-21 10:00:00")
    }

    @Test func organizationIsNeverSentWithTheQuestionnaire() {
        var quiz = sample("Q1"); quiz.tags = ["x"]; quiz.cardColor = .blue; quiz.folderID = "local"
        let payload = quiz.payload().object
        #expect(payload["tags"] == nil && payload["cardColor"] == nil && payload["localFolder"] == nil)
        #expect(quiz.syncFingerprint == sample("Q1").syncFingerprint)
    }

    @Test func backupsKeepFoldersWithoutWebsiteIdentifiers() throws {
        var source = LibraryArchive()
        var folder = QuizFolder(name: "Exporté", color: .slate); folder.remoteID = 42; folder.account = "other"
        source.folders[folder.id] = QuizFolder(id: folder.id, name: folder.name, color: folder.quizColor)
        var quiz = sample("Q1"); quiz.folderID = folder.id
        source.quizzes["Q1"] = quiz
        let decoded = try JSONDecoder().decode(LibraryArchive.self, from: JSONEncoder().encode(source))
        var target = LibraryArchive()
        #expect(target.merge(decoded) == 1)
        let imported = try #require(target.folders.values.first)
        #expect(imported.name == "Exporté" && imported.remoteID == nil && imported.account == nil)
        #expect(target.quizzes["Q1"]?.folderID == imported.id)
    }

    @Test func htmlEntitiesAreDecodedForDisplay() {
        #expect("Qu&#39;est-ce que l&#x27;intrigue ?".plainText == "Qu'est-ce que l'intrigue ?")
        #expect("&laquo;&nbsp;Th&eacute;&acirc;tre&nbsp;&raquo; &amp;#39;".plainText == "« Théâtre » &#39;")
        #expect("A & B &unknown; &".plainText == "A & B &unknown; &")
    }

    @Test func dateParsingHandlesBothFormats() {
        #expect(Quiz.date(from: "2026-11-21T09:30:00Z") > Quiz.date(from: "2020-01-01 08:00:00"))
        #expect(Quiz.date(from: "2026-11-21 09:30:00") != .distantPast)
        #expect(Quiz.date(from: "garbage") == .distantPast)
    }
}

private actor CountingRemote: SyncRemote {
    var quiz: Quiz
    var stamp = "2026-11-21 08:00:00"
    var reads = 0
    init(_ quiz: Quiz) { self.quiz = quiz }
    func inventory() -> [RemoteItem] {
        [RemoteItem(fields: .object(["code": .string(quiz.code), "updatedAt": .string(stamp), "isFavorite": .bool(quiz.isFavorite)]))]
    }
    func read(_ item: RemoteItem) -> RemoteQuiz { reads += 1; return RemoteQuiz(quiz: quiz) }
    func write(_ quiz: Quiz, replacing item: RemoteItem?) -> RemoteQuiz { self.quiz = quiz; return RemoteQuiz(quiz: quiz) }
    func setDeleted(code: String, deleted: Bool) {}
    func purge(code: String) {}
    func change(_ title: String) { quiz.title = title; stamp = "2026-11-21 09:00:00" }
    func readCount() -> Int { reads }
}

private actor ContentLibrary {
    var archive = LibraryArchive()
    func snapshot() -> LibraryArchive { archive }
    func apply(_ event: SyncEvent) { archive.apply(event) }
}

struct IncrementalSyncTests {
    @Test func unchangedQuestionnairesAreNotDownloadedAgain() async throws {
        let remote = CountingRemote(sample("Q1"))
        let library = ContentLibrary()
        let engine = SyncEngine()
        _ = try await engine.run(account: "A", snapshot: await library.snapshot(), remote: remote, fullRefresh: false) { await library.apply($0) }
        #expect(await remote.readCount() == 1)
        _ = try await engine.run(account: "A", snapshot: await library.snapshot(), remote: remote, fullRefresh: false) { await library.apply($0) }
        #expect(await remote.readCount() == 1, "Same website date: no download")
        await remote.change("Modifié sur le site")
        _ = try await engine.run(account: "A", snapshot: await library.snapshot(), remote: remote, fullRefresh: false) { await library.apply($0) }
        #expect(await remote.readCount() == 2)
        #expect(await library.snapshot().quizzes["Q1"]?.title == "Modifié sur le site")
        _ = try await engine.run(account: "A", snapshot: await library.snapshot(), remote: remote) { await library.apply($0) }
        #expect(await remote.readCount() == 3, "A full refresh always downloads")
    }
}
