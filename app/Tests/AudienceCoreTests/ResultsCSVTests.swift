import Testing
import Foundation
@testable import AudienceCore

struct ResultsCSVTests {
    func quiz(_ questions: [[String: JSONValue]]) -> Quiz {
        var quiz = Quiz(code: "ABC123")
        quiz.questions = questions.map(Question.init(fields:))
        return quiz
    }
    func decode(_ json: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) }

    @Test func namedParticipantsGetOneColumnEach() throws {
        let q = quiz([["type": .string("multiple"), "question": .string("<p>Capitale ?</p>")],
                      ["type": .string("open"), "question": .string("Pourquoi, \"vraiment\" ?")]])
        let results = decode(#"""
        {"questions":[
          {"questionIndex":0,"type":"multiple","question":"<p>Capitale ?</p>","answers":["Paris","Lyon"],"results":{"0":1,"1":1},
           "participantResponses":[{"participantKey":"a","participantName":"Alice","responseText":"Paris"},
                                   {"participantKey":"b","participantName":"Alice","responseText":"Lyon"}]},
          {"questionIndex":1,"type":"open","question":"Pourquoi, \"vraiment\" ?","openResponses":["Parce que"],
           "participantResponses":[{"participantKey":"b","participantName":"Alice","responseText":"Parce que"},
                                   {"participantKey":"b","participantName":"Alice","responseText":"et aussi"}]}
        ]}
        """#)
        let csv = try #require(ResultsCSV.build(quiz: q, responses: results))
        #expect(csv == """
        question,Alice,Alice (2)
        Capitale ?,Paris,Lyon
        "Pourquoi, ""vraiment"" ?",,Parce que | et aussi
        """)
    }

    @Test func withoutParticipantDetailsColumnsAreAnonymous() throws {
        let q = quiz([["type": .string("multiple"), "question": .string("Choix"), "answers": .array([.string("Oui"), .string("Non")])],
                      ["type": .string("rating"), "question": .string("Note"), "maxRating": .number(5)],
                      ["type": .string("wordcloud"), "question": .string("Mot")]])
        // Electron backups store one bucket per question index.
        let results = decode(#"{"0":{"counts":{"0":2,"1":1}},"1":{"counts":{"4":1}},"2":{"openResponses":["chat"," "]}}"#)
        let csv = try #require(ResultsCSV.build(quiz: q, responses: results))
        #expect(csv == """
        question,participant_1,participant_2,participant_3
        Choix,Oui,Oui,Non
        Note,4,,
        Mot,chat,,
        """)
    }

    @Test func filenameMatchesTheWebsite() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 7))!
        #expect(ResultsCSV.filename(code: "ABC123", date: date) == "audience-bilan-ABC123-2026-03-07.csv")
        #expect(ResultsCSV.escape("a\r\nb") == "\"a\r\nb\"")
    }
}
