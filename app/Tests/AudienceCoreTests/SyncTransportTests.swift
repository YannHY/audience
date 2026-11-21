import Testing
import Foundation
@testable import AudienceCore

struct SyncTransportTests {
    private func client(host: String = "sync.example") async throws -> RemoteClient {
        let client = RemoteClient(configurationFactory: {
            let config = RemoteClient.sessionConfiguration()
            config.protocolClasses = [SyncProtocol.self]
            return config
        })
        _ = try await client.connect(address: "https://\(host)/apps/audience/", email: "fixture@example.org", password: "synthetic")
        return client
    }
    @Test func inventoryIncludesActiveQuestionnairesAndTrash() async throws {
        let client = try await client()
        let items = try await client.inventory()
        #expect(items.map(\.code) == ["EMPTY", "IMAGE", "TRASH"])
        #expect(items.last?.isDeleted == true)
    }
    @Test func emptyServerDraftIsDownloadedWithoutRequestingInvalidResults() async throws {
        let client = try await client()
        let received = try await client.read(RemoteItem(fields: .object(["code": .string("EMPTY"), "isFavorite": .bool(true)])))
        #expect(received.quiz.questions.isEmpty)
        #expect(received.quiz.isFavorite)
        #expect(received.warning == nil)
    }
    @Test func brokenImageAndResultsDoNotPreventQuestionnaireDownload() async throws {
        let client = try await client()
        let received = try await client.read(RemoteItem(fields: .object(["code": .string("IMAGE")])))
        #expect(received.quiz.questions.count == 1)
        #expect(received.quiz.questions[0]["questionImage"].string == "https://sync.example/apps/audience/uploads/missing.png")
        #expect(received.warning?.contains("Résultats") == true)
    }
    @Test func backgroundUploadUsesDraftModeAndNeverResetsResponses() async throws {
        let client = try await client()
        var quiz = Quiz(code: "NEW"); quiz.title = "Remote"
        var question = Question(); question.text = "2 < 3 & 4 > 1"; question.answers = ["Oui", "Non"]
        quiz.questions = [question]; quiz.isFavorite = true
        let saved = try await client.write(quiz, replacing: nil)
        #expect(saved.quiz.isFavorite)
    }
    @Test func liveLaunchSendsARunIdAndReportsTimingAndPresence() async throws {
        let client = try await client(host: "present.example")
        var quiz = Quiz(code: "LIVE2")
        var first = Question(); first.text = "Un"; first.answers = ["A", "B"]
        var second = Question(); second.text = "Deux"; second.answers = ["C", "D"]
        quiz.questions = [first, second]
        let response = try await client.send(quiz, index: 1, live: true, runID: "run_fixture", resetResponses: true)
        #expect(response["timeLimitSec"].int == 45)
        #expect(try await client.presence(code: "LIVE2") == 7)
        #expect(RemoteClient.makeRunID().hasPrefix("run_"))
    }
    @Test func presentationOnWebsitePreventsBackgroundOverwrite() async throws {
        let client = try await client(host: "live.example")
        do {
            _ = try await client.write(Quiz(code: "LIVE"), replacing: RemoteItem(fields: .object(["code": .string("LIVE")])))
            Issue.record("A live session must not be overwritten")
        } catch { #expect(error.localizedDescription.contains("direct")) }
    }
    @Test func lastMinuteWebsiteEditDefersUpload() async throws {
        let client = try await client(host: "race.example")
        do {
            _ = try await client.write(Quiz(code: "RACE"), replacing: RemoteItem(fields: .object(["code": .string("RACE"), "expectedFingerprint": .string("previous-version")])))
            Issue.record("An intervening website edit must not be overwritten")
        } catch { #expect(error.localizedDescription.contains("vient de changer")) }
    }
}

private final class SyncProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value ?? "NEW"
        var value: JSONValue = .object(["success": .bool(true)])
        var status = 200
        switch url.lastPathComponent {
        case "login.php": break
        case "auth_me.php": value = .object(["success": .bool(true), "user": .object(["id": .number(1), "username": .string("Fixture")])])
        case "list_quizzes.php": value = .object(["success": .bool(true), "items": .array([.object(["code": .string("EMPTY")]), .object(["code": .string("IMAGE")])])])
        case "list_deleted_quizzes.php": value = .object(["success": .bool(true), "items": .array([.object(["code": .string("TRASH"), "deletedAt": .string("2026-11-21 10:00:00")])])])
        case "get_batch.php":
            var q = Question(); q.text = "Question"; q.answers = ["Oui", "Non"]
            if code == "IMAGE" { q["questionImage"] = .string("uploads/missing.png") }
            value = .object(["success": .bool(true), "code": .string(code), "quizTitle": .string("Remote"),
                             "liveActive": .bool(url.host == "live.example"),
                             "batch": .array(code == "EMPTY" ? [] : [.object(q.fields)])])
        case "get_batch_results.php":
            #expect(code != "EMPTY")
            if code == "IMAGE" { status = 503; value = .object(["success": .bool(false), "error": .string("Fixture indisponible")]) }
            else { value = .object(["success": .bool(true), "questions": .array([])]) }
        case "save_question.php" where url.host == "present.example":
            // A live launch behaves like the website: new run, live, fresh results when asked.
            let body = (try? JSONDecoder().decode(JSONValue.self, from: requestBody)) ?? .null
            #expect(body["liveActive"] == .bool(true))
            #expect(body["draftMode"] == .bool(false))
            #expect(body["resetAllResponses"] == .bool(true))
            #expect(body["currentIndex"].int == 1)
            #expect(body["batch"].array.count == 2 && body["batch"].array.allSatisfy { $0["runId"].string == "run_fixture" })
            value = .object(["success": .bool(true), "timeLimitSec": .number(45), "questionStartedAtMs": .number(1_000_000), "serverNowMs": .number(999_000)])
        case "get_presence_count.php":
            value = .object(["success": .bool(true), "connectedCount": .number(7)])
        case "save_question.php":
            #expect(url.host != "live.example" && url.host != "race.example")
            let body = (try? JSONDecoder().decode(JSONValue.self, from: requestBody)) ?? .null
            #expect(body["draftMode"].bool)
            #expect(body["resetAllResponses"] == .bool(false))
            #expect(body["liveActive"] == .bool(false))
            #expect(body["batch"].array.first?["question"].string == "<p>2 &lt; 3 &amp; 4 &gt; 1</p>")
        case "set_quiz_favorite.php":
            let body = (try? JSONDecoder().decode(JSONValue.self, from: requestBody)) ?? .null
            #expect(body["favorite"].bool)
        case "missing.png": status = 404
        default: Issue.record("Unexpected fixture request: \(url.lastPathComponent)")
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONEncoder().encode(value)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    private var requestBody: Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
