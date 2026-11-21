import Testing
import Foundation
@testable import AudienceCore

struct CompatibilityTests {
    let fixture = Data(#"""
    {
      "app":"Audience", "version":1,
      "quizzes": {"ABC123": {
        "code":"ABC123", "quizTitle":"Révisions", "isFavorite":true,
        "batch":[{"type":"multiple","question":"<p>Combien font <b>2 + 2</b> ?</p>","answers":["3","4","5"],"correctIndex":1,"timeLimitSec":30,"futureField":{"value":42}}],
        "deletedAt":null,"updatedAt":"2026-01-01T12:00:00Z"
      }},
      "responses":{"ABC123":{"0":{"counts":{"1":7},"openResponses":[],"details":[{"participantName":"Alice"}]}}},
      "sync":{"remoteBase":"https://example.org/audience/","password":"must-not-export"}
    }
    """#.utf8)

    @Test func readsElectronBackupAndPreservesUnknownFieldsAndResponses() throws {
        let archive = try JSONDecoder().decode(LibraryArchive.self, from: fixture)
        let q = try #require(archive.quizzes["ABC123"])
        #expect(q.title == "Révisions")
        #expect(q.isFavorite)
        #expect(q.questions[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == "Combien font 2 + 2 ?")
        #expect(q.questions[0]["futureField"]["value"].int == 42)
        #expect(archive.responses["ABC123"]?["0"]["counts"]["1"].int == 7)
        let data = try JSONEncoder().encode(archive)
        let restored = try JSONDecoder().decode(LibraryArchive.self, from: data)
        #expect(restored.quizzes == archive.quizzes)
        #expect(restored.responses == archive.responses)
        #expect(!String(decoding: data, as: UTF8.self).contains("must-not-export"))
    }
    @Test func importCollisionKeepsBothQuestionnairesAndTheirResults() throws {
        let incoming = try JSONDecoder().decode(LibraryArchive.self, from: fixture)
        var archive = incoming
        archive.quizzes["ABC123"]?.title = "Ma version locale"
        #expect(archive.merge(incoming) == 1)
        #expect(archive.quizzes.count == 2)
        #expect(archive.quizzes["ABC123"]?.title == "Ma version locale")
        let imported = try #require(archive.quizzes.values.first(where: { $0.code != "ABC123" }))
        #expect(imported.title == "Révisions (importé)")
        #expect(archive.responses[imported.code] == incoming.responses["ABC123"])
        #expect(!imported["liveActive"].bool)
    }
    @Test func malformedBackupIsRejectedAsAWhole() {
        for text in [#"{"quizzes":{"OK":{"batch":[]},"BAD":5}}"#, #"{"quizzes":{"../escape":{"batch":[]}}}"#, #"{"unrelated":true}"#] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(LibraryArchive.self, from: Data(text.utf8)) }
        }
    }
    @Test func allQuestionFormatsAndInlineImagesSurviveRoundTrip() throws {
        var quiz = Quiz(code: "TEST")
        quiz.questions = QuestionKind.allCases.map { kind in
            var question = Question(kind: kind)
            question.text = "Question \(kind.rawValue)"
            question["questionImage"] = .string("data:image/png;base64,YWJj")
            return question
        }
        let restored = try JSONDecoder().decode(Quiz.self, from: JSONEncoder().encode(quiz))
        #expect(restored == quiz)
        #expect(restored.questions.map(\.kind) == QuestionKind.allCases)
    }
    @Test func answerRemovalAdjustsSingleAndMultipleCorrections() {
        var question = Question(kind: .checkbox)
        question.answers = ["a", "b", "c", "d"]
        question["correctIndex"] = .number(3)
        question["correctIndexes"] = .array([.number(0), .number(2), .number(3)])
        question.removeAnswer(at: 1)
        #expect(question.answers == ["a", "c", "d"])
        #expect(question["correctIndex"].int == 2)
        #expect(question["correctIndexes"].array.map(\.int) == [0, 1, 2])
        question.removeAnswer(at: 1)
        question.removeAnswer(at: 0)
        #expect(question.answers.count == 2)
    }
    @Test func editorPreservesTrailingSpacesAndLineBreaks() {
        var question = Question()
        question.text = "Une question "
        #expect(question.text == "Une question ")
        question.text += "avec des espaces\n"
        #expect(question.text == "Une question avec des espaces\n")
    }
    @Test func uploadDoesNotResetExistingResponses() {
        let quiz = Quiz(code: "HELLO")
        let payload = quiz.payload(index: 3, live: true)
        #expect(payload["resetAllResponses"] == .bool(false))
        #expect(payload["liveActive"].bool)
        #expect(payload["currentIndex"].int == 3)
    }
    @Test func plainTextEditingEscapesHTMLWithoutLosingComparisonSymbols() {
        var question = Question()
        question.text = "Si 2 < 3 & 5 > 4\nAlors ?"
        #expect(question.text == "Si 2 < 3 & 5 > 4\nAlors ?")
        #expect(question["question"].string.contains("&lt;"))
    }
    @Test func validationRejectsUnusableQuestionsBeforeSending() {
        var quiz = Quiz(code: "TEST")
        #expect(quiz.validationMessage != nil)
        var q = Question()
        q.text = "Question"
        quiz.questions = [q]
        #expect(quiz.validationMessage != nil)
        q.answers = ["Oui", "Non"]; quiz.questions = [q]
        #expect(quiz.validationMessage == nil)
        q.kind = .cloze
        q["clozeText"] = .string("Aucun trou")
        #expect(q.validationMessage != nil)
        q["clozeText"] = .string("Le ciel est [bleu].")
        #expect(q.validationMessage == nil)
    }
    @Test func remoteRejectsInsecureAddressesBeforeSendingCredentials() async {
        let client = RemoteClient()
        do {
            _ = try await client.connect(address: "http://example.org/", email: "test", password: "secret")
            Issue.record("An HTTP endpoint should be rejected")
        } catch { #expect(error.localizedDescription.contains("HTTPS")) }
    }
}
