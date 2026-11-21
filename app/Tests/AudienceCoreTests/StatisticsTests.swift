import Foundation
import Testing
@testable import AudienceCore

struct StatisticsTests {
    func json(_ value: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)) }
    func stats(_ question: String, _ responses: String) -> QuizStatistics {
        var quiz = Quiz(code: "STATS")
        quiz.questions = [Question(fields: json(question).object)]
        return QuizStatistics(quiz: quiz, responses: json(responses))
    }
    @Test func singleChoiceUsesCountsAndDoesNotGradeMissingResponses() {
        let s = stats(#"{"type":"multiple","question":"Choix","answers":["Oui","Non"],"correctIndex":0}"#,
                      #"{"questions":[{"results":[3,2],"total":7}]}"#)
        #expect(s.correct == 3 && s.incorrect == 2 && s.submissions == 7)
        #expect(s.questions[0].ungraded == 2)
        #expect(s.successRate == 0.6)
        #expect(s.participants == nil)
    }
    @Test func pollsAndMissingKeysAreNotGraded() {
        for question in [#"{"type":"multiple","answers":["A","B"],"correctIndex":0,"isPollMode":true}"#,
                         #"{"type":"multiple","answers":["A","B"]}"#] {
            let s = stats(question, #"{"0":{"counts":[1,2]}}"#)
            #expect(s.correct == 0 && s.incorrect == 0 && s.successRate == nil)
            #expect(s.questions[0].ungraded == 3)
        }
    }
    @Test func multipleChoicesAreGradedAsCompleteSubmissions() {
        let s = stats(#"{"type":"checkbox","answers":["A","B","C"],"correctIndexes":[0,2]}"#,
                      #"{"questions":[{"results":[3,1,2],"total":6,"participantResponses":[{"participantKey":"a","responseText":"C | A"},{"participantKey":"b","responseText":"A"},{"participantKey":"a","responseText":"A | B | C"}]}]}"#)
        #expect(s.submissions == 3 && s.correct == 1 && s.incorrect == 2)
        #expect(s.participants == 2)
        #expect(s.questions[0].selections == 6)
    }
    @Test func aggregateCheckboxCountsCannotRevealCompleteSuccesses() {
        let s = stats(#"{"type":"checkbox","answers":["A","B"],"correctIndexes":[0,1]}"#,
                      #"{"0":{"counts":{"0":5,"1":3},"total":8}}"#)
        #expect(s.submissions == nil && s.correct == 0 && s.incorrect == 0)
        #expect(s.hasResponses && s.questions[0].note != nil)
    }
    @Test func ambiguousCheckboxLabelsAreNotGuessed() {
        let s = stats(#"{"type":"checkbox","answers":["A | B","B"],"correctIndexes":[0]}"#,
                      #"{"questions":[{"results":[1,0],"participantResponses":[{"responseText":"A | B"}]}]}"#)
        #expect(s.correct == 0 && s.incorrect == 0 && s.questions[0].ungraded == 1)
    }
    @Test func freeResponsesAreGroupedWithoutBeingGraded() {
        let s = stats(#"{"type":"open","question":"Pourquoi ?"}"#,
                      #"{"0":{"openResponses":[" Paris ","paris","PARIS","Lyon",{"text":"Lyon"}]}}"#)
        #expect(s.submissions == 5 && s.questions[0].ungraded == 5)
        #expect(s.questions[0].frequencies.map(\.count) == [3,2])
        #expect(s.questions[0].frequencies.first?.label == "Paris")
        #expect(s.correct == 0 && s.incorrect == 0)
    }
    @Test func clozeAndRankingUseTheExpectedAnswer() {
        let cloze = stats(#"{"type":"cloze","clozeText":"Le [chat] est {{noir}}."}"#,
                          #"{"0":{"openResponses":["Le chat est noir.","le CHAT est noir.","Le chien est noir."]}}"#)
        #expect(cloze.correct == 2 && cloze.incorrect == 1)
        let ranking = stats(#"{"type":"ranking","answers":["A","B"]}"#,
                            #"{"0":{"openResponses":["A -> B","B -> A","[\"A\",\"B\"]"]}}"#)
        #expect(ranking.correct == 2 && ranking.incorrect == 1)
    }
    @Test func ratingAndImagesStayUngraded() {
        let rating = stats(#"{"type":"rating","maxRating":5}"#, #"{"0":{"counts":[0,0,0,1,2,3]}}"#)
        #expect(rating.submissions == 6 && rating.questions[0].ungraded == 6)
        #expect(rating.correct == 0 && rating.incorrect == 0)
        let image = stats(#"{"type":"labelimage"}"#, #"{"0":{"openResponses":["Placement complété"]}}"#)
        #expect(image.questions[0].ungraded == 1 && image.questions[0].note != nil)
    }
    @Test func questionIndicesDoNotDependOnServerOrderAndVideosAreExcluded() {
        var quiz = Quiz()
        quiz.questions = [Question(fields: json(#"{"type":"multiple","answers":["A","B"],"correctIndex":0}"#).object), Question(kind: .video), Question(kind: .open)]
        let s = QuizStatistics(quiz: quiz, responses: json(#"{"questions":[{"questionIndex":2,"openResponses":["Salut"]},{"questionIndex":0,"results":[2,1]}]}"#))
        #expect(s.questions.map(\.index) == [0,2])
        #expect(s.submissions == 4 && s.correct == 2 && s.incorrect == 1)
    }
    @Test func emptyAndNegativeCountsDoNotCreateResponses() {
        let s = stats(#"{"type":"multiple","answers":["A","B"],"correctIndex":0}"#, #"{"0":{"counts":[-4,0]}}"#)
        #expect(!s.hasResponses && s.submissions == 0 && s.successRate == nil)
    }
    @Test func synthesisDoesNotContainParticipantMetadata() {
        let s = stats(#"{"type":"open","question":"Pourquoi ?"}"#,
                      #"{"questions":[{"openResponses":["Un avis"],"participantResponses":[{"participantName":"SECRET_NAME","participantKey":"SECRET_ID","responseText":"Un avis"}]}]}"#)
        let evidence = s.synthesisEvidence(title: "Mon test")
        #expect(!evidence.contains("SECRET_NAME") && !evidence.contains("SECRET_ID"))
        #expect(evidence.contains("Un avis") && evidence.contains("Non évaluées : 1"))
    }
}
