import Foundation
import Testing
@testable import AudienceCore

struct QuizMarkdownTests {
    /// Same layout as `audience_export_build_quiz_markdown` in lib/quiz_export.php.
    static let export = #"""
    # Révision \| chapitre 2

    - Code: `ABC123`
    - Nombre de questions: 9
    - Rapport participant: activé
    - Nom participant: optionnel

    ## Question 1

    Capitale de la France ?

    - [ ] Lyon
    - [x] Paris
    - [ ] Marseille

    ## Question 2

    Nombres pairs ?

    - Type: cases à cocher
    - [x] 2
    - [ ] 3
    - [x] 4

    ## Question 3

    Résolvez x² = 4

    - Type: question ouverte
    - Format de réponse: mathématique
    - Réponses des participants: masquées

    ## Question 4

    Complétez

    - Type: texte à trous
    - Texte à trous:
    ```
    Le [chat] dort.
    ```

    ## Question 5

    Un mot ?

    - Type: nuage de mots

    ## Question 6

    Votre avis

    - Type: notation en étoiles (1 à 5)

    ## Question 7

    Ordre chronologique

    - Type: classement
    - Éléments à classer:
    ```
    Antiquité
    Moyen Âge
    ```

    ## Question 8

    Regardez

    - Type: vidéo YouTube
    - URL vidéo: https://youtu.be/abc
    - Début vidéo (s): 1:30
    - Fin vidéo (s): 60

    ## Question 9

    Légendez

    - Type: légender une image
    - Image: https://example.com/a.png
    - Zoom image: 3
    - Étiquettes:
    ```json
    [
        {"id": "a", "text": "Cœur", "x": 40.5, "y": 20},
        {"id": "b", "text": "Poumon", "x": null, "y": null}
    ]
    ```
    """#

    @Test func readsTheWebsiteExport() throws {
        let quiz = try QuizMarkdown.parse(Self.export)
        #expect(quiz.title == "Révision | chapitre 2")
        #expect(quiz["participantReportEnabled"].bool && !quiz["requireParticipantName"].bool)
        #expect(quiz.code != "ABC123")
        let q = quiz.questions
        #expect(q.map(\.kind) == [.multiple, .checkbox, .open, .cloze, .wordcloud, .rating, .ranking, .video, .labelimage])
        #expect(q[0].text == "Capitale de la France ?" && q[0].answers == ["Lyon", "Paris", "Marseille"] && q[0]["correctIndex"].int == 1)
        #expect(q[1]["correctIndexes"].array.map(\.int) == [0, 2])
        #expect(q[2]["responseFormat"].string == "math" && !q[2]["participantResponsesVisible"].bool)
        #expect(q[3]["clozeText"].string == "Le [chat] dort.")
        #expect(q[6].answers == ["Antiquité", "Moyen Âge"])
        #expect(q[7]["youtubeUrl"].string == "https://youtu.be/abc" && q[7]["videoStartSec"].int == 90 && q[7]["videoEndSec"] == .null)
        #expect(q[8]["questionImage"].string == "https://example.com/a.png" && q[8]["questionImageZoom"].double == 2.2)
        #expect(q[8]["legendLabels"].array.map { $0["text"].string } == ["Cœur", "Poumon"])
        #expect(q[8]["legendLabels"]["0"]["x"].double == 40.5)
        #expect(q.allSatisfy { $0.validationMessage == nil })
    }

    @Test func infersTypesFromHandWrittenMarkdown() throws {
        let quiz = try QuizMarkdown.parse("""
        ## Question
        Sans réponse
        ## Question
        Classez ces nombres
        - [ ] 3
        - [ ] 1
        ## Question
        Deux bonnes
        - [x] A
        - [X] B
        """)
        #expect(quiz.title == "Questionnaire importé")
        #expect(quiz.questions.map(\.kind) == [.open, .ranking, .checkbox])
        #expect(quiz.questions[1].answers == ["3", "1"])
    }

    @Test func rejectsFilesWithoutQuestions() {
        #expect(throws: AudienceError.self) { try QuizMarkdown.parse("# Titre\n\nTexte libre") }
        #expect(throws: AudienceError.self) { try QuizMarkdown.parse("## Question 1\n\n- [x] seule puce") }
    }

    @Test func videoBoundaries() {
        #expect(QuizMarkdown.videoSeconds("1:02:03") == 3723)
        #expect(QuizMarkdown.videoSeconds("2,05") == 125)
        #expect(QuizMarkdown.videoSeconds("1:75") == nil)
        #expect(QuizMarkdown.videoSeconds("99999") == 43_200)
    }

    @Test func readsAZipArchiveOfMarkdownFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.export.write(to: dir.appendingPathComponent("revision.md"), atomically: true, encoding: .utf8)
        try "# Court\n\n## Question 1\n\nOui ?\n".write(to: dir.appendingPathComponent("court.md"), atomically: true, encoding: .utf8)
        try "Lisez-moi".write(to: dir.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-q", "-9", "export.zip", "revision.md", "court.md", "README.txt"]
        try zip.run(); zip.waitUntilExit()
        let quizzes = try QuizMarkdown.parseArchive(Data(contentsOf: dir.appendingPathComponent("export.zip")))
        #expect(Set(quizzes.map(\.title)) == ["Révision | chapitre 2", "Court"])
        #expect(quizzes.first { $0.title == "Court" }?.questions.first?.kind == .open)
    }

    @Test func rejectsFilesThatAreNotZip() {
        #expect(throws: AudienceError.self) { try QuizMarkdown.parseArchive(Data("pas un zip".utf8)) }
    }
}
