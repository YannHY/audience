import Foundation
import Testing
@testable import AudienceCore

struct OllamaClientTests {
    @Test func modelNamesMustBeLocal() throws {
        for name in ["qwen3:4b", "gemma3:1b", "deepseek-r1:8b", "namespace/model:q4"] { try OllamaClient.validateModel(name) }
        for name in ["", "qwen:cloud", "model-cloud", "x\nmalicious", "../model", "model name"] {
            #expect(throws: (any Error).self) { try OllamaClient.validateModel(name) }
        }
    }
    @Test func internalReasoningIsNotDisplayed() {
        #expect(OllamaClient.visibleOutput("<think>interne</think>Résumé") == "Résumé")
        #expect(OllamaClient.visibleOutput("<think>encore en cours") == "")
    }
    @Test func installedModelsFilterCloudAndUseLoopbackWithoutCredentials() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaProtocol.self]
        let client = OllamaClient(session: URLSession(configuration: config))
        let models = try await client.models()
        #expect(models.map(\.name) == ["gemma3:1b", "qwen3:4b"])
        #expect(models.last?.bytes == 2_000_000_000)
    }
}
private final class OllamaProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        #expect(request.url?.host == "127.0.0.1")
        #expect(request.url?.path == "/api/tags")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let data = Data(#"{"models":[{"name":"qwen3:4b","size":2000000000},{"name":"qwen3:cloud"},{"name":"remote","remote_host":"https://ollama.com"},{"name":"gemma3:1b","size":800000000}]}"#.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct OllamaStreamingTests {
    private func client(_ fixture: String) -> OllamaClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OllamaStreamProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Fixture": fixture]
        return OllamaClient(session: URLSession(configuration: config))
    }
    @Test func streamedSynthesisOnlyReturnsVisibleCompleteContent() async throws {
        let output = try await client("chat").synthesize(model: "qwen3:4b", evidence: "Données agrégées") { _ in }
        #expect(output == "Synthèse terminée.")
    }
    @Test func interruptedAndFailedStreamsAreNotSuccessfulSyntheses() async {
        for fixture in ["incomplete", "error", "length"] {
            await #expect(throws: (any Error).self) {
                _ = try await client(fixture).synthesize(model: "qwen3:4b", evidence: "Données") { _ in }
            }
        }
    }
    @Test func pullRequiresFinalSuccessEvent() async throws {
        try await client("pull").pull("gemma3:1b") { _ in }
        await #expect(throws: (any Error).self) {
            try await client("incomplete").pull("gemma3:1b") { _ in }
        }
    }
}
private final class OllamaStreamProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        #expect(request.url?.host == "127.0.0.1")
        let fixture = request.value(forHTTPHeaderField: "X-Test-Fixture")
        let body: String
        switch fixture {
        case "chat": body = """
        {"message":{"content":"<think>Interne</think>Synthèse "},"done":false}
        {"message":{"content":"terminée."},"done":true,"done_reason":"stop"}

        """
        case "pull": body = """
        {"status":"pulling manifest"}
        {"status":"pulling data","total":100,"completed":50}
        {"status":"success"}

        """
        case "length": body = "{\"message\":{\"content\":\"Incomplet\"},\"done\":true,\"done_reason\":\"length\"}\n"
        case "error": body = "{\"error\":\"Mémoire insuffisante\"}\n"
        default: body = "{\"message\":{\"content\":\"Interrompu\"},\"done\":false}\n"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/x-ndjson"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
