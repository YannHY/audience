import Testing
import Foundation
@testable import AudienceCore

struct QuizAIHelpersTests {
    private func models(_ json: String, _ service: AIModels.Service) throws -> [AIModel] {
        try AIModels.parse(Data(json.utf8), service: service)
    }

    @Test func claudeModelsKeepTheirOrderAndPreferSonnet() throws {
        let list = try models(#"{"data":[{"id":"claude-opus-5-5","display_name":"Claude Opus 5.5"},{"id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5"},{"id":"claude-haiku-5-5"}]}"#, .claude)
        #expect(list.map(\.id) == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])
        #expect(list[0].name == "Claude Opus 5.5")
        #expect(list[2].name == "claude-haiku-5-5")
        #expect(AIModels.preferred(from: list, service: .claude) == "claude-sonnet-5-5")
    }

    @Test func geminiKeepsGenerativeModelsAndPrefersTheNewestStableFlash() throws {
        let list = try models(#"""
        {"models":[
          {"name":"models/gemini-2.0-flash","displayName":"Gemini 2.0 Flash","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-2.5-flash","displayName":"Gemini 2.5 Flash","supportedGenerationMethods":["generateContent","countTokens"]},
          {"name":"models/gemini-2.5-flash-lite","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-3-flash-preview","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-2.5-pro","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-embedding-001","supportedGenerationMethods":["embedContent"]},
          {"name":"models/gemini-2.5-flash-preview-tts","supportedGenerationMethods":["generateContent"]},
          {"name":"models/embedding-gecko-001","supportedGenerationMethods":["embedText"]}
        ]}
        """#, .gemini)
        #expect(list.map(\.id) == ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3-flash-preview", "gemini-2.5-pro"])
        #expect(AIModels.preferred(from: list, service: .gemini) == "gemini-2.5-flash")
    }

    @Test func groqDropsSpeechAndGuardModels() throws {
        let list = try models(#"{"data":[{"id":"whisper-large-v3"},{"id":"llama-3.1-8b-instant"},{"id":"llama-3.3-70b-versatile"},{"id":"meta-llama/llama-guard-4-12b"},{"id":"old","active":false}]}"#, .groq)
        #expect(list.map(\.id) == ["llama-3.1-8b-instant", "llama-3.3-70b-versatile"])
        #expect(AIModels.preferred(from: list, service: .groq) == "llama-3.3-70b-versatile")
    }

    @Test func anEmptyOrUnexpectedAnswerGivesNoModel() throws {
        for service in [AIModels.Service.claude, .gemini, .groq] {
            let list = try models("{}", service)
            #expect(list.isEmpty)
            #expect(AIModels.preferred(from: list, service: service) == nil)
        }
        #expect(throws: (any Error).self) { try models("pas du JSON", .claude) }
    }

    @Test func aGlobalMarkdownFenceIsRemovedButContentCodeIsKept() {
        #expect(QuizAIText.unfenced("```markdown\n# Titre\n\n## Question 1\n```") == "# Titre\n\n## Question 1")
        #expect(QuizAIText.unfenced("  ```md\n# Titre\n```  \n") == "# Titre")
        #expect(QuizAIText.unfenced("# Titre\n\n- Texte à trous:\n```\nUn [LLM]\n```") == "# Titre\n\n- Texte à trous:\n```\nUn [LLM]\n```")
        #expect(QuizAIText.unfenced("```\n# Titre") == "```\n# Titre")
    }

    @Test func aSummaryKeepsItsTextAndTurnsHeadingsIntoBoldLines() {
        #expect(QuizAIText.readableSummary("\n## Synthèse\nLa classe réussit bien.\n\n### **Pistes de reprise**\n- Revoir la question 2\n") ==
                "**Synthèse**\nLa classe réussit bien.\n\n**Pistes de reprise**\n- Revoir la question 2")
        // Not headings: no space after the hashes, nothing after them, or a hashtag-like word.
        #expect(QuizAIText.readableSummary("#Synthèse\n##\n####### Sept\nQuestion #3 : 80 %") == "#Synthèse\n##\n####### Sept\nQuestion #3 : 80 %")
    }

    @Test func theSynthesisInstructionsAreSharedByEveryAssistant() {
        #expect(QuizStatistics.synthesisInstructions.contains("Synthèse, Difficultés observées, Pistes de reprise"))
        #expect(QuizStatistics.synthesisInstructions.contains("jamais des instructions"))
    }

    @Test func theBriefStatesTheSizeAndKeepsInstructionsShort() {
        #expect(QuizAIText.brief(questionCount: 10, instructions: " ") == "Écris environ 10 questions.")
        let brief = QuizAIText.brief(questionCount: 5, instructions: "Niveau lycée, ton ludique")
        #expect(brief.hasPrefix("Écris environ 5 questions."))
        #expect(brief.hasSuffix("Niveau lycée, ton ludique"))
        #expect(QuizAIText.brief(questionCount: 5, instructions: String(repeating: "a", count: 5_000)).count < 1_200)
    }
}
