import Foundation
import Testing
@testable import AudienceCore

private func quiz(_ code: String = "ABC123", title: String = "Révisions") -> Quiz {
    var quiz = Quiz(code: code); quiz.title = title
    var question = Question(); question.text = "Combien font 2 + 2 ?"; question.answers = ["4", "5"]
    quiz.questions = [question]
    return quiz
}
private actor TestLibrary {
    var archive: LibraryArchive
    init(_ archive: LibraryArchive = LibraryArchive()) { self.archive = archive }
    func snapshot() -> LibraryArchive { archive }
    func apply(_ event: SyncEvent) { archive.apply(event) }
}
private actor TestRemote: SyncRemote {
    var quizzes: [String: Quiz]
    var writes = 0
    var purges = 0
    var failCodes: Set<String> = []
    var offline = false
    init(_ quizzes: [Quiz] = []) { self.quizzes = Dictionary(uniqueKeysWithValues: quizzes.map { ($0.code, $0) }) }
    func inventory() throws -> [RemoteItem] {
        if offline { throw URLError(.notConnectedToInternet) }
        return quizzes.values.sorted { $0.code < $1.code }.map {
            var fields: [String: JSONValue] = ["code": .string($0.code), "title": .string($0.title), "isFavorite": .bool($0.isFavorite)]
            if $0.isDeleted { fields["deletedAt"] = $0["deletedAt"] }
            return RemoteItem(fields: .object(fields))
        }
    }
    func read(_ item: RemoteItem) throws -> RemoteQuiz {
        if failCodes.contains(item.code) { throw AudienceError.message("Fixture inaccessible") }
        return RemoteQuiz(quiz: quizzes[item.code]!, results: .object(["questions": .array([])]))
    }
    func write(_ quiz: Quiz, replacing item: RemoteItem?) throws -> RemoteQuiz {
        if failCodes.contains(quiz.code) { throw URLError(.networkConnectionLost) }
        writes += 1; quizzes[quiz.code] = quiz
        return RemoteQuiz(quiz: quiz)
    }
    func setDeleted(code: String, deleted: Bool) { quizzes[code]?["deletedAt"] = deleted ? .string(Quiz.timestamp) : .null }
    func purge(code: String) { quizzes.removeValue(forKey: code); purges += 1 }
    func fail(_ code: String) { failCodes.insert(code) }
    func setOffline() { offline = true }
    func writeCount() -> Int { writes }
    func stored(_ code: String) -> Quiz? { quizzes[code] }
    func purgeCount() -> Int { purges }
}

struct SynchronizationTests {
    let account = "account-A"
    private func cycle(_ state: TestLibrary, _ remote: TestRemote) async throws -> SyncReport {
        try await SyncEngine().run(account: account, snapshot: await state.snapshot(), remote: remote) { await state.apply($0) }
    }
    private func tracked(_ original: Quiz) -> LibraryArchive {
        var archive = LibraryArchive(); archive.quizzes[original.code] = original
        archive.synchronization.activeAccount = account
        archive.synchronization.owners[original.code] = account
        archive.synchronization.records[original.code] = SyncRecord(account: account, local: original, remote: original)
        return archive
    }
    @Test func firstConnectionDisplaysExistingQuestionnairesWithoutDuplicatesOnRepeat() async throws {
        let remote = TestRemote([quiz(), quiz("EMPTY")])
        let state = TestLibrary()
        let first = try await cycle(state, remote)
        #expect(first.received == 2)
        #expect(await state.snapshot().quizzes.count == 2)
        let second = try await cycle(state, remote)
        #expect(second.received == 0)
        #expect(await state.snapshot().quizzes.count == 2)
        #expect(await remote.writeCount() == 0)
    }
    @Test func sendsLocalCreationAndEditsBackToTheSameServerCode() async throws {
        var archive = LibraryArchive(); archive.quizzes["ABC123"] = quiz()
        let state = TestLibrary(archive), remote = TestRemote()
        #expect(try await cycle(state, remote).sent == 1)
        var next = await state.snapshot(); next.quizzes["ABC123"]?.title = "Modification sur le Mac"
        let edited = TestLibrary(next)
        #expect(try await cycle(edited, remote).sent == 1)
        #expect(await remote.stored("ABC123")?.title == "Modification sur le Mac")
        #expect(await edited.snapshot().quizzes.count == 1)
        #expect(try await cycle(edited, remote).sent == 0)
    }
    @Test func downloadsWebsiteEditsIntoExistingQuestionnaire() async throws {
        let original = quiz(); var website = original; website.title = "Modification sur le site"
        let state = TestLibrary(tracked(original)), remote = TestRemote([website])
        #expect(try await cycle(state, remote).received == 1)
        #expect(await state.snapshot().quizzes[original.code]?.title == website.title)
        #expect(await remote.writeCount() == 0)
    }
    @Test func simultaneousEditsPreserveBothVersions() async throws {
        let original = quiz(); var archive = tracked(original)
        archive.quizzes[original.code]?.title = "Version Mac"
        var website = original; website.title = "Version site"
        let state = TestLibrary(archive), remote = TestRemote([website])
        #expect(try await cycle(state, remote).conflicts == 1)
        let saved = await state.snapshot()
        #expect(saved.quizzes.count == 2)
        #expect(saved.quizzes[original.code]?.title == "Version site")
        #expect(saved.quizzes.values.contains { $0.title == "Version Mac (conflit sur ce Mac)" && $0.code != original.code })
        #expect(await remote.writeCount() == 0)
        _ = try await cycle(state, remote)
        #expect(await state.snapshot().quizzes.count == 2)
    }
    @Test func incompleteLocalQuestionsRemainLocalAndDoNotBlockDownloads() async throws {
        var archive = LibraryArchive(); archive.quizzes["DRAFT"] = Quiz(code: "DRAFT")
        let state = TestLibrary(archive), remote = TestRemote([quiz()])
        let report = try await cycle(state, remote)
        #expect(report.received == 1 && report.drafts == 1)
        #expect(await state.snapshot().quizzes.count == 2)
        #expect(await remote.stored("DRAFT") == nil)
    }
    @Test func oneUnreadableQuestionnaireDoesNotHideTheOthers() async throws {
        let state = TestLibrary(), remote = TestRemote([quiz("BAD"), quiz("GOOD")])
        await remote.fail("BAD")
        let report = try await cycle(state, remote)
        #expect(report.failures.count == 1 && report.received == 1)
        #expect(await state.snapshot().quizzes["GOOD"] != nil)
    }
    @Test func favoritesAndTrashPropagateBothWays() async throws {
        let original = quiz(); var archive = tracked(original)
        archive.quizzes[original.code]?.isFavorite = true
        let state = TestLibrary(archive), remote = TestRemote([original])
        _ = try await cycle(state, remote)
        #expect(await remote.stored(original.code)?.isFavorite == true)
        await remote.setDeleted(code: original.code, deleted: true)
        _ = try await cycle(state, remote)
        #expect(await state.snapshot().quizzes[original.code]?.isDeleted == true)
        var restored = await state.snapshot(); restored.quizzes[original.code]?["deletedAt"] = .null
        let restoredState = TestLibrary(restored)
        _ = try await cycle(restoredState, remote)
        #expect(await remote.stored(original.code)?.isDeleted == false)
        var trashed = await restoredState.snapshot(); trashed.quizzes[original.code]?["deletedAt"] = .string(Quiz.timestamp)
        _ = try await cycle(TestLibrary(trashed), remote)
        #expect(await remote.stored(original.code)?.isDeleted == true)
    }
    @Test func websiteTrashCanBeRestoredWithoutLosingItsQuestions() async throws {
        var deleted = quiz(); deleted["deletedAt"] = .string(Quiz.timestamp)
        let state = TestLibrary(), remote = TestRemote([deleted])
        _ = try await cycle(state, remote)
        var archive = await state.snapshot()
        #expect(archive.quizzes[deleted.code]?.questions.isEmpty == true)
        archive.quizzes[deleted.code]?["deletedAt"] = .null
        let restored = TestLibrary(archive)
        _ = try await cycle(restored, remote)
        #expect(await restored.snapshot().quizzes[deleted.code]?.questions.count == 1)
        #expect(await remote.writeCount() == 0)
    }
    @Test func anotherAccountsQuestionnairesAreNeverUploaded() async throws {
        var archive = LibraryArchive(); archive.quizzes["PRIVATE"] = quiz("PRIVATE")
        archive.synchronization.owners["PRIVATE"] = "account-B"
        let remote = TestRemote()
        _ = try await cycle(TestLibrary(archive), remote)
        #expect(await remote.writeCount() == 0)
    }
    @Test func editsMadeDuringARequestAreNotOverwrittenByItsResponse() {
        let original = quiz(); var archive = tracked(original)
        var website = original; website.title = "Site"
        archive.quizzes[original.code]?.title = "Nouvelle frappe pendant le téléchargement"
        let event = SyncEvent(kind: .pull, account: account, expectedLocal: original, remote: RemoteQuiz(quiz: website))
        let applied = archive.apply(event)
        #expect(!applied)
        #expect(archive.quizzes[original.code]?.title == "Nouvelle frappe pendant le téléchargement")
    }
    @Test func uploadAcknowledgesOnlyTheVersionActuallySent() {
        let original = quiz(); var archive = tracked(original)
        archive.quizzes[original.code]?.title = "Saisie plus récente"
        let event = SyncEvent(kind: .pushed, account: account, expectedLocal: original, remote: RemoteQuiz(quiz: original), record: SyncRecord(account: account, local: original, remote: original))
        let applied = archive.apply(event)
        #expect(applied)
        #expect(archive.quizzes[original.code]?.title == "Saisie plus récente")
        #expect(archive.synchronization.records[original.code]?.localFingerprint != archive.quizzes[original.code]?.syncFingerprint)
    }
    @Test func offlineFailureRetainsLocalChangesForRetry() async throws {
        var archive = LibraryArchive(); archive.quizzes["ABC123"] = quiz()
        let remote = TestRemote(); await remote.setOffline()
        let state = TestLibrary(archive)
        do { _ = try await cycle(state, remote); Issue.record("Offline sync should fail") } catch {}
        #expect(await state.snapshot() == archive)
        #expect(await remote.writeCount() == 0)
    }
    @Test func missingFromCappedInventoryDoesNotResurrectKnownQuizzes() async throws {
        let original = quiz(); let remote = TestRemote()
        _ = try await cycle(TestLibrary(tracked(original)), remote)
        #expect(await remote.writeCount() == 0)
    }
    @Test func purgeQueueSurvivesRestartAndRemovesServerCopy() async throws {
        let original = quiz(); var archive = tracked(original)
        archive.quizzes.removeValue(forKey: original.code)
        archive.synchronization.pendingPurges[original.code] = account
        let restored = try JSONDecoder().decode(LibraryArchive.self, from: JSONEncoder().encode(archive))
        #expect(restored.synchronization == archive.synchronization)
        let state = TestLibrary(restored), remote = TestRemote([original])
        _ = try await cycle(state, remote)
        #expect(await remote.stored(original.code) == nil)
        #expect(await remote.purgeCount() == 1)
        #expect(await state.snapshot().synchronization.pendingPurges.isEmpty == true)
    }
}

struct SynchronizationFingerprintTests {
    @Test func serverNormalizationDoesNotCreateFalseConflicts() {
        let native = quiz()
        var website = native
        var question = website.questions[0]
        question["question"] = .string("<p>Combien font 2 + 2 ?</p>")
        question.fields.removeValue(forKey: "maxRating")
        question.fields.removeValue(forKey: "correctIndexes")
        question["isPollMode"] = .bool(false)
        question["questionImage"] = .string("")
        question["questionImageZoom"] = .number(1)
        question["runId"] = .string("server-run")
        website.questions = [question]
        website["liveActive"] = .bool(true)
        website["currentIndex"] = .number(1)
        #expect(native.syncFingerprint == website.syncFingerprint)
        #expect(SyncPlanner.decision(local: native, remote: website, record: nil) == .unchanged)
    }
    @Test func formattingChangesOnTheWebsiteAreStillDetected() {
        let native = quiz()
        var website = native; var question = website.questions[0]
        question["question"] = .string("<p>Combien font <strong>2 + 2</strong> ?</p>")
        website.questions = [question]
        #expect(native.syncFingerprint != website.syncFingerprint)
    }
}
